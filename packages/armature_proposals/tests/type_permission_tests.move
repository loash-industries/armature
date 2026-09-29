/// Permission coverage for every armature_proposals payload type, through the
/// real path: the type is enabled with a config, `submit_vote_execute` mints
/// the ticket from that slot, and the handler runs.
///
/// - `<type>_grant`: a config holding exactly the `type_permissions` bits (and
///   borrow scope) executes, and the effect lands. The bits are sufficient.
/// - `<type>_needs_<bit>`: the same config minus one bit aborts
///   `EPermissionDenied`; `<type>_needs_scope` drops the borrow scope and
///   aborts `EBorrowScopeDenied`. Each bit is necessary.
///
/// `scripts/check_request_gates.py` requires a grant test for every handled
/// type, and a `_needs_` test for every type that holds bits.
#[test_only]
module armature_proposals::type_permission_tests;

use armature::board_voting;
use armature::capability_vault::{CapabilityVault, SubOUControl};
use armature::emergency::EmergencyFreeze;
use armature::governance;
use armature::ou::{Self, OU};
use armature::permissions;
use armature::proposal::{Self, ProposalConfig};
use armature::treasury_vault::TreasuryVault;
use armature::tribe;
use armature_proposals::adopt_currency::{Self, AdoptCurrency};
use armature_proposals::burn_coin::{Self, BurnCoin};
use armature_proposals::configure_mint_allowance::{Self, ConfigureMintAllowance};
use armature_proposals::controller_batch_add_members::{Self, ControllerBatchAddMembers};
use armature_proposals::controller_batch_remove_members::{Self, ControllerBatchRemoveMembers};
use armature_proposals::currency_ops;
use armature_proposals::mint_allowance::{Self, MintAllowance};
use armature_proposals::mint_coin::{Self, MintCoin};
use armature_proposals::pause_execution::{Self, PauseSubOUExecution, UnpauseSubOUExecution};
use armature_proposals::propose_upgrade::{Self, ProposeUpgrade};
use armature_proposals::reclaim_cap_from_subou::{Self, ReclaimCapFromSubOU};
use armature_proposals::return_currency_cap::{Self, ReturnCurrencyCap};
use armature_proposals::send_coin::{Self, SendCoin};
use armature_proposals::send_coin_to_ou::{Self, SendCoinToOU};
use armature_proposals::send_small_payment::{Self, SendSmallPayment};
use armature_proposals::subou_ops;
use armature_proposals::transfer_cap_to_subou::{Self, TransferCapToSubOU};
use armature_proposals::treasury_ops;
use armature_proposals::type_permissions;
use armature_proposals::upgrade_ops;
use std::string;
use std::type_name::TypeName;
use sui::clock::{Self, Clock};
use sui::coin::{Self, TreasuryCap};
use sui::package;
use sui::sui::SUI;
use sui::test_scenario;

const CREATOR: address = @0xA;
const RECIPIENT: address = @0xB;
const SUBOU_MEMBER: address = @0xC;

public struct GLYPH has drop {}

public struct TestCap has key, store { id: UID }

/// Payload type of the synthetic request that wires a SubOU in setup.
public struct Wiring has drop, store {}

/// Single-vote config (one-member board) holding `bits` and `scope`. The 80%
/// threshold meets the floor of every bit these types hold.
fun cfg(bits: u64, scope: vector<TypeName>): ProposalConfig {
    proposal::new_config(5_000, 8_000, 0, 604_800_000, 0, 0)
        .with_permissions(bits)
        .with_borrow_scope(scope)
}

fun glyph_scope(): vector<TypeName> { type_permissions::currency_scope<GLYPH>() }

fun control_id(vault: &CapabilityVault): ID { vault.ids_for_type<SubOUControl>()[0] }

/// Create an OU (board [CREATOR]) with type `$T` enabled under `cfg($bits,
/// $scope)`, plus a second OU whose treasury is a transfer target. `$f` gets
/// (ou, treasury, vault, freeze, clock, other_treasury, ctx).
macro fun run<$T>(
    $bits: u64,
    $scope: vector<TypeName>,
    $f: |
        &mut OU,
        &mut TreasuryVault,
        &mut CapabilityVault,
        &EmergencyFreeze,
        &Clock,
        &mut TreasuryVault,
        &mut TxContext,
    |,
) {
    let mut scenario = test_scenario::begin(CREATOR);
    let init = governance::init_board(vector[CREATOR]);
    let ou_id = ou::create(&init, string::utf8(b"OU"), string::utf8(b""), scenario.ctx());
    let other_id = ou::create(&init, string::utf8(b"Other"), string::utf8(b""), scenario.ctx());
    scenario.next_tx(CREATOR);
    let mut ou = scenario.take_shared_by_id<OU>(ou_id);
    let other = scenario.take_shared_by_id<OU>(other_id);
    ou.test_enable_type<$T>(b"UnderTest".to_ascii_string(), cfg($bits, $scope));
    let mut treasury = scenario.take_shared_by_id<TreasuryVault>(ou.treasury_id());
    let mut vault = scenario.take_shared_by_id<CapabilityVault>(ou.capability_vault_id());
    let freeze = scenario.take_shared_by_id<EmergencyFreeze>(ou.emergency_freeze_id());
    let mut other_treasury = scenario.take_shared_by_id<TreasuryVault>(other.treasury_id());
    let clock = clock::create_for_testing(scenario.ctx());
    $f(
        &mut ou,
        &mut treasury,
        &mut vault,
        &freeze,
        &clock,
        &mut other_treasury,
        scenario.ctx(),
    );
    clock.destroy_for_testing();
    test_scenario::return_shared(other_treasury);
    test_scenario::return_shared(freeze);
    test_scenario::return_shared(vault);
    test_scenario::return_shared(treasury);
    test_scenario::return_shared(other);
    test_scenario::return_shared(ou);
    scenario.end();
}

/// Create a controller OU (board [CREATOR]) with type `$T` enabled under
/// `cfg($bits, $scope)` and a SubOU (board [CREATOR, SUBOU_MEMBER]) wired to
/// it. `$f` gets (controller, controller_vault, subou, subou_vault, freeze,
/// clock, ctx).
macro fun run_controller<$T>(
    $bits: u64,
    $scope: vector<TypeName>,
    $f: |
        &mut OU,
        &mut CapabilityVault,
        &mut OU,
        &mut CapabilityVault,
        &EmergencyFreeze,
        &Clock,
        &mut TxContext,
    |,
) {
    let mut scenario = test_scenario::begin(CREATOR);
    let init = governance::init_board(vector[CREATOR]);
    let ou_id = ou::create(&init, string::utf8(b"OU"), string::utf8(b""), scenario.ctx());
    scenario.next_tx(CREATOR);
    let subou_id = {
        let mut ou = scenario.take_shared_by_id<OU>(ou_id);
        ou.test_enable_type<$T>(b"UnderTest".to_ascii_string(), cfg($bits, $scope));
        let mut vault = scenario.take_shared_by_id<CapabilityVault>(ou.capability_vault_id());
        let wire = proposal::new_permitted_request_for_testing<Wiring>(
            ou.id(),
            object::id_from_address(@0x1),
            permissions::vault_store() | permissions::vault_extract(),
        );
        let subou_id = tribe::create_wired_subou(
            vector[CREATOR, SUBOU_MEMBER],
            string::utf8(b"Sub"),
            string::utf8(b""),
            CREATOR,
            &mut vault,
            &wire,
            vector[],
            scenario.ctx(),
        );
        proposal::consume_execution_request_for_testing(wire);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(ou);
        subou_id
    };
    scenario.next_tx(CREATOR);
    let mut ou = scenario.take_shared_by_id<OU>(ou_id);
    let mut vault = scenario.take_shared_by_id<CapabilityVault>(ou.capability_vault_id());
    let freeze = scenario.take_shared_by_id<EmergencyFreeze>(ou.emergency_freeze_id());
    let mut subou = scenario.take_shared_by_id<OU>(subou_id);
    let mut subou_vault = scenario.take_shared_by_id<CapabilityVault>(subou.capability_vault_id());
    let clock = clock::create_for_testing(scenario.ctx());
    $f(&mut ou, &mut vault, &mut subou, &mut subou_vault, &freeze, &clock, scenario.ctx());
    clock.destroy_for_testing();
    test_scenario::return_shared(subou_vault);
    test_scenario::return_shared(subou);
    test_scenario::return_shared(freeze);
    test_scenario::return_shared(vault);
    test_scenario::return_shared(ou);
    scenario.end();
}

// === Treasury ===

macro fun send_coin($bits: u64) {
    run!<SendCoin<SUI>>($bits, vector[], |ou, treasury, _, freeze, clock, _, ctx| {
        treasury.deposit(coin::mint_for_testing<SUI>(100, ctx), ctx);
        let payload = send_coin::new<SUI>(RECIPIENT, 40);
        let ticket = board_voting::submit_vote_execute(
            ou,
            option::none(),
            payload,
            freeze,
            clock,
            ctx,
        );
        treasury_ops::execute_send_coin<SUI>(treasury, ticket, ctx);
        assert!(treasury.balance<SUI>() == 60);
    });
}

#[test]
fun send_coin_grant() { send_coin!(type_permissions::treasury_spend()) }

#[test, expected_failure(abort_code = armature::proposal::EPermissionDenied)]
fun send_coin_needs_treasury_withdraw() { send_coin!(0) }

macro fun send_coin_to_ou($bits: u64) {
    run!<SendCoinToOU<SUI>>($bits, vector[], |ou, treasury, _, freeze, clock, other, ctx| {
        treasury.deposit(coin::mint_for_testing<SUI>(100, ctx), ctx);
        let payload = send_coin_to_ou::new<SUI>(object::id(other), 40);
        let ticket = board_voting::submit_vote_execute(
            ou,
            option::none(),
            payload,
            freeze,
            clock,
            ctx,
        );
        treasury_ops::execute_send_coin_to_ou<SUI>(treasury, other, ticket, ctx);
        assert!(other.balance<SUI>() == 40);
    });
}

#[test]
fun send_coin_to_ou_grant() { send_coin_to_ou!(type_permissions::treasury_spend()) }

#[test, expected_failure(abort_code = armature::proposal::EPermissionDenied)]
fun send_coin_to_ou_needs_treasury_withdraw() { send_coin_to_ou!(0) }

macro fun send_small_payment($bits: u64) {
    run!<SendSmallPayment<SUI>>($bits, vector[], |ou, treasury, _, freeze, clock, _, ctx| {
        treasury.deposit(coin::mint_for_testing<SUI>(10_000, ctx), ctx);
        // The default cap is 1% of the balance per epoch: 100.
        let payload = send_small_payment::new<SUI>(RECIPIENT, 50);
        let ticket = board_voting::submit_vote_execute(
            ou,
            option::none(),
            payload,
            freeze,
            clock,
            ctx,
        );
        treasury_ops::execute_send_small_payment<SUI>(ou, treasury, ticket, clock, ctx);
        assert!(treasury.balance<SUI>() == 9_950);
    });
}

#[test]
fun send_small_payment_grant() { send_small_payment!(type_permissions::treasury_spend()) }

#[test, expected_failure(abort_code = armature::proposal::EPermissionDenied)]
fun send_small_payment_needs_treasury_withdraw() { send_small_payment!(0) }

// === Currency ===

macro fun adopt_currency($bits: u64) {
    run!<AdoptCurrency<GLYPH>>($bits, vector[], |ou, _, vault, freeze, clock, _, ctx| {
        let cap = coin::create_treasury_cap_for_testing<GLYPH>(ctx);
        let cap_id = object::id(&cap);
        let ticket = board_voting::submit_vote_execute(
            ou,
            option::none(),
            adopt_currency::new<GLYPH>(),
            freeze,
            clock,
            ctx,
        );
        currency_ops::execute_adopt_currency<GLYPH>(vault, cap, ticket);
        assert!(vault.contains(cap_id));
    });
}

#[test]
fun adopt_currency_grant() { adopt_currency!(type_permissions::adopt_currency()) }

#[test, expected_failure(abort_code = armature::proposal::EPermissionDenied)]
fun adopt_currency_needs_vault_store() { adopt_currency!(0) }

macro fun mint_coin($bits: u64, $scope: vector<TypeName>) {
    run!<MintCoin<GLYPH>>($bits, $scope, |ou, treasury, vault, freeze, clock, _, ctx| {
        let cap = coin::create_treasury_cap_for_testing<GLYPH>(ctx);
        let cap_id = object::id(&cap);
        vault.store_cap_for_testing(cap);
        let payload = mint_coin::new<GLYPH>(cap_id, 1_000, option::none());
        let ticket = board_voting::submit_vote_execute(
            ou,
            option::none(),
            payload,
            freeze,
            clock,
            ctx,
        );
        currency_ops::execute_mint_coin<GLYPH>(vault, treasury, ticket, ctx);
        assert!(treasury.balance<GLYPH>() == 1_000);
    });
}

#[test]
fun mint_coin_grant() { mint_coin!(type_permissions::mint(), glyph_scope()) }

#[test, expected_failure(abort_code = armature::proposal::EPermissionDenied)]
fun mint_coin_needs_vault_borrow() { mint_coin!(0, glyph_scope()) }

#[test, expected_failure(abort_code = armature::proposal::EBorrowScopeDenied)]
fun mint_coin_needs_scope() { mint_coin!(type_permissions::mint(), vector[]) }

macro fun mint_allowance($bits: u64, $scope: vector<TypeName>) {
    run!<MintAllowance<GLYPH>>($bits, $scope, |ou, treasury, vault, freeze, clock, _, ctx| {
        let cap = coin::create_treasury_cap_for_testing<GLYPH>(ctx);
        let cap_id = object::id(&cap);
        vault.store_cap_for_testing(cap);
        let payload = mint_allowance::new<GLYPH>(cap_id, 1_000, option::none());
        let ticket = board_voting::submit_vote_execute(
            ou,
            option::none(),
            payload,
            freeze,
            clock,
            ctx,
        );
        currency_ops::execute_mint_allowance<GLYPH>(vault, treasury, ticket, ctx);
        assert!(treasury.balance<GLYPH>() == 1_000);
    });
}

#[test]
fun mint_allowance_grant() { mint_allowance!(type_permissions::mint(), glyph_scope()) }

#[test, expected_failure(abort_code = armature::proposal::EPermissionDenied)]
fun mint_allowance_needs_vault_borrow() { mint_allowance!(0, glyph_scope()) }

#[test, expected_failure(abort_code = armature::proposal::EBorrowScopeDenied)]
fun mint_allowance_needs_scope() { mint_allowance!(type_permissions::mint(), vector[]) }

#[test]
/// ConfigureMintAllowance writes only its own type-state: it runs with no bits.
fun configure_mint_allowance_grant() {
    run!<ConfigureMintAllowance<GLYPH>>(
        type_permissions::configure_mint_allowance(),
        vector[],
        |ou, _, _, freeze, clock, _, ctx| {
            let payload = configure_mint_allowance::new<GLYPH>(
                vector[RECIPIENT],
                vector[],
                option::some(100),
                option::some(true),
            );
            let ticket = board_voting::submit_vote_execute(
                ou,
                option::none(),
                payload,
                freeze,
                clock,
                ctx,
            );
            configure_mint_allowance::execute_configure_mint_allowance<GLYPH>(ou, ticket);
            assert!(ou.has_type_state<ConfigureMintAllowance<GLYPH>>());
        },
    );
}

macro fun burn_coin($bits: u64, $scope: vector<TypeName>) {
    run!<BurnCoin<GLYPH>>($bits, $scope, |ou, treasury, vault, freeze, clock, _, ctx| {
        let mut cap = coin::create_treasury_cap_for_testing<GLYPH>(ctx);
        let cap_id = object::id(&cap);
        treasury.deposit(coin::mint(&mut cap, 1_000, ctx), ctx);
        vault.store_cap_for_testing(cap);
        let payload = burn_coin::new<GLYPH>(cap_id, 400);
        let ticket = board_voting::submit_vote_execute(
            ou,
            option::none(),
            payload,
            freeze,
            clock,
            ctx,
        );
        currency_ops::execute_burn_coin<GLYPH>(vault, treasury, ticket, ctx);
        assert!(treasury.balance<GLYPH>() == 600);
    });
}

#[test]
fun burn_coin_grant() { burn_coin!(type_permissions::burn_coin(), glyph_scope()) }

#[test, expected_failure(abort_code = armature::proposal::EPermissionDenied)]
fun burn_coin_needs_treasury_withdraw() {
    burn_coin!(type_permissions::burn_coin() ^ permissions::treasury_withdraw(), glyph_scope())
}

#[test, expected_failure(abort_code = armature::proposal::EPermissionDenied)]
fun burn_coin_needs_vault_borrow() {
    burn_coin!(type_permissions::burn_coin() ^ permissions::vault_borrow(), glyph_scope())
}

#[test, expected_failure(abort_code = armature::proposal::EBorrowScopeDenied)]
fun burn_coin_needs_scope() { burn_coin!(type_permissions::burn_coin(), vector[]) }

macro fun return_currency_cap($bits: u64) {
    run!<ReturnCurrencyCap<GLYPH>>($bits, vector[], |ou, _, vault, freeze, clock, _, ctx| {
        let cap = coin::create_treasury_cap_for_testing<GLYPH>(ctx);
        let cap_id = object::id(&cap);
        vault.store_cap_for_testing(cap);
        let payload = return_currency_cap::new<GLYPH>(cap_id, RECIPIENT);
        let ticket = board_voting::submit_vote_execute(
            ou,
            option::none(),
            payload,
            freeze,
            clock,
            ctx,
        );
        currency_ops::execute_return_currency_cap<GLYPH>(vault, ticket);
        assert!(!vault.contains(cap_id));
        assert!(vault.ids_for_type<TreasuryCap<GLYPH>>().is_empty());
    });
}

#[test]
fun return_currency_cap_grant() { return_currency_cap!(type_permissions::return_currency_cap()) }

#[test, expected_failure(abort_code = armature::proposal::EPermissionDenied)]
fun return_currency_cap_needs_vault_extract() { return_currency_cap!(0) }

// === Upgrade ===

macro fun propose_upgrade($bits: u64, $scope: vector<TypeName>) {
    run!<ProposeUpgrade>($bits, $scope, |ou, _, vault, freeze, clock, _, ctx| {
        let package_id = object::id_from_address(@0xABC1);
        let cap = package::test_publish(package_id, ctx);
        let cap_id = object::id(&cap);
        vault.store_cap_for_testing(cap);
        let payload = propose_upgrade::new(cap_id, package_id, b"digest", 0);
        let ticket = board_voting::submit_vote_execute(
            ou,
            option::none(),
            payload,
            freeze,
            clock,
            ctx,
        );
        let (upgrade_ticket, pending) = upgrade_ops::execute_propose_upgrade(vault, ticket);
        let receipt = package::test_upgrade(upgrade_ticket);
        upgrade_ops::commit_upgrade(vault, pending, receipt);
        assert!(vault.contains(cap_id));
    });
}

#[test]
fun propose_upgrade_grant() {
    propose_upgrade!(type_permissions::propose_upgrade(), type_permissions::propose_upgrade_scope())
}

#[test, expected_failure(abort_code = armature::proposal::EPermissionDenied)]
fun propose_upgrade_needs_vault_borrow() {
    propose_upgrade!(0, type_permissions::propose_upgrade_scope())
}

#[test, expected_failure(abort_code = armature::proposal::EBorrowScopeDenied)]
fun propose_upgrade_needs_scope() {
    propose_upgrade!(type_permissions::propose_upgrade(), vector[])
}

// === SubOU control ===

macro fun transfer_cap_to_sub_ou($bits: u64) {
    run_controller!<TransferCapToSubOU>(
        $bits,
        vector[],
        |ou, vault, subou, subou_vault, freeze, clock, ctx| {
            let cap = TestCap { id: object::new(ctx) };
            let cap_id = object::id(&cap);
            vault.store_cap_for_testing(cap);
            let payload = transfer_cap_to_subou::new(cap_id, subou.id());
            let ticket = board_voting::submit_vote_execute(
                ou,
                option::none(),
                payload,
                freeze,
                clock,
                ctx,
            );
            subou_ops::execute_transfer_cap<TestCap>(vault, subou_vault, subou, ticket);
            assert!(subou_vault.contains(cap_id));
            assert!(!vault.contains(cap_id));
        },
    );
}

#[test]
fun transfer_cap_to_sub_ou_grant() {
    transfer_cap_to_sub_ou!(type_permissions::transfer_cap_to_subou())
}

#[test, expected_failure(abort_code = armature::proposal::EPermissionDenied)]
fun transfer_cap_to_sub_ou_needs_vault_extract() { transfer_cap_to_sub_ou!(0) }

macro fun reclaim_cap_from_sub_ou($bits: u64, $scope: vector<TypeName>) {
    run_controller!<ReclaimCapFromSubOU>(
        $bits,
        $scope,
        |ou, vault, subou, subou_vault, freeze, clock, ctx| {
            let cap = TestCap { id: object::new(ctx) };
            let cap_id = object::id(&cap);
            subou_vault.store_cap_for_testing(cap);
            let payload = reclaim_cap_from_subou::new(subou.id(), cap_id, control_id(vault));
            let ticket = board_voting::submit_vote_execute(
                ou,
                option::none(),
                payload,
                freeze,
                clock,
                ctx,
            );
            subou_ops::execute_reclaim_cap<TestCap>(vault, subou_vault, subou, ticket);
            assert!(vault.contains(cap_id));
            assert!(!subou_vault.contains(cap_id));
        },
    );
}

#[test]
fun reclaim_cap_from_sub_ou_grant() {
    reclaim_cap_from_sub_ou!(
        type_permissions::reclaim_cap_from_subou(),
        type_permissions::subou_control_scope(),
    )
}

#[test, expected_failure(abort_code = armature::proposal::EPermissionDenied)]
fun reclaim_cap_from_sub_ou_needs_vault_borrow() {
    reclaim_cap_from_sub_ou!(
        type_permissions::reclaim_cap_from_subou() ^ permissions::vault_borrow(),
        type_permissions::subou_control_scope(),
    )
}

#[test, expected_failure(abort_code = armature::proposal::EPermissionDenied)]
fun reclaim_cap_from_sub_ou_needs_vault_store() {
    reclaim_cap_from_sub_ou!(
        type_permissions::reclaim_cap_from_subou() ^ permissions::vault_store(),
        type_permissions::subou_control_scope(),
    )
}

#[test, expected_failure(abort_code = armature::proposal::EBorrowScopeDenied)]
fun reclaim_cap_from_sub_ou_needs_scope() {
    reclaim_cap_from_sub_ou!(type_permissions::reclaim_cap_from_subou(), vector[])
}

macro fun pause_sub_ou_execution($bits: u64, $scope: vector<TypeName>) {
    run_controller!<PauseSubOUExecution>($bits, $scope, |ou, vault, subou, _, freeze, clock, ctx| {
        let payload = pause_execution::new_pause(control_id(vault));
        let ticket = board_voting::submit_vote_execute(
            ou,
            option::none(),
            payload,
            freeze,
            clock,
            ctx,
        );
        subou_ops::execute_pause_subou_execution(vault, subou, ticket, ctx);
        assert!(subou.is_controller_paused());
    });
}

#[test]
fun pause_sub_ou_execution_grant() {
    pause_sub_ou_execution!(
        type_permissions::subou_control(),
        type_permissions::subou_control_scope(),
    )
}

#[test, expected_failure(abort_code = armature::proposal::EPermissionDenied)]
fun pause_sub_ou_execution_needs_vault_borrow() {
    pause_sub_ou_execution!(0, type_permissions::subou_control_scope())
}

#[test, expected_failure(abort_code = armature::proposal::EBorrowScopeDenied)]
fun pause_sub_ou_execution_needs_scope() {
    pause_sub_ou_execution!(type_permissions::subou_control(), vector[])
}

macro fun unpause_sub_ou_execution($bits: u64, $scope: vector<TypeName>) {
    run_controller!<UnpauseSubOUExecution>(
        $bits,
        $scope,
        |ou, vault, subou, _, freeze, clock, ctx| {
            let payload = pause_execution::new_unpause(control_id(vault));
            let ticket = board_voting::submit_vote_execute(
                ou,
                option::none(),
                payload,
                freeze,
                clock,
                ctx,
            );
            subou_ops::execute_unpause_subou_execution(vault, subou, ticket, ctx);
            assert!(!subou.is_controller_paused());
        },
    );
}

#[test]
fun unpause_sub_ou_execution_grant() {
    unpause_sub_ou_execution!(
        type_permissions::subou_control(),
        type_permissions::subou_control_scope(),
    )
}

#[test, expected_failure(abort_code = armature::proposal::EPermissionDenied)]
fun unpause_sub_ou_execution_needs_vault_borrow() {
    unpause_sub_ou_execution!(0, type_permissions::subou_control_scope())
}

#[test, expected_failure(abort_code = armature::proposal::EBorrowScopeDenied)]
fun unpause_sub_ou_execution_needs_scope() {
    unpause_sub_ou_execution!(type_permissions::subou_control(), vector[])
}

macro fun controller_batch_add_members($bits: u64, $scope: vector<TypeName>) {
    run_controller!<ControllerBatchAddMembers>(
        $bits,
        $scope,
        |ou, vault, subou, _, freeze, clock, ctx| {
            let payload = controller_batch_add_members::new(control_id(vault), vector[@0xD]);
            let ticket = board_voting::submit_vote_execute(
                ou,
                option::none(),
                payload,
                freeze,
                clock,
                ctx,
            );
            subou_ops::execute_controller_batch_add_members(vault, subou, ticket, ctx);
            assert!(subou.governance().is_board_member(@0xD));
        },
    );
}

#[test]
fun controller_batch_add_members_grant() {
    controller_batch_add_members!(
        type_permissions::subou_control(),
        type_permissions::subou_control_scope(),
    )
}

#[test, expected_failure(abort_code = armature::proposal::EPermissionDenied)]
fun controller_batch_add_members_needs_vault_borrow() {
    controller_batch_add_members!(0, type_permissions::subou_control_scope())
}

#[test, expected_failure(abort_code = armature::proposal::EBorrowScopeDenied)]
fun controller_batch_add_members_needs_scope() {
    controller_batch_add_members!(type_permissions::subou_control(), vector[])
}

macro fun controller_batch_remove_members($bits: u64, $scope: vector<TypeName>) {
    run_controller!<ControllerBatchRemoveMembers>(
        $bits,
        $scope,
        |ou, vault, subou, _, freeze, clock, ctx| {
            let payload = controller_batch_remove_members::new(
                control_id(vault),
                vector[SUBOU_MEMBER],
            );
            let ticket = board_voting::submit_vote_execute(
                ou,
                option::none(),
                payload,
                freeze,
                clock,
                ctx,
            );
            subou_ops::execute_controller_batch_remove_members(vault, subou, ticket, ctx);
            assert!(!subou.governance().is_board_member(SUBOU_MEMBER));
        },
    );
}

#[test]
fun controller_batch_remove_members_grant() {
    controller_batch_remove_members!(
        type_permissions::subou_control(),
        type_permissions::subou_control_scope(),
    )
}

#[test, expected_failure(abort_code = armature::proposal::EPermissionDenied)]
fun controller_batch_remove_members_needs_vault_borrow() {
    controller_batch_remove_members!(0, type_permissions::subou_control_scope())
}

#[test, expected_failure(abort_code = armature::proposal::EBorrowScopeDenied)]
fun controller_batch_remove_members_needs_scope() {
    controller_batch_remove_members!(type_permissions::subou_control(), vector[])
}

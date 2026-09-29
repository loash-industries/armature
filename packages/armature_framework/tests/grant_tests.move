/// Positive authorization suite, the counterpart of `gate_tests`: every
/// framework mutator that acts on an ExecutionRequest succeeds for a request
/// carrying exactly the bits it documents and nothing else (plus the borrow
/// scope, for the borrow paths). With `gate_tests` this pins each mutator to
/// its bit: that bit is necessary (`gate_tests`) and sufficient (here).
/// `scripts/check_request_gates.py` requires a test here for every gated
/// function, named with the function's name as its prefix.
#[test_only]
module armature::grant_tests;

use armature::add_member::AddMember;
use armature::capability_vault::{CapabilityVault, SubOUControl};
use armature::charter::Charter;
use armature::controller;
use armature::emergency::{EmergencyFreeze, FreezeAdminCap};
use armature::governance;
use armature::ou::{Self, OU};
use armature::permissions;
use armature::proposal::{Self, ExecutionRequest};
use armature::treasury_vault::TreasuryVault;
use armature::tribe;
use std::string;
use std::type_name;
use sui::clock;
use sui::coin;
use sui::sui::SUI;
use sui::test_scenario::{Self, Scenario};

const CREATOR: address = @0xA;
const OTHER: address = @0xB;

/// The request's payload type. Its bits come from the request, not a slot.
public struct Probe has drop, store {}

public struct TestCap has key, store { id: UID }

/// A request for `ou` carrying exactly `bits`.
fun only(ou: &OU, bits: u64): ExecutionRequest<Probe> {
    proposal::new_permitted_request_for_testing<Probe>(
        ou.id(),
        object::id_from_address(@0x1),
        bits,
    )
}

/// A request carrying exactly VAULT_BORROW, scoped to `TestCap`.
fun borrow_only(ou: &OU): ExecutionRequest<Probe> {
    proposal::with_borrow_scope_for_testing(
        only(ou, permissions::vault_borrow()),
        vector[type_name::with_defining_ids<TestCap>()],
    )
}

fun privileged(ou: &OU): ExecutionRequest<Probe> {
    proposal::new_privileged_request_for_testing<Probe>(ou.id(), object::id_from_address(@0x1))
}

fun done(r: ExecutionRequest<Probe>) {
    proposal::consume_execution_request_for_testing(r);
}

/// Store a fresh TestCap with a VAULT_STORE-only request; return its ID.
fun stored_cap(ou: &OU, vault: &mut CapabilityVault, ctx: &mut TxContext): ID {
    let cap = TestCap { id: object::new(ctx) };
    let cap_id = object::id(&cap);
    let r = only(ou, permissions::vault_store());
    vault.store_cap(cap, &r);
    done(r);
    cap_id
}

/// Create an OU with board [CREATOR, OTHER] and start the next transaction.
fun create_ou(scenario: &mut Scenario) {
    scenario.next_tx(CREATOR);
    let init = governance::init_board(vector[CREATOR, OTHER]);
    ou::create(&init, string::utf8(b"OU"), string::utf8(b""), scenario.ctx());
    scenario.next_tx(CREATOR);
}

/// Create an OU, hand its shared objects to `$f`, then return them.
macro fun run(
    $f: |
        &mut OU,
        &mut TreasuryVault,
        &mut CapabilityVault,
        &mut Charter,
        &mut EmergencyFreeze,
        &mut TxContext,
    |,
) {
    let mut scenario = test_scenario::begin(CREATOR);
    create_ou(&mut scenario);
    let mut ou = scenario.take_shared<OU>();
    let mut treasury = scenario.take_shared_by_id<TreasuryVault>(ou.treasury_id());
    let mut vault = scenario.take_shared_by_id<CapabilityVault>(ou.capability_vault_id());
    let mut charter = scenario.take_shared_by_id<Charter>(ou.charter_id());
    let mut freeze = scenario.take_shared_by_id<EmergencyFreeze>(ou.emergency_freeze_id());
    $f(&mut ou, &mut treasury, &mut vault, &mut charter, &mut freeze, scenario.ctx());
    test_scenario::return_shared(ou);
    test_scenario::return_shared(treasury);
    test_scenario::return_shared(vault);
    test_scenario::return_shared(charter);
    test_scenario::return_shared(freeze);
    scenario.end();
}

// === ou: board ===

#[test]
fun set_board_governance_with_board_set() {
    run!(|ou, _, _, _, _, _| {
        let r = only(ou, permissions::board_set());
        ou.set_board_governance(vector[@0xC], vector[OTHER], &r);
        done(r);
        assert!(ou.governance().is_board_member(@0xC));
        assert!(!ou.governance().is_board_member(OTHER));
    });
}

#[test]
fun add_board_member_governance_with_board_add() {
    run!(|ou, _, _, _, _, _| {
        let r = only(ou, permissions::board_add());
        ou.add_board_member_governance(@0xC, &r);
        done(r);
        assert!(ou.governance().is_board_member(@0xC));
    });
}

#[test]
fun add_board_members_governance_with_board_add() {
    run!(|ou, _, _, _, _, _| {
        let r = only(ou, permissions::board_add());
        ou.add_board_members_governance(vector[@0xC, @0xD], &r);
        done(r);
        assert!(ou.governance().is_board_member(@0xC));
        assert!(ou.governance().is_board_member(@0xD));
    });
}

#[test]
fun remove_board_member_governance_with_board_remove() {
    run!(|ou, _, _, _, _, _| {
        let r = only(ou, permissions::board_remove());
        ou.remove_board_member_governance(OTHER, &r);
        done(r);
        assert!(!ou.governance().is_board_member(OTHER));
    });
}

#[test]
fun remove_board_members_governance_with_board_remove() {
    run!(|ou, _, _, _, _, _| {
        let r = only(ou, permissions::board_remove());
        ou.remove_board_members_governance(vector[OTHER], &r);
        done(r);
        assert!(!ou.governance().is_board_member(OTHER));
    });
}

// === ou: type registry ===

#[test]
fun enable_proposal_type_with_type_admin() {
    run!(|ou, _, _, _, _, _| {
        let r = only(ou, permissions::type_admin());
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        ou.enable_proposal_type<Probe, Probe>(b"Probe".to_ascii_string(), config, &r);
        done(r);
        assert!(ou.is_type_enabled<Probe>());
    });
}

#[test]
fun disable_proposal_type_with_type_admin() {
    run!(|ou, _, _, _, _, _| {
        let r = only(ou, permissions::type_admin());
        ou.disable_proposal_type(type_name::with_defining_ids<AddMember>(), &r);
        done(r);
        assert!(!ou.is_type_enabled<AddMember>());
    });
}

#[test]
fun update_proposal_config_with_type_admin() {
    run!(|ou, _, _, _, _, _| {
        let r = only(ou, permissions::type_admin());
        let name = type_name::with_defining_ids<AddMember>();
        let old = ou.type_config_by_name(&name);
        let config = proposal::new_config(
            old.quorum(),
            old.approval_threshold(),
            old.propose_threshold(),
            old.expiry_ms() * 2,
            old.execution_delay_ms(),
            old.cooldown_ms(),
        )
            .with_composable_allowed(old.composable_allowed())
            .with_permissions(old.permissions())
            .with_borrow_scope(old.borrow_scope());
        ou.update_proposal_config(name, config, &r);
        done(r);
        assert!(ou.type_config_by_name(&name).expiry_ms() == old.expiry_ms() * 2);
    });
}

// === ou: lifecycle ===

#[test]
fun set_execution_paused_with_pause() {
    run!(|ou, _, _, _, _, _| {
        let r = only(ou, permissions::pause());
        ou.set_execution_paused(true, &r);
        done(r);
        assert!(ou.is_execution_paused());
    });
}

#[test]
fun set_migrating_with_migrate() {
    run!(|ou, _, _, _, _, _| {
        let r = only(ou, permissions::migrate());
        ou.set_migrating(object::id_from_address(@0x2), &r);
        done(r);
        assert!(ou.status().is_migrating());
    });
}

#[test]
/// No bit grants the controller-only mutators; a privileged request does.
fun set_controller_paused_with_privileged_request() {
    run!(|ou, _, _, _, _, _| {
        let r = privileged(ou);
        ou.set_controller_paused(true, &r);
        done(r);
        assert!(ou.is_controller_paused());
    });
}

#[test]
fun clear_controller_with_privileged_request() {
    run!(|ou, _, _, _, _, _| {
        ou.set_controller_for_testing(object::id_from_address(@0x3));
        let r = privileged(ou);
        ou.clear_controller(&r);
        done(r);
        assert!(ou.controller_cap_id().is_none());
    });
}

// === charter ===

#[test]
fun update_metadata_with_metadata() {
    run!(|ou, _, _, charter, _, _| {
        let r = only(ou, permissions::metadata());
        charter.update_metadata(string::utf8(b"ipfs://x"), &r);
        done(r);
        assert!(charter.metadata_uri() == &string::utf8(b"ipfs://x"));
    });
}

// === emergency ===

#[test]
fun governance_unfreeze_type_with_freeze() {
    let mut scenario = test_scenario::begin(CREATOR);
    create_ou(&mut scenario);
    let ou = scenario.take_shared<OU>();
    let mut freeze = scenario.take_shared_by_id<EmergencyFreeze>(ou.emergency_freeze_id());
    let cap = scenario.take_from_sender<FreezeAdminCap>();
    let clock = clock::create_for_testing(scenario.ctx());
    freeze.freeze_type<Probe>(&cap, &clock);
    assert!(freeze.is_frozen<Probe>(&clock));

    let r = only(&ou, permissions::emergency_freeze());
    freeze.governance_unfreeze_type(type_name::with_defining_ids<Probe>(), &r);
    done(r);
    assert!(!freeze.is_frozen<Probe>(&clock));

    clock.destroy_for_testing();
    scenario.return_to_sender(cap);
    test_scenario::return_shared(freeze);
    test_scenario::return_shared(ou);
    scenario.end();
}

#[test]
fun update_freeze_duration_with_freeze() {
    run!(|ou, _, _, _, freeze, _| {
        let r = only(ou, permissions::emergency_freeze());
        freeze.update_freeze_duration(1, &r);
        done(r);
        assert!(freeze.max_freeze_duration_ms() == 1);
    });
}

#[test]
fun unfreeze_all_with_freeze() {
    let mut scenario = test_scenario::begin(CREATOR);
    create_ou(&mut scenario);
    let ou = scenario.take_shared<OU>();
    let mut freeze = scenario.take_shared_by_id<EmergencyFreeze>(ou.emergency_freeze_id());
    let cap = scenario.take_from_sender<FreezeAdminCap>();
    let clock = clock::create_for_testing(scenario.ctx());
    freeze.freeze_type<Probe>(&cap, &clock);

    let r = only(&ou, permissions::emergency_freeze());
    freeze.unfreeze_all(&r);
    done(r);
    assert!(!freeze.is_frozen<Probe>(&clock));

    clock.destroy_for_testing();
    scenario.return_to_sender(cap);
    test_scenario::return_shared(freeze);
    test_scenario::return_shared(ou);
    scenario.end();
}

#[test]
fun add_freeze_exempt_type_with_freeze() {
    run!(|ou, _, _, _, freeze, _| {
        let name = type_name::with_defining_ids<Probe>();
        let r = only(ou, permissions::emergency_freeze());
        freeze.add_freeze_exempt_type(name, &r);
        done(r);
        assert!(freeze.is_exempt_by_name(&name));
    });
}

#[test]
fun remove_freeze_exempt_type_with_freeze() {
    run!(|ou, _, _, _, freeze, _| {
        let name = type_name::with_defining_ids<Probe>();
        let r = only(ou, permissions::emergency_freeze());
        freeze.add_freeze_exempt_type(name, &r);
        freeze.remove_freeze_exempt_type(name, &r);
        done(r);
        assert!(!freeze.is_exempt_by_name(&name));
    });
}

// === treasury_vault ===

#[test]
fun withdraw_with_treasury_withdraw() {
    run!(|ou, treasury, _, _, _, ctx| {
        treasury.deposit(coin::mint_for_testing<SUI>(100, ctx), ctx);
        let r = only(ou, permissions::treasury_withdraw());
        let coin = treasury.withdraw<SUI, Probe>(40, &r, ctx);
        done(r);
        assert!(coin.value() == 40);
        assert!(treasury.balance<SUI>() == 60);
        coin.burn_for_testing();
    });
}

// === capability_vault ===

#[test]
fun store_cap_with_vault_store() {
    run!(|ou, _, vault, _, _, ctx| {
        let cap_id = stored_cap(ou, vault, ctx);
        assert!(vault.contains(cap_id));
    });
}

#[test]
fun receive_cap_with_vault_extract() {
    run!(|ou, _, vault, _, _, ctx| {
        let cap = TestCap { id: object::new(ctx) };
        let cap_id = object::id(&cap);
        let r = only(ou, permissions::vault_extract());
        vault.receive_cap(cap, &r);
        done(r);
        assert!(vault.contains(cap_id));
    });
}

#[test]
fun receive_cap_authorized_with_extract_and_store() {
    run!(|ou, _, vault, _, _, ctx| {
        let cap = TestCap { id: object::new(ctx) };
        let cap_id = object::id(&cap);
        let send = only(ou, permissions::vault_extract());
        let recv = only(ou, permissions::vault_store());
        vault.receive_cap_authorized(cap, &send, &recv);
        done(send);
        done(recv);
        assert!(vault.contains(cap_id));
    });
}

#[test]
fun receive_cap_from_controller_with_vault_extract() {
    let mut scenario = test_scenario::begin(CREATOR);
    create_ou(&mut scenario);
    let parent = scenario.take_shared<OU>();
    let mut parent_vault = scenario.take_shared_by_id<CapabilityVault>(
        parent.capability_vault_id(),
    );
    let wire = only(&parent, permissions::vault_store() | permissions::vault_extract());
    let subou_id = tribe::create_wired_subou(
        vector[CREATOR],
        string::utf8(b"Sub"),
        string::utf8(b""),
        CREATOR,
        &mut parent_vault,
        &wire,
        vector[],
        scenario.ctx(),
    );
    done(wire);

    scenario.next_tx(CREATOR);
    let subou = scenario.take_shared_by_id<OU>(subou_id);
    let mut subou_vault = scenario.take_shared_by_id<CapabilityVault>(
        subou.capability_vault_id(),
    );
    let cap = TestCap { id: object::new(scenario.ctx()) };
    let cap_id = object::id(&cap);
    let r = only(&parent, permissions::vault_extract());
    controller::receive_cap_from_controller(&mut subou_vault, cap, &subou, &parent_vault, &r);
    done(r);
    assert!(subou_vault.contains(cap_id));

    test_scenario::return_shared(subou_vault);
    test_scenario::return_shared(subou);
    test_scenario::return_shared(parent_vault);
    test_scenario::return_shared(parent);
    scenario.end();
}

#[test]
fun borrow_cap_with_vault_borrow_and_scope() {
    run!(|ou, _, vault, _, _, ctx| {
        let cap_id = stored_cap(ou, vault, ctx);
        let r = borrow_only(ou);
        let cap: &TestCap = vault.borrow_cap(cap_id, &r);
        assert!(object::id(cap) == cap_id);
        done(r);
    });
}

#[test]
fun borrow_cap_mut_with_vault_borrow_and_scope() {
    run!(|ou, _, vault, _, _, ctx| {
        let cap_id = stored_cap(ou, vault, ctx);
        let r = borrow_only(ou);
        let cap: &mut TestCap = vault.borrow_cap_mut(cap_id, &r);
        assert!(object::id(cap) == cap_id);
        done(r);
    });
}

#[test]
fun loan_cap_with_vault_borrow_and_scope() {
    run!(|ou, _, vault, _, _, ctx| {
        let cap_id = stored_cap(ou, vault, ctx);
        let r = borrow_only(ou);
        let (cap, loan) = vault.loan_cap<TestCap, Probe>(cap_id, &r);
        done(r);
        assert!(object::id(&cap) == cap_id);
        vault.return_cap(cap, loan);
        assert!(vault.contains(cap_id));
    });
}

#[test]
fun extract_cap_with_vault_extract() {
    run!(|ou, _, vault, _, _, ctx| {
        let cap_id = stored_cap(ou, vault, ctx);
        let r = only(ou, permissions::vault_extract());
        let cap: TestCap = vault.extract_cap(cap_id, &r);
        done(r);
        assert!(!vault.contains(cap_id));
        transfer::public_transfer(cap, CREATOR);
    });
}

#[test]
fun create_subou_control_with_vault_extract() {
    run!(|ou, _, vault, _, _, ctx| {
        let r = only(ou, permissions::vault_extract());
        let control_id = vault.create_subou_control(object::id_from_address(@0x5), &r, ctx);
        done(r);
        assert!(vault.contains(control_id));
    });
}

#[test]
fun destroy_subou_control_with_vault_extract() {
    run!(|ou, _, vault, _, _, ctx| {
        let r = only(ou, permissions::vault_extract());
        let control_id = vault.create_subou_control(object::id_from_address(@0x5), &r, ctx);
        vault.destroy_subou_control(control_id, &r);
        done(r);
        assert!(!vault.contains(control_id));
    });
}

// === tribe ===

#[test]
fun create_wired_subou_with_vault_store_and_extract() {
    run!(|ou, _, vault, _, _, ctx| {
        let r = only(ou, permissions::vault_store() | permissions::vault_extract());
        tribe::create_wired_subou(
            vector[CREATOR],
            string::utf8(b"Sub"),
            string::utf8(b""),
            CREATOR,
            vault,
            &r,
            vector[],
            ctx,
        );
        done(r);
        assert!(vault.ids_for_type<SubOUControl>().length() == 1);
    });
}

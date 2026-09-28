/// End-to-end lifecycle of a proposal type defined outside the armature
/// packages: enabled by a board vote through the production handlers, executed
/// on the two-PTB, atomic and bypass paths, frozen by `TypeName`, and unfrozen
/// by an `UnfreezeProposalType` vote. No test seams touch the DAO's registry.
#[test_only]
module armature_external_type_tests::external_type_lifecycle_tests;

use armature::admin_ops;
use armature::board_voting;
use armature::capability_vault::CapabilityVault;
use armature::dao::{Self, DAO};
use armature::emergency::{Self, EmergencyFreeze, FreezeAdminCap};
use armature::enable_bypass_type::EnableBypassType;
use armature::enable_proposal_type::{Self, EnableProposalType};
use armature::external_execution;
use armature::freeze_ops;
use armature::governance;
use armature::proposal::{Self, ExecutionRequest, ExternalExecutionCap, Proposal};
use armature::treasury_vault::TreasuryVault;
use armature::unfreeze_proposal_type::{Self, UnfreezeProposalType};
use armature_external_type_tests::rebalance::{Self, Rebalance};
use std::string;
use std::type_name;
use sui::clock::{Self, Clock};
use sui::sui::SUI;
use sui::test_scenario::{Self as ts, Scenario};

const CREATOR: address = @0xA;

/// Phantom markers for two instantiations of the third-party payload.
public struct CredA {}
public struct CredB {}

// === Setup ===

/// Single-member board, so every proposal passes on the creator's vote.
fun create_dao(scenario: &mut Scenario) {
    scenario.next_tx(CREATOR);
    let init = governance::init_board(vector[CREATOR]);
    dao::create(
        &init,
        string::utf8(b"Test DAO"),
        string::utf8(b"https://example.com/logo.png"),
        scenario.ctx(),
    );
}

fun rebalance_config(): proposal::ProposalConfig {
    proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0)
}

fun tick(clock: &mut Clock) {
    let now = clock.timestamp_ms();
    clock.set_for_testing(now + 1_000);
}

/// Submit `payload` as a two-PTB proposal and vote it through.
fun submit_and_pass<P: store + drop>(scenario: &mut Scenario, clock: &mut Clock, payload: P) {
    tick(clock);
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        board_voting::submit_proposal(&dao, option::none(), payload, clock, scenario.ctx());
        ts::return_shared(dao);
    };

    tick(clock);
    scenario.next_tx(CREATOR);
    {
        let mut prop = scenario.take_shared<Proposal<P>>();
        let dao = scenario.take_shared<DAO>();
        board_voting::vote(&mut prop, &dao, true, clock, scenario.ctx());
        ts::return_shared(dao);
        ts::return_shared(prop);
    };
}

// === Governance flows (production handlers) ===

/// Enable `Rebalance<T>` via an EnableProposalType vote and
/// `admin_ops::execute_enable_proposal_type`.
fun enable_via_vote<T>(scenario: &mut Scenario, clock: &mut Clock, key: vector<u8>) {
    let payload = enable_proposal_type::new(
        key.to_ascii_string(),
        type_name::with_defining_ids<Rebalance<T>>(),
        rebalance_config(),
    );
    submit_and_pass(scenario, clock, payload);

    tick(clock);
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let prop = scenario.take_shared<Proposal<EnableProposalType>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        let ticket = board_voting::ticket_from_vote(&mut dao, prop, &freeze, clock, scenario.ctx());
        admin_ops::execute_enable_proposal_type<Rebalance<T>>(&mut dao, ticket);
        ts::return_shared(freeze);
        ts::return_shared(dao);
    };
}

/// Enable `Rebalance<T>` as a bypass type via an EnableBypassType vote.
/// Returns the ID of the ExternalExecutionCap deposited in the vault.
fun enable_bypass_via_vote<T>(scenario: &mut Scenario, clock: &mut Clock, key: vector<u8>): ID {
    let payload = external_execution::new_enable_bypass_type(
        key.to_ascii_string(),
        type_name::with_defining_ids<Rebalance<T>>(),
        rebalance_config(),
    );
    submit_and_pass(scenario, clock, payload);

    tick(clock);
    scenario.next_tx(CREATOR);
    let cap_id;
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut vault = scenario.take_shared<CapabilityVault>();
        let prop = scenario.take_shared<Proposal<EnableBypassType>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        let ticket = board_voting::ticket_from_vote(&mut dao, prop, &freeze, clock, scenario.ctx());
        external_execution::execute_enable_bypass_type<Rebalance<T>>(
            &mut dao,
            &mut vault,
            ticket,
            scenario.ctx(),
        );
        cap_id = vault.ids_for_type<ExternalExecutionCap<Rebalance<T>>>()[0];
        ts::return_shared(freeze);
        ts::return_shared(vault);
        ts::return_shared(dao);
    };
    cap_id
}

/// Unfreeze `Rebalance<T>` via an UnfreezeProposalType vote and
/// `freeze_ops::execute_unfreeze_proposal_type`.
fun unfreeze_via_vote<T>(scenario: &mut Scenario, clock: &mut Clock) {
    submit_and_pass(scenario, clock, unfreeze_proposal_type::new<Rebalance<T>>());

    tick(clock);
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let prop = scenario.take_shared<Proposal<UnfreezeProposalType>>();
        let mut freeze = scenario.take_shared<EmergencyFreeze>();
        let ticket = board_voting::ticket_from_vote(&mut dao, prop, &freeze, clock, scenario.ctx());
        freeze_ops::execute_unfreeze_proposal_type(&mut freeze, ticket);
        ts::return_shared(freeze);
        ts::return_shared(dao);
    };
}

/// Freeze `Rebalance<T>` with the FreezeAdminCap.
fun admin_freeze<T>(scenario: &mut Scenario, clock: &mut Clock) {
    tick(clock);
    scenario.next_tx(CREATOR);
    let mut freeze = scenario.take_shared<EmergencyFreeze>();
    let cap = scenario.take_from_sender<FreezeAdminCap>();
    freeze.freeze_type<Rebalance<T>>(&cap, clock);
    scenario.return_to_sender(cap);
    ts::return_shared(freeze);
}

// === Execution paths (read-only DAO, as on the trading path) ===

fun execute_two_ptb<T>(scenario: &mut Scenario, clock: &mut Clock) {
    submit_and_pass(scenario, clock, rebalance::new<T>(10));

    tick(clock);
    scenario.next_tx(CREATOR);
    let dao = scenario.take_shared<DAO>();
    let prop = scenario.take_shared<Proposal<Rebalance<T>>>();
    let freeze = scenario.take_shared<EmergencyFreeze>();
    let ticket = board_voting::ticket_from_vote_readonly(
        &dao,
        prop,
        &freeze,
        clock,
        scenario.ctx(),
    );
    rebalance::execute_rebalance(&dao, ticket);
    ts::return_shared(freeze);
    ts::return_shared(dao);
}

fun execute_atomic<T>(scenario: &mut Scenario, clock: &mut Clock) {
    tick(clock);
    scenario.next_tx(CREATOR);
    let dao = scenario.take_shared<DAO>();
    let freeze = scenario.take_shared<EmergencyFreeze>();
    let ticket = board_voting::submit_vote_execute_readonly(
        &dao,
        option::none(),
        rebalance::new<T>(20),
        &freeze,
        clock,
        scenario.ctx(),
    );
    rebalance::execute_rebalance(&dao, ticket);
    ts::return_shared(freeze);
    ts::return_shared(dao);
}

fun execute_bypass<T>(scenario: &mut Scenario, clock: &mut Clock, cap_id: ID) {
    tick(clock);
    scenario.next_tx(CREATOR);
    let dao = scenario.take_shared<DAO>();
    let vault = scenario.take_shared<CapabilityVault>();
    let freeze = scenario.take_shared<EmergencyFreeze>();
    let cap: &ExternalExecutionCap<Rebalance<T>> = vault.borrow_external_cap(dao.id(), cap_id);
    let ticket = rebalance::submit_bypass<T>(cap, &dao, &freeze, 30, clock, scenario.ctx());
    rebalance::execute_rebalance(&dao, ticket);
    ts::return_shared(freeze);
    ts::return_shared(vault);
    ts::return_shared(dao);
}

fun begin(): (Scenario, Clock) {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000);
    create_dao(&mut scenario);
    (scenario, clock)
}

fun end(scenario: Scenario, clock: Clock) {
    clock.destroy_for_testing();
    scenario.end();
}

// === Tests ===

#[test]
/// A governance-enabled third-party type executes on the two-PTB and atomic
/// paths; a bypass-enabled one executes through its ExternalExecutionCap.
fun enabled_type_executes_on_every_path() {
    let (mut scenario, mut clock) = begin();
    enable_via_vote<CredA>(&mut scenario, &mut clock, b"RebalanceCredA");
    let cap_id = enable_bypass_via_vote<CredB>(&mut scenario, &mut clock, b"RebalanceCredB");

    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        assert!(dao.is_type_enabled<Rebalance<CredA>>());
        assert!(dao.is_type_enabled<Rebalance<CredB>>());
        ts::return_shared(dao);
    };

    execute_two_ptb<CredA>(&mut scenario, &mut clock);
    execute_atomic<CredA>(&mut scenario, &mut clock);
    execute_bypass<CredB>(&mut scenario, &mut clock, cap_id);
    end(scenario, clock);
}

#[test, expected_failure(abort_code = emergency::EFrozen)]
fun frozen_type_blocks_two_ptb() {
    let (mut scenario, mut clock) = begin();
    enable_via_vote<CredA>(&mut scenario, &mut clock, b"RebalanceCredA");
    admin_freeze<CredA>(&mut scenario, &mut clock);
    execute_two_ptb<CredA>(&mut scenario, &mut clock);
    end(scenario, clock);
}

#[test, expected_failure(abort_code = emergency::EFrozen)]
fun frozen_type_blocks_atomic() {
    let (mut scenario, mut clock) = begin();
    enable_via_vote<CredA>(&mut scenario, &mut clock, b"RebalanceCredA");
    admin_freeze<CredA>(&mut scenario, &mut clock);
    execute_atomic<CredA>(&mut scenario, &mut clock);
    end(scenario, clock);
}

#[test, expected_failure(abort_code = emergency::EFrozen)]
fun frozen_type_blocks_bypass() {
    let (mut scenario, mut clock) = begin();
    let cap_id = enable_bypass_via_vote<CredA>(&mut scenario, &mut clock, b"RebalanceCredA");
    admin_freeze<CredA>(&mut scenario, &mut clock);
    execute_bypass<CredA>(&mut scenario, &mut clock, cap_id);
    end(scenario, clock);
}

#[test]
/// Freezing `Rebalance<CredA>` leaves `Rebalance<CredB>` executable.
fun freeze_leaves_other_instantiation_executable() {
    let (mut scenario, mut clock) = begin();
    enable_via_vote<CredA>(&mut scenario, &mut clock, b"RebalanceCredA");
    enable_via_vote<CredB>(&mut scenario, &mut clock, b"RebalanceCredB");
    admin_freeze<CredA>(&mut scenario, &mut clock);

    execute_atomic<CredB>(&mut scenario, &mut clock);
    execute_two_ptb<CredB>(&mut scenario, &mut clock);
    end(scenario, clock);
}

#[test]
/// A board vote on `UnfreezeProposalType::new<Rebalance<CredA>>()` lifts the
/// admin freeze and the type executes again.
fun governance_unfreeze_restores_execution() {
    let (mut scenario, mut clock) = begin();
    enable_via_vote<CredA>(&mut scenario, &mut clock, b"RebalanceCredA");
    admin_freeze<CredA>(&mut scenario, &mut clock);
    unfreeze_via_vote<CredA>(&mut scenario, &mut clock);

    scenario.next_tx(CREATOR);
    {
        let freeze = scenario.take_shared<EmergencyFreeze>();
        assert!(!freeze.is_frozen<Rebalance<CredA>>(&clock));
        ts::return_shared(freeze);
    };

    execute_atomic<CredA>(&mut scenario, &mut clock);
    execute_two_ptb<CredA>(&mut scenario, &mut clock);
    end(scenario, clock);
}

// === Permission denials (ROAD-39, ARMATURE-32) ===
//
// A ticket for Rebalance<CredB>, a type granted no bits, must not reach any
// DAO-wide mutator. Before ROAD-39 its request could lift an admin freeze on
// Rebalance<CredA>, drain the treasury or add a board member mid-PTB.
//
// A ticket holder can no longer reach the request at all: ticket_request needs
// Permit<Rebalance<CredB>>, which only the rebalance module can mint. These
// tests take the request through rebalance::request_for_testing, standing in
// for a buggy handler in that module, and check the permission bits still stop it.

/// Mint a Rebalance<CredB> ticket (bypass path when `bypass`, else a
/// single-vote atomic execution) and hand its request to `$f`, which must abort.
macro fun with_rebalance_request(
    $bypass: bool,
    $f: |
        &mut DAO,
        &mut EmergencyFreeze,
        &mut TreasuryVault,
        &ExecutionRequest<Rebalance<CredB>>,
        &mut TxContext,
    |,
) {
    let (mut scenario, mut clock) = begin();
    admin_freeze<CredA>(&mut scenario, &mut clock);
    let cap_id = if ($bypass) {
        enable_bypass_via_vote<CredB>(&mut scenario, &mut clock, b"RebalanceB")
    } else {
        enable_via_vote<CredB>(&mut scenario, &mut clock, b"RebalanceB");
        object::id_from_address(@0x0)
    };

    tick(&mut clock);
    scenario.next_tx(CREATOR);
    let mut dao = scenario.take_shared<DAO>();
    let vault = scenario.take_shared<CapabilityVault>();
    let mut freeze = scenario.take_shared<EmergencyFreeze>();
    let mut treasury = scenario.take_shared<TreasuryVault>();
    let ticket = if ($bypass) {
        let cap: &ExternalExecutionCap<Rebalance<CredB>> = vault.borrow_external_cap(
            dao.id(),
            cap_id,
        );
        rebalance::submit_bypass<CredB>(cap, &dao, &freeze, 1, &clock, scenario.ctx())
    } else {
        board_voting::submit_vote_execute_readonly(
            &dao,
            option::none(),
            rebalance::new<CredB>(1),
            &freeze,
            &clock,
            scenario.ctx(),
        )
    };
    $f(
        &mut dao,
        &mut freeze,
        &mut treasury,
        rebalance::request_for_testing(&ticket),
        scenario.ctx(),
    );
    abort 0
}

#[test, expected_failure(abort_code = proposal::EPermissionDenied)]
/// The confirmed attack: a Rebalance<CredB> bypass ticket lifting an admin
/// freeze on Rebalance<CredA>.
fun bypass_ticket_cannot_unfreeze_other_type() {
    with_rebalance_request!(true, |_, freeze, _, req, _| {
        freeze.unfreeze_all(req);
    });
}

#[test, expected_failure(abort_code = proposal::EPermissionDenied)]
fun bypass_ticket_cannot_withdraw_from_treasury() {
    with_rebalance_request!(true, |_, _, treasury, req, ctx| {
        let coin = treasury.withdraw<SUI, Rebalance<CredB>>(1, req, ctx);
        abort 0
    });
}

#[test, expected_failure(abort_code = proposal::EPermissionDenied)]
fun bypass_ticket_cannot_add_board_member() {
    with_rebalance_request!(true, |dao, _, _, req, _| {
        dao.add_board_member_governance(@0xBAD, req);
    });
}

#[test, expected_failure(abort_code = proposal::EPermissionDenied)]
/// A single member's atomic vote on a low-threshold type carries no authority
/// beyond its own type either.
fun atomic_ticket_cannot_migrate_dao() {
    with_rebalance_request!(false, |dao, _, _, req, _| {
        dao.set_migrating(object::id_from_address(@0x2), req);
    });
}

#[test, expected_failure(abort_code = proposal::EPermissionDenied)]
fun atomic_ticket_cannot_unfreeze_other_type() {
    with_rebalance_request!(false, |_, freeze, _, req, _| {
        freeze.governance_unfreeze_type(type_name::with_defining_ids<Rebalance<CredA>>(), req);
    });
}

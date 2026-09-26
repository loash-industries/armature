#[test_only]
module armature::external_execution_tests;

use armature::board_voting;
use armature::capability_vault::CapabilityVault;
use armature::dao::{Self, DAO};
use armature::disable_bypass_type::DisableBypassType;
use armature::emergency::EmergencyFreeze;
use armature::enable_bypass_type::EnableBypassType;
use armature::external_execution;
use armature::governance;
use armature::permissions;
use armature::proposal::{
    Self,
    ExternalExecutionCap,
    Proposal,
    ProposalCreated,
    ProposalExecuted,
    ProposalPayloadCreated,
};
use std::internal;
use std::string;
use std::type_name;
use sui::clock;
use sui::event;
use sui::test_scenario;

const CREATOR: address = @0xA;

/// Stand-in payload type for external-execution tests.
public struct DummyBypass has drop, store { x: u64 }

/// Second payload type for verifying type-slot mismatches.
public struct OtherBypass has drop, store {}

fun create_test_dao(scenario: &mut test_scenario::Scenario) {
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR]);
        dao::create(
            &init,
            string::utf8(b"Test DAO"),
            string::utf8(b"https://example.com/logo.png"),
            scenario.ctx(),
        );
    };
}

/// Enable a custom proposal type on the DAO without going through governance.
/// Gives `DummyBypass` a slot so ticket_from_cap recognizes it.
fun enable_dummy_type(scenario: &mut test_scenario::Scenario) {
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        dao.test_enable_type<DummyBypass>(b"DummyBypass".to_ascii_string(), config);
        test_scenario::return_shared(dao);
    };
}

/// Run a full EnableBypassType lifecycle: submit, vote (100% from a single
/// CREATOR-only board), execute. Returns the cap_id deposited in the vault.
fun run_enable_bypass<NewType: store>(
    scenario: &mut test_scenario::Scenario,
    clock: &mut clock::Clock,
    type_key: vector<u8>,
    ts_submit: u64,
    ts_vote: u64,
    ts_exec: u64,
): ID {
    clock.set_for_testing(ts_submit);
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let config = proposal::new_config(5_000, 8_000, 0, 604_800_000, 0, 0);
        let payload = external_execution::new_enable_bypass_type(
            type_key.to_ascii_string(),
            type_name::with_defining_ids<NewType>(),
            config,
        );
        board_voting::submit_proposal(
            &dao,
            option::none(),
            payload,
            clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    clock.set_for_testing(ts_vote);
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<EnableBypassType>>();
        let vote_dao = scenario.take_shared_by_id<DAO>(proposal.dao_id());
        board_voting::vote(&mut proposal, &vote_dao, true, clock, scenario.ctx());
        test_scenario::return_shared(vote_dao);
        test_scenario::return_shared(proposal);
    };

    clock.set_for_testing(ts_exec);
    let mut cap_id_opt = option::none<ID>();
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut vault = scenario.take_shared<CapabilityVault>();
        let proposal = scenario.take_shared<Proposal<EnableBypassType>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            proposal,
            &freeze,
            clock,
            scenario.ctx(),
        );
        external_execution::execute_enable_bypass_type<NewType>(
            &mut dao,
            &mut vault,
            ticket,
            scenario.ctx(),
        );

        let ids = vault.ids_for_type<ExternalExecutionCap<NewType>>();
        cap_id_opt.fill(ids[0]);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(dao);
    };

    cap_id_opt.destroy_some()
}

#[test]
/// Happy path: a valid cap mints an ExecutionRequest<DummyBypass> for the same DAO.
fun external_executed_create_happy_path() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_test_dao(&mut scenario);
    enable_dummy_type(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(1000);

        let cap = proposal::new_external_execution_cap_for_testing<DummyBypass>(
            dao.id(),
            scenario.ctx(),
        );

        let ticket = external_execution::ticket_from_cap<DummyBypass>(
            &cap,
            &mut dao,
            &freeze,
            option::none(),
            DummyBypass { x: 42 },
            internal::permit(),
            &clock,
            scenario.ctx(),
        );

        // Request is for this DAO
        assert!(ticket.ticket_dao_id() == dao.id());
        // record_execution updated
        assert!(dao.last_executed_ms<DummyBypass>().is_some());

        ticket.discharge(internal::permit());
        proposal::destroy_external_execution_cap_for_testing(cap);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = armature::proposal::ECapDAOMismatch)]
/// A cap minted for a different DAO must not authorize execution.
fun external_executed_create_cap_for_wrong_dao_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_test_dao(&mut scenario);
    enable_dummy_type(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(1000);

        // Construct a cap pointing at a fabricated, unrelated DAO ID.
        let fake_dao_id = object::id_from_address(@0xDEAD);
        let cap = proposal::new_external_execution_cap_for_testing<DummyBypass>(
            fake_dao_id,
            scenario.ctx(),
        );

        let ticket = external_execution::ticket_from_cap<DummyBypass>(
            &cap,
            &mut dao,
            &freeze,
            option::none(),
            DummyBypass { x: 0 },
            internal::permit(),
            &clock,
            scenario.ctx(),
        );

        ticket.discharge(internal::permit());
        proposal::destroy_external_execution_cap_for_testing(cap);
        test_scenario::return_shared(freeze);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = armature::external_execution::ETypeNotEnabled)]
/// A cap for a valid DAO cannot mint a request for a type that isn't enabled there.
fun external_executed_create_type_not_enabled_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_test_dao(&mut scenario);
    // NOTE: deliberately skipping enable_dummy_type — DummyBypass is not enabled.

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(1000);

        let cap = proposal::new_external_execution_cap_for_testing<DummyBypass>(
            dao.id(),
            scenario.ctx(),
        );

        let ticket = external_execution::ticket_from_cap<DummyBypass>(
            &cap,
            &mut dao,
            &freeze,
            option::none(),
            DummyBypass { x: 0 },
            internal::permit(),
            &clock,
            scenario.ctx(),
        );

        ticket.discharge(internal::permit());
        proposal::destroy_external_execution_cap_for_testing(cap);
        test_scenario::return_shared(freeze);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = armature::external_execution::ECooldownActive)]
/// Two back-to-back calls within the cooldown window must abort the second.
fun external_executed_create_cooldown_enforced() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_test_dao(&mut scenario);

    // Enable DummyBypass with a non-zero cooldown.
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 60_000); // 60s cooldown
        dao.test_enable_type<DummyBypass>(b"DummyBypass".to_ascii_string(), config);
        test_scenario::return_shared(dao);
    };

    // First call at t=1000 — should succeed.
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(1000);

        let cap = proposal::new_external_execution_cap_for_testing<DummyBypass>(
            dao.id(),
            scenario.ctx(),
        );

        let ticket = external_execution::ticket_from_cap<DummyBypass>(
            &cap,
            &mut dao,
            &freeze,
            option::none(),
            DummyBypass { x: 1 },
            internal::permit(),
            &clock,
            scenario.ctx(),
        );
        ticket.discharge(internal::permit());
        proposal::destroy_external_execution_cap_for_testing(cap);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(dao);
    };

    // Second call at t=2000 (< 1000 + 60_000) — should abort with ECooldownActive.
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(2000);

        let cap = proposal::new_external_execution_cap_for_testing<DummyBypass>(
            dao.id(),
            scenario.ctx(),
        );

        let ticket = external_execution::ticket_from_cap<DummyBypass>(
            &cap,
            &mut dao,
            &freeze,
            option::none(),
            DummyBypass { x: 2 },
            internal::permit(),
            &clock,
            scenario.ctx(),
        );
        ticket.discharge(internal::permit());
        proposal::destroy_external_execution_cap_for_testing(cap);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = armature::external_execution::ETypeNotEnabled)]
/// A slot for a *different* type under the same display key does not enable P:
/// slots are keyed by the Move type, so P must have its own slot.
fun external_executed_create_other_type_slot_does_not_enable_p() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_test_dao(&mut scenario);

    // Give OtherBypass a slot whose display key is "DummyBypass".
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        dao.test_enable_type<OtherBypass>(b"DummyBypass".to_ascii_string(), config);
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(1000);

        let cap = proposal::new_external_execution_cap_for_testing<DummyBypass>(
            dao.id(),
            scenario.ctx(),
        );

        // P = DummyBypass has no slot of its own → not enabled.
        let ticket = external_execution::ticket_from_cap<DummyBypass>(
            &cap,
            &mut dao,
            &freeze,
            option::none(),
            DummyBypass { x: 0 },
            internal::permit(),
            &clock,
            scenario.ctx(),
        );
        ticket.discharge(internal::permit());
        proposal::destroy_external_execution_cap_for_testing(cap);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// =========================================================================
// EnableBypassType e2e tests
// =========================================================================

#[test]
/// E2E: EnableBypassType proposal → vote (100%) → execute mints an
/// ExternalExecutionCap<DummyBypass> and adds the type's slot.
/// Then borrow the cap from the vault without an ExecutionRequest and use it
/// with external_executed_create — must succeed.
fun execute_enable_bypass_type_e2e() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_test_dao(&mut scenario);

    // Submit.
    clock.set_for_testing(1000);
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let config = proposal::new_config(5_000, 8_000, 0, 604_800_000, 0, 0);
        let payload = external_execution::new_enable_bypass_type(
            b"DummyBypass".to_ascii_string(),
            type_name::with_defining_ids<DummyBypass>(),
            config,
        );
        board_voting::submit_proposal(
            &dao,
            option::none(),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    // Vote.
    clock.set_for_testing(2000);
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<EnableBypassType>>();
        let vote_dao = scenario.take_shared_by_id<DAO>(proposal.dao_id());
        board_voting::vote(&mut proposal, &vote_dao, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_dao);
        test_scenario::return_shared(proposal);
    };

    // Execute.
    let mut cap_id_opt = option::none<ID>();
    clock.set_for_testing(3000);
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut vault = scenario.take_shared<CapabilityVault>();
        let proposal = scenario.take_shared<Proposal<EnableBypassType>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        external_execution::execute_enable_bypass_type<DummyBypass>(
            &mut dao,
            &mut vault,
            ticket,
            scenario.ctx(),
        );

        assert!(dao.is_type_enabled<DummyBypass>());
        assert!(dao.type_display_key<DummyBypass>() == b"DummyBypass".to_ascii_string());

        let ids = vault.ids_for_type<ExternalExecutionCap<DummyBypass>>();
        assert!(ids.length() == 1);
        cap_id_opt.fill(ids[0]);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(dao);
    };

    // Use the deposited cap end-to-end via borrow_external_cap (no ExecutionRequest).
    clock.set_for_testing(4000);
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let vault = scenario.take_shared<CapabilityVault>();
        let freeze = scenario.take_shared<EmergencyFreeze>();

        let cap_id = cap_id_opt.destroy_some();
        let cap: &ExternalExecutionCap<DummyBypass> = vault.borrow_external_cap(dao.id(), cap_id);
        let ticket = external_execution::ticket_from_cap<DummyBypass>(
            cap,
            &mut dao,
            &freeze,
            option::none(),
            DummyBypass { x: 7 },
            internal::permit(),
            &clock,
            scenario.ctx(),
        );
        ticket.discharge(internal::permit());

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = armature::external_execution::EApprovalFloorNotMet)]
/// Below-80% vote at execute time aborts even if the proposal otherwise passes.
fun execute_enable_bypass_type_below_floor_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    let member_b: address = @0xB1;
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR, member_b]);
        dao::create(
            &init,
            string::utf8(b"Test DAO"),
            string::utf8(b"https://example.com/logo.png"),
            scenario.ctx(),
        );
    };

    // Relax on-DAO config so vote can "pass" at 50%; floor still 80% at execute.
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let weak = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        dao.test_update_config<EnableBypassType>(weak);
        test_scenario::return_shared(dao);
    };

    clock.set_for_testing(1000);
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let config = proposal::new_config(5_000, 8_000, 0, 604_800_000, 0, 0);
        let payload = external_execution::new_enable_bypass_type(
            b"MyBypass".to_ascii_string(),
            type_name::with_defining_ids<DummyBypass>(),
            config,
        );
        board_voting::submit_proposal(
            &dao,
            option::none(),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    clock.set_for_testing(2000);
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<EnableBypassType>>();
        let vote_dao = scenario.take_shared_by_id<DAO>(proposal.dao_id());
        board_voting::vote(&mut proposal, &vote_dao, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_dao);
        test_scenario::return_shared(proposal);
    };

    clock.set_for_testing(3000);
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut vault = scenario.take_shared<CapabilityVault>();
        let proposal = scenario.take_shared<Proposal<EnableBypassType>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        external_execution::execute_enable_bypass_type<DummyBypass>(
            &mut dao,
            &mut vault,
            ticket,
            scenario.ctx(),
        );

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = armature::external_execution::ESelfBootstrapDenied)]
/// Self-bootstrap defense: EnableBypassType cannot be used as its own NewType.
/// Even with a clean 100% vote, the handler must refuse — otherwise a single
/// successful bypass-enable would let an attacker mint arbitrary caps via
/// the bypass path with zero-weight proposals.
fun execute_enable_bypass_type_self_bootstrap_denied() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_test_dao(&mut scenario);

    clock.set_for_testing(1000);
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let config = proposal::new_config(5_000, 8_000, 0, 604_800_000, 0, 0);
        let payload = external_execution::new_enable_bypass_type(
            b"SelfBootstrap".to_ascii_string(),
            type_name::with_defining_ids<EnableBypassType>(),
            config,
        );
        board_voting::submit_proposal(
            &dao,
            option::none(),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    clock.set_for_testing(2000);
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<EnableBypassType>>();
        let vote_dao = scenario.take_shared_by_id<DAO>(proposal.dao_id());
        board_voting::vote(&mut proposal, &vote_dao, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_dao);
        test_scenario::return_shared(proposal);
    };

    clock.set_for_testing(3000);
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut vault = scenario.take_shared<CapabilityVault>();
        let proposal = scenario.take_shared<Proposal<EnableBypassType>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        // NewType = EnableBypassType — must abort.
        external_execution::execute_enable_bypass_type<EnableBypassType>(
            &mut dao,
            &mut vault,
            ticket,
            scenario.ctx(),
        );

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = armature::external_execution::EApprovalFloorNotMet)]
/// Vacuous-floor defense: a zero-weight proposal (snapshot total == 0) must
/// abort the floor check even if yes_weight == total == 0 would naively satisfy
/// gte_bps(0, 0, 8000). Constructs the proposal directly via the framework's
/// test seam so the regression is independent of any specific attack path.
fun execute_enable_bypass_type_zero_weight_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_test_dao(&mut scenario);

    // Mint a zero-weight Proposal<EnableBypassType> via privileged_create.
    clock.set_for_testing(1000);
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut vault = scenario.take_shared<CapabilityVault>();
        let config = proposal::new_config(5_000, 8_000, 0, 604_800_000, 0, 0);
        let payload = external_execution::new_enable_bypass_type(
            b"DummyBypass".to_ascii_string(),
            type_name::with_defining_ids<DummyBypass>(),
            config,
        );
        // Use privileged_create_for_testing to get a zero-weight ExecutionTicket.
        // yes_weight == 0 and total_snapshot_weight == 0 — the floor check should
        // reject gte_bps(0, 0, 8000) because total == 0 (vacuous).
        let ticket = proposal::privileged_create_for_testing<EnableBypassType>(
            dao.id(),
            b"EnableBypassType".to_ascii_string(),
            CREATOR,
            option::none(),
            payload,
            scenario.ctx(),
        );

        // Pass the zero-weight ticket to the handler — must abort at floor check.
        external_execution::execute_enable_bypass_type<DummyBypass>(
            &mut dao,
            &mut vault,
            ticket,
            scenario.ctx(),
        );
        test_scenario::return_shared(vault);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = armature::external_execution::EExecutionPaused)]
/// external_executed_create must refuse when DAO execution is paused.
fun external_executed_create_execution_paused_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_test_dao(&mut scenario);
    enable_dummy_type(&mut scenario);

    // Flip execution_paused via a manually-minted request (same-package test seam).
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let req = proposal::new_execution_request_for_testing<DummyBypass>(
            dao.id(),
            object::id_from_address(@0xBEEF),
        );
        dao.set_execution_paused(true, &req);
        proposal::consume_execution_request_for_testing(req);
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(1000);

        let cap = proposal::new_external_execution_cap_for_testing<DummyBypass>(
            dao.id(),
            scenario.ctx(),
        );
        let ticket = external_execution::ticket_from_cap<DummyBypass>(
            &cap,
            &mut dao,
            &freeze,
            option::none(),
            DummyBypass { x: 0 },
            internal::permit(),
            &clock,
            scenario.ctx(),
        );
        ticket.discharge(internal::permit());
        proposal::destroy_external_execution_cap_for_testing(cap);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = armature::external_execution::EControllerPaused)]
/// external_executed_create must refuse when a SubDAO controller has paused execution.
fun external_executed_create_controller_paused_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_test_dao(&mut scenario);
    enable_dummy_type(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let req = proposal::new_privileged_request_for_testing<DummyBypass>(
            dao.id(),
            object::id_from_address(@0xBEEF),
        );
        dao.set_controller_paused(true, &req);
        proposal::consume_execution_request_for_testing(req);
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(1000);

        let cap = proposal::new_external_execution_cap_for_testing<DummyBypass>(
            dao.id(),
            scenario.ctx(),
        );
        let ticket = external_execution::ticket_from_cap<DummyBypass>(
            &cap,
            &mut dao,
            &freeze,
            option::none(),
            DummyBypass { x: 0 },
            internal::permit(),
            &clock,
            scenario.ctx(),
        );
        ticket.discharge(internal::permit());
        proposal::destroy_external_execution_cap_for_testing(cap);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// =========================================================================
// DisableBypassType tests
// =========================================================================

#[test]
/// E2E: enable bypass for a type, then disable it via a passing
/// DisableBypassType proposal. After execute, the type is no longer enabled
/// and the cap is no longer present in the vault.
fun execute_disable_bypass_type_e2e() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_test_dao(&mut scenario);
    let cap_id = run_enable_bypass<DummyBypass>(
        &mut scenario,
        &mut clock,
        b"DummyBypass",
        1000,
        2000,
        3000,
    );

    // Submit DisableBypassType.
    clock.set_for_testing(4000);
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let payload = external_execution::new_disable_bypass_type(
            b"DummyBypass".to_ascii_string(),
            cap_id,
        );
        board_voting::submit_proposal(
            &dao,
            option::none(),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    clock.set_for_testing(5000);
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<DisableBypassType>>();
        let vote_dao = scenario.take_shared_by_id<DAO>(proposal.dao_id());
        board_voting::vote(&mut proposal, &vote_dao, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_dao);
        test_scenario::return_shared(proposal);
    };

    clock.set_for_testing(6000);
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut vault = scenario.take_shared<CapabilityVault>();
        let proposal = scenario.take_shared<Proposal<DisableBypassType>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        external_execution::execute_disable_bypass_type<DummyBypass>(
            &mut dao,
            &mut vault,
            ticket,
        );

        // Slot removed, display key released.
        assert!(!dao.is_type_enabled<DummyBypass>());
        assert!(dao.type_for_display_key(&b"DummyBypass".to_ascii_string()).is_none());
        // Cap no longer in vault.
        let remaining = vault.ids_for_type<ExternalExecutionCap<DummyBypass>>();
        assert!(remaining.is_empty());

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = armature::external_execution::ETypeMismatch)]
/// Disable handler invoked with a NewType whose slot carries a different display
/// key than the payload names must abort, even if the cap_id is otherwise valid.
/// Guards against ID-confusion attacks where a malicious proposal would
/// destroy a different cap than the type_key suggests.
fun execute_disable_bypass_type_wrong_new_type_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_test_dao(&mut scenario);
    let cap_id = run_enable_bypass<DummyBypass>(
        &mut scenario,
        &mut clock,
        b"DummyBypass",
        1000,
        2000,
        3000,
    );

    clock.set_for_testing(4000);
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let payload = external_execution::new_disable_bypass_type(
            b"DummyBypass".to_ascii_string(),
            cap_id,
        );
        board_voting::submit_proposal(
            &dao,
            option::none(),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    clock.set_for_testing(5000);
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<DisableBypassType>>();
        let vote_dao = scenario.take_shared_by_id<DAO>(proposal.dao_id());
        board_voting::vote(&mut proposal, &vote_dao, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_dao);
        test_scenario::return_shared(proposal);
    };

    // OtherBypass gets its own slot (display "OtherBypass") so the handler's
    // display-key check, not the slot-existence check, is what fires.
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        dao.test_enable_type<OtherBypass>(b"OtherBypass".to_ascii_string(), config);
        test_scenario::return_shared(dao);
    };

    clock.set_for_testing(6000);
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut vault = scenario.take_shared<CapabilityVault>();
        let proposal = scenario.take_shared<Proposal<DisableBypassType>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        // The payload's display key is "DummyBypass", but NewType = OtherBypass.
        external_execution::execute_disable_bypass_type<OtherBypass>(
            &mut dao,
            &mut vault,
            ticket,
        );

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = armature::external_execution::ECapNotFound)]
/// Disable handler must abort when the cap_id is not in the vault for
/// the given NewType, even if everything else lines up.
fun execute_disable_bypass_type_wrong_cap_id_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_test_dao(&mut scenario);
    let _real_cap_id = run_enable_bypass<DummyBypass>(
        &mut scenario,
        &mut clock,
        b"DummyBypass",
        1000,
        2000,
        3000,
    );

    let bogus_cap_id = object::id_from_address(@0xBADC);

    clock.set_for_testing(4000);
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let payload = external_execution::new_disable_bypass_type(
            b"DummyBypass".to_ascii_string(),
            bogus_cap_id,
        );
        board_voting::submit_proposal(
            &dao,
            option::none(),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    clock.set_for_testing(5000);
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<DisableBypassType>>();
        let vote_dao = scenario.take_shared_by_id<DAO>(proposal.dao_id());
        board_voting::vote(&mut proposal, &vote_dao, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_dao);
        test_scenario::return_shared(proposal);
    };

    clock.set_for_testing(6000);
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut vault = scenario.take_shared<CapabilityVault>();
        let proposal = scenario.take_shared<Proposal<DisableBypassType>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        external_execution::execute_disable_bypass_type<DummyBypass>(
            &mut dao,
            &mut vault,
            ticket,
        );

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// =========================================================================
// ETypeMismatch: the executor cannot register a different type than voted on
// =========================================================================

#[test, expected_failure(abort_code = armature::external_execution::ETypeMismatch)]
/// The EnableBypassType payload pins the Move type the board approved. Executing
/// the handler with a different NewType must abort, so an executor cannot
/// register an unrelated payload type under the approved display key.
fun execute_enable_bypass_type_wrong_new_type_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_test_dao(&mut scenario);

    clock.set_for_testing(1000);
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let config = proposal::new_config(5_000, 8_000, 0, 604_800_000, 0, 0);
        // Board approves DummyBypass under the display key "DummyBypass".
        let payload = external_execution::new_enable_bypass_type(
            b"DummyBypass".to_ascii_string(),
            type_name::with_defining_ids<DummyBypass>(),
            config,
        );
        board_voting::submit_proposal(
            &dao,
            option::none(),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    clock.set_for_testing(2000);
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<EnableBypassType>>();
        let vote_dao = scenario.take_shared_by_id<DAO>(proposal.dao_id());
        board_voting::vote(&mut proposal, &vote_dao, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_dao);
        test_scenario::return_shared(proposal);
    };

    clock.set_for_testing(3000);
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut vault = scenario.take_shared<CapabilityVault>();
        let proposal = scenario.take_shared<Proposal<EnableBypassType>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        // Executor tries to register OtherBypass instead — must abort.
        external_execution::execute_enable_bypass_type<OtherBypass>(
            &mut dao,
            &mut vault,
            ticket,
            scenario.ctx(),
        );

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// =========================================================================
// EComposableCooldownConflict: enable_bypass_type rejects cooldown+composable
// =========================================================================

#[test, expected_failure(abort_code = armature::external_execution::EComposableCooldownConflict)]
/// execute_enable_bypass_type aborts when config has cooldown_ms > 0 AND composable_allowed = true.
fun enable_bypass_type_composable_cooldown_conflict_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_test_dao(&mut scenario);

    // Submit EnableBypassType with a config that sets cooldown_ms > 0 and composable_allowed =
    // true.
    clock.set_for_testing(1000);
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        // Config with cooldown + composable_allowed — should be rejected
        let bad_config = proposal::new_config(
            5_000,
            8_000,
            0,
            604_800_000,
            0,
            3_600_000,
        ).with_composable_allowed(true);
        let payload = external_execution::new_enable_bypass_type(
            b"DummyBypass".to_ascii_string(),
            type_name::with_defining_ids<DummyBypass>(),
            bad_config,
        );
        board_voting::submit_proposal(
            &dao,
            option::none(),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    // Vote
    clock.set_for_testing(2000);
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<EnableBypassType>>();
        let vote_dao = scenario.take_shared_by_id<DAO>(proposal.dao_id());
        board_voting::vote(&mut proposal, &vote_dao, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_dao);
        test_scenario::return_shared(proposal);
    };

    // Execute — must abort at composable_cooldown_conflict check
    clock.set_for_testing(3000);
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut vault = scenario.take_shared<CapabilityVault>();
        let proposal = scenario.take_shared<Proposal<EnableBypassType>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        external_execution::execute_enable_bypass_type<DummyBypass>(
            &mut dao,
            &mut vault,
            ticket,
            scenario.ctx(),
        );

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// === ticket_from_cap_readonly ===

/// Mint a cap for DummyBypass and call ticket_from_cap_readonly with an immutable DAO.
fun cap_readonly_and_discharge(scenario: &mut test_scenario::Scenario, clock: &clock::Clock) {
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        let cap = proposal::new_external_execution_cap_for_testing<DummyBypass>(
            dao.id(),
            scenario.ctx(),
        );

        let ticket = external_execution::ticket_from_cap_readonly<DummyBypass>(
            &cap,
            &dao,
            &freeze,
            option::none(),
            DummyBypass { x: 42 },
            internal::permit(),
            clock,
            scenario.ctx(),
        );

        assert!(ticket.ticket_dao_id() == dao.id());
        assert!(dao.last_executed_ms<DummyBypass>().is_none());

        ticket.discharge(internal::permit());
        proposal::destroy_external_execution_cap_for_testing(cap);
        test_scenario::return_shared(freeze);
        test_scenario::return_shared(dao);
    };
}

#[test]
/// Read-only bypass mints the ticket without recording anything on the DAO,
/// and can run back-to-back for a cooldown-free type.
fun ticket_from_cap_readonly_happy_path() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1000);

    create_test_dao(&mut scenario);
    enable_dummy_type(&mut scenario);
    cap_readonly_and_discharge(&mut scenario, &clock);
    cap_readonly_and_discharge(&mut scenario, &clock);

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = armature::external_execution::ECooldownRequiresMutableDAO)]
/// A type with a cooldown must use ticket_from_cap so the timestamp is recorded.
fun ticket_from_cap_readonly_cooldown_type_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1000);

    create_test_dao(&mut scenario);
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 60_000);
        dao.test_enable_type<DummyBypass>(b"DummyBypass".to_ascii_string(), config);
        test_scenario::return_shared(dao);
    };
    cap_readonly_and_discharge(&mut scenario, &clock);

    clock.destroy_for_testing();
    scenario.end();
}

// === Event-only audit (no Proposal object) ===

/// Bypass execution through either variant creates no objects: ProposalCreated,
/// ProposalPayloadCreated and ProposalExecuted carry the audit record under the
/// ticket's proposal ID.
fun cap_execution_creates_no_objects(readonly: bool) {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1000);

    create_test_dao(&mut scenario);
    enable_dummy_type(&mut scenario);

    // Mint the cap in its own transaction so the execution's effects only
    // reflect what ticket_from_cap does.
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let cap = proposal::new_external_execution_cap_for_testing<DummyBypass>(
            dao.id(),
            scenario.ctx(),
        );
        transfer::public_transfer(cap, CREATOR);
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        let cap = scenario.take_from_sender<ExternalExecutionCap<DummyBypass>>();
        let metadata = option::some(string::utf8(b"QmBypass"));

        let ticket = if (readonly) {
            external_execution::ticket_from_cap_readonly<DummyBypass>(
                &cap,
                &dao,
                &freeze,
                metadata,
                DummyBypass { x: 7 },
                internal::permit(),
                &clock,
                scenario.ctx(),
            )
        } else {
            external_execution::ticket_from_cap<DummyBypass>(
                &cap,
                &mut dao,
                &freeze,
                metadata,
                DummyBypass { x: 7 },
                internal::permit(),
                &clock,
                scenario.ctx(),
            )
        };
        let proposal_id = ticket.ticket_request(internal::permit()).req_proposal_id();

        let created = event::events_by_type<ProposalCreated>();
        assert!(created.length() == 1);
        assert!(created[0].created_event_proposal_id() == proposal_id);
        assert!(created[0].created_event_metadata_ipfs() == metadata);

        let payloads = event::events_by_type<ProposalPayloadCreated>();
        assert!(payloads.length() == 1);
        assert!(payloads[0].payload_event_proposal_id() == proposal_id);
        assert!(payloads[0].payload_event_bcs() == std::bcs::to_bytes(&DummyBypass { x: 7 }));

        let executed = event::events_by_type<ProposalExecuted>();
        assert!(executed.length() == 1);
        assert!(executed[0].executed_event_proposal_id() == proposal_id);

        ticket.discharge(internal::permit());
        scenario.return_to_sender(cap);
        test_scenario::return_shared(freeze);
        test_scenario::return_shared(dao);
    };

    let effects = scenario.next_tx(CREATOR);
    assert!(effects.created().is_empty());
    // ExternalExecutionCreated + the three proposal events.
    assert!(effects.num_user_events() == 4);

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
fun ticket_from_cap_creates_no_objects() {
    cap_execution_creates_no_objects(false);
}

#[test]
fun ticket_from_cap_readonly_creates_no_objects() {
    cap_execution_creates_no_objects(true);
}

// === Bypass-safe bits ===

#[test, expected_failure(abort_code = armature::external_execution::EBypassForbiddenBits)]
/// EnableBypassType refuses a config holding an authority-graph bit
/// (TYPE_ADMIN here), even at the 80% floor.
fun execute_enable_bypass_type_forbidden_bits_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    create_test_dao(&mut scenario);

    clock.set_for_testing(1000);
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let config = proposal::new_config(5_000, 8_000, 0, 604_800_000, 0, 0).with_permissions(
            permissions::type_admin(),
        );
        let payload = external_execution::new_enable_bypass_type(
            b"DummyBypass".to_ascii_string(),
            type_name::with_defining_ids<DummyBypass>(),
            config,
        );
        board_voting::submit_proposal(&dao, option::none(), payload, &clock, scenario.ctx());
        test_scenario::return_shared(dao);
    };
    clock.set_for_testing(2000);
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<EnableBypassType>>();
        let vote_dao = scenario.take_shared_by_id<DAO>(proposal.dao_id());
        board_voting::vote(&mut proposal, &vote_dao, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_dao);
        test_scenario::return_shared(proposal);
    };
    clock.set_for_testing(3000);
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut vault = scenario.take_shared<CapabilityVault>();
        let proposal = scenario.take_shared<Proposal<EnableBypassType>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        external_execution::execute_enable_bypass_type<DummyBypass>(
            &mut dao,
            &mut vault,
            ticket,
            scenario.ctx(),
        );
        test_scenario::return_shared(freeze);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = armature::external_execution::EBypassForbiddenBits)]
/// A slot that later gains a forbidden bit (as an UpdateProposalConfig grant
/// would) stops minting bypass tickets, whatever cap sits in the vault.
fun ticket_from_cap_forbidden_bits_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    create_test_dao(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let config = proposal::new_config(5_000, 8_000, 0, 604_800_000, 0, 0).with_permissions(
            permissions::vault_extract(),
        );
        dao.test_enable_type<DummyBypass>(b"DummyBypass".to_ascii_string(), config);
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(1000);
        let cap = proposal::new_external_execution_cap_for_testing<DummyBypass>(
            dao.id(),
            scenario.ctx(),
        );
        let ticket = external_execution::ticket_from_cap<DummyBypass>(
            &cap,
            &mut dao,
            &freeze,
            option::none(),
            DummyBypass { x: 1 },
            internal::permit(),
            &clock,
            scenario.ctx(),
        );
        ticket.discharge(internal::permit());
        proposal::destroy_external_execution_cap_for_testing(cap);
        test_scenario::return_shared(freeze);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test_only]
module armature::external_execution_tests;

use armature::board_voting;
use armature::capability_vault::CapabilityVault;
use armature::dao::{Self, DAO};
use armature::emergency::EmergencyFreeze;
use armature::external_execution::{Self, EnableBypassType};
use armature::governance;
use armature::proposal::{Self, ExternalExecutionCap, Proposal};
use std::string;
use sui::clock;
use sui::test_scenario;

const CREATOR: address = @0xA;

/// Stand-in payload type for external-execution tests.
public struct DummyBypass has drop, store { x: u64 }

/// Second payload type for verifying type-binding mismatch.
public struct OtherBypass has drop, store {}

fun create_test_dao(scenario: &mut test_scenario::Scenario) {
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR]);
        dao::create(
            &init,
            string::utf8(b"Test DAO"),
            string::utf8(b"External-execution test DAO"),
            string::utf8(b"https://example.com/logo.png"),
            scenario.ctx(),
        );
    };
}

/// Enable a custom proposal type on the DAO without going through governance.
/// Used to make `DummyBypass` recognizable to external_executed_create.
fun enable_dummy_type(scenario: &mut test_scenario::Scenario) {
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        dao.test_enable_type(b"DummyBypass".to_ascii_string(), config);
        dao.test_bind_type<DummyBypass>(b"DummyBypass".to_ascii_string());
        test_scenario::return_shared(dao);
    };
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

        let req = external_execution::external_executed_create<DummyBypass>(
            &cap,
            &mut dao,
            &freeze,
            b"DummyBypass".to_ascii_string(),
            option::none(),
            DummyBypass { x: 42 },
            &clock,
            scenario.ctx(),
        );

        // Request is for this DAO
        assert!(req.req_dao_id() == dao.id());
        // record_execution updated
        assert!(dao.last_executed_at().contains(&b"DummyBypass".to_ascii_string()));

        proposal::consume_execution_request(req);
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

        let req = external_execution::external_executed_create<DummyBypass>(
            &cap,
            &mut dao,
            &freeze,
            b"DummyBypass".to_ascii_string(),
            option::none(),
            DummyBypass { x: 0 },
            &clock,
            scenario.ctx(),
        );

        proposal::consume_execution_request(req);
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

        let req = external_execution::external_executed_create<DummyBypass>(
            &cap,
            &mut dao,
            &freeze,
            b"DummyBypass".to_ascii_string(),
            option::none(),
            DummyBypass { x: 0 },
            &clock,
            scenario.ctx(),
        );

        proposal::consume_execution_request(req);
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
        dao.test_enable_type(b"DummyBypass".to_ascii_string(), config);
        dao.test_bind_type<DummyBypass>(b"DummyBypass".to_ascii_string());
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

        let req = external_execution::external_executed_create<DummyBypass>(
            &cap,
            &mut dao,
            &freeze,
            b"DummyBypass".to_ascii_string(),
            option::none(),
            DummyBypass { x: 1 },
            &clock,
            scenario.ctx(),
        );
        proposal::consume_execution_request(req);
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

        let req = external_execution::external_executed_create<DummyBypass>(
            &cap,
            &mut dao,
            &freeze,
            b"DummyBypass".to_ascii_string(),
            option::none(),
            DummyBypass { x: 2 },
            &clock,
            scenario.ctx(),
        );
        proposal::consume_execution_request(req);
        proposal::destroy_external_execution_cap_for_testing(cap);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = armature::external_execution::ETypeMismatch)]
/// If the type_key is bound to a different Move type, P must match.
fun external_executed_create_type_binding_mismatch_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_test_dao(&mut scenario);

    // Enable DummyBypass key bound to a *different* type (OtherBypass).
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        dao.test_enable_type(b"DummyBypass".to_ascii_string(), config);
        dao.test_bind_type<OtherBypass>(b"DummyBypass".to_ascii_string());
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

        // P = DummyBypass, but the key is bound to OtherBypass → mismatch.
        let req = external_execution::external_executed_create<DummyBypass>(
            &cap,
            &mut dao,
            &freeze,
            b"DummyBypass".to_ascii_string(),
            option::none(),
            DummyBypass { x: 0 },
            &clock,
            scenario.ctx(),
        );
        proposal::consume_execution_request(req);
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
/// ExternalExecutionCap<DummyBypass>, enables the type, binds the Move type.
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
            config,
        );
        board_voting::submit_proposal(
            &dao,
            b"EnableBypassType".to_ascii_string(),
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
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    // Execute.
    let mut cap_id_opt = option::none<ID>();
    clock.set_for_testing(3000);
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut vault = scenario.take_shared<CapabilityVault>();
        let mut proposal = scenario.take_shared<Proposal<EnableBypassType>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();

        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        external_execution::execute_enable_bypass_type<DummyBypass>(
            &mut dao,
            &mut vault,
            &proposal,
            request,
            scenario.ctx(),
        );

        assert!(dao.enabled_proposal_types().contains(&b"DummyBypass".to_ascii_string()));
        assert!(dao.has_type_binding(&b"DummyBypass".to_ascii_string()));

        let ids = vault.ids_for_type<ExternalExecutionCap<DummyBypass>>();
        assert!(ids.length() == 1);
        cap_id_opt.fill(ids[0]);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
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
        let cap: &ExternalExecutionCap<DummyBypass> = vault.borrow_external_cap(cap_id);
        let req = external_execution::external_executed_create<DummyBypass>(
            cap,
            &mut dao,
            &freeze,
            b"DummyBypass".to_ascii_string(),
            option::none(),
            DummyBypass { x: 7 },
            &clock,
            scenario.ctx(),
        );
        proposal::consume_execution_request(req);

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
            string::utf8(b"2-member DAO"),
            string::utf8(b"https://example.com/logo.png"),
            scenario.ctx(),
        );
    };

    // Relax on-DAO config so vote can "pass" at 50%; floor still 80% at execute.
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let weak = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        dao.test_update_config(b"EnableBypassType".to_ascii_string(), weak);
        test_scenario::return_shared(dao);
    };

    clock.set_for_testing(1000);
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let config = proposal::new_config(5_000, 8_000, 0, 604_800_000, 0, 0);
        let payload = external_execution::new_enable_bypass_type(
            b"MyBypass".to_ascii_string(),
            config,
        );
        board_voting::submit_proposal(
            &dao,
            b"EnableBypassType".to_ascii_string(),
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
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    clock.set_for_testing(3000);
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut vault = scenario.take_shared<CapabilityVault>();
        let mut proposal = scenario.take_shared<Proposal<EnableBypassType>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();

        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        external_execution::execute_enable_bypass_type<DummyBypass>(
            &mut dao,
            &mut vault,
            &proposal,
            request,
            scenario.ctx(),
        );

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
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
            config,
        );
        board_voting::submit_proposal(
            &dao,
            b"EnableBypassType".to_ascii_string(),
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
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    clock.set_for_testing(3000);
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut vault = scenario.take_shared<CapabilityVault>();
        let mut proposal = scenario.take_shared<Proposal<EnableBypassType>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();

        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        // NewType = EnableBypassType — must abort.
        external_execution::execute_enable_bypass_type<EnableBypassType>(
            &mut dao,
            &mut vault,
            &proposal,
            request,
            scenario.ctx(),
        );

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
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
        let dao = scenario.take_shared<DAO>();
        let config = proposal::new_config(5_000, 8_000, 0, 604_800_000, 0, 0);
        let payload = external_execution::new_enable_bypass_type(
            b"DummyBypass".to_ascii_string(),
            config,
        );
        let req = proposal::privileged_create<EnableBypassType>(
            dao.id(),
            b"EnableBypassType".to_ascii_string(),
            CREATOR,
            option::none(),
            payload,
            &clock,
            scenario.ctx(),
        );
        // Consume the request immediately to avoid leaking the hot potato —
        // the test only needs the shared Proposal<EnableBypassType> with
        // zero weight. The handler under test will receive its own request
        // (one constructed manually below).
        proposal::consume_execution_request(req);
        test_scenario::return_shared(dao);
    };

    // Now run the handler against the zero-weight proposal — must abort
    // at the floor check (before finalize), so the exact request contents
    // don't matter beyond having the right dao_id.
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut vault = scenario.take_shared<CapabilityVault>();
        let proposal = scenario.take_shared<Proposal<EnableBypassType>>();

        let request = proposal::new_execution_request<EnableBypassType>(
            dao.id(),
            object::id(&proposal),
        );

        external_execution::execute_enable_bypass_type<DummyBypass>(
            &mut dao,
            &mut vault,
            &proposal,
            request,
            scenario.ctx(),
        );

        test_scenario::return_shared(proposal);
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
        let req = proposal::new_execution_request<DummyBypass>(
            dao.id(),
            object::id_from_address(@0xBEEF),
        );
        dao.set_execution_paused(true, &req);
        proposal::consume_execution_request(req);
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
        let req = external_execution::external_executed_create<DummyBypass>(
            &cap,
            &mut dao,
            &freeze,
            b"DummyBypass".to_ascii_string(),
            option::none(),
            DummyBypass { x: 0 },
            &clock,
            scenario.ctx(),
        );
        proposal::consume_execution_request(req);
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
        let req = proposal::new_execution_request<DummyBypass>(
            dao.id(),
            object::id_from_address(@0xBEEF),
        );
        dao.set_controller_paused(true, &req);
        proposal::consume_execution_request(req);
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
        let req = external_execution::external_executed_create<DummyBypass>(
            &cap,
            &mut dao,
            &freeze,
            b"DummyBypass".to_ascii_string(),
            option::none(),
            DummyBypass { x: 0 },
            &clock,
            scenario.ctx(),
        );
        proposal::consume_execution_request(req);
        proposal::destroy_external_execution_cap_for_testing(cap);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test_only]
module armature::external_execution_tests;

use armature::dao::{Self, DAO};
use armature::emergency::EmergencyFreeze;
use armature::external_execution;
use armature::governance;
use armature::proposal;
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

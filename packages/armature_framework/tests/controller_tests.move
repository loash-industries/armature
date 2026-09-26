#[test_only]
module armature::controller_tests;

use armature::board_voting;
use armature::capability_vault::{Self, CapabilityVault, SubDAOControl};
use armature::controller;
use armature::dao::{Self, DAO};
use armature::emergency::EmergencyFreeze;
use armature::governance;
use armature::proposal::{Self, Proposal, ProposalCreated, ProposalExecuted, ProposalPayloadCreated};
use std::internal;
use std::string;
use sui::clock;
use sui::event;
use sui::test_scenario;

// === Test addresses ===

const CREATOR: address = @0xA;
const MEMBER_B: address = @0xB;

// === Test payload ===

public struct TestPayload has drop, store {
    value: u64,
}

// === Helpers ===

fun create_dao(scenario: &mut test_scenario::Scenario) {
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR, MEMBER_B]);
        dao::create(
            &init,
            string::utf8(b"Parent DAO"),
            string::utf8(b"https://example.com/logo.png"),
            scenario.ctx(),
        );
    };
}

// === Test 1: privileged_submit records the execution in events only ===

#[test]
/// privileged_submit returns an ExecutionRequest bound to the SubDAO's ID and
/// creates no Proposal object: ProposalCreated, ProposalPayloadCreated and
/// ProposalExecuted carry the audit record, including the payload.
fun privileged_submit_records_execution_in_events() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1000);

    // Create parent DAO
    create_dao(&mut scenario);

    // Create SubDAO
    scenario.next_tx(CREATOR);
    let subdao_id = {
        let init = governance::init_board(vector[CREATOR]);
        let (subdao, freeze_cap) = dao::create_subdao(
            &init,
            string::utf8(b"SubDAO"),
            string::utf8(b"https://example.com/sub.png"),
            scenario.ctx(),
        );
        let control = capability_vault::new_subdao_control_for_testing(
            object::id(&subdao),
            scenario.ctx(),
        );

        let subdao_id = object::id(&subdao);
        transfer::public_transfer(control, CREATOR);
        sui::test_utils::destroy(freeze_cap);
        transfer::public_share_object(subdao);
        subdao_id
    };

    // Submit the privileged proposal in its own transaction so its effects
    // only reflect what privileged_submit does.
    scenario.next_tx(CREATOR);
    {
        let subdao = scenario.take_shared_by_id<DAO>(subdao_id);
        let control = scenario.take_from_sender<SubDAOControl>();
        let metadata = option::some(string::utf8(b"Privileged test"));

        let req = controller::privileged_submit(
            &control,
            &subdao,
            b"TestPayload".to_ascii_string(),
            metadata,
            TestPayload { value: 42 },
            scenario.ctx(),
        );

        // Verify the request is bound to the SubDAO
        assert!(req.req_dao_id() == subdao_id);

        let created = event::events_by_type<ProposalCreated>();
        assert!(created.length() == 1);
        assert!(created[0].created_event_proposal_id() == req.req_proposal_id());
        assert!(created[0].created_event_metadata_ipfs() == metadata);

        let payloads = event::events_by_type<ProposalPayloadCreated>();
        assert!(payloads.length() == 1);
        assert!(payloads[0].payload_event_bcs() == std::bcs::to_bytes(&TestPayload { value: 42 }));

        let executed = event::events_by_type<ProposalExecuted>();
        assert!(executed.length() == 1);
        assert!(executed[0].executed_event_proposal_id() == req.req_proposal_id());

        controller::privileged_consume(req, &control);

        scenario.return_to_sender(control);
        test_scenario::return_shared(subdao);
    };

    let effects = scenario.next_tx(CREATOR);
    assert!(effects.created().is_empty());
    assert!(effects.num_user_events() == 3);

    clock.destroy_for_testing();
    scenario.end();
}

// === Test 2: privileged_submit rejects mismatched SubDAOControl ===

#[test, expected_failure(abort_code = controller::EControlMismatch)]
/// privileged_submit aborts when SubDAOControl.subdao_id != subdao.id().
fun privileged_submit_rejects_wrong_control() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1000);

    create_dao(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR]);
        let (subdao, freeze_cap) = dao::create_subdao(
            &init,
            string::utf8(b"SubDAO"),
            string::utf8(b"https://example.com/sub.png"),
            scenario.ctx(),
        );

        // Create SubDAOControl pointing to a DIFFERENT ID
        let wrong_control = capability_vault::new_subdao_control_for_testing(
            object::id_from_address(@0xDEAD),
            scenario.ctx(),
        );

        let req = controller::privileged_submit(
            &wrong_control,
            &subdao,
            b"TestPayload".to_ascii_string(),
            option::some(string::utf8(b"Should fail")),
            TestPayload { value: 1 },
            scenario.ctx(),
        );

        controller::privileged_consume(req, &wrong_control);
        sui::test_utils::destroy(wrong_control);
        sui::test_utils::destroy(freeze_cap);
        transfer::public_share_object(subdao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// === Test 3: privileged_consume rejects mismatched request ===

#[test, expected_failure(abort_code = controller::EControlMismatch)]
/// privileged_consume aborts when the ExecutionRequest's DAO ID doesn't
/// match the SubDAOControl's subdao_id.
fun privileged_consume_rejects_wrong_control() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1000);

    create_dao(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR]);
        let (subdao, freeze_cap) = dao::create_subdao(
            &init,
            string::utf8(b"SubDAO"),
            string::utf8(b"https://example.com/sub.png"),
            scenario.ctx(),
        );

        let correct_control = capability_vault::new_subdao_control_for_testing(
            object::id(&subdao),
            scenario.ctx(),
        );
        let wrong_control = capability_vault::new_subdao_control_for_testing(
            object::id_from_address(@0xDEAD),
            scenario.ctx(),
        );

        let req = controller::privileged_submit(
            &correct_control,
            &subdao,
            b"TestPayload".to_ascii_string(),
            option::some(string::utf8(b"Privileged test")),
            TestPayload { value: 1 },
            scenario.ctx(),
        );

        // Try to consume with the wrong control — should abort
        controller::privileged_consume(req, &wrong_control);

        sui::test_utils::destroy(correct_control);
        sui::test_utils::destroy(wrong_control);
        sui::test_utils::destroy(freeze_cap);
        transfer::public_share_object(subdao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// === Test 4: authorize_execution blocks when controller_paused ===

#[test, expected_failure(abort_code = board_voting::EControllerPaused)]
/// authorize_execution aborts when the SubDAO's controller_paused flag is set.
fun authorize_execution_blocks_when_controller_paused() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1000);

    // Create a DAO
    create_dao(&mut scenario);

    // Enable test type and submit a proposal
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let config = proposal::new_config(5_000, 5_000, 0, 3_600_000, 0, 0);
        dao.test_enable_type<TestPayload>(b"TestPayload".to_ascii_string(), config);
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        board_voting::submit_proposal(
            &dao,
            option::some(string::utf8(b"Test proposal")),
            TestPayload { value: 99 },
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    // Vote to pass
    scenario.next_tx(CREATOR);
    {
        let mut prop = scenario.take_shared<Proposal<TestPayload>>();
        let vote_dao = scenario.take_shared_by_id<DAO>(prop.dao_id());
        board_voting::vote(&mut prop, &vote_dao, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_dao);
        test_scenario::return_shared(prop);
    };

    // Set controller_paused via privileged mechanism
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        // Simulate controller_paused by using set_controller_paused with a fake exec req
        let req = proposal::new_privileged_request_for_testing<TestPayload>(
            dao.id(),
            object::id_from_address(@0xBEEF),
        );
        dao.set_controller_paused(true, &req);
        proposal::consume_execution_request_for_testing(req);
        test_scenario::return_shared(dao);
    };

    // Try to execute — should abort with EControllerPaused
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let prop = scenario.take_shared<Proposal<TestPayload>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();

        let req = board_voting::ticket_from_vote(
            &mut dao,
            prop,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        req.discharge(internal::permit());
        test_scenario::return_shared(freeze);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// === Test 5: privileged_submit rejects inactive SubDAO ===

#[test, expected_failure(abort_code = controller::EDAONotActive)]
/// privileged_submit aborts when the SubDAO status is not Active (e.g., Migrating).
fun privileged_submit_rejects_inactive_subdao() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1000);

    create_dao(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR]);
        let (mut subdao, freeze_cap) = dao::create_subdao(
            &init,
            string::utf8(b"SubDAO"),
            string::utf8(b"https://example.com/sub.png"),
            scenario.ctx(),
        );

        let control = capability_vault::new_subdao_control_for_testing(
            object::id(&subdao),
            scenario.ctx(),
        );

        // Transition SubDAO to Migrating
        let req = proposal::new_execution_request_for_testing<TestPayload>(
            object::id(&subdao),
            object::id_from_address(@0xBEEF),
        );
        subdao.set_migrating(object::id_from_address(@0xDEAD), &req);
        proposal::consume_execution_request_for_testing(req);

        // Try privileged_submit on inactive SubDAO — should abort
        let req = controller::privileged_submit(
            &control,
            &subdao,
            b"TestPayload".to_ascii_string(),
            option::some(string::utf8(b"Should fail")),
            TestPayload { value: 1 },
            scenario.ctx(),
        );

        controller::privileged_consume(req, &control);
        sui::test_utils::destroy(control);
        sui::test_utils::destroy(freeze_cap);
        transfer::public_share_object(subdao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

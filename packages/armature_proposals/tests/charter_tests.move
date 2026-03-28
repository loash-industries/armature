#[test_only]
module armature_proposals::charter_tests;

use armature::board_voting;
use armature::charter::Charter;
use armature::dao::{Self, DAO};
use armature::emergency::EmergencyFreeze;
use armature::governance;
use armature::proposal::{Self, Proposal};
use armature_proposals::admin_ops;
use armature_proposals::update_metadata::{Self, UpdateMetadata};
use std::string;
use sui::clock;
use sui::test_scenario;

const CREATOR: address = @0xA;
const MEMBER_B: address = @0xB;

#[test]
/// E2E: Create DAO → submit UpdateMetadata (CharterUpdate) → vote → execute
/// → verify metadata updated → submit second update → verify again.
fun charter_update_lifecycle() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    // Create DAO
    let dao_id;
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR, MEMBER_B]);
        dao_id =
            dao::create(
                &init,
                string::utf8(b"Charter DAO"),
                string::utf8(b"Charter update test"),
                string::utf8(b"https://old-logo.png"),
                scenario.ctx(),
            );
    };

    // Verify initial charter
    let charter_id;
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared_by_id<DAO>(dao_id);
        charter_id = dao.charter_id();
        let charter = scenario.take_shared_by_id<Charter>(charter_id);
        assert!(charter.image_url() == &string::utf8(b"https://old-logo.png"));
        test_scenario::return_shared(charter);
        test_scenario::return_shared(dao);
    };

    // Submit CharterUpdate proposal
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared_by_id<DAO>(dao_id);
        clock.set_for_testing(1_000);
        let payload = update_metadata::new(
            string::utf8(b"ipfs://QmNewHashV1"),
        );
        board_voting::submit_proposal(
            &dao,
            b"CharterUpdate".to_ascii_string(),
            option::some(string::utf8(b"Update logo to v1")),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    // Vote yes
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<UpdateMetadata>>();
        clock.set_for_testing(2_000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    // Execute
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared_by_id<DAO>(dao_id);
        let mut proposal = scenario.take_shared<Proposal<UpdateMetadata>>();
        let mut charter = scenario.take_shared_by_id<Charter>(charter_id);
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(dao.emergency_freeze_id());
        clock.set_for_testing(3_000);

        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        admin_ops::execute_update_metadata(&mut charter, &proposal, request);

        // Verify metadata updated
        assert!(charter.image_url() == &string::utf8(b"ipfs://QmNewHashV1"));

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(charter);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    // Submit a second update to verify charter can be updated multiple times
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared_by_id<DAO>(dao_id);
        clock.set_for_testing(10_000);
        board_voting::submit_proposal(
            &dao,
            b"CharterUpdate".to_ascii_string(),
            option::some(string::utf8(b"Update logo to v2")),
            update_metadata::new(string::utf8(b"ipfs://QmNewHashV2")),
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<UpdateMetadata>>();
        clock.set_for_testing(11_000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared_by_id<DAO>(dao_id);
        let mut proposal = scenario.take_shared<Proposal<UpdateMetadata>>();
        let mut charter = scenario.take_shared_by_id<Charter>(charter_id);
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(dao.emergency_freeze_id());
        clock.set_for_testing(12_000);

        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        admin_ops::execute_update_metadata(&mut charter, &proposal, request);

        assert!(charter.image_url() == &string::utf8(b"ipfs://QmNewHashV2"));

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(charter);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = armature_proposals::admin_ops::ECharterDaoMismatch)]
/// UpdateMetadata rejects charter from a different DAO.
fun charter_update_wrong_dao_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    // Create two DAOs
    let dao_a_id;
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR]);
        dao_a_id =
            dao::create(
                &init,
                string::utf8(b"DAO A"),
                string::utf8(b"First"),
                string::utf8(b""),
                scenario.ctx(),
            );
    };

    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR]);
        dao::create(
            &init,
            string::utf8(b"DAO B"),
            string::utf8(b"Second"),
            string::utf8(b""),
            scenario.ctx(),
        );
    };

    // Capture DAO B's charter ID
    let dao_b_charter_id;
    scenario.next_tx(CREATOR);
    {
        let dao_a = scenario.take_shared_by_id<DAO>(dao_a_id);
        let dao_b = scenario.take_shared<DAO>();
        dao_b_charter_id = dao_b.charter_id();
        test_scenario::return_shared(dao_b);
        test_scenario::return_shared(dao_a);
    };

    // Submit CharterUpdate on DAO A
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared_by_id<DAO>(dao_a_id);
        clock.set_for_testing(1_000);
        board_voting::submit_proposal(
            &dao,
            b"CharterUpdate".to_ascii_string(),
            option::some(string::utf8(b"Mismatch test")),
            update_metadata::new(string::utf8(b"ipfs://malicious")),
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<UpdateMetadata>>();
        clock.set_for_testing(2_000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    // Execute with DAO B's charter — should abort
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared_by_id<DAO>(dao_a_id);
        let mut proposal = scenario.take_shared<Proposal<UpdateMetadata>>();
        let mut wrong_charter = scenario.take_shared_by_id<Charter>(dao_b_charter_id);
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(dao.emergency_freeze_id());
        clock.set_for_testing(3_000);

        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        // This should abort with ECharterDaoMismatch
        admin_ops::execute_update_metadata(
            &mut wrong_charter,
            &proposal,
            request,
        );

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(wrong_charter);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

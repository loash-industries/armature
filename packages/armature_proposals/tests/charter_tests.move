#[test_only]
module armature_proposals::charter_tests;

use armature::admin_ops;
use armature::board_voting;
use armature::charter::Charter;
use armature::ou::{Self, OU};
use armature::emergency::EmergencyFreeze;
use armature::governance;
use armature::proposal::{Self, Proposal};
use armature::update_metadata::{Self, UpdateMetadata};
use std::string;
use sui::clock;
use sui::test_scenario;

const CREATOR: address = @0xA;
const MEMBER_B: address = @0xB;

#[test]
/// E2E: Create OU → submit UpdateMetadata (CharterUpdate) → vote → execute
/// → verify metadata updated → submit second update → verify again.
fun charter_update_lifecycle() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    // Create OU
    let ou_id;
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR, MEMBER_B]);
        ou_id =
            ou::create(
                &init,
                string::utf8(b"Charter OU"),
                string::utf8(b"https://old-logo.png"),
                scenario.ctx(),
            );
    };

    // Verify initial charter
    let charter_id;
    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared_by_id<OU>(ou_id);
        charter_id = ou.charter_id();
        let charter = scenario.take_shared_by_id<Charter>(charter_id);
        assert!(charter.metadata_uri() == &string::utf8(b"https://old-logo.png"));
        test_scenario::return_shared(charter);
        test_scenario::return_shared(ou);
    };

    // Submit CharterUpdate proposal
    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared_by_id<OU>(ou_id);
        clock.set_for_testing(1_000);
        let payload = update_metadata::new(
            string::utf8(b"ipfs://QmNewHashV1"),
        );
        board_voting::submit_proposal(
            &ou,
            option::some(string::utf8(b"Update logo to v1")),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    // Vote yes
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<UpdateMetadata>>();
        clock.set_for_testing(2_000);
        let vote_ou = scenario.take_shared_by_id<OU>(proposal.ou_id());
        board_voting::vote(&mut proposal, &vote_ou, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_ou);
        test_scenario::return_shared(proposal);
    };

    // Execute
    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared_by_id<OU>(ou_id);
        let mut proposal = scenario.take_shared<Proposal<UpdateMetadata>>();
        let mut charter = scenario.take_shared_by_id<Charter>(charter_id);
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(ou.emergency_freeze_id());
        clock.set_for_testing(3_000);

        let ticket = board_voting::ticket_from_vote(
            &mut ou,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        admin_ops::execute_update_metadata(&mut charter, ticket);

        // Verify metadata updated
        assert!(charter.metadata_uri() == &string::utf8(b"ipfs://QmNewHashV1"));

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(charter);
        test_scenario::return_shared(ou);
    };

    // Submit a second update to verify charter can be updated multiple times
    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared_by_id<OU>(ou_id);
        clock.set_for_testing(10_000);
        board_voting::submit_proposal(
            &ou,
            option::some(string::utf8(b"Update logo to v2")),
            update_metadata::new(string::utf8(b"ipfs://QmNewHashV2")),
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<UpdateMetadata>>();
        clock.set_for_testing(11_000);
        let vote_ou = scenario.take_shared_by_id<OU>(proposal.ou_id());
        board_voting::vote(&mut proposal, &vote_ou, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_ou);
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared_by_id<OU>(ou_id);
        let mut proposal = scenario.take_shared<Proposal<UpdateMetadata>>();
        let mut charter = scenario.take_shared_by_id<Charter>(charter_id);
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(ou.emergency_freeze_id());
        clock.set_for_testing(12_000);

        let ticket = board_voting::ticket_from_vote(
            &mut ou,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        admin_ops::execute_update_metadata(&mut charter, ticket);

        assert!(charter.metadata_uri() == &string::utf8(b"ipfs://QmNewHashV2"));

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(charter);
        test_scenario::return_shared(ou);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = armature::admin_ops::ECharterOuMismatch)]
/// UpdateMetadata rejects charter from a different OU.
fun charter_update_wrong_ou_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    // Create two OUs
    let ou_a_id;
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR]);
        ou_a_id =
            ou::create(
                &init,
                string::utf8(b"OU A"),
                string::utf8(b""),
                scenario.ctx(),
            );
    };

    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR]);
        ou::create(
            &init,
            string::utf8(b"OU B"),
            string::utf8(b""),
            scenario.ctx(),
        );
    };

    // Capture OU B's charter ID
    let ou_b_charter_id;
    scenario.next_tx(CREATOR);
    {
        let ou_a = scenario.take_shared_by_id<OU>(ou_a_id);
        let ou_b = scenario.take_shared<OU>();
        ou_b_charter_id = ou_b.charter_id();
        test_scenario::return_shared(ou_b);
        test_scenario::return_shared(ou_a);
    };

    // Submit CharterUpdate on OU A
    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared_by_id<OU>(ou_a_id);
        clock.set_for_testing(1_000);
        board_voting::submit_proposal(
            &ou,
            option::some(string::utf8(b"Mismatch test")),
            update_metadata::new(string::utf8(b"ipfs://malicious")),
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<UpdateMetadata>>();
        clock.set_for_testing(2_000);
        let vote_ou = scenario.take_shared_by_id<OU>(proposal.ou_id());
        board_voting::vote(&mut proposal, &vote_ou, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_ou);
        test_scenario::return_shared(proposal);
    };

    // Execute with OU B's charter — should abort
    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared_by_id<OU>(ou_a_id);
        let mut proposal = scenario.take_shared<Proposal<UpdateMetadata>>();
        let mut wrong_charter = scenario.take_shared_by_id<Charter>(ou_b_charter_id);
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(ou.emergency_freeze_id());
        clock.set_for_testing(3_000);

        let ticket = board_voting::ticket_from_vote(
            &mut ou,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        // This should abort with ECharterOuMismatch
        admin_ops::execute_update_metadata(
            &mut wrong_charter,
            ticket,
        );

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(wrong_charter);
        test_scenario::return_shared(ou);
    };

    clock.destroy_for_testing();
    scenario.end();
}

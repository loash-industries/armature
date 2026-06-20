#[test_only]
module armature_proposals::member_ops_tests;

use armature::board_voting;
use armature::dao::{Self, DAO};
use armature::emergency::EmergencyFreeze;
use armature::governance;
use armature::proposal::Proposal;
use armature_proposals::add_member::{Self, AddMember};
use armature_proposals::batch_add_members::{Self, BatchAddMembers};
use armature_proposals::batch_remove_members::{Self, BatchRemoveMembers};
use armature_proposals::member_ops;
use armature_proposals::remove_member::{Self, RemoveMember};
use std::string;
use sui::clock;
use sui::test_scenario;

const CREATOR: address = @0xA;
const MEMBER_B: address = @0xB;
const NEW_MEMBER: address = @0xC;
const BATCH_MEMBER_1: address = @0xD;
const BATCH_MEMBER_2: address = @0xE;
const BATCH_MEMBER_3: address = @0xF;

// =========================================================================
// AddMember tests
// =========================================================================

#[test]
/// E2E: Create DAO → create AddMember proposal → vote → execute → verify member added.
fun test_add_member_e2e() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    // 1. Create a DAO with Board governance (CREATOR + MEMBER_B)
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR, MEMBER_B]);
        dao::create(
            &init,
            string::utf8(b"Test DAO"),
            string::utf8(b"https://example.com/logo.png"),
            scenario.ctx(),
        );
    };

    // 2. Create a Proposal<AddMember> to add NEW_MEMBER
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);

        let payload = add_member::new(NEW_MEMBER);
        board_voting::submit_proposal(
            &dao,
            b"AddMember".to_ascii_string(),
            option::some(string::utf8(b"Add NEW_MEMBER to board")),
            payload,
            &clock,
            scenario.ctx(),
        );

        test_scenario::return_shared(dao);
    };

    // 3. Vote yes (CREATOR)
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<AddMember>>();
        clock.set_for_testing(2000);

        proposal.vote(true, &clock, scenario.ctx());

        test_scenario::return_shared(proposal);
    };

    // 4. Execute the proposal
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<AddMember>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        member_ops::execute_add_member(&mut dao, ticket);

        // 5. Verify the member was added
        let gov = dao.governance();
        assert!(gov.is_board_member(CREATOR));
        assert!(gov.is_board_member(MEMBER_B));
        assert!(gov.is_board_member(NEW_MEMBER));
        // encrypt_epoch should not change on add
        assert!(dao.encrypt_epoch() == 0);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = armature::governance::EDuplicateBoardMember)]
/// Adding an existing member should abort.
fun test_add_member_duplicate_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR, MEMBER_B]);
        dao::create(
            &init,
            string::utf8(b"Test DAO"),
            string::utf8(b"https://example.com/logo.png"),
            scenario.ctx(),
        );
    };

    // Propose adding MEMBER_B who is already on the board
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);

        let payload = add_member::new(MEMBER_B);
        board_voting::submit_proposal(
            &dao,
            b"AddMember".to_ascii_string(),
            option::some(string::utf8(b"Duplicate add")),
            payload,
            &clock,
            scenario.ctx(),
        );

        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<AddMember>>();
        clock.set_for_testing(2000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<AddMember>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        member_ops::execute_add_member(&mut dao, ticket);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// =========================================================================
// RemoveMember tests
// =========================================================================

#[test]
/// E2E: Create DAO → create RemoveMember proposal → vote → execute → verify member removed.
fun test_remove_member_e2e() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    // 1. Create a DAO with Board governance (CREATOR + MEMBER_B + NEW_MEMBER)
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR, MEMBER_B, NEW_MEMBER]);
        dao::create(
            &init,
            string::utf8(b"Test DAO"),
            string::utf8(b"https://example.com/logo.png"),
            scenario.ctx(),
        );
    };

    // 2. Create a Proposal<RemoveMember> to remove MEMBER_B
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);

        let payload = remove_member::new(MEMBER_B);
        board_voting::submit_proposal(
            &dao,
            b"RemoveMember".to_ascii_string(),
            option::some(string::utf8(b"Remove MEMBER_B from board")),
            payload,
            &clock,
            scenario.ctx(),
        );

        test_scenario::return_shared(dao);
    };

    // 3. Vote yes (CREATOR + NEW_MEMBER — need 2/3 for quorum)
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<RemoveMember>>();
        clock.set_for_testing(2000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(NEW_MEMBER);
    {
        let mut proposal = scenario.take_shared<Proposal<RemoveMember>>();
        clock.set_for_testing(2500);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    // 4. Execute the proposal
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<RemoveMember>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        member_ops::execute_remove_member(&mut dao, ticket);

        // 5. Verify the member was removed
        let gov = dao.governance();
        assert!(gov.is_board_member(CREATOR));
        assert!(!gov.is_board_member(MEMBER_B));
        assert!(gov.is_board_member(NEW_MEMBER));
        // encrypt_epoch should increment on removal
        assert!(dao.encrypt_epoch() == 1);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = armature::governance::ENotBoardMember)]
/// Removing a non-member should abort.
fun test_remove_nonmember_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR, MEMBER_B]);
        dao::create(
            &init,
            string::utf8(b"Test DAO"),
            string::utf8(b"https://example.com/logo.png"),
            scenario.ctx(),
        );
    };

    // Propose removing NEW_MEMBER who is not on the board
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);

        let payload = remove_member::new(NEW_MEMBER);
        board_voting::submit_proposal(
            &dao,
            b"RemoveMember".to_ascii_string(),
            option::some(string::utf8(b"Remove non-member")),
            payload,
            &clock,
            scenario.ctx(),
        );

        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<RemoveMember>>();
        clock.set_for_testing(2000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<RemoveMember>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        member_ops::execute_remove_member(&mut dao, ticket);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = armature::governance::EEmptyBoard)]
/// Removing the last member should abort (board can never be empty).
fun test_remove_last_member_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    // Create DAO with single member
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

    // Propose removing the only member
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);

        let payload = remove_member::new(CREATOR);
        board_voting::submit_proposal(
            &dao,
            b"RemoveMember".to_ascii_string(),
            option::some(string::utf8(b"Remove last member")),
            payload,
            &clock,
            scenario.ctx(),
        );

        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<RemoveMember>>();
        clock.set_for_testing(2000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<RemoveMember>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        member_ops::execute_remove_member(&mut dao, ticket);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// =========================================================================
// BatchAddMembers tests
// =========================================================================

#[test]
/// E2E: Create DAO → BatchAddMembers proposal → vote → execute → verify all added.
fun test_batch_add_members_e2e() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR, MEMBER_B]);
        dao::create(
            &init,
            string::utf8(b"Test DAO"),
            string::utf8(b"https://example.com/logo.png"),
            scenario.ctx(),
        );
    };

    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);

        let payload = batch_add_members::new(vector[
            BATCH_MEMBER_1,
            BATCH_MEMBER_2,
            BATCH_MEMBER_3,
        ]);
        board_voting::submit_proposal(
            &dao,
            b"BatchAddMembers".to_ascii_string(),
            option::some(string::utf8(b"Add three at once")),
            payload,
            &clock,
            scenario.ctx(),
        );

        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<BatchAddMembers>>();
        clock.set_for_testing(2000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<BatchAddMembers>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        member_ops::execute_batch_add_members(&mut dao, ticket);

        let gov = dao.governance();
        assert!(gov.is_board_member(CREATOR));
        assert!(gov.is_board_member(MEMBER_B));
        assert!(gov.is_board_member(BATCH_MEMBER_1));
        assert!(gov.is_board_member(BATCH_MEMBER_2));
        assert!(gov.is_board_member(BATCH_MEMBER_3));
        // encrypt_epoch should not change on add
        assert!(dao.encrypt_epoch() == 0);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// Batch containing an address already on the board should skip it silently:
/// new members are added, existing members are reported in the event's
/// `skipped` field rather than aborting the whole batch.
fun test_batch_add_members_existing_member_skipped() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR, MEMBER_B]);
        dao::create(
            &init,
            string::utf8(b"Test DAO"),
            string::utf8(b"https://example.com/logo.png"),
            scenario.ctx(),
        );
    };

    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);

        // MEMBER_B is already on the board; BATCH_MEMBER_1 is new.
        let payload = batch_add_members::new(vector[BATCH_MEMBER_1, MEMBER_B]);
        board_voting::submit_proposal(
            &dao,
            b"BatchAddMembers".to_ascii_string(),
            option::some(string::utf8(b"Batch with one existing")),
            payload,
            &clock,
            scenario.ctx(),
        );

        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<BatchAddMembers>>();
        clock.set_for_testing(2000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<BatchAddMembers>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        member_ops::execute_batch_add_members(&mut dao, ticket);

        // New member was added, existing member untouched.
        let gov = dao.governance();
        assert!(gov.is_board_member(CREATOR));
        assert!(gov.is_board_member(MEMBER_B));
        assert!(gov.is_board_member(BATCH_MEMBER_1));

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = armature::governance::EDuplicateBoardMember)]
/// Batch with an address duplicated within itself should abort atomically.
fun test_batch_add_members_internal_duplicate_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR, MEMBER_B]);
        dao::create(
            &init,
            string::utf8(b"Test DAO"),
            string::utf8(b"https://example.com/logo.png"),
            scenario.ctx(),
        );
    };

    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);

        // BATCH_MEMBER_1 appears twice within the batch itself
        let payload = batch_add_members::new(vector[
            BATCH_MEMBER_1,
            BATCH_MEMBER_2,
            BATCH_MEMBER_1,
        ]);
        board_voting::submit_proposal(
            &dao,
            b"BatchAddMembers".to_ascii_string(),
            option::some(string::utf8(b"Internal dup")),
            payload,
            &clock,
            scenario.ctx(),
        );

        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<BatchAddMembers>>();
        clock.set_for_testing(2000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<BatchAddMembers>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        member_ops::execute_batch_add_members(&mut dao, ticket);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = armature_proposals::member_ops::EEmptyBatch)]
/// Empty batch should abort with EEmptyBatch.
fun test_batch_add_members_empty_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR, MEMBER_B]);
        dao::create(
            &init,
            string::utf8(b"Test DAO"),
            string::utf8(b"https://example.com/logo.png"),
            scenario.ctx(),
        );
    };

    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);

        let payload = batch_add_members::new(vector[]);
        board_voting::submit_proposal(
            &dao,
            b"BatchAddMembers".to_ascii_string(),
            option::some(string::utf8(b"Empty")),
            payload,
            &clock,
            scenario.ctx(),
        );

        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<BatchAddMembers>>();
        clock.set_for_testing(2000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<BatchAddMembers>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        member_ops::execute_batch_add_members(&mut dao, ticket);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// =========================================================================
// BatchRemoveMembers tests
// =========================================================================

#[test]
/// E2E: Create DAO → BatchRemoveMembers proposal → vote → execute → verify removed.
fun test_batch_remove_members_e2e() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    // 4-member board: need 2 yes votes to reach 50% quorum
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[
            CREATOR,
            MEMBER_B,
            BATCH_MEMBER_1,
            BATCH_MEMBER_2,
        ]);
        dao::create(
            &init,
            string::utf8(b"Test DAO"),
            string::utf8(b"https://example.com/logo.png"),
            scenario.ctx(),
        );
    };

    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);
        board_voting::submit_proposal(
            &dao,
            b"BatchRemoveMembers".to_ascii_string(),
            option::some(string::utf8(b"Remove two members")),
            batch_remove_members::new(vector[BATCH_MEMBER_1, BATCH_MEMBER_2]),
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<BatchRemoveMembers>>();
        clock.set_for_testing(2000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(MEMBER_B);
    {
        let mut proposal = scenario.take_shared<Proposal<BatchRemoveMembers>>();
        clock.set_for_testing(2500);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<BatchRemoveMembers>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        member_ops::execute_batch_remove_members(&mut dao, ticket);

        let gov = dao.governance();
        assert!(gov.is_board_member(CREATOR));
        assert!(gov.is_board_member(MEMBER_B));
        assert!(!gov.is_board_member(BATCH_MEMBER_1));
        assert!(!gov.is_board_member(BATCH_MEMBER_2));
        // encrypt_epoch increments once for the batch
        assert!(dao.encrypt_epoch() == 1);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = armature::governance::ENotBoardMember)]
/// Removing a non-member address aborts.
fun test_batch_remove_members_nonmember_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR, MEMBER_B]);
        dao::create(
            &init,
            string::utf8(b"Test DAO"),
            string::utf8(b"https://example.com/logo.png"),
            scenario.ctx(),
        );
    };

    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);
        // NEW_MEMBER is not on the board
        board_voting::submit_proposal(
            &dao,
            b"BatchRemoveMembers".to_ascii_string(),
            option::some(string::utf8(b"Remove non-member")),
            batch_remove_members::new(vector[NEW_MEMBER]),
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<BatchRemoveMembers>>();
        clock.set_for_testing(2000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<BatchRemoveMembers>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        member_ops::execute_batch_remove_members(&mut dao, ticket);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = armature::governance::EDuplicateBoardMember)]
/// Batch containing an internally duplicated address aborts.
fun test_batch_remove_members_internal_duplicate_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR, MEMBER_B, NEW_MEMBER]);
        dao::create(
            &init,
            string::utf8(b"Test DAO"),
            string::utf8(b"https://example.com/logo.png"),
            scenario.ctx(),
        );
    };

    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);
        // MEMBER_B listed twice in the batch
        board_voting::submit_proposal(
            &dao,
            b"BatchRemoveMembers".to_ascii_string(),
            option::some(string::utf8(b"Dup in batch")),
            batch_remove_members::new(vector[MEMBER_B, MEMBER_B]),
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<BatchRemoveMembers>>();
        clock.set_for_testing(2000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(NEW_MEMBER);
    {
        let mut proposal = scenario.take_shared<Proposal<BatchRemoveMembers>>();
        clock.set_for_testing(2500);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<BatchRemoveMembers>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        member_ops::execute_batch_remove_members(&mut dao, ticket);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = armature::governance::EEmptyBoard)]
/// Removing all members aborts with EEmptyBoard.
fun test_batch_remove_members_would_empty_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    // 3-member board so we can reach 50% quorum with 2 voters while still
    // proposing to remove all 3 (which would leave the board empty).
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR, MEMBER_B, NEW_MEMBER]);
        dao::create(
            &init,
            string::utf8(b"Test DAO"),
            string::utf8(b"https://example.com/logo.png"),
            scenario.ctx(),
        );
    };

    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);
        // Removing all three members would leave the board empty
        board_voting::submit_proposal(
            &dao,
            b"BatchRemoveMembers".to_ascii_string(),
            option::some(string::utf8(b"Remove all")),
            batch_remove_members::new(vector[CREATOR, MEMBER_B, NEW_MEMBER]),
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<BatchRemoveMembers>>();
        clock.set_for_testing(2000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(MEMBER_B);
    {
        let mut proposal = scenario.take_shared<Proposal<BatchRemoveMembers>>();
        clock.set_for_testing(2500);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<BatchRemoveMembers>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        member_ops::execute_batch_remove_members(&mut dao, ticket);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = armature_proposals::member_ops::EEmptyBatch)]
/// Empty BatchRemoveMembers aborts with EEmptyBatch.
fun test_batch_remove_members_empty_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR, MEMBER_B]);
        dao::create(
            &init,
            string::utf8(b"Test DAO"),
            string::utf8(b"https://example.com/logo.png"),
            scenario.ctx(),
        );
    };

    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);
        board_voting::submit_proposal(
            &dao,
            b"BatchRemoveMembers".to_ascii_string(),
            option::some(string::utf8(b"Empty")),
            batch_remove_members::new(vector[]),
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<BatchRemoveMembers>>();
        clock.set_for_testing(2000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<BatchRemoveMembers>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        member_ops::execute_batch_remove_members(&mut dao, ticket);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = armature_proposals::member_ops::EBatchTooLarge)]
/// Batch exceeding MAX_BATCH_SIZE (100) should abort with EBatchTooLarge.
fun test_batch_add_members_oversize_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR, MEMBER_B]);
        dao::create(
            &init,
            string::utf8(b"Test DAO"),
            string::utf8(b"https://example.com/logo.png"),
            scenario.ctx(),
        );
    };

    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);

        // Build a batch of 101 distinct addresses: 31 zero bytes + 1 byte i,
        // starting at i=10 to stay clear of CREATOR/MEMBER_B/named consts.
        let mut addrs = vector::empty<address>();
        let mut i: u8 = 10;
        while ((i as u64) < 111) {
            let mut bytes = vector[
                0u8,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
            ];
            bytes.push_back(i);
            addrs.push_back(sui::address::from_bytes(bytes));
            i = i + 1;
        };

        let payload = batch_add_members::new(addrs);
        board_voting::submit_proposal(
            &dao,
            b"BatchAddMembers".to_ascii_string(),
            option::some(string::utf8(b"Too many")),
            payload,
            &clock,
            scenario.ctx(),
        );

        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<BatchAddMembers>>();
        clock.set_for_testing(2000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<BatchAddMembers>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        member_ops::execute_batch_add_members(&mut dao, ticket);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test_only]
module armature_proposals::member_ops_tests;

use armature::board_voting;
use armature::dao::{Self, DAO};
use armature::emergency::EmergencyFreeze;
use armature::governance;
use armature::proposal::Proposal;
use armature_proposals::add_member::{Self, AddMember};
use armature_proposals::member_ops;
use armature_proposals::remove_member::{Self, RemoveMember};
use std::string;
use sui::clock;
use sui::test_scenario;

const CREATOR: address = @0xA;
const MEMBER_B: address = @0xB;
const NEW_MEMBER: address = @0xC;

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
            string::utf8(b"Add member e2e test"),
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

        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        member_ops::execute_add_member(&mut dao, &proposal, request);

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
            string::utf8(b"Duplicate add test"),
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

        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        member_ops::execute_add_member(&mut dao, &proposal, request);

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
            string::utf8(b"Remove member e2e test"),
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

        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        member_ops::execute_remove_member(&mut dao, &proposal, request);

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
            string::utf8(b"Remove non-member test"),
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

        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        member_ops::execute_remove_member(&mut dao, &proposal, request);

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
            string::utf8(b"Remove last member test"),
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

        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        member_ops::execute_remove_member(&mut dao, &proposal, request);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test_only]
module armature_proposals::board_ops_tests;

use armature::board_ops;
use armature::board_voting;
use armature::emergency::EmergencyFreeze;
use armature::governance;
use armature::ou::{Self, OU};
use armature::proposal::{Self, Proposal};
use armature::set_board::{Self, SetBoard};
use std::string;
use sui::clock;
use sui::test_scenario;

const CREATOR: address = @0xA;
const MEMBER_B: address = @0xB;
const NEW_MEMBER: address = @0xC;
const MEMBER_D: address = @0xD;
const MEMBER_E: address = @0xE;

#[test]
/// E2E: Create OU → create SetBoard proposal → vote → execute → verify board changed.
fun test_set_board_e2e() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    // 1. Create an OU with Board governance (CREATOR + MEMBER_B)
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR, MEMBER_B]);
        ou::create(
            &init,
            string::utf8(b"Test OU"),
            string::utf8(b"https://example.com/logo.png"),
            scenario.ctx(),
        );
    };

    // 2. Create a Proposal<SetBoard> to add NEW_MEMBER
    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared<OU>();
        clock.set_for_testing(1000);

        let payload = set_board::new(vector[NEW_MEMBER], vector[]);
        board_voting::submit_proposal(
            &ou,
            option::some(string::utf8(b"Add NEW_MEMBER to board")),
            payload,
            &clock,
            scenario.ctx(),
        );

        test_scenario::return_shared(ou);
    };

    // 3. Vote yes (CREATOR) — with default config (quorum=50%, threshold=50%),
    // 1 out of 2 board members voting yes is enough to pass.
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<set_board::SetBoard>>();
        clock.set_for_testing(2000);

        let vote_ou = scenario.take_shared_by_id<OU>(proposal.ou_id());
        board_voting::vote(&mut proposal, &vote_ou, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_ou);

        test_scenario::return_shared(proposal);
    };

    // 4. Execute the proposal and call the handler
    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared<OU>();
        let mut proposal = scenario.take_shared<Proposal<set_board::SetBoard>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut ou,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        // Handler: apply the board change and consume the request
        board_ops::execute_set_board(&mut ou, ticket);

        // 5. Verify the board was updated
        let gov = ou.governance();
        assert!(gov.is_board_member(CREATOR));
        assert!(gov.is_board_member(MEMBER_B));
        assert!(gov.is_board_member(NEW_MEMBER));

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(ou);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = armature::governance::EEmptyBoard)]
/// Verify handler rejects empty board via governance validation.
fun test_set_board_empty_members_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    // Create OU
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR, MEMBER_B]);
        ou::create(
            &init,
            string::utf8(b"Test OU"),
            string::utf8(b"https://example.com/logo.png"),
            scenario.ctx(),
        );
    };

    // Create proposal removing every member
    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared<OU>();
        clock.set_for_testing(1000);

        let payload = set_board::new(vector[], vector[CREATOR, MEMBER_B]);
        board_voting::submit_proposal(
            &ou,
            option::some(string::utf8(b"Empty board")),
            payload,
            &clock,
            scenario.ctx(),
        );

        test_scenario::return_shared(ou);
    };

    // Vote to pass
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<set_board::SetBoard>>();
        clock.set_for_testing(2000);
        let vote_ou = scenario.take_shared_by_id<OU>(proposal.ou_id());
        board_voting::vote(&mut proposal, &vote_ou, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_ou);
        test_scenario::return_shared(proposal);
    };

    // Execute — should abort in governance::set_board with EEmptyBoard
    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared<OU>();
        let mut proposal = scenario.take_shared<Proposal<set_board::SetBoard>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut ou,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        board_ops::execute_set_board(&mut ou, ticket);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(ou);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// =========================================================================
// Full board replacement tests
// =========================================================================

/// Helper: create OU, submit SetBoard, vote to pass, execute, return new ou state.
fun setup_ou_with_board(
    members: vector<address>,
    scenario: &mut test_scenario::Scenario,
    clock: &clock::Clock,
): ID {
    let ou_id;
    scenario.next_tx(members[0]);
    {
        let init = governance::init_board(members);
        ou_id =
            ou::create(
                &init,
                string::utf8(b"Test OU"),
                string::utf8(b"https://example.com/logo.png"),
                scenario.ctx(),
            );
    };
    ou_id
}

#[test]
/// Full board replacement: swap all members atomically [A,B] → [C,D,E].
fun test_full_board_replacement() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    let ou_id = setup_ou_with_board(
        vector[CREATOR, MEMBER_B],
        &mut scenario,
        &mut clock,
    );

    // Propose replacing entire board
    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared_by_id<OU>(ou_id);
        clock.set_for_testing(1_000);
        let payload = set_board::new(
            vector[NEW_MEMBER, MEMBER_D, MEMBER_E],
            vector[CREATOR, MEMBER_B],
        );
        board_voting::submit_proposal(
            &ou,
            option::some(string::utf8(b"Full board replacement")),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    // Vote yes
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<SetBoard>>();
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
        let mut proposal = scenario.take_shared<Proposal<SetBoard>>();
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(ou.emergency_freeze_id());
        clock.set_for_testing(3_000);

        let ticket = board_voting::ticket_from_vote(
            &mut ou,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        board_ops::execute_set_board(&mut ou, ticket);

        // Old members gone
        assert!(!ou.governance().is_board_member(CREATOR));
        assert!(!ou.governance().is_board_member(MEMBER_B));
        // New members present
        assert!(ou.governance().is_board_member(NEW_MEMBER));
        assert!(ou.governance().is_board_member(MEMBER_D));
        assert!(ou.governance().is_board_member(MEMBER_E));

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(ou);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// Shrink board: [A,B,C] → [A] (single member).
fun test_shrink_board_to_single_member() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    let ou_id = setup_ou_with_board(
        vector[CREATOR, MEMBER_B, NEW_MEMBER],
        &mut scenario,
        &mut clock,
    );

    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared_by_id<OU>(ou_id);
        clock.set_for_testing(1_000);
        let payload = set_board::new(vector[], vector[MEMBER_B, NEW_MEMBER]);
        board_voting::submit_proposal(
            &ou,
            option::some(string::utf8(b"Shrink to solo")),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<SetBoard>>();
        clock.set_for_testing(2_000);
        let vote_ou = scenario.take_shared_by_id<OU>(proposal.ou_id());
        board_voting::vote(&mut proposal, &vote_ou, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_ou);
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(MEMBER_B);
    {
        let mut proposal = scenario.take_shared<Proposal<SetBoard>>();
        clock.set_for_testing(2_100);
        let vote_ou = scenario.take_shared_by_id<OU>(proposal.ou_id());
        board_voting::vote(&mut proposal, &vote_ou, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_ou);
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared_by_id<OU>(ou_id);
        let mut proposal = scenario.take_shared<Proposal<SetBoard>>();
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(ou.emergency_freeze_id());
        clock.set_for_testing(3_000);

        let ticket = board_voting::ticket_from_vote(
            &mut ou,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        board_ops::execute_set_board(&mut ou, ticket);

        assert!(ou.governance().is_board_member(CREATOR));
        assert!(!ou.governance().is_board_member(MEMBER_B));
        assert!(!ou.governance().is_board_member(NEW_MEMBER));

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(ou);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// Board grow: [A] → [A,B,C,D,E] (scale up from solo to 5-member board).
fun test_grow_board_from_single() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    let ou_id = setup_ou_with_board(
        vector[CREATOR],
        &mut scenario,
        &mut clock,
    );

    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared_by_id<OU>(ou_id);
        clock.set_for_testing(1_000);
        let payload = set_board::new(vector[MEMBER_B, NEW_MEMBER, MEMBER_D, MEMBER_E], vector[]);
        board_voting::submit_proposal(
            &ou,
            option::some(string::utf8(b"Scale up board")),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<SetBoard>>();
        clock.set_for_testing(2_000);
        let vote_ou = scenario.take_shared_by_id<OU>(proposal.ou_id());
        board_voting::vote(&mut proposal, &vote_ou, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_ou);
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared_by_id<OU>(ou_id);
        let mut proposal = scenario.take_shared<Proposal<SetBoard>>();
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(ou.emergency_freeze_id());
        clock.set_for_testing(3_000);

        let ticket = board_voting::ticket_from_vote(
            &mut ou,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        board_ops::execute_set_board(&mut ou, ticket);

        assert!(ou.governance().is_board_member(CREATOR));
        assert!(ou.governance().is_board_member(MEMBER_B));
        assert!(ou.governance().is_board_member(NEW_MEMBER));
        assert!(ou.governance().is_board_member(MEMBER_D));
        assert!(ou.governance().is_board_member(MEMBER_E));

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(ou);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// Sequential board changes: [A,B] → [A,C] → [C,D].
fun test_sequential_board_changes() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    let ou_id = setup_ou_with_board(
        vector[CREATOR, MEMBER_B],
        &mut scenario,
        &mut clock,
    );

    // First change: [A,B] → [A,C]
    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared_by_id<OU>(ou_id);
        clock.set_for_testing(1_000);
        board_voting::submit_proposal(
            &ou,
            option::some(string::utf8(b"Swap B for C")),
            set_board::new(vector[NEW_MEMBER], vector[MEMBER_B]),
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<SetBoard>>();
        clock.set_for_testing(2_000);
        let vote_ou = scenario.take_shared_by_id<OU>(proposal.ou_id());
        board_voting::vote(&mut proposal, &vote_ou, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_ou);
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared_by_id<OU>(ou_id);
        let mut proposal = scenario.take_shared<Proposal<SetBoard>>();
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(ou.emergency_freeze_id());
        clock.set_for_testing(3_000);
        let ticket = board_voting::ticket_from_vote(
            &mut ou,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        board_ops::execute_set_board(&mut ou, ticket);
        assert!(ou.governance().is_board_member(CREATOR));
        assert!(ou.governance().is_board_member(NEW_MEMBER));
        assert!(!ou.governance().is_board_member(MEMBER_B));
        test_scenario::return_shared(freeze);
        test_scenario::return_shared(ou);
    };

    // Second change: [A,C] → [C,D]
    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared_by_id<OU>(ou_id);
        clock.set_for_testing(10_000);
        board_voting::submit_proposal(
            &ou,
            option::some(string::utf8(b"Swap A for D")),
            set_board::new(vector[MEMBER_D], vector[CREATOR]),
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<SetBoard>>();
        clock.set_for_testing(11_000);
        let vote_ou = scenario.take_shared_by_id<OU>(proposal.ou_id());
        board_voting::vote(&mut proposal, &vote_ou, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_ou);
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared_by_id<OU>(ou_id);
        let mut proposal = scenario.take_shared<Proposal<SetBoard>>();
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(ou.emergency_freeze_id());
        clock.set_for_testing(12_000);
        let ticket = board_voting::ticket_from_vote(
            &mut ou,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        board_ops::execute_set_board(&mut ou, ticket);
        assert!(!ou.governance().is_board_member(CREATOR));
        assert!(ou.governance().is_board_member(NEW_MEMBER));
        assert!(ou.governance().is_board_member(MEMBER_D));
        test_scenario::return_shared(freeze);
        test_scenario::return_shared(ou);
    };

    clock.destroy_for_testing();
    scenario.end();
}

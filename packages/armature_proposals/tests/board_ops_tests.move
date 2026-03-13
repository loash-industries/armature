#[test_only]
module armature_proposals::board_ops_tests;

use armature::board_voting;
use armature::dao::{Self, DAO};
use armature::emergency::EmergencyFreeze;
use armature::governance;
use armature::proposal::{Self, Proposal};
use armature_proposals::board_ops;
use armature_proposals::set_board::{Self, SetBoard};
use std::string;
use sui::clock;
use sui::test_scenario;

const CREATOR: address = @0xA;
const MEMBER_B: address = @0xB;
const NEW_MEMBER: address = @0xC;
const MEMBER_D: address = @0xD;
const MEMBER_E: address = @0xE;

#[test]
/// E2E: Create DAO → create SetBoard proposal → vote → execute → verify board changed.
fun test_set_board_e2e() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    // 1. Create a DAO with Board governance (CREATOR + MEMBER_B)
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR, MEMBER_B]);
        dao::create(
            &init,
            string::utf8(b"Test DAO"),
            string::utf8(b"Board update e2e test"),
            string::utf8(b"https://example.com/logo.png"),
            scenario.ctx(),
        );
    };

    // 2. Create a Proposal<SetBoard> to add NEW_MEMBER
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);

        let payload = set_board::new(vector[CREATOR, MEMBER_B, NEW_MEMBER]);
        board_voting::submit_proposal(
            &dao,
            b"SetBoard".to_ascii_string(),
            string::utf8(b"Add NEW_MEMBER to board"),
            payload,
            &clock,
            scenario.ctx(),
        );

        test_scenario::return_shared(dao);
    };

    // 3. Vote yes (CREATOR) — with default config (quorum=50%, threshold=50%),
    //    1 out of 2 board members voting yes is enough to pass.
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<set_board::SetBoard>>();
        clock.set_for_testing(2000);

        proposal.vote(true, &clock, scenario.ctx());

        test_scenario::return_shared(proposal);
    };

    // 4. Execute the proposal and call the handler
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<set_board::SetBoard>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        // Handler: apply the board change and consume the request
        board_ops::execute_set_board(&mut dao, &proposal, request);

        // 5. Verify the board was updated
        let gov = dao.governance();
        assert!(gov.is_board_member(CREATOR));
        assert!(gov.is_board_member(MEMBER_B));
        assert!(gov.is_board_member(NEW_MEMBER));

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = armature::governance::EEmptyBoard)]
/// Verify handler rejects empty board via governance validation.
fun test_set_board_empty_members_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    // Create DAO
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR, MEMBER_B]);
        dao::create(
            &init,
            string::utf8(b"Test DAO"),
            string::utf8(b"Empty board test"),
            string::utf8(b"https://example.com/logo.png"),
            scenario.ctx(),
        );
    };

    // Create proposal with empty members
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);

        let payload = set_board::new(vector[]);
        board_voting::submit_proposal(
            &dao,
            b"SetBoard".to_ascii_string(),
            string::utf8(b"Empty board"),
            payload,
            &clock,
            scenario.ctx(),
        );

        test_scenario::return_shared(dao);
    };

    // Vote to pass
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<set_board::SetBoard>>();
        clock.set_for_testing(2000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    // Execute — should abort in governance::set_board with EEmptyBoard
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<set_board::SetBoard>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        board_ops::execute_set_board(&mut dao, &proposal, request);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// =========================================================================
// Full board replacement tests
// =========================================================================

/// Helper: create DAO, submit SetBoard, vote to pass, execute, return new dao state.
fun setup_dao_with_board(
    members: vector<address>,
    scenario: &mut test_scenario::Scenario,
    clock: &clock::Clock,
): ID {
    let dao_id;
    scenario.next_tx(members[0]);
    {
        let init = governance::init_board(members);
        dao_id =
            dao::create(
                &init,
                string::utf8(b"Test DAO"),
                string::utf8(b"Board ops test"),
                string::utf8(b"https://example.com/logo.png"),
                scenario.ctx(),
            );
    };
    dao_id
}

#[test]
/// Full board replacement: swap all members atomically [A,B] → [C,D,E].
fun test_full_board_replacement() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    let dao_id = setup_dao_with_board(
        vector[CREATOR, MEMBER_B],
        &mut scenario,
        &mut clock,
    );

    // Propose replacing entire board
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared_by_id<DAO>(dao_id);
        clock.set_for_testing(1_000);
        let payload = set_board::new(vector[NEW_MEMBER, MEMBER_D, MEMBER_E]);
        board_voting::submit_proposal(
            &dao,
            b"SetBoard".to_ascii_string(),
            string::utf8(b"Full board replacement"),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    // Vote yes
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<SetBoard>>();
        clock.set_for_testing(2_000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    // Execute
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared_by_id<DAO>(dao_id);
        let mut proposal = scenario.take_shared<Proposal<SetBoard>>();
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(dao.emergency_freeze_id());
        clock.set_for_testing(3_000);

        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        board_ops::execute_set_board(&mut dao, &proposal, request);

        // Old members gone
        assert!(!dao.governance().is_board_member(CREATOR));
        assert!(!dao.governance().is_board_member(MEMBER_B));
        // New members present
        assert!(dao.governance().is_board_member(NEW_MEMBER));
        assert!(dao.governance().is_board_member(MEMBER_D));
        assert!(dao.governance().is_board_member(MEMBER_E));

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// Shrink board: [A,B,C] → [A] (single member).
fun test_shrink_board_to_single_member() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    let dao_id = setup_dao_with_board(
        vector[CREATOR, MEMBER_B, NEW_MEMBER],
        &mut scenario,
        &mut clock,
    );

    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared_by_id<DAO>(dao_id);
        clock.set_for_testing(1_000);
        let payload = set_board::new(vector[CREATOR]);
        board_voting::submit_proposal(
            &dao,
            b"SetBoard".to_ascii_string(),
            string::utf8(b"Shrink to solo"),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<SetBoard>>();
        clock.set_for_testing(2_000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(MEMBER_B);
    {
        let mut proposal = scenario.take_shared<Proposal<SetBoard>>();
        clock.set_for_testing(2_100);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared_by_id<DAO>(dao_id);
        let mut proposal = scenario.take_shared<Proposal<SetBoard>>();
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(dao.emergency_freeze_id());
        clock.set_for_testing(3_000);

        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        board_ops::execute_set_board(&mut dao, &proposal, request);

        assert!(dao.governance().is_board_member(CREATOR));
        assert!(!dao.governance().is_board_member(MEMBER_B));
        assert!(!dao.governance().is_board_member(NEW_MEMBER));

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// Board grow: [A] → [A,B,C,D,E] (scale up from solo to 5-member board).
fun test_grow_board_from_single() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    let dao_id = setup_dao_with_board(
        vector[CREATOR],
        &mut scenario,
        &mut clock,
    );

    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared_by_id<DAO>(dao_id);
        clock.set_for_testing(1_000);
        let payload = set_board::new(vector[CREATOR, MEMBER_B, NEW_MEMBER, MEMBER_D, MEMBER_E]);
        board_voting::submit_proposal(
            &dao,
            b"SetBoard".to_ascii_string(),
            string::utf8(b"Scale up board"),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<SetBoard>>();
        clock.set_for_testing(2_000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared_by_id<DAO>(dao_id);
        let mut proposal = scenario.take_shared<Proposal<SetBoard>>();
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(dao.emergency_freeze_id());
        clock.set_for_testing(3_000);

        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        board_ops::execute_set_board(&mut dao, &proposal, request);

        assert!(dao.governance().is_board_member(CREATOR));
        assert!(dao.governance().is_board_member(MEMBER_B));
        assert!(dao.governance().is_board_member(NEW_MEMBER));
        assert!(dao.governance().is_board_member(MEMBER_D));
        assert!(dao.governance().is_board_member(MEMBER_E));

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// Sequential board changes: [A,B] → [A,C] → [C,D].
fun test_sequential_board_changes() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    let dao_id = setup_dao_with_board(
        vector[CREATOR, MEMBER_B],
        &mut scenario,
        &mut clock,
    );

    // First change: [A,B] → [A,C]
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared_by_id<DAO>(dao_id);
        clock.set_for_testing(1_000);
        board_voting::submit_proposal(
            &dao,
            b"SetBoard".to_ascii_string(),
            string::utf8(b"Swap B for C"),
            set_board::new(vector[CREATOR, NEW_MEMBER]),
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<SetBoard>>();
        clock.set_for_testing(2_000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared_by_id<DAO>(dao_id);
        let mut proposal = scenario.take_shared<Proposal<SetBoard>>();
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(dao.emergency_freeze_id());
        clock.set_for_testing(3_000);
        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        board_ops::execute_set_board(&mut dao, &proposal, request);
        assert!(dao.governance().is_board_member(CREATOR));
        assert!(dao.governance().is_board_member(NEW_MEMBER));
        assert!(!dao.governance().is_board_member(MEMBER_B));
        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    // Second change: [A,C] → [C,D]
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared_by_id<DAO>(dao_id);
        clock.set_for_testing(10_000);
        board_voting::submit_proposal(
            &dao,
            b"SetBoard".to_ascii_string(),
            string::utf8(b"Swap A for D"),
            set_board::new(vector[NEW_MEMBER, MEMBER_D]),
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<SetBoard>>();
        clock.set_for_testing(11_000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared_by_id<DAO>(dao_id);
        let mut proposal = scenario.take_shared<Proposal<SetBoard>>();
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(dao.emergency_freeze_id());
        clock.set_for_testing(12_000);
        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        board_ops::execute_set_board(&mut dao, &proposal, request);
        assert!(!dao.governance().is_board_member(CREATOR));
        assert!(dao.governance().is_board_member(NEW_MEMBER));
        assert!(dao.governance().is_board_member(MEMBER_D));
        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

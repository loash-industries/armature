#[test_only]
module armature_proposals::board_ops_tests;

use armature::board_voting;
use armature::dao::{Self, DAO};
use armature::governance;
use armature::proposal::Proposal;
use armature_proposals::board_ops;
use armature_proposals::set_board;
use std::string;
use sui::clock;
use sui::test_scenario;

const CREATOR: address = @0xA;
const MEMBER_B: address = @0xB;
const NEW_MEMBER: address = @0xC;

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
        clock.set_for_testing(3000);

        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
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
        clock.set_for_testing(3000);

        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
            &clock,
            scenario.ctx(),
        );
        board_ops::execute_set_board(&mut dao, &proposal, request);

        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

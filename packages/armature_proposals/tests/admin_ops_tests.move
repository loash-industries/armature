#[test_only]
module armature_proposals::admin_ops_tests;

use armature::board_voting;
use armature::dao::{Self, DAO};
use armature::governance;
use armature::proposal::{Self, Proposal};
use armature_proposals::admin_ops;
use armature_proposals::enable_proposal_type::{Self, EnableProposalType};
use std::string;
use sui::clock;
use sui::test_scenario;

const CREATOR: address = @0xA;

// === Test helpers ===

/// Create a standalone DAO (no controller) with a single board member.
fun create_dao(scenario: &mut test_scenario::Scenario) {
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR]);
        dao::create(
            &init,
            string::utf8(b"Test DAO"),
            string::utf8(b"A test DAO"),
            string::utf8(b"https://example.com/logo.png"),
            scenario.ctx(),
        );
    };
}

/// Create a SubDAO with a controller cap ID set, then share it.
fun create_and_share_subdao(scenario: &mut test_scenario::Scenario) {
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR]);
        let (subdao, freeze_cap) = dao::create_subdao(
            &init,
            string::utf8(b"Sub DAO"),
            string::utf8(b"A test sub-DAO"),
            string::utf8(b"https://example.com/sub.png"),
            scenario.ctx(),
        );
        // Use the FreezeAdminCap's object ID as a stand-in controller cap ID.
        let controller_id = sui::object::id(&freeze_cap);
        dao::share_subdao(subdao, controller_id);
        std::unit_test::destroy(freeze_cap);
    };
}

/// Submit an EnableProposalType proposal for the given type key.
fun submit_enable_type_proposal(
    scenario: &mut test_scenario::Scenario,
    clock: &clock::Clock,
    type_key: vector<u8>,
) {
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        let payload = enable_proposal_type::new(type_key.to_ascii_string(), config);
        board_voting::submit_proposal(
            &dao,
            b"EnableProposalType".to_ascii_string(),
            string::utf8(b"Enable proposal type"),
            payload,
            clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };
}

/// Vote yes on the pending proposal (single board member → 100% approval).
fun vote_yes(scenario: &mut test_scenario::Scenario, clock: &clock::Clock) {
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<EnableProposalType>>();
        proposal.vote(true, clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };
}

// === Tests ===

#[test, expected_failure(abort_code = admin_ops::ESubDAOBlockedType)]
/// SubDAO with a controller cannot enable hierarchy-altering types (SpawnDAO).
fun enable_blocked_type_aborts_for_subdao_with_controller() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_and_share_subdao(&mut scenario);
    clock.set_for_testing(1000);
    submit_enable_type_proposal(&mut scenario, &clock, b"SpawnDAO");
    clock.set_for_testing(2000);
    vote_yes(&mut scenario, &clock);

    // Execute — must abort with ESubDAOBlockedType
    scenario.next_tx(CREATOR);
    {
        let mut subdao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<EnableProposalType>>();
        clock.set_for_testing(3000);

        let request = board_voting::authorize_execution(
            &mut subdao,
            &mut proposal,
            &clock,
            scenario.ctx(),
        );
        admin_ops::execute_enable_proposal_type(&mut subdao, &proposal, request);

        test_scenario::return_shared(proposal);
        test_scenario::return_shared(subdao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// SubDAO with a controller CAN enable a non-blocked type.
fun enable_non_blocked_type_succeeds_for_subdao_with_controller() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_and_share_subdao(&mut scenario);
    clock.set_for_testing(1000);
    submit_enable_type_proposal(&mut scenario, &clock, b"CustomAction");
    clock.set_for_testing(2000);
    vote_yes(&mut scenario, &clock);

    scenario.next_tx(CREATOR);
    {
        let mut subdao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<EnableProposalType>>();
        clock.set_for_testing(3000);

        let request = board_voting::authorize_execution(
            &mut subdao,
            &mut proposal,
            &clock,
            scenario.ctx(),
        );
        admin_ops::execute_enable_proposal_type(&mut subdao, &proposal, request);

        // Verify the type was added
        assert!(subdao.enabled_proposal_types().contains(&b"CustomAction".to_ascii_string()));

        test_scenario::return_shared(proposal);
        test_scenario::return_shared(subdao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// Independent DAO (no controller) CAN enable a hierarchy-altering type (SpawnDAO).
fun enable_blocked_type_succeeds_for_independent_dao() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_dao(&mut scenario);
    clock.set_for_testing(1000);
    submit_enable_type_proposal(&mut scenario, &clock, b"SpawnDAO");
    clock.set_for_testing(2000);
    vote_yes(&mut scenario, &clock);

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<EnableProposalType>>();
        clock.set_for_testing(3000);

        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
            &clock,
            scenario.ctx(),
        );
        admin_ops::execute_enable_proposal_type(&mut dao, &proposal, request);

        // Verify SpawnDAO is now enabled
        assert!(dao.enabled_proposal_types().contains(&b"SpawnDAO".to_ascii_string()));

        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test_only]
module armature_proposals::emergency_freeze_tests;

use armature::board_voting;
use armature::dao::{Self, DAO};
use armature::emergency::{Self, EmergencyFreeze, FreezeAdminCap};
use armature::governance;
use armature::proposal::Proposal;
use armature_proposals::board_ops;
use armature_proposals::security_ops;
use armature_proposals::set_board::{Self, SetBoard};
use armature_proposals::unfreeze_proposal_type::{Self, UnfreezeProposalType};
use std::string;
use sui::clock;
use sui::test_scenario;

const CREATOR: address = @0xA;
const MEMBER_B: address = @0xB;

// === Helpers ===

fun create_dao(scenario: &mut test_scenario::Scenario): ID {
    scenario.next_tx(CREATOR);
    let init = governance::init_board(vector[CREATOR, MEMBER_B]);
    dao::create(
        &init,
        string::utf8(b"Test DAO"),
        string::utf8(b"Emergency freeze test"),
        string::utf8(b"https://example.com/logo.png"),
        scenario.ctx(),
    )
}

fun submit_set_board(
    scenario: &mut test_scenario::Scenario,
    clock: &clock::Clock,
    new_members: vector<address>,
) {
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let payload = set_board::new(new_members);
        board_voting::submit_proposal(
            &dao,
            b"SetBoard".to_ascii_string(),
            string::utf8(b"Board change"),
            payload,
            clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };
}

fun vote_yes_set_board(scenario: &mut test_scenario::Scenario, clock: &clock::Clock) {
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<SetBoard>>();
        proposal.vote(true, clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };
}

// =========================================================================
// E2E: Freeze type → attempt execute (fail) → unfreeze → execute (succeed)
// =========================================================================

#[test, expected_failure(abort_code = emergency::EFrozen)]
/// Frozen type blocks authorize_execution.
fun frozen_type_blocks_execution() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_dao(&mut scenario);

    // Submit + pass a SetBoard proposal
    clock.set_for_testing(1000);
    submit_set_board(&mut scenario, &clock, vector[CREATOR, MEMBER_B]);
    clock.set_for_testing(2000);
    vote_yes_set_board(&mut scenario, &clock);

    // Freeze "SetBoard" type
    scenario.next_tx(CREATOR);
    {
        let mut freeze = scenario.take_shared<EmergencyFreeze>();
        let cap = scenario.take_from_sender<FreezeAdminCap>();
        clock.set_for_testing(3000);
        freeze.freeze_type(&cap, b"SetBoard".to_ascii_string(), &clock);
        assert!(freeze.is_frozen(&b"SetBoard".to_ascii_string(), &clock));
        scenario.return_to_sender(cap);
        test_scenario::return_shared(freeze);
    };

    // Attempt execute — should abort with EFrozen
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<SetBoard>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(4000);

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

#[test]
/// Freeze → unfreeze via admin cap → execute succeeds.
fun unfreeze_allows_execution() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_dao(&mut scenario);

    // Submit + pass a SetBoard proposal
    clock.set_for_testing(1000);
    submit_set_board(&mut scenario, &clock, vector[CREATOR, MEMBER_B]);
    clock.set_for_testing(2000);
    vote_yes_set_board(&mut scenario, &clock);

    // Freeze "SetBoard" type
    scenario.next_tx(CREATOR);
    {
        let mut freeze = scenario.take_shared<EmergencyFreeze>();
        let cap = scenario.take_from_sender<FreezeAdminCap>();
        clock.set_for_testing(3000);
        freeze.freeze_type(&cap, b"SetBoard".to_ascii_string(), &clock);
        assert!(freeze.is_frozen(&b"SetBoard".to_ascii_string(), &clock));

        // Unfreeze via admin cap
        freeze.unfreeze_type(&cap, b"SetBoard".to_ascii_string());
        assert!(!freeze.is_frozen(&b"SetBoard".to_ascii_string(), &clock));

        scenario.return_to_sender(cap);
        test_scenario::return_shared(freeze);
    };

    // Execute — should succeed now
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<SetBoard>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(4000);

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
// Auto-expiry: Freeze expires after max_freeze_duration_ms, execution succeeds
// =========================================================================

#[test]
/// Freeze automatically expires after max_freeze_duration_ms, allowing execution.
fun auto_expiry_allows_execution() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_dao(&mut scenario);

    // Submit + pass a SetBoard proposal
    clock.set_for_testing(1000);
    submit_set_board(&mut scenario, &clock, vector[CREATOR, MEMBER_B]);
    clock.set_for_testing(2000);
    vote_yes_set_board(&mut scenario, &clock);

    // Freeze "SetBoard" type at t=3000
    scenario.next_tx(CREATOR);
    {
        let mut freeze = scenario.take_shared<EmergencyFreeze>();
        let cap = scenario.take_from_sender<FreezeAdminCap>();
        clock.set_for_testing(3000);
        freeze.freeze_type(&cap, b"SetBoard".to_ascii_string(), &clock);

        // Should be frozen now
        assert!(freeze.is_frozen(&b"SetBoard".to_ascii_string(), &clock));

        scenario.return_to_sender(cap);
        test_scenario::return_shared(freeze);
    };

    // Advance clock past freeze expiry (default max = 604_800_000 ms = 7 days)
    // Freeze was at t=3000, expiry at t=3000 + 604_800_000 = 604_803_000
    let after_expiry = 3000 + 604_800_000 + 1;

    // Execute after expiry — should succeed without unfreezing
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<SetBoard>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(after_expiry);

        // Verify freeze expired
        assert!(!freeze.is_frozen(&b"SetBoard".to_ascii_string(), &clock));

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
// Governance unfreeze: Board can unfreeze via UnfreezeProposalType proposal
// =========================================================================

#[test]
/// Board governance can unfreeze a type via UnfreezeProposalType proposal.
fun governance_unfreeze_via_proposal() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_dao(&mut scenario);

    // Freeze "SetBoard" type
    scenario.next_tx(CREATOR);
    {
        let mut freeze = scenario.take_shared<EmergencyFreeze>();
        let cap = scenario.take_from_sender<FreezeAdminCap>();
        clock.set_for_testing(1000);
        freeze.freeze_type(&cap, b"SetBoard".to_ascii_string(), &clock);
        scenario.return_to_sender(cap);
        test_scenario::return_shared(freeze);
    };

    // Submit + vote UnfreezeProposalType proposal
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(2000);
        let payload = unfreeze_proposal_type::new(b"SetBoard".to_ascii_string());
        board_voting::submit_proposal(
            &dao,
            b"UnfreezeProposalType".to_ascii_string(),
            string::utf8(b"Unfreeze SetBoard"),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<UnfreezeProposalType>>();
        clock.set_for_testing(3000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    // Execute UnfreezeProposalType — UnfreezeProposalType is itself exempt from freezing
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<UnfreezeProposalType>>();
        let mut freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(4000);

        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        security_ops::execute_unfreeze_proposal_type(&mut freeze, &proposal, request);

        // Verify SetBoard is no longer frozen
        assert!(!freeze.is_frozen(&b"SetBoard".to_ascii_string(), &clock));

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// =========================================================================
// Protected types: TransferFreezeAdmin and UnfreezeProposalType cannot be frozen
// =========================================================================

#[test, expected_failure(abort_code = emergency::EProtectedType)]
/// Cannot freeze the TransferFreezeAdmin type (exempt by default).
fun cannot_freeze_transfer_freeze_admin() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_dao(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let mut freeze = scenario.take_shared<EmergencyFreeze>();
        let cap = scenario.take_from_sender<FreezeAdminCap>();
        clock.set_for_testing(1000);
        freeze.freeze_type(&cap, b"TransferFreezeAdmin".to_ascii_string(), &clock);
        scenario.return_to_sender(cap);
        test_scenario::return_shared(freeze);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = emergency::EProtectedType)]
/// Cannot freeze the UnfreezeProposalType type (exempt by default).
fun cannot_freeze_unfreeze_proposal_type() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_dao(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let mut freeze = scenario.take_shared<EmergencyFreeze>();
        let cap = scenario.take_from_sender<FreezeAdminCap>();
        clock.set_for_testing(1000);
        freeze.freeze_type(&cap, b"UnfreezeProposalType".to_ascii_string(), &clock);
        scenario.return_to_sender(cap);
        test_scenario::return_shared(freeze);
    };

    clock.destroy_for_testing();
    scenario.end();
}

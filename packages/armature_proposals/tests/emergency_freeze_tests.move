#[test_only]
module armature_proposals::emergency_freeze_tests;

use armature::board_voting;
use armature::dao::{Self, DAO};
use armature::emergency::{Self, EmergencyFreeze, FreezeAdminCap};
use armature::governance;
use armature::proposal::{Self, Proposal};
use armature::set_board::{Self, SetBoard};
use armature::transfer_freeze_admin::TransferFreezeAdmin;
use armature::unfreeze_proposal_type::{Self, UnfreezeProposalType};
use armature_proposals::board_ops;
use armature_proposals::security_ops;
use armature_proposals::type_permissions;
use armature_proposals::update_freeze_config::{Self, UpdateFreezeConfig};
use armature_proposals::update_freeze_exempt_types::{Self, UpdateFreezeExemptTypes};
use std::string;
use std::type_name;
use sui::clock;
use sui::test_scenario;

const CREATOR: address = @0xA;
const MEMBER_B: address = @0xB;
const MEMBER_C: address = @0xC;

// === Helpers ===

fun create_dao(scenario: &mut test_scenario::Scenario): ID {
    scenario.next_tx(CREATOR);
    let init = governance::init_board(vector[CREATOR, MEMBER_B]);
    dao::create(
        &init,
        string::utf8(b"Test DAO"),
        string::utf8(b"https://example.com/logo.png"),
        scenario.ctx(),
    )
}

fun submit_set_board(
    scenario: &mut test_scenario::Scenario,
    clock: &clock::Clock,
    to_add: vector<address>,
) {
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let payload = set_board::new(to_add, vector[]);
        board_voting::submit_proposal(
            &dao,
            option::some(string::utf8(b"Board change")),
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
        let vote_dao = scenario.take_shared_by_id<DAO>(proposal.dao_id());
        board_voting::vote(&mut proposal, &vote_dao, true, clock, scenario.ctx());
        test_scenario::return_shared(vote_dao);
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
    submit_set_board(&mut scenario, &clock, vector[MEMBER_C]);
    clock.set_for_testing(2000);
    vote_yes_set_board(&mut scenario, &clock);

    // Freeze the SetBoard type
    scenario.next_tx(CREATOR);
    {
        let mut freeze = scenario.take_shared<EmergencyFreeze>();
        let cap = scenario.take_from_sender<FreezeAdminCap>();
        clock.set_for_testing(3000);
        freeze.freeze_type<SetBoard>(&cap, &clock);
        assert!(freeze.is_frozen<SetBoard>(&clock));
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

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        board_ops::execute_set_board(&mut dao, ticket);
        test_scenario::return_shared(freeze);
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
    submit_set_board(&mut scenario, &clock, vector[MEMBER_C]);
    clock.set_for_testing(2000);
    vote_yes_set_board(&mut scenario, &clock);

    // Freeze the SetBoard type
    scenario.next_tx(CREATOR);
    {
        let mut freeze = scenario.take_shared<EmergencyFreeze>();
        let cap = scenario.take_from_sender<FreezeAdminCap>();
        clock.set_for_testing(3000);
        freeze.freeze_type<SetBoard>(&cap, &clock);
        assert!(freeze.is_frozen<SetBoard>(&clock));

        // Unfreeze via admin cap
        freeze.unfreeze_type<SetBoard>(&cap);
        assert!(!freeze.is_frozen<SetBoard>(&clock));

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

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        board_ops::execute_set_board(&mut dao, ticket);

        test_scenario::return_shared(freeze);
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

    // Submit a SetBoard proposal
    clock.set_for_testing(1000);
    submit_set_board(&mut scenario, &clock, vector[MEMBER_C]);

    // Freeze the SetBoard type at t=3000
    scenario.next_tx(CREATOR);
    {
        let mut freeze = scenario.take_shared<EmergencyFreeze>();
        let cap = scenario.take_from_sender<FreezeAdminCap>();
        clock.set_for_testing(3000);
        freeze.freeze_type<SetBoard>(&cap, &clock);

        // Should be frozen now
        assert!(freeze.is_frozen<SetBoard>(&clock));

        scenario.return_to_sender(cap);
        test_scenario::return_shared(freeze);
    };

    // Pass it while frozen (a freeze blocks execution, not voting). Its
    // execution window (expiry_ms = 7 days from passing) then outlasts the freeze.
    clock.set_for_testing(4000);
    vote_yes_set_board(&mut scenario, &clock);

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
        assert!(!freeze.is_frozen<SetBoard>(&clock));

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        board_ops::execute_set_board(&mut dao, ticket);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// =========================================================================
// Freeze outlasting a passed proposal's execution window cancels it
// =========================================================================

/// Pass a SetBoard proposal at t=2000, then freeze the type at t=3000. With the
/// default 7-day expiry_ms and 7-day freeze, the execution window closes at
/// t=604_802_000, before the freeze lifts at t=604_803_000.
fun pass_then_freeze(scenario: &mut test_scenario::Scenario, clock: &mut clock::Clock) {
    create_dao(scenario);
    clock.set_for_testing(1000);
    submit_set_board(scenario, clock, vector[MEMBER_C]);
    clock.set_for_testing(2000);
    vote_yes_set_board(scenario, clock);

    scenario.next_tx(CREATOR);
    {
        let mut freeze = scenario.take_shared<EmergencyFreeze>();
        let cap = scenario.take_from_sender<FreezeAdminCap>();
        clock.set_for_testing(3000);
        freeze.freeze_type<SetBoard>(&cap, clock);
        scenario.return_to_sender(cap);
        test_scenario::return_shared(freeze);
    };

    clock.set_for_testing(3000 + 604_800_000 + 1);
}

#[test, expected_failure(abort_code = proposal::EExecutionWindowClosed)]
/// Accepted behaviour: once the freeze lifts, the window has closed, so the
/// proposal can no longer execute and must be re-proposed.
fun freeze_outlasting_window_blocks_execution() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    pass_then_freeze(&mut scenario, &mut clock);

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let proposal = scenario.take_shared<Proposal<SetBoard>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        board_ops::execute_set_board(&mut dao, ticket);
        test_scenario::return_shared(freeze);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// The cancelled proposal can be deleted by anyone.
fun freeze_outlasting_window_allows_delete() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    pass_then_freeze(&mut scenario, &mut clock);

    scenario.next_tx(MEMBER_B);
    {
        let proposal = scenario.take_shared<Proposal<SetBoard>>();
        proposal::delete_expired_proposal(proposal, &clock);
    };

    scenario.next_tx(CREATOR);
    assert!(!test_scenario::has_most_recent_shared<Proposal<SetBoard>>());

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

    // Freeze the SetBoard type
    scenario.next_tx(CREATOR);
    {
        let mut freeze = scenario.take_shared<EmergencyFreeze>();
        let cap = scenario.take_from_sender<FreezeAdminCap>();
        clock.set_for_testing(1000);
        freeze.freeze_type<SetBoard>(&cap, &clock);
        scenario.return_to_sender(cap);
        test_scenario::return_shared(freeze);
    };

    // Submit + vote UnfreezeProposalType proposal
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(2000);
        let payload = unfreeze_proposal_type::new<SetBoard>();
        board_voting::submit_proposal(
            &dao,
            option::some(string::utf8(b"Unfreeze SetBoard")),
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
        let vote_dao = scenario.take_shared_by_id<DAO>(proposal.dao_id());
        board_voting::vote(&mut proposal, &vote_dao, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_dao);
        test_scenario::return_shared(proposal);
    };

    // Execute UnfreezeProposalType — UnfreezeProposalType is itself exempt from freezing
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<UnfreezeProposalType>>();
        let mut freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(4000);

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        security_ops::execute_unfreeze_proposal_type(&mut freeze, ticket);

        // Verify SetBoard is no longer frozen
        assert!(!freeze.is_frozen<SetBoard>(&clock));

        test_scenario::return_shared(freeze);
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
        freeze.freeze_type<TransferFreezeAdmin>(&cap, &clock);
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
        freeze.freeze_type<UnfreezeProposalType>(&cap, &clock);
        scenario.return_to_sender(cap);
        test_scenario::return_shared(freeze);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// =========================================================================
// UpdateFreezeConfig tests
// =========================================================================

#[test]
/// E2E: Submit UpdateFreezeConfig → vote → execute → verify duration changed.
fun update_freeze_config_e2e() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_dao(&mut scenario);

    // Enable UpdateFreezeConfig type
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        dao.test_enable_type<UpdateFreezeConfig>(
            b"UpdateFreezeConfig".to_ascii_string(),
            config.with_permissions(type_permissions::freeze_config()),
        );
        test_scenario::return_shared(dao);
    };

    // Verify default max freeze duration is 7 days
    scenario.next_tx(CREATOR);
    {
        let freeze = scenario.take_shared<EmergencyFreeze>();
        assert!(freeze.max_freeze_duration_ms() == 604_800_000);
        test_scenario::return_shared(freeze);
    };

    // Submit proposal to change max duration to 3 days
    let new_duration: u64 = 259_200_000; // 3 days

    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);
        let payload = update_freeze_config::new(new_duration);
        board_voting::submit_proposal(
            &dao,
            option::some(string::utf8(b"Reduce freeze duration")),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    // Vote yes
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<UpdateFreezeConfig>>();
        clock.set_for_testing(2000);
        let vote_dao = scenario.take_shared_by_id<DAO>(proposal.dao_id());
        board_voting::vote(&mut proposal, &vote_dao, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_dao);
        test_scenario::return_shared(proposal);
    };

    // Execute
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<UpdateFreezeConfig>>();
        let mut freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        security_ops::execute_update_freeze_config(&mut freeze, ticket);

        // Verify duration was updated
        assert!(freeze.max_freeze_duration_ms() == new_duration);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(dao);
    };

    // Verify new freeze duration takes effect
    scenario.next_tx(CREATOR);
    {
        let mut freeze = scenario.take_shared<EmergencyFreeze>();
        let cap = scenario.take_from_sender<FreezeAdminCap>();
        clock.set_for_testing(10000);
        freeze.freeze_type<SetBoard>(&cap, &clock);

        // Freeze should expire at t=10000 + 259_200_000 = 259_210_000
        assert!(freeze.is_frozen<SetBoard>(&clock));

        // Advance past new expiry
        clock.set_for_testing(259_210_001);
        assert!(!freeze.is_frozen<SetBoard>(&clock));

        scenario.return_to_sender(cap);
        test_scenario::return_shared(freeze);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// =========================================================================
// UpdateFreezeExemptTypes tests
// =========================================================================

#[test]
/// E2E: Add a custom exempt type → verify it cannot be frozen.
fun add_freeze_exempt_type_e2e() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_dao(&mut scenario);

    // Enable UpdateFreezeExemptTypes type
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        dao.test_enable_type<UpdateFreezeExemptTypes>(
            b"UpdateFreezeExemptTypes".to_ascii_string(),
            config.with_permissions(type_permissions::freeze_config()),
        );
        test_scenario::return_shared(dao);
    };

    // Submit proposal to add "SetBoard" to exempt set
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);
        let mut payload = update_freeze_exempt_types::new();
        payload.add_type<SetBoard>();
        board_voting::submit_proposal(
            &dao,
            option::some(string::utf8(b"Exempt SetBoard from freezing")),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    // Vote yes
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<UpdateFreezeExemptTypes>>();
        clock.set_for_testing(2000);
        let vote_dao = scenario.take_shared_by_id<DAO>(proposal.dao_id());
        board_voting::vote(&mut proposal, &vote_dao, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_dao);
        test_scenario::return_shared(proposal);
    };

    // Execute
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<UpdateFreezeExemptTypes>>();
        let mut freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        security_ops::execute_update_freeze_exempt_types(&mut freeze, ticket);

        // Verify "SetBoard" is now in the exempt set
        assert!(freeze.is_exempt_by_name(&type_name::with_defining_ids<SetBoard>()));

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(dao);
    };

    // Verify: cannot freeze "SetBoard" now (it's exempt)
    scenario.next_tx(CREATOR);
    {
        let mut freeze = scenario.take_shared<EmergencyFreeze>();
        let cap = scenario.take_from_sender<FreezeAdminCap>();
        clock.set_for_testing(4000);
        // This would abort with EProtectedType — but we just want to verify exempt status
        assert!(freeze.is_exempt_by_name(&type_name::with_defining_ids<SetBoard>()));
        scenario.return_to_sender(cap);
        test_scenario::return_shared(freeze);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// E2E: Remove a non-mandatory exempt type → verify it can now be frozen.
fun remove_freeze_exempt_type_e2e() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_dao(&mut scenario);

    // Enable UpdateFreezeExemptTypes type
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        dao.test_enable_type<UpdateFreezeExemptTypes>(
            b"UpdateFreezeExemptTypes".to_ascii_string(),
            config.with_permissions(type_permissions::freeze_config()),
        );
        test_scenario::return_shared(dao);
    };

    // First: add "SetBoard" to exempt set via proposal
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);
        let mut payload = update_freeze_exempt_types::new();
        payload.add_type<SetBoard>();
        board_voting::submit_proposal(
            &dao,
            option::some(string::utf8(b"Add SetBoard exemption")),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let mut p = scenario.take_shared<Proposal<UpdateFreezeExemptTypes>>();
        clock.set_for_testing(2000);
        let vote_dao = scenario.take_shared_by_id<DAO>(p.dao_id());
        board_voting::vote(&mut p, &vote_dao, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_dao);
        test_scenario::return_shared(p);
    };

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut p = scenario.take_shared<Proposal<UpdateFreezeExemptTypes>>();
        let mut freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);
        let req = board_voting::ticket_from_vote(
            &mut dao,
            p,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        security_ops::execute_update_freeze_exempt_types(&mut freeze, req);
        assert!(freeze.is_exempt_by_name(&type_name::with_defining_ids<SetBoard>()));
        test_scenario::return_shared(freeze);
        test_scenario::return_shared(dao);
    };

    // Second: remove "SetBoard" from exempt set via proposal
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(4000);
        let mut payload = update_freeze_exempt_types::new();
        payload.remove_type<SetBoard>();
        board_voting::submit_proposal(
            &dao,
            option::some(string::utf8(b"Remove SetBoard exemption")),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let mut p = scenario.take_shared<Proposal<UpdateFreezeExemptTypes>>();
        clock.set_for_testing(5000);
        let vote_dao = scenario.take_shared_by_id<DAO>(p.dao_id());
        board_voting::vote(&mut p, &vote_dao, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_dao);
        test_scenario::return_shared(p);
    };

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut p = scenario.take_shared<Proposal<UpdateFreezeExemptTypes>>();
        let mut freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(6000);
        let req = board_voting::ticket_from_vote(
            &mut dao,
            p,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        security_ops::execute_update_freeze_exempt_types(&mut freeze, req);
        // Verify "SetBoard" is no longer exempt
        assert!(!freeze.is_exempt_by_name(&type_name::with_defining_ids<SetBoard>()));
        test_scenario::return_shared(freeze);
        test_scenario::return_shared(dao);
    };

    // Verify: "SetBoard" can now be frozen again
    scenario.next_tx(CREATOR);
    {
        let mut freeze = scenario.take_shared<EmergencyFreeze>();
        let cap = scenario.take_from_sender<FreezeAdminCap>();
        clock.set_for_testing(7000);
        freeze.freeze_type<SetBoard>(&cap, &clock);
        assert!(freeze.is_frozen<SetBoard>(&clock));
        scenario.return_to_sender(cap);
        test_scenario::return_shared(freeze);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = emergency::EMandatoryExemptType)]
/// Cannot remove mandatory exempt type (TransferFreezeAdmin) from exempt set.
fun remove_mandatory_exempt_type_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_dao(&mut scenario);

    // Enable UpdateFreezeExemptTypes type
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        dao.test_enable_type<UpdateFreezeExemptTypes>(
            b"UpdateFreezeExemptTypes".to_ascii_string(),
            config.with_permissions(type_permissions::freeze_config()),
        );
        test_scenario::return_shared(dao);
    };

    // Try to remove mandatory type "TransferFreezeAdmin"
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);
        let mut payload = update_freeze_exempt_types::new();
        payload.remove_type<TransferFreezeAdmin>();
        board_voting::submit_proposal(
            &dao,
            option::some(string::utf8(b"Remove mandatory type")),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let mut p = scenario.take_shared<Proposal<UpdateFreezeExemptTypes>>();
        clock.set_for_testing(2000);
        let vote_dao = scenario.take_shared_by_id<DAO>(p.dao_id());
        board_voting::vote(&mut p, &vote_dao, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_dao);
        test_scenario::return_shared(p);
    };

    // Execute — should abort with EMandatoryExemptType
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut p = scenario.take_shared<Proposal<UpdateFreezeExemptTypes>>();
        let mut freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);
        let req = board_voting::ticket_from_vote(
            &mut dao,
            p,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        security_ops::execute_update_freeze_exempt_types(&mut freeze, req);
        test_scenario::return_shared(freeze);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

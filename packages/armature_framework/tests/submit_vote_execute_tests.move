#[test_only]
module armature::submit_vote_execute_tests;

use armature::board_voting;
use armature::dao::{Self, DAO};
use armature::emergency::{EmergencyFreeze, FreezeAdminCap};
use armature::governance;
use armature::proposal;
use std::string;
use sui::clock::{Self, Clock};
use sui::test_scenario;

// === Addresses ===

const CREATOR: address = @0xA;
const MEMBER_B: address = @0xB;
const MEMBER_C: address = @0xC;
const NON_MEMBER: address = @0xFF;

// === Test payload ===

public struct FastPayload has drop, store { value: u64 }

// === Helpers ===

fun create_single_member_dao(scenario: &mut test_scenario::Scenario) {
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR]);
        dao::create(
            &init,
            string::utf8(b"Fast DAO"),
            string::utf8(b"https://example.com/logo.png"),
            scenario.ctx(),
        );
    };
}

fun create_two_member_dao(scenario: &mut test_scenario::Scenario) {
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR, MEMBER_B]);
        dao::create(
            &init,
            string::utf8(b"Two-Member DAO"),
            string::utf8(b"https://example.com/logo.png"),
            scenario.ctx(),
        );
    };
}

fun create_three_member_dao(scenario: &mut test_scenario::Scenario) {
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR, MEMBER_B, MEMBER_C]);
        dao::create(
            &init,
            string::utf8(b"Three-Member DAO"),
            string::utf8(b"https://example.com/logo.png"),
            scenario.ctx(),
        );
    };
}

/// Enable the "FastPayload" type on the DAO with the given config.
fun enable_fast_type(
    scenario: &mut test_scenario::Scenario,
    quorum: u16,
    threshold: u16,
    delay_ms: u64,
    cooldown_ms: u64,
) {
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let config = proposal::new_config(quorum, threshold, 0, 3_600_000, delay_ms, cooldown_ms);
        dao.test_enable_type(b"FastPayload".to_ascii_string(), config);
        test_scenario::return_shared(dao);
    };
}

/// Call submit_vote_execute and drop the returned ticket.
fun call_sve_drop_ticket(scenario: &mut test_scenario::Scenario, clock: &Clock) {
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        let ticket = board_voting::submit_vote_execute<FastPayload>(
            &mut dao,
            b"FastPayload".to_ascii_string(),
            option::none(),
            FastPayload { value: 1 },
            &freeze,
            clock,
            scenario.ctx(),
        );
        ticket.discharge();
        test_scenario::return_shared(dao);
        test_scenario::return_shared(freeze);
    };
}

// =========================================================================
// Happy-path tests
// =========================================================================

#[test]
/// Single-member board: 1/1 = 100%, passes any quorum/threshold.
/// Ticket is returned, is Standalone, and carries the correct vote weights.
fun test_sve__single_member_returns_ticket() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000_000);

    create_single_member_dao(&mut scenario);
    enable_fast_type(&mut scenario, 5_000, 5_000, 0, 0);

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let freeze = scenario.take_shared<EmergencyFreeze>();

        let ticket = board_voting::submit_vote_execute<FastPayload>(
            &mut dao,
            b"FastPayload".to_ascii_string(),
            option::none(),
            FastPayload { value: 42 },
            &freeze,
            &clock,
            scenario.ctx(),
        );

        // Ticket is Standalone — vote weights are accessible
        assert!(ticket.ticket_is_standalone());
        assert!(ticket.ticket_yes_weight() == 1);
        assert!(ticket.ticket_total_snapshot_weight() == 1);
        ticket.discharge();

        test_scenario::return_shared(dao);
        test_scenario::return_shared(freeze);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// Two-member board, quorum=50%: a single vote satisfies quorum.
/// Quorum: 1*10000=10000 >= 5000*2=10000 → exactly met (>=).
/// Threshold: 1*10000=10000 >= 5000*1=5000 → met.
fun test_sve__two_member_50_quorum_single_vote_passes() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000_000);

    create_two_member_dao(&mut scenario);
    enable_fast_type(&mut scenario, 5_000, 5_000, 0, 0);

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let freeze = scenario.take_shared<EmergencyFreeze>();

        let ticket = board_voting::submit_vote_execute<FastPayload>(
            &mut dao,
            b"FastPayload".to_ascii_string(),
            option::none(),
            FastPayload { value: 7 },
            &freeze,
            &clock,
            scenario.ctx(),
        );

        assert!(ticket.ticket_is_standalone());
        assert!(ticket.ticket_yes_weight() == 1);
        assert!(ticket.ticket_total_snapshot_weight() == 2);
        ticket.discharge();

        test_scenario::return_shared(dao);
        test_scenario::return_shared(freeze);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// Cooldown is recorded after execution: last_executed_at is updated for the type.
/// A second immediate call (cooldown=0) also succeeds — no cooldown stale block.
fun test_sve__cooldown_zero_allows_back_to_back() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000_000);

    create_single_member_dao(&mut scenario);
    enable_fast_type(&mut scenario, 5_000, 5_000, 0, 0);

    call_sve_drop_ticket(&mut scenario, &clock);
    // Second call with no cooldown configured — must also succeed.
    call_sve_drop_ticket(&mut scenario, &clock);

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// Metadata is forwarded: option::some with IPFS string is accepted.
fun test_sve__metadata_some_accepted() {
    let mut scenario = test_scenario::begin(CREATOR);
    let clock = clock::create_for_testing(scenario.ctx());

    create_single_member_dao(&mut scenario);
    enable_fast_type(&mut scenario, 5_000, 5_000, 0, 0);

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let freeze = scenario.take_shared<EmergencyFreeze>();

        let ticket = board_voting::submit_vote_execute<FastPayload>(
            &mut dao,
            b"FastPayload".to_ascii_string(),
            option::some(string::utf8(b"ipfs://Qm...")),
            FastPayload { value: 0 },
            &freeze,
            &clock,
            scenario.ctx(),
        );
        ticket.discharge();

        test_scenario::return_shared(dao);
        test_scenario::return_shared(freeze);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// =========================================================================
// EInsufficientVotingWeight
// =========================================================================

#[test, expected_failure(abort_code = armature::board_voting::EInsufficientVotingWeight)]
/// Three-member board, quorum=60%: 1 vote = 1/3 = 33% < 60% — quorum not met.
/// Quorum: 1*10000=10000 vs 6000*3=18000 → NOT met → proposal stays Active → abort.
fun test_sve__quorum_not_met_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let clock = clock::create_for_testing(scenario.ctx());

    create_three_member_dao(&mut scenario);
    enable_fast_type(&mut scenario, 6_000, 5_000, 0, 0);

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let freeze = scenario.take_shared<EmergencyFreeze>();

        let ticket = board_voting::submit_vote_execute<FastPayload>(
            &mut dao,
            b"FastPayload".to_ascii_string(),
            option::none(),
            FastPayload { value: 1 },
            &freeze,
            &clock,
            scenario.ctx(),
        );
        ticket.discharge();

        test_scenario::return_shared(dao);
        test_scenario::return_shared(freeze);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = armature::board_voting::EInsufficientVotingWeight)]
/// Three-member board, quorum=34%: quorum met (1/3 ≈ 33.3% — just below), threshold=51%.
/// Quorum: 1*10000=10000 vs 3400*3=10200 → NOT met (10000 < 10200) → abort.
fun test_sve__quorum_boundary_just_below_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let clock = clock::create_for_testing(scenario.ctx());

    create_three_member_dao(&mut scenario);
    // quorum=3400 (34%). With 3 members: 1*10000=10000 vs 3400*3=10200 → just fails.
    enable_fast_type(&mut scenario, 3_400, 5_000, 0, 0);

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let freeze = scenario.take_shared<EmergencyFreeze>();

        let ticket = board_voting::submit_vote_execute<FastPayload>(
            &mut dao,
            b"FastPayload".to_ascii_string(),
            option::none(),
            FastPayload { value: 1 },
            &freeze,
            &clock,
            scenario.ctx(),
        );
        ticket.discharge();

        test_scenario::return_shared(dao);
        test_scenario::return_shared(freeze);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// =========================================================================
// EDelayForbidsAtomicExecution
// =========================================================================

#[test, expected_failure(abort_code = armature::board_voting::EDelayForbidsAtomicExecution)]
/// Any non-zero execution_delay_ms blocks the atomic path before any mutation.
fun test_sve__nonzero_delay_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let clock = clock::create_for_testing(scenario.ctx());

    create_single_member_dao(&mut scenario);
    // 1-second execution delay — incompatible with atomic execution.
    enable_fast_type(&mut scenario, 5_000, 5_000, 1_000, 0);

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let freeze = scenario.take_shared<EmergencyFreeze>();

        let ticket = board_voting::submit_vote_execute<FastPayload>(
            &mut dao,
            b"FastPayload".to_ascii_string(),
            option::none(),
            FastPayload { value: 1 },
            &freeze,
            &clock,
            scenario.ctx(),
        );
        ticket.discharge();

        test_scenario::return_shared(dao);
        test_scenario::return_shared(freeze);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// =========================================================================
// Board-member check
// =========================================================================

#[test, expected_failure(abort_code = armature::governance::ENotBoardMember)]
/// Non-member caller is rejected before any proposal object is created.
fun test_sve__non_member_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let clock = clock::create_for_testing(scenario.ctx());

    create_single_member_dao(&mut scenario);
    enable_fast_type(&mut scenario, 5_000, 5_000, 0, 0);

    // Call from NON_MEMBER — not on the board.
    scenario.next_tx(NON_MEMBER);
    {
        let mut dao = scenario.take_shared<DAO>();
        let freeze = scenario.take_shared<EmergencyFreeze>();

        let ticket = board_voting::submit_vote_execute<FastPayload>(
            &mut dao,
            b"FastPayload".to_ascii_string(),
            option::none(),
            FastPayload { value: 1 },
            &freeze,
            &clock,
            scenario.ctx(),
        );
        ticket.discharge();

        test_scenario::return_shared(dao);
        test_scenario::return_shared(freeze);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// =========================================================================
// Type-enabled check
// =========================================================================

#[test, expected_failure(abort_code = armature::board_voting::ETypeNotEnabled)]
/// Type not in enabled_proposal_types — rejected before any mutation.
fun test_sve__disabled_type_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let clock = clock::create_for_testing(scenario.ctx());

    create_single_member_dao(&mut scenario);
    // Intentionally do NOT enable "FastPayload".

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let freeze = scenario.take_shared<EmergencyFreeze>();

        let ticket = board_voting::submit_vote_execute<FastPayload>(
            &mut dao,
            b"FastPayload".to_ascii_string(),
            option::none(),
            FastPayload { value: 1 },
            &freeze,
            &clock,
            scenario.ctx(),
        );
        ticket.discharge();

        test_scenario::return_shared(dao);
        test_scenario::return_shared(freeze);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// =========================================================================
// Cooldown enforcement
// =========================================================================

#[test, expected_failure(abort_code = armature::proposal::ECooldownActive)]
/// A second call within the cooldown window is rejected.
/// Cooldown=60s. First call at t=1000ms, second at t=2000ms → only 1s elapsed < 60s.
fun test_sve__cooldown_active_aborts_second_call() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000);

    create_single_member_dao(&mut scenario);
    enable_fast_type(&mut scenario, 5_000, 5_000, 0, 60_000); // 60s cooldown

    // First call succeeds.
    call_sve_drop_ticket(&mut scenario, &clock);

    // Advance clock by only 1 second — still within cooldown.
    clock.set_for_testing(2_000);

    // Second call must abort with ECooldownActive.
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let freeze = scenario.take_shared<EmergencyFreeze>();

        let ticket = board_voting::submit_vote_execute<FastPayload>(
            &mut dao,
            b"FastPayload".to_ascii_string(),
            option::none(),
            FastPayload { value: 2 },
            &freeze,
            &clock,
            scenario.ctx(),
        );
        ticket.discharge();

        test_scenario::return_shared(dao);
        test_scenario::return_shared(freeze);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// After the cooldown window elapses a second call succeeds.
/// Cooldown=60s. First at t=1000ms, second at t=62000ms → 61s elapsed > 60s.
fun test_sve__cooldown_elapsed_allows_second_call() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000);

    create_single_member_dao(&mut scenario);
    enable_fast_type(&mut scenario, 5_000, 5_000, 0, 60_000);

    call_sve_drop_ticket(&mut scenario, &clock);

    // Advance past cooldown window.
    clock.set_for_testing(62_000);
    call_sve_drop_ticket(&mut scenario, &clock);

    clock.destroy_for_testing();
    scenario.end();
}

// =========================================================================
// Emergency freeze
// =========================================================================

#[test, expected_failure]
/// Frozen type cannot be executed via the atomic path.
fun test_sve__frozen_type_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000);

    create_single_member_dao(&mut scenario);
    enable_fast_type(&mut scenario, 5_000, 5_000, 0, 0);

    // Freeze the type via the FreezeAdminCap.
    scenario.next_tx(CREATOR);
    {
        let freeze_cap = scenario.take_from_sender<FreezeAdminCap>();
        let mut freeze = scenario.take_shared<EmergencyFreeze>();
        freeze.freeze_type(&freeze_cap, b"FastPayload".to_ascii_string(), &clock);
        test_scenario::return_to_sender(&scenario, freeze_cap);
        test_scenario::return_shared(freeze);
    };

    // Attempt to submit_vote_execute on the frozen type.
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let freeze = scenario.take_shared<EmergencyFreeze>();

        let ticket = board_voting::submit_vote_execute<FastPayload>(
            &mut dao,
            b"FastPayload".to_ascii_string(),
            option::none(),
            FastPayload { value: 1 },
            &freeze,
            &clock,
            scenario.ctx(),
        );
        ticket.discharge();

        test_scenario::return_shared(dao);
        test_scenario::return_shared(freeze);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// =========================================================================
// Execution paused
// =========================================================================

#[test, expected_failure(abort_code = armature::proposal::EExecutionPaused)]
/// When execution is paused on the DAO, submit_vote_execute aborts.
fun test_sve__execution_paused_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let clock = clock::create_for_testing(scenario.ctx());

    create_single_member_dao(&mut scenario);
    enable_fast_type(&mut scenario, 5_000, 5_000, 0, 0);

    // Pause execution via the test helper on DAO.
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        // Use a privileged test request to pause execution.
        let req = proposal::new_execution_request_for_testing<FastPayload>(
            dao.id(),
            @0x1.to_id(),
        );
        dao.set_execution_paused(true, &req);
        proposal::consume_execution_request_for_testing(req);
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let freeze = scenario.take_shared<EmergencyFreeze>();

        let ticket = board_voting::submit_vote_execute<FastPayload>(
            &mut dao,
            b"FastPayload".to_ascii_string(),
            option::none(),
            FastPayload { value: 1 },
            &freeze,
            &clock,
            scenario.ctx(),
        );
        ticket.discharge();

        test_scenario::return_shared(dao);
        test_scenario::return_shared(freeze);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// =========================================================================
// Controller paused
// =========================================================================

#[test, expected_failure(abort_code = armature::board_voting::EControllerPaused)]
/// When the controller has paused the SubDAO, submit_vote_execute aborts.
fun test_sve__controller_paused_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let clock = clock::create_for_testing(scenario.ctx());

    create_single_member_dao(&mut scenario);
    enable_fast_type(&mut scenario, 5_000, 5_000, 0, 0);

    // Pause via the test execution-request helper.
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let req = proposal::new_execution_request_for_testing<FastPayload>(
            dao.id(),
            @0x1.to_id(),
        );
        dao.set_controller_paused(true, &req);
        proposal::consume_execution_request_for_testing(req);
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let freeze = scenario.take_shared<EmergencyFreeze>();

        let ticket = board_voting::submit_vote_execute<FastPayload>(
            &mut dao,
            b"FastPayload".to_ascii_string(),
            option::none(),
            FastPayload { value: 1 },
            &freeze,
            &clock,
            scenario.ctx(),
        );
        ticket.discharge();

        test_scenario::return_shared(dao);
        test_scenario::return_shared(freeze);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// =========================================================================
// EnableProposalType floor check
// =========================================================================

#[test, expected_failure(abort_code = armature::board_voting::EFloorNotMet)]
/// EnableProposalType config with approval_threshold below 66% is rejected at
/// submission time — same floor enforced in submit_proposal.
fun test_sve__enable_proposal_type_below_floor_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let clock = clock::create_for_testing(scenario.ctx());

    create_single_member_dao(&mut scenario);

    // Lower the EnableProposalType config threshold below the 66% floor.
    // "EnableProposalType" is enabled by default; test_update_config replaces its config.
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let config = proposal::new_config(5_000, 5_000, 0, 3_600_000, 0, 0);
        dao.test_update_config(b"EnableProposalType".to_ascii_string(), config);
        test_scenario::return_shared(dao);
    };

    // "EnableProposalType" has no type binding by default so FastPayload is accepted
    // for the type-mismatch check; the floor assert fires first anyway.
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let freeze = scenario.take_shared<EmergencyFreeze>();

        let ticket = board_voting::submit_vote_execute<FastPayload>(
            &mut dao,
            b"EnableProposalType".to_ascii_string(),
            option::none(),
            FastPayload { value: 0 },
            &freeze,
            &clock,
            scenario.ctx(),
        );
        ticket.discharge();

        test_scenario::return_shared(dao);
        test_scenario::return_shared(freeze);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test_only]
module armature::submit_vote_execute_tests;

use armature::board_voting;
use armature::dao::{Self, DAO};
use armature::emergency::{EmergencyFreeze, FreezeAdminCap};
use armature::enable_proposal_type::{Self, EnableProposalType};
use armature::governance;
use armature::proposal::{
    Self,
    ProposalCreated,
    ProposalExecuted,
    ProposalPassed,
    ProposalPayloadCreated,
    VoteCast
};
use std::string;
use std::type_name;
use sui::clock::{Self, Clock};
use sui::event;
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
        dao.test_enable_type<FastPayload>(b"FastPayload".to_ascii_string(), config);
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
/// Cooldown is recorded after execution: last_executed_ms is updated for the type's slot.
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
/// Type has no slot on the DAO — rejected before any mutation.
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

#[test, expected_failure(abort_code = armature::emergency::EFrozen)]
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
        freeze.freeze_type<FastPayload>(&freeze_cap, &clock);
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
/// EnableProposalType config with approval_threshold below 80% is rejected at
/// submission time — same floor enforced in submit_proposal.
fun test_sve__enable_proposal_type_below_floor_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let clock = clock::create_for_testing(scenario.ctx());

    create_single_member_dao(&mut scenario);

    // Lower the EnableProposalType config threshold below the 80% floor.
    // "EnableProposalType" is enabled by default; test_update_config replaces its config.
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let config = proposal::new_config(5_000, 5_000, 0, 3_600_000, 0, 0);
        dao.test_update_config<EnableProposalType>(config);
        test_scenario::return_shared(dao);
    };

    // The floor is keyed on the EnableProposalType payload type itself; it fires
    // before the delay / quorum checks.
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let freeze = scenario.take_shared<EmergencyFreeze>();

        let ticket = board_voting::submit_vote_execute<EnableProposalType>(
            &mut dao,
            option::none(),
            enable_proposal_type::new(
                b"FastPayload".to_ascii_string(),
                type_name::with_defining_ids<FastPayload>(),
                proposal::new_config(5_000, 5_000, 0, 3_600_000, 0, 0),
            ),
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
// Read-only variant (submit_vote_execute_readonly)
// =========================================================================

/// Call submit_vote_execute_readonly with an immutable DAO and drop the ticket.
fun call_sve_readonly_drop_ticket(scenario: &mut test_scenario::Scenario, clock: &Clock) {
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        let ticket = board_voting::submit_vote_execute_readonly<FastPayload>(
            &dao,
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

#[test]
/// Read-only variant returns the same Standalone ticket and records nothing on the DAO.
fun test_sve_readonly__returns_ticket_and_leaves_dao_untouched() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000_000);

    create_single_member_dao(&mut scenario);
    enable_fast_type(&mut scenario, 5_000, 5_000, 0, 0);

    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let freeze = scenario.take_shared<EmergencyFreeze>();

        let ticket = board_voting::submit_vote_execute_readonly<FastPayload>(
            &dao,
            option::none(),
            FastPayload { value: 42 },
            &freeze,
            &clock,
            scenario.ctx(),
        );

        assert!(ticket.ticket_is_standalone());
        assert!(ticket.ticket_dao_id() == dao.id());
        assert!(ticket.ticket_yes_weight() == 1);
        assert!(ticket.ticket_total_snapshot_weight() == 1);
        assert!(ticket.ticket_payload().value == 42);
        ticket.discharge();

        assert!(dao.last_executed_ms<FastPayload>().is_none());

        test_scenario::return_shared(dao);
        test_scenario::return_shared(freeze);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// The &mut DAO variant still records the execution timestamp in the type's slot.
fun test_sve__mutable_variant_records_execution() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000_000);

    create_single_member_dao(&mut scenario);
    enable_fast_type(&mut scenario, 5_000, 5_000, 0, 0);
    call_sve_drop_ticket(&mut scenario, &clock);

    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        assert!(dao.last_executed_ms<FastPayload>() == option::some(1_000_000));
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// Cooldown-free types can execute back-to-back through the read-only variant.
fun test_sve_readonly__back_to_back() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000_000);

    create_single_member_dao(&mut scenario);
    enable_fast_type(&mut scenario, 5_000, 5_000, 0, 0);
    call_sve_readonly_drop_ticket(&mut scenario, &clock);
    call_sve_readonly_drop_ticket(&mut scenario, &clock);

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = armature::board_voting::ECooldownRequiresMutableDAO)]
/// A type with a cooldown cannot use the read-only variant: skipping the
/// timestamp write would let the next execution bypass the cooldown.
fun test_sve_readonly__cooldown_type_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000_000);

    create_single_member_dao(&mut scenario);
    enable_fast_type(&mut scenario, 5_000, 5_000, 0, 60_000);
    call_sve_readonly_drop_ticket(&mut scenario, &clock);

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = armature::board_voting::EDelayForbidsAtomicExecution)]
/// The read-only variant keeps the atomic path's execution-delay rule.
fun test_sve_readonly__nonzero_delay_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000_000);

    create_single_member_dao(&mut scenario);
    enable_fast_type(&mut scenario, 5_000, 5_000, 1_000, 0);
    call_sve_readonly_drop_ticket(&mut scenario, &clock);

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = armature::board_voting::ETypeNotEnabled)]
/// The read-only variant rejects types without a slot.
fun test_sve_readonly__type_not_enabled_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000_000);

    create_single_member_dao(&mut scenario);
    call_sve_readonly_drop_ticket(&mut scenario, &clock);

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = armature::board_voting::EInsufficientVotingWeight)]
/// The read-only variant cannot execute when the caller's single vote does not pass
/// the proposal on its own. Three-member board, quorum=60%: 1/3 = 33% < 60%.
fun test_sve_readonly__quorum_not_met_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000_000);

    create_three_member_dao(&mut scenario);
    enable_fast_type(&mut scenario, 6_000, 5_000, 0, 0);
    call_sve_readonly_drop_ticket(&mut scenario, &clock);

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = armature::board_voting::EInsufficientVotingWeight)]
/// Quorum boundary on the read-only variant: three-member board, quorum=34%.
/// 1*10000=10000 vs 3400*3=10200 → one vote falls just short → abort.
fun test_sve_readonly__quorum_boundary_just_below_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000_000);

    create_three_member_dao(&mut scenario);
    enable_fast_type(&mut scenario, 3_400, 5_000, 0, 0);
    call_sve_readonly_drop_ticket(&mut scenario, &clock);

    clock.destroy_for_testing();
    scenario.end();
}

// =========================================================================
// Event-only audit (no Proposal object)
// =========================================================================

/// Run one atomic execution (either variant) with metadata and check it emits
/// the proposal lifecycle events under the ticket's proposal ID. Returns that ID.
fun sve_and_check_events(
    scenario: &mut test_scenario::Scenario,
    clock: &Clock,
    readonly: bool,
): ID {
    scenario.next_tx(CREATOR);
    let mut dao = scenario.take_shared<DAO>();
    let freeze = scenario.take_shared<EmergencyFreeze>();
    let metadata = option::some(string::utf8(b"QmTestHash"));

    let ticket = if (readonly) {
        board_voting::submit_vote_execute_readonly<FastPayload>(
            &dao,
            metadata,
            FastPayload { value: 42 },
            &freeze,
            clock,
            scenario.ctx(),
        )
    } else {
        board_voting::submit_vote_execute<FastPayload>(
            &mut dao,
            metadata,
            FastPayload { value: 42 },
            &freeze,
            clock,
            scenario.ctx(),
        )
    };
    let proposal_id = ticket.ticket_request().req_proposal_id();

    let created = event::events_by_type<ProposalCreated>();
    assert!(created.length() == 1);
    assert!(created[0].created_event_proposal_id() == proposal_id);
    assert!(created[0].created_event_proposer() == CREATOR);
    assert!(created[0].created_event_metadata_ipfs() == metadata);

    let payloads = event::events_by_type<ProposalPayloadCreated>();
    assert!(payloads.length() == 1);
    assert!(payloads[0].payload_event_proposal_id() == proposal_id);
    assert!(payloads[0].payload_event_bcs() == std::bcs::to_bytes(&FastPayload { value: 42 }));

    let votes = event::events_by_type<VoteCast>();
    assert!(votes.length() == 1);
    assert!(votes[0].vote_event_weight() == 1);

    let passed = event::events_by_type<ProposalPassed>();
    assert!(passed.length() == 1);
    assert!(passed[0].passed_event_yes_weight() == 1);

    let executed = event::events_by_type<ProposalExecuted>();
    assert!(executed.length() == 1);
    assert!(executed[0].executed_event_proposal_id() == proposal_id);

    ticket.discharge();
    test_scenario::return_shared(dao);
    test_scenario::return_shared(freeze);
    proposal_id
}

#[test]
/// submit_vote_execute creates no objects: the five lifecycle events are the
/// audit record, and the minted proposal ID is not an object.
fun test_sve__creates_no_objects_and_emits_lifecycle_events() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000_000);

    create_single_member_dao(&mut scenario);
    enable_fast_type(&mut scenario, 5_000, 5_000, 0, 0);
    sve_and_check_events(&mut scenario, &clock, false);

    let effects = scenario.next_tx(CREATOR);
    assert!(effects.created().is_empty());
    assert!(effects.num_user_events() == 5);

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// The read-only variant is also event-only, and each execution gets a distinct proposal ID.
fun test_sve_readonly__creates_no_objects_and_ids_are_distinct() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000_000);

    create_single_member_dao(&mut scenario);
    enable_fast_type(&mut scenario, 5_000, 5_000, 0, 0);
    let first = sve_and_check_events(&mut scenario, &clock, true);

    let effects = scenario.next_tx(CREATOR);
    assert!(effects.created().is_empty());
    assert!(effects.num_user_events() == 5);

    let second = sve_and_check_events(&mut scenario, &clock, true);
    assert!(first != second);

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// Two atomic executions in the same transaction get distinct proposal IDs.
fun test_sve__same_tx_executions_get_distinct_ids() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000_000);

    create_single_member_dao(&mut scenario);
    enable_fast_type(&mut scenario, 5_000, 5_000, 0, 0);

    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        let a = board_voting::submit_vote_execute_readonly<FastPayload>(
            &dao,
            option::none(),
            FastPayload { value: 1 },
            &freeze,
            &clock,
            scenario.ctx(),
        );
        let b = board_voting::submit_vote_execute_readonly<FastPayload>(
            &dao,
            option::none(),
            FastPayload { value: 2 },
            &freeze,
            &clock,
            scenario.ctx(),
        );
        assert!(a.ticket_request().req_proposal_id() != b.ticket_request().req_proposal_id());
        a.discharge();
        b.discharge();
        test_scenario::return_shared(dao);
        test_scenario::return_shared(freeze);
    };

    clock.destroy_for_testing();
    scenario.end();
}

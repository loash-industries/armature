#[test_only]
module armature::proposal_tests;

use armature::dao::{Self, DAO};
use armature::governance;
use armature::proposal::{Self, Proposal};
use std::string;
use sui::clock::{Self, Clock};
use sui::test_scenario;

// === Test addresses ===

const CREATOR: address = @0xA;
const MEMBER_B: address = @0xB;
const NON_MEMBER: address = @0xD;

// === Test payload ===

public struct TestPayload has drop, store {
    value: u64,
}

// === Helpers ===

fun create_test_dao(scenario: &mut test_scenario::Scenario) {
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
}

fun default_config(): proposal::ProposalConfig {
    proposal::new_config(
        5_000, // quorum 50%
        5_000, // threshold 50%
        0, // propose_threshold
        3_600_000, // expiry 1 hour
        0, // execution_delay
        0, // cooldown
    )
}

fun create_test_proposal(scenario: &mut test_scenario::Scenario, clock: &Clock) {
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let config = default_config();
        proposal::create<TestPayload>(
            dao.id(),
            b"SetBoard".to_ascii_string(),
            CREATOR,
            option::some(string::utf8(b"ipfs://test")),
            TestPayload { value: 42 },
            config,
            dao.governance(),
            dao.status().is_active(),
            clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };
}

// === Test 1: ExecutionRequest has no abilities (compile-time) ===

#[test]
/// ExecutionRequest has no drop/copy/store — it's a hot potato.
/// This test just verifies it can be created and consumed.
fun test_execution_request_no_drop() {
    let req = proposal::new_execution_request<TestPayload>(
        object::id_from_address(@0x1),
        object::id_from_address(@0x2),
    );
    proposal::consume(req);
}

// === Test 5: Active -> Passed ===

#[test]
/// Vote triggers Passed when threshold met.
fun test_status_active_to_passed() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000_000);

    create_test_dao(&mut scenario);
    create_test_proposal(&mut scenario, &clock);

    // CREATOR votes yes (weight 1, total 2 members)
    scenario.next_tx(CREATOR);
    {
        let mut prop = scenario.take_shared<Proposal<TestPayload>>();
        prop.vote(true, &clock, scenario.ctx());
        // quorum: 1*10000 >= 5000*2 → 10000 >= 10000 ✓
        // threshold: 1*10000 >= 5000*1 → 10000 >= 5000 ✓
        assert!(prop.status().is_passed());
        test_scenario::return_shared(prop);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// === Test 6: Active proposal deleted after expiry ===

#[test]
/// delete_expired_proposal deletes an Active proposal once expiry_ms has passed.
fun test_delete_expired_active() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000_000);

    create_test_dao(&mut scenario);
    create_test_proposal(&mut scenario, &clock);

    // Advance clock to expiry (1 hour = 3_600_000ms)
    clock.set_for_testing(1_000_000 + 3_600_000);

    // Anyone may delete it, not just board members.
    scenario.next_tx(NON_MEMBER);
    let prop_id;
    {
        let prop = scenario.take_shared<Proposal<TestPayload>>();
        prop_id = object::id(&prop);
        proposal::delete_expired_proposal(prop, &clock);
    };

    let effects = scenario.next_tx(CREATOR);
    assert!(effects.deleted() == vector[prop_id]);
    assert!(!test_scenario::has_most_recent_shared<Proposal<TestPayload>>());

    clock.destroy_for_testing();
    scenario.end();
}

// === Test 7: Execute deletes the proposal ===

#[test]
/// execute returns the payload and an ExecutionRequest and deletes the proposal.
fun test_execute_deletes_proposal() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000_000);

    create_test_dao(&mut scenario);
    create_test_proposal(&mut scenario, &clock);

    // Vote to pass
    scenario.next_tx(CREATOR);
    {
        let mut prop = scenario.take_shared<Proposal<TestPayload>>();
        prop.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(prop);
    };

    // Execute
    scenario.next_tx(CREATOR);
    let prop_id;
    {
        let prop = scenario.take_shared<Proposal<TestPayload>>();
        prop_id = object::id(&prop);
        let dao = scenario.take_shared<DAO>();
        let (payload, req) = prop.execute(
            dao.governance(),
            option::none(),
            false,
            &clock,
            scenario.ctx(),
        );
        assert!(payload.value == 42);
        assert!(req.req_proposal_id() == prop_id);
        proposal::consume(req);
        test_scenario::return_shared(dao);
    };

    let effects = scenario.next_tx(CREATOR);
    assert!(effects.deleted() == vector[prop_id]);
    assert!(!test_scenario::has_most_recent_shared<Proposal<TestPayload>>());

    clock.destroy_for_testing();
    scenario.end();
}

// === Test 8: Cannot vote on Passed ===

#[test, expected_failure(abort_code = proposal::ENotActive)]
/// Abort — Passed is terminal for voting.
fun test_cannot_vote_on_passed_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000_000);

    create_test_dao(&mut scenario);
    create_test_proposal(&mut scenario, &clock);

    // Pass the proposal
    scenario.next_tx(CREATOR);
    {
        let mut prop = scenario.take_shared<Proposal<TestPayload>>();
        prop.vote(true, &clock, scenario.ctx());
        assert!(prop.status().is_passed());
        test_scenario::return_shared(prop);
    };

    // Try to vote again (MEMBER_B)
    scenario.next_tx(MEMBER_B);
    {
        let mut prop = scenario.take_shared<Proposal<TestPayload>>();
        prop.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(prop);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// === Test 9: Active proposal cannot be deleted before expiry ===

#[test, expected_failure(abort_code = proposal::ENotExpired)]
/// Abort — an Active proposal is still open for voting until expiry_ms passes.
fun test_delete_expired_active_too_early_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000_000);

    create_test_dao(&mut scenario);
    create_test_proposal(&mut scenario, &clock);

    clock.set_for_testing(1_000_000 + 3_600_000 - 1);
    scenario.next_tx(NON_MEMBER);
    {
        let prop = scenario.take_shared<Proposal<TestPayload>>();
        proposal::delete_expired_proposal(prop, &clock);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// === Test 10: Passed proposal deleted after its execution window ===

#[test]
/// A Passed proposal that nobody executes can be deleted once its execution
/// window (passed_at + execution_delay_ms + expiry_ms) has closed.
fun test_delete_expired_passed_after_window() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000_000);

    create_test_dao(&mut scenario);
    create_test_proposal(&mut scenario, &clock);

    // Pass 10 minutes after creation, so the window runs from the pass time.
    clock.set_for_testing(1_600_000);
    scenario.next_tx(CREATOR);
    {
        let mut prop = scenario.take_shared<Proposal<TestPayload>>();
        prop.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(prop);
    };

    clock.set_for_testing(1_600_000 + 3_600_000);
    scenario.next_tx(NON_MEMBER);
    {
        let prop = scenario.take_shared<Proposal<TestPayload>>();
        proposal::delete_expired_proposal(prop, &clock);
    };

    scenario.next_tx(CREATOR);
    assert!(!test_scenario::has_most_recent_shared<Proposal<TestPayload>>());

    clock.destroy_for_testing();
    scenario.end();
}

// === Test 11: Passed proposal cannot be deleted inside its window ===

#[test, expected_failure(abort_code = proposal::ENotExpired)]
/// Abort — the window is measured from the pass time, not the creation time.
fun test_delete_expired_passed_inside_window_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000_000);

    create_test_dao(&mut scenario);
    create_test_proposal(&mut scenario, &clock);

    clock.set_for_testing(1_600_000);
    scenario.next_tx(CREATOR);
    {
        let mut prop = scenario.take_shared<Proposal<TestPayload>>();
        prop.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(prop);
    };

    // Past created_at + expiry_ms, but inside passed_at + expiry_ms.
    clock.set_for_testing(1_600_000 + 3_600_000 - 1);
    scenario.next_tx(NON_MEMBER);
    {
        let prop = scenario.take_shared<Proposal<TestPayload>>();
        proposal::delete_expired_proposal(prop, &clock);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// === Test 12: Cannot execute after the execution window ===

#[test, expected_failure(abort_code = proposal::EExecutionWindowClosed)]
/// Abort — once a Passed proposal's window closes it can only be deleted.
fun test_execute_after_window_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000_000);

    create_test_dao(&mut scenario);
    create_test_proposal(&mut scenario, &clock);

    scenario.next_tx(CREATOR);
    {
        let mut prop = scenario.take_shared<Proposal<TestPayload>>();
        prop.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(prop);
    };

    clock.set_for_testing(1_000_000 + 3_600_000);
    scenario.next_tx(CREATOR);
    {
        let prop = scenario.take_shared<Proposal<TestPayload>>();
        let dao = scenario.take_shared<DAO>();
        let (_payload, req) = prop.execute(
            dao.governance(),
            option::none(),
            false,
            &clock,
            scenario.ctx(),
        );
        proposal::consume(req);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// === Test 12a: Enormous expiry saturates instead of overflowing ===

/// Create a proposal whose expiry_ms is u64::MAX (a "never expires" config)
/// and pass it at the current clock time.
fun create_and_pass_max_expiry_proposal(scenario: &mut test_scenario::Scenario, clock: &Clock) {
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let config = proposal::new_config(
            5_000,
            5_000,
            0,
            std::u64::max_value!(), // expiry: never
            0,
            0,
        );
        proposal::create<TestPayload>(
            dao.id(),
            b"SetBoard".to_ascii_string(),
            CREATOR,
            option::some(string::utf8(b"ipfs://test")),
            TestPayload { value: 42 },
            config,
            dao.governance(),
            dao.status().is_active(),
            clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let mut prop = scenario.take_shared<Proposal<TestPayload>>();
        prop.vote(true, clock, scenario.ctx());
        test_scenario::return_shared(prop);
    };
}

#[test]
/// passed_at + execution_delay_ms + expiry_ms would overflow; the deadline
/// saturates at u64::MAX so the proposal still executes.
fun test_execute_with_max_expiry_does_not_overflow() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000_000);

    create_test_dao(&mut scenario);
    create_and_pass_max_expiry_proposal(&mut scenario, &clock);

    clock.set_for_testing(1_000_000_000_000);
    scenario.next_tx(CREATOR);
    {
        let prop = scenario.take_shared<Proposal<TestPayload>>();
        let dao = scenario.take_shared<DAO>();
        let (_payload, req) = prop.execute(
            dao.governance(),
            option::none(),
            false,
            &clock,
            scenario.ctx(),
        );
        proposal::consume(req);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = proposal::ENotExpired)]
/// With a saturated deadline the proposal never expires: delete aborts with
/// ENotExpired, not an arithmetic overflow.
fun test_delete_with_max_expiry_not_expired() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000_000);

    create_test_dao(&mut scenario);
    create_and_pass_max_expiry_proposal(&mut scenario, &clock);

    clock.set_for_testing(1_000_000_000_000);
    scenario.next_tx(NON_MEMBER);
    {
        let prop = scenario.take_shared<Proposal<TestPayload>>();
        proposal::delete_expired_proposal(prop, &clock);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// === Test 13: Vote snapshot immutable after creation ===

#[test]
/// Snapshot unchanged after board change.
fun test_vote_snapshot_immutable_after_creation() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000_000);

    create_test_dao(&mut scenario);
    create_test_proposal(&mut scenario, &clock);

    // Change board members via governance_mut
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let new_member: address = @0xC;
        dao.governance_mut().set_board(vector[CREATOR, new_member]);
        test_scenario::return_shared(dao);
    };

    // Original MEMBER_B can still vote (in snapshot)
    scenario.next_tx(MEMBER_B);
    {
        let mut prop = scenario.take_shared<Proposal<TestPayload>>();
        prop.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(prop);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// === Test 14: New member cannot vote on old proposal ===

#[test, expected_failure(abort_code = proposal::ENotInSnapshot)]
/// Abort — new member not in snapshot.
fun test_new_member_cannot_vote_on_old_proposal() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000_000);

    create_test_dao(&mut scenario);
    create_test_proposal(&mut scenario, &clock);

    // Add new member
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let new_member: address = @0xC;
        dao.governance_mut().set_board(vector[CREATOR, MEMBER_B, new_member]);
        test_scenario::return_shared(dao);
    };

    // New member tries to vote
    scenario.next_tx(@0xC);
    {
        let mut prop = scenario.take_shared<Proposal<TestPayload>>();
        prop.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(prop);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// === Test 15: Non-board member cannot execute ===

#[test, expected_failure(abort_code = proposal::ENotEligible)]
/// Abort — non-board member cannot execute.
fun test_non_board_member_cannot_execute_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000_000);

    create_test_dao(&mut scenario);
    create_test_proposal(&mut scenario, &clock);

    // Pass
    scenario.next_tx(CREATOR);
    {
        let mut prop = scenario.take_shared<Proposal<TestPayload>>();
        prop.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(prop);
    };

    // Non-member tries to execute
    scenario.next_tx(NON_MEMBER);
    {
        let prop = scenario.take_shared<Proposal<TestPayload>>();
        let dao = scenario.take_shared<DAO>();
        let (_payload, req) = prop.execute(
            dao.governance(),
            option::none(),
            false,
            &clock,
            scenario.ctx(),
        );
        proposal::consume(req);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// === Test 16: Board member can execute ===

#[test]
/// Execution succeeds for board member.
fun test_board_member_can_execute() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000_000);

    create_test_dao(&mut scenario);
    create_test_proposal(&mut scenario, &clock);

    // Pass
    scenario.next_tx(CREATOR);
    {
        let mut prop = scenario.take_shared<Proposal<TestPayload>>();
        prop.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(prop);
    };

    // MEMBER_B executes (board member, not the voter)
    scenario.next_tx(MEMBER_B);
    {
        let prop = scenario.take_shared<Proposal<TestPayload>>();
        let dao = scenario.take_shared<DAO>();
        let (_payload, req) = prop.execute(
            dao.governance(),
            option::none(),
            false,
            &clock,
            scenario.ctx(),
        );
        proposal::consume(req);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// === Test 18: Passed proposal retryable ===

#[test]
/// Second execute attempt succeeds (proposal stays Passed if handler aborts,
/// but here we test that a Passed proposal can be executed).
fun test_passed_proposal_retryable_after_failure() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000_000);

    create_test_dao(&mut scenario);
    create_test_proposal(&mut scenario, &clock);

    // Pass
    scenario.next_tx(CREATOR);
    {
        let mut prop = scenario.take_shared<Proposal<TestPayload>>();
        prop.vote(true, &clock, scenario.ctx());
        assert!(prop.status().is_passed());
        test_scenario::return_shared(prop);
    };

    // Execute succeeds
    scenario.next_tx(CREATOR);
    {
        let prop = scenario.take_shared<Proposal<TestPayload>>();
        let dao = scenario.take_shared<DAO>();
        let (_payload, req) = prop.execute(
            dao.governance(),
            option::none(),
            false,
            &clock,
            scenario.ctx(),
        );
        proposal::consume(req);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// === Test 19: Double vote aborts ===

#[test, expected_failure(abort_code = proposal::EAlreadyVoted)]
/// Abort — same voter cannot vote twice.
fun test_vote_double_vote_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000_000);

    create_test_dao(&mut scenario);
    create_test_proposal(&mut scenario, &clock);

    // First vote (NO so proposal stays Active)
    scenario.next_tx(CREATOR);
    {
        let mut prop = scenario.take_shared<Proposal<TestPayload>>();
        prop.vote(false, &clock, scenario.ctx());
        test_scenario::return_shared(prop);
    };

    // Second vote — should abort
    scenario.next_tx(CREATOR);
    {
        let mut prop = scenario.take_shared<Proposal<TestPayload>>();
        prop.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(prop);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// === Test 20: Non-snapshot member cannot vote ===

#[test, expected_failure(abort_code = proposal::ENotInSnapshot)]
/// Abort — not in vote_snapshot.
fun test_vote_non_snapshot_member_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000_000);

    create_test_dao(&mut scenario);
    create_test_proposal(&mut scenario, &clock);

    // Non-member tries to vote
    scenario.next_tx(NON_MEMBER);
    {
        let mut prop = scenario.take_shared<Proposal<TestPayload>>();
        prop.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(prop);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// === Test 21: NO vote counted correctly ===

#[test]
/// NO votes increase no_weight.
fun test_vote_no_vote_counted_correctly() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000_000);

    create_test_dao(&mut scenario);
    create_test_proposal(&mut scenario, &clock);

    // Vote NO
    scenario.next_tx(CREATOR);
    {
        let mut prop = scenario.take_shared<Proposal<TestPayload>>();
        prop.vote(false, &clock, scenario.ctx());
        assert!(prop.no_weight() == 1);
        assert!(prop.yes_weight() == 0);
        assert!(prop.status().is_active()); // Not passed
        test_scenario::return_shared(prop);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// === Test 22: Execution delay not elapsed aborts ===

#[test, expected_failure(abort_code = proposal::EDelayNotElapsed)]
/// Abort — execution delay not met.
fun test_execute_delay_not_elapsed_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000_000);

    create_test_dao(&mut scenario);

    // Create proposal with 1 hour execution delay
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let config = proposal::new_config(
            5_000,
            5_000,
            0,
            3_600_000, // expiry
            3_600_000, // execution_delay = 1 hour
            0,
        );
        proposal::create<TestPayload>(
            dao.id(),
            b"SetBoard".to_ascii_string(),
            CREATOR,
            option::some(string::utf8(b"ipfs://test")),
            TestPayload { value: 42 },
            config,
            dao.governance(),
            dao.status().is_active(),
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    // Pass
    scenario.next_tx(CREATOR);
    {
        let mut prop = scenario.take_shared<Proposal<TestPayload>>();
        prop.vote(true, &clock, scenario.ctx());
        assert!(prop.status().is_passed());
        test_scenario::return_shared(prop);
    };

    // Try execute immediately (delay not elapsed)
    scenario.next_tx(CREATOR);
    {
        let prop = scenario.take_shared<Proposal<TestPayload>>();
        let dao = scenario.take_shared<DAO>();
        let (_payload, req) = prop.execute(
            dao.governance(),
            option::none(),
            false,
            &clock,
            scenario.ctx(),
        );
        proposal::consume(req);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// === Test 23: Execution delay elapsed succeeds ===

#[test]
/// Execution proceeds after delay.
fun test_execute_delay_elapsed_succeeds() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000_000);

    create_test_dao(&mut scenario);

    // Create proposal with 1 hour execution delay
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let config = proposal::new_config(
            5_000,
            5_000,
            0,
            3_600_000,
            3_600_000, // execution_delay = 1 hour
            0,
        );
        proposal::create<TestPayload>(
            dao.id(),
            b"SetBoard".to_ascii_string(),
            CREATOR,
            option::some(string::utf8(b"ipfs://test")),
            TestPayload { value: 42 },
            config,
            dao.governance(),
            dao.status().is_active(),
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    // Pass
    scenario.next_tx(CREATOR);
    {
        let mut prop = scenario.take_shared<Proposal<TestPayload>>();
        prop.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(prop);
    };

    // Advance past delay
    clock.set_for_testing(1_000_000 + 3_600_000);

    // Execute succeeds
    scenario.next_tx(CREATOR);
    {
        let prop = scenario.take_shared<Proposal<TestPayload>>();
        let dao = scenario.take_shared<DAO>();
        let (_payload, req) = prop.execute(
            dao.governance(),
            option::none(),
            false,
            &clock,
            scenario.ctx(),
        );
        proposal::consume(req);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// === Test 23a: Execution window starts after the delay ===

#[test]
/// The window stays open for expiry_ms after the delay elapses, so a proposal
/// with a delay is still executable at passed_at + delay + expiry - 1.
fun test_execute_window_starts_after_delay() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000_000);

    create_test_dao(&mut scenario);

    // Create proposal with 1 hour execution delay
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let config = proposal::new_config(
            5_000,
            5_000,
            0,
            3_600_000,
            3_600_000, // execution_delay = 1 hour
            0,
        );
        proposal::create<TestPayload>(
            dao.id(),
            b"SetBoard".to_ascii_string(),
            CREATOR,
            option::some(string::utf8(b"ipfs://test")),
            TestPayload { value: 42 },
            config,
            dao.governance(),
            dao.status().is_active(),
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    // Pass
    scenario.next_tx(CREATOR);
    {
        let mut prop = scenario.take_shared<Proposal<TestPayload>>();
        prop.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(prop);
    };

    // Last millisecond of the window
    clock.set_for_testing(1_000_000 + 3_600_000 + 3_600_000 - 1);

    // Execute succeeds
    scenario.next_tx(CREATOR);
    {
        let prop = scenario.take_shared<Proposal<TestPayload>>();
        let dao = scenario.take_shared<DAO>();
        let (_payload, req) = prop.execute(
            dao.governance(),
            option::none(),
            false,
            &clock,
            scenario.ctx(),
        );
        proposal::consume(req);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// === Test 24: Cooldown active aborts ===

#[test, expected_failure(abort_code = proposal::ECooldownActive)]
/// Abort — cooldown period not elapsed.
fun test_execute_cooldown_active_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000_000);

    create_test_dao(&mut scenario);

    // Create proposal with 1 hour cooldown
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let config = proposal::new_config(
            5_000,
            5_000,
            0,
            3_600_000,
            0,
            3_600_000, // cooldown = 1 hour
        );
        proposal::create<TestPayload>(
            dao.id(),
            b"SetBoard".to_ascii_string(),
            CREATOR,
            option::some(string::utf8(b"ipfs://test")),
            TestPayload { value: 42 },
            config,
            dao.governance(),
            dao.status().is_active(),
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    // Pass
    scenario.next_tx(CREATOR);
    {
        let mut prop = scenario.take_shared<Proposal<TestPayload>>();
        prop.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(prop);
    };

    // Try execute with recent last_executed_at (cooldown active)
    scenario.next_tx(CREATOR);
    {
        let prop = scenario.take_shared<Proposal<TestPayload>>();
        let dao = scenario.take_shared<DAO>();
        // Last executed 500ms ago — within 1hr cooldown
        let (_payload, req) = prop.execute(
            dao.governance(),
            option::some(999_500),
            false,
            &clock,
            scenario.ctx(),
        );
        proposal::consume(req);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// === Test 25: Cooldown elapsed succeeds ===

#[test]
/// Execution proceeds after cooldown.
fun test_execute_cooldown_elapsed_succeeds() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(10_000_000);

    create_test_dao(&mut scenario);

    // Create proposal with 1 hour cooldown
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let config = proposal::new_config(
            5_000,
            5_000,
            0,
            3_600_000,
            0,
            3_600_000, // cooldown = 1 hour
        );
        proposal::create<TestPayload>(
            dao.id(),
            b"SetBoard".to_ascii_string(),
            CREATOR,
            option::some(string::utf8(b"ipfs://test")),
            TestPayload { value: 42 },
            config,
            dao.governance(),
            dao.status().is_active(),
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    // Pass
    scenario.next_tx(CREATOR);
    {
        let mut prop = scenario.take_shared<Proposal<TestPayload>>();
        prop.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(prop);
    };

    // Execute with old last_executed_at (cooldown elapsed)
    scenario.next_tx(CREATOR);
    {
        let prop = scenario.take_shared<Proposal<TestPayload>>();
        let dao = scenario.take_shared<DAO>();
        // Last executed 2 hours ago — cooldown elapsed
        let (_payload, req) = prop.execute(
            dao.governance(),
            option::some(10_000_000 - 7_200_000),
            false,
            &clock,
            scenario.ctx(),
        );
        proposal::consume(req);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = armature::proposal::EExecutionPaused)]
fun test_execute_paused_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000_000);

    create_test_dao(&mut scenario);
    create_test_proposal(&mut scenario, &clock);

    // CREATOR's single vote meets 50% threshold — proposal passes
    scenario.next_tx(CREATOR);
    {
        let mut prop = scenario.take_shared<Proposal<TestPayload>>();
        prop.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(prop);
    };

    // Execute with execution_paused=true — should abort with EExecutionPaused
    scenario.next_tx(CREATOR);
    {
        let prop = scenario.take_shared<Proposal<TestPayload>>();
        let dao = scenario.take_shared<DAO>();
        let (_payload, req) = prop.execute(
            dao.governance(),
            option::none(),
            true,
            &clock,
            scenario.ctx(),
        );
        proposal::consume(req);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// =========================================================================
// consume_execution_request tests
// =========================================================================

#[test]
/// consume_execution_request destroys the hot potato without requiring a Proposal object.
fun consume_execution_request_destroys_hot_potato() {
    let dao_id = object::id_from_address(@0xDA0);
    let proposal_id = object::id_from_address(@0xBEEF);
    let req = proposal::new_execution_request<TestPayload>(dao_id, proposal_id);

    assert!(req.req_dao_id() == dao_id);
    assert!(req.req_proposal_id() == proposal_id);

    proposal::consume_execution_request_for_testing(req);
}

#[test]
/// consume_execution_request works as an alternative to finalize when the handler
/// does not need to cross-validate the Proposal object.
fun consume_execution_request_works_after_governance_execution() {
    let mut scenario = test_scenario::begin(CREATOR);
    let clock = clock::create_for_testing(scenario.ctx());

    create_test_dao(&mut scenario);
    create_test_proposal(&mut scenario, &clock);

    scenario.next_tx(CREATOR);
    {
        let mut prop = scenario.take_shared<Proposal<TestPayload>>();
        prop.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(prop);
    };

    scenario.next_tx(CREATOR);
    {
        let prop = scenario.take_shared<Proposal<TestPayload>>();
        let dao = scenario.take_shared<DAO>();
        let (_payload, req) = prop.execute(
            dao.governance(),
            option::none(),
            false,
            &clock,
            scenario.ctx(),
        );
        // Consume without passing the Proposal object — the hot potato is sufficient proof.
        proposal::consume_execution_request_for_testing(req);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// =========================================================================
// ExecutionTicket accessor tests
// =========================================================================

#[test]
/// ticket_is_standalone returns true for Standalone tickets.
fun test_ticket_is_standalone_true() {
    let dao_id = object::id_from_address(@0xDA0);
    let proposal_id = object::id_from_address(@0xBEEF);
    let ticket = proposal::new_standalone_ticket_for_testing<TestPayload>(
        dao_id,
        proposal_id,
        TestPayload { value: 1 },
        100,
        200,
    );
    assert!(ticket.ticket_is_standalone());
    assert!(ticket.ticket_yes_weight() == 100);
    assert!(ticket.ticket_total_snapshot_weight() == 200);
    assert!(ticket.ticket_dao_id() == dao_id);
    ticket.discharge();
}

#[test, expected_failure(abort_code = armature::proposal::ENotStandaloneTicket)]
/// ticket_yes_weight aborts on Composite tickets.
fun test_ticket_yes_weight_aborts_on_composite() {
    let dao_id = object::id_from_address(@0xDA0);
    let proposal_id = object::id_from_address(@0xBEEF);
    let ticket = proposal::new_composite_ticket_for_testing<TestPayload>(
        dao_id,
        proposal_id,
        TestPayload { value: 1 },
    );
    // Composite ticket — this must abort
    let _w = ticket.ticket_yes_weight();
    ticket.discharge();
}

#[test, expected_failure(abort_code = armature::proposal::ENotStandaloneTicket)]
/// ticket_total_snapshot_weight aborts on External tickets.
fun test_ticket_total_snapshot_weight_aborts_on_external() {
    let dao_id = object::id_from_address(@0xDA0);
    let proposal_id = object::id_from_address(@0xBEEF);
    let ticket = proposal::new_external_ticket_for_testing<TestPayload>(
        dao_id,
        proposal_id,
        TestPayload { value: 1 },
    );
    // External ticket — this must abort
    let _w = ticket.ticket_total_snapshot_weight();
    ticket.discharge();
}

#[test]
/// ticket_is_standalone returns false for Composite tickets.
fun test_ticket_is_standalone_false_for_composite() {
    let dao_id = object::id_from_address(@0xDA0);
    let proposal_id = object::id_from_address(@0xBEEF);
    let ticket = proposal::new_composite_ticket_for_testing<TestPayload>(
        dao_id,
        proposal_id,
        TestPayload { value: 1 },
    );
    assert!(!ticket.ticket_is_standalone());
    ticket.discharge();
}

#[test]
/// ticket_is_standalone returns false for External tickets.
fun test_ticket_is_standalone_false_for_external() {
    let dao_id = object::id_from_address(@0xDA0);
    let proposal_id = object::id_from_address(@0xBEEF);
    let ticket = proposal::new_external_ticket_for_testing<TestPayload>(
        dao_id,
        proposal_id,
        TestPayload { value: 1 },
    );
    assert!(!ticket.ticket_is_standalone());
    ticket.discharge();
}

// =========================================================================
// discharge_returning_payload tests
// =========================================================================

/// Payload type without drop — only has store.
public struct NonDropPayload has store {
    value: u64,
}

#[test]
/// discharge_returning_payload returns the payload from a Standalone ticket.
fun test_discharge_returning_payload() {
    let dao_id = object::id_from_address(@0xDA0);
    let proposal_id = object::id_from_address(@0xBEEF);
    let ticket = proposal::new_standalone_ticket_for_testing<NonDropPayload>(
        dao_id,
        proposal_id,
        NonDropPayload { value: 42 },
        100,
        200,
    );
    let payload = proposal::discharge_returning_payload(ticket);
    assert!(payload.value == 42);
    // Manually destructure since NonDropPayload has no drop
    let NonDropPayload { value: _ } = payload;
}

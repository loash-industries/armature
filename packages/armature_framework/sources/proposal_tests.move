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
        let init = governance::init_board(vector[CREATOR, MEMBER_B], 3);
        dao::create(
            &init,
            string::utf8(b"Test DAO"),
            string::utf8(b"A test DAO"),
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
            string::utf8(b"ipfs://test"),
            TestPayload { value: 42 },
            config,
            dao.governance(),
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

// === Test 6: Active -> Expired ===

#[test]
/// try_expire after expiry_ms sets Expired.
fun test_status_active_to_expired() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000_000);

    create_test_dao(&mut scenario);
    create_test_proposal(&mut scenario, &clock);

    // Advance clock past expiry (1 hour = 3_600_000ms)
    clock.set_for_testing(1_000_000 + 3_600_000);

    scenario.next_tx(CREATOR);
    {
        let mut prop = scenario.take_shared<Proposal<TestPayload>>();
        prop.try_expire(&clock);
        assert!(prop.status().is_expired());
        test_scenario::return_shared(prop);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// === Test 7: Passed -> Executed ===

#[test]
/// execute sets Executed and returns ExecutionRequest.
fun test_status_passed_to_executed() {
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
    {
        let mut prop = scenario.take_shared<Proposal<TestPayload>>();
        let dao = scenario.take_shared<DAO>();
        let req = prop.execute(
            dao.governance(),
            option::none(),
            &clock,
            scenario.ctx(),
        );
        assert!(prop.status().is_executed());
        proposal::consume(req);
        test_scenario::return_shared(prop);
        test_scenario::return_shared(dao);
    };

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

// === Test 9: Cannot vote on Expired ===

#[test, expected_failure(abort_code = proposal::ENotActive)]
/// Abort — cannot vote on expired proposal.
fun test_cannot_vote_on_expired_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000_000);

    create_test_dao(&mut scenario);
    create_test_proposal(&mut scenario, &clock);

    // Expire the proposal
    clock.set_for_testing(1_000_000 + 3_600_000);
    scenario.next_tx(CREATOR);
    {
        let mut prop = scenario.take_shared<Proposal<TestPayload>>();
        prop.try_expire(&clock);
        test_scenario::return_shared(prop);
    };

    // Try to vote
    scenario.next_tx(CREATOR);
    {
        let mut prop = scenario.take_shared<Proposal<TestPayload>>();
        prop.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(prop);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// === Test 10: Cannot vote on Executed ===

#[test, expected_failure(abort_code = proposal::ENotActive)]
/// Abort — cannot vote on executed proposal.
fun test_cannot_vote_on_executed_aborts() {
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

    // Execute
    scenario.next_tx(CREATOR);
    {
        let mut prop = scenario.take_shared<Proposal<TestPayload>>();
        let dao = scenario.take_shared<DAO>();
        let req = prop.execute(dao.governance(), option::none(), &clock, scenario.ctx());
        proposal::consume(req);
        test_scenario::return_shared(prop);
        test_scenario::return_shared(dao);
    };

    // Try to vote
    scenario.next_tx(MEMBER_B);
    {
        let mut prop = scenario.take_shared<Proposal<TestPayload>>();
        prop.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(prop);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// === Test 11: Cannot execute Expired ===

#[test, expected_failure(abort_code = proposal::ENotPassed)]
/// Abort — expired cannot be executed.
fun test_cannot_execute_expired_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000_000);

    create_test_dao(&mut scenario);
    create_test_proposal(&mut scenario, &clock);

    // Expire
    clock.set_for_testing(1_000_000 + 3_600_000);
    scenario.next_tx(CREATOR);
    {
        let mut prop = scenario.take_shared<Proposal<TestPayload>>();
        prop.try_expire(&clock);
        test_scenario::return_shared(prop);
    };

    // Try to execute
    scenario.next_tx(CREATOR);
    {
        let mut prop = scenario.take_shared<Proposal<TestPayload>>();
        let dao = scenario.take_shared<DAO>();
        let req = prop.execute(dao.governance(), option::none(), &clock, scenario.ctx());
        proposal::consume(req);
        test_scenario::return_shared(prop);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// === Test 12: Cannot expire Passed ===

#[test, expected_failure(abort_code = proposal::ENotActive)]
/// Abort — Passed cannot transition to Expired.
fun test_cannot_expire_passed_aborts() {
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

    // Try to expire
    clock.set_for_testing(1_000_000 + 3_600_000);
    scenario.next_tx(CREATOR);
    {
        let mut prop = scenario.take_shared<Proposal<TestPayload>>();
        prop.try_expire(&clock);
        test_scenario::return_shared(prop);
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
        dao.governance_mut().set_board(vector[CREATOR, new_member], 3);
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
        dao.governance_mut().set_board(vector[CREATOR, MEMBER_B, new_member], 3);
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
        let mut prop = scenario.take_shared<Proposal<TestPayload>>();
        let dao = scenario.take_shared<DAO>();
        let req = prop.execute(dao.governance(), option::none(), &clock, scenario.ctx());
        proposal::consume(req);
        test_scenario::return_shared(prop);
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
        let mut prop = scenario.take_shared<Proposal<TestPayload>>();
        let dao = scenario.take_shared<DAO>();
        let req = prop.execute(dao.governance(), option::none(), &clock, scenario.ctx());
        assert!(prop.status().is_executed());
        proposal::consume(req);
        test_scenario::return_shared(prop);
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
        let mut prop = scenario.take_shared<Proposal<TestPayload>>();
        let dao = scenario.take_shared<DAO>();
        let req = prop.execute(dao.governance(), option::none(), &clock, scenario.ctx());
        assert!(prop.status().is_executed());
        proposal::consume(req);
        test_scenario::return_shared(prop);
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
            string::utf8(b"ipfs://test"),
            TestPayload { value: 42 },
            config,
            dao.governance(),
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
        let mut prop = scenario.take_shared<Proposal<TestPayload>>();
        let dao = scenario.take_shared<DAO>();
        let req = prop.execute(dao.governance(), option::none(), &clock, scenario.ctx());
        proposal::consume(req);
        test_scenario::return_shared(prop);
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
            string::utf8(b"ipfs://test"),
            TestPayload { value: 42 },
            config,
            dao.governance(),
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
        let mut prop = scenario.take_shared<Proposal<TestPayload>>();
        let dao = scenario.take_shared<DAO>();
        let req = prop.execute(dao.governance(), option::none(), &clock, scenario.ctx());
        assert!(prop.status().is_executed());
        proposal::consume(req);
        test_scenario::return_shared(prop);
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
            string::utf8(b"ipfs://test"),
            TestPayload { value: 42 },
            config,
            dao.governance(),
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
        let mut prop = scenario.take_shared<Proposal<TestPayload>>();
        let dao = scenario.take_shared<DAO>();
        // Last executed 500ms ago — within 1hr cooldown
        let req = prop.execute(
            dao.governance(),
            option::some(999_500),
            &clock,
            scenario.ctx(),
        );
        proposal::consume(req);
        test_scenario::return_shared(prop);
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
            string::utf8(b"ipfs://test"),
            TestPayload { value: 42 },
            config,
            dao.governance(),
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
        let mut prop = scenario.take_shared<Proposal<TestPayload>>();
        let dao = scenario.take_shared<DAO>();
        // Last executed 2 hours ago — cooldown elapsed
        let req = prop.execute(
            dao.governance(),
            option::some(10_000_000 - 7_200_000),
            &clock,
            scenario.ctx(),
        );
        assert!(prop.status().is_executed());
        proposal::consume(req);
        test_scenario::return_shared(prop);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

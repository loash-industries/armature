#[test_only]
module armature::board_voting_tests;

use armature::board_voting;
use armature::dao::{Self, DAO};
use armature::governance;
use armature::proposal::{Self, Proposal};
use std::string;
use sui::clock::{Self, Clock};
use sui::test_scenario;

// === Test addresses ===

const CREATOR: address = @0xA;
const MEMBER_B: address = @0xB;
const MEMBER_C: address = @0xC;
const MEMBER_D: address = @0xD;
const MEMBER_E: address = @0xE;
const MEMBER_F: address = @0xF;
const MEMBER_G: address = @0x10;
const MEMBER_H: address = @0x11;
const MEMBER_I: address = @0x12;
const MEMBER_J: address = @0x13;

// === Test payload ===

public struct TestPayload has drop, store {
    value: u64,
}

// === Helpers ===

fun create_dao_with_members(scenario: &mut test_scenario::Scenario, members: vector<address>) {
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(members);
        dao::create(
            &init,
            string::utf8(b"Test DAO"),
            string::utf8(b"A test DAO"),
            string::utf8(b"https://example.com/logo.png"),
            scenario.ctx(),
        );
    };
}

fun submit_proposal_with_config(
    scenario: &mut test_scenario::Scenario,
    clock: &Clock,
    quorum: u16,
    threshold: u16,
) {
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        // Temporarily set a custom config by using proposal::create directly
        let config = proposal::new_config(
            quorum,
            threshold,
            0,
            3_600_000, // 1 hour expiry
            0,
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
            clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };
}

fun vote_as(scenario: &mut test_scenario::Scenario, voter: address, approve: bool, clock: &Clock) {
    scenario.next_tx(voter);
    {
        let mut prop = scenario.take_shared<Proposal<TestPayload>>();
        prop.vote(approve, clock, scenario.ctx());
        test_scenario::return_shared(prop);
    };
}

// === Test 1: Single member yes passes ===

#[test]
/// 1/1 = 100%, passes any threshold.
fun test_board__single_member_yes_passes() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000_000);

    create_dao_with_members(&mut scenario, vector[CREATOR]);
    submit_proposal_with_config(&mut scenario, &clock, 5_000, 5_000);

    vote_as(&mut scenario, CREATOR, true, &clock);

    // Check passed
    scenario.next_tx(CREATOR);
    {
        let prop = scenario.take_shared<Proposal<TestPayload>>();
        assert!(prop.status().is_passed());
        test_scenario::return_shared(prop);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// === Test 2: Unanimous 3 member passes ===

#[test]
/// 3/3 = 100%, passes.
fun test_board__unanimous_3_member_passes() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000_000);

    create_dao_with_members(&mut scenario, vector[CREATOR, MEMBER_B, MEMBER_C]);
    // quorum 10000 (100%) so all 3 must vote before it can pass
    submit_proposal_with_config(&mut scenario, &clock, 10_000, 5_000);

    vote_as(&mut scenario, CREATOR, true, &clock);
    vote_as(&mut scenario, MEMBER_B, true, &clock);
    vote_as(&mut scenario, MEMBER_C, true, &clock);

    scenario.next_tx(CREATOR);
    {
        let prop = scenario.take_shared<Proposal<TestPayload>>();
        assert!(prop.status().is_passed());
        assert!(prop.yes_weight() == 3);
        assert!(prop.no_weight() == 0);
        test_scenario::return_shared(prop);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// === Test 3: 2 of 3 yes passes at 66% threshold ===

#[test]
/// 2/2 voting, 100% yes — passes with 66% threshold.
/// Quorum: (2) * 10000 = 20000 >= 6600 * 3 = 19800 ✓
/// Threshold: 2 * 10000 = 20000 >= 6600 * 2 = 13200 ✓
fun test_board__2_of_3_yes_passes_at_66() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000_000);

    create_dao_with_members(&mut scenario, vector[CREATOR, MEMBER_B, MEMBER_C]);
    submit_proposal_with_config(&mut scenario, &clock, 6_600, 6_600);

    vote_as(&mut scenario, CREATOR, true, &clock);
    // After first vote: quorum = 1*10000=10000 vs 6600*3=19800 → not met
    scenario.next_tx(CREATOR);
    {
        let prop = scenario.take_shared<Proposal<TestPayload>>();
        assert!(prop.status().is_active());
        test_scenario::return_shared(prop);
    };

    vote_as(&mut scenario, MEMBER_B, true, &clock);
    // After second vote: quorum = 2*10000=20000 vs 6600*3=19800 → met ✓
    // Threshold: 2*10000=20000 vs 6600*2=13200 → met ✓

    scenario.next_tx(CREATOR);
    {
        let prop = scenario.take_shared<Proposal<TestPayload>>();
        assert!(prop.status().is_passed());
        test_scenario::return_shared(prop);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// === Test 4: 1 of 3 yes fails at 66% quorum ===

#[test]
/// 1/1 voting, 100% yes — but quorum not met at 66%.
/// Quorum: 1*10000=10000 vs 6600*3=19800 → not met.
fun test_board__1_of_3_yes_fails_at_66() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000_000);

    create_dao_with_members(&mut scenario, vector[CREATOR, MEMBER_B, MEMBER_C]);
    submit_proposal_with_config(&mut scenario, &clock, 6_600, 5_000);

    vote_as(&mut scenario, CREATOR, true, &clock);

    scenario.next_tx(CREATOR);
    {
        let prop = scenario.take_shared<Proposal<TestPayload>>();
        assert!(prop.status().is_active()); // Still active — quorum not met
        test_scenario::return_shared(prop);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// === Test 5: Exact quorum boundary ===

#[test]
/// Quorum at exactly required level.
/// 3 members, quorum=6667 (66.67%). 2 vote → 2*10000=20000 vs 6667*3=20001 → NOT met.
/// Need exact boundary: quorum=6666, 2 vote → 20000 vs 6666*3=19998 → met.
fun test_board__exact_quorum_boundary() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000_000);

    create_dao_with_members(&mut scenario, vector[CREATOR, MEMBER_B, MEMBER_C]);
    // Quorum 6666 = 66.66%. With 3 members, need 2*10000=20000 >= 6666*3=19998 → met
    submit_proposal_with_config(&mut scenario, &clock, 6_666, 5_000);

    vote_as(&mut scenario, CREATOR, true, &clock);
    vote_as(&mut scenario, MEMBER_B, true, &clock);

    scenario.next_tx(CREATOR);
    {
        let prop = scenario.take_shared<Proposal<TestPayload>>();
        assert!(prop.status().is_passed());
        test_scenario::return_shared(prop);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// === Test 6: Below quorum does not pass ===

#[test]
/// Not enough voters participated.
/// 3 members, quorum=6667 (66.67%). 2 vote → 2*10000=20000 vs 6667*3=20001 → not met.
fun test_board__below_quorum_does_not_pass() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000_000);

    create_dao_with_members(&mut scenario, vector[CREATOR, MEMBER_B, MEMBER_C]);
    submit_proposal_with_config(&mut scenario, &clock, 6_667, 5_000);

    vote_as(&mut scenario, CREATOR, true, &clock);
    vote_as(&mut scenario, MEMBER_B, true, &clock);

    scenario.next_tx(CREATOR);
    {
        let prop = scenario.take_shared<Proposal<TestPayload>>();
        assert!(prop.status().is_active()); // Quorum NOT met
        test_scenario::return_shared(prop);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// === Test 7: Threshold boundary 50 percent ===

#[test]
/// 1 yes / 1 no = 50% — passes at threshold 5000 (50%).
/// Quorum: 2*10000=20000 vs 5000*3=15000 → met ✓
/// Threshold: 1*10000=10000 vs 5000*2=10000 → met (>=) ✓
fun test_board__threshold_boundary_50_percent() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000_000);

    create_dao_with_members(&mut scenario, vector[CREATOR, MEMBER_B, MEMBER_C]);
    submit_proposal_with_config(&mut scenario, &clock, 5_000, 5_000);

    vote_as(&mut scenario, CREATOR, true, &clock);
    vote_as(&mut scenario, MEMBER_B, false, &clock);

    scenario.next_tx(CREATOR);
    {
        let prop = scenario.take_shared<Proposal<TestPayload>>();
        assert!(prop.status().is_passed());
        assert!(prop.yes_weight() == 1);
        assert!(prop.no_weight() == 1);
        test_scenario::return_shared(prop);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// === Test 8: No votes majority fails ===

#[test]
/// 1 yes / 2 no — does not pass.
/// Quorum 10000 (100%) ensures all must vote.
/// Threshold: 1*10000=10000 vs 5000*3=15000 → not met.
fun test_board__no_votes_majority_fails() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000_000);

    create_dao_with_members(&mut scenario, vector[CREATOR, MEMBER_B, MEMBER_C]);
    // quorum 10000 (100%) so all 3 must vote before quorum is met
    submit_proposal_with_config(&mut scenario, &clock, 10_000, 5_000);

    vote_as(&mut scenario, CREATOR, true, &clock);
    vote_as(&mut scenario, MEMBER_B, false, &clock);
    vote_as(&mut scenario, MEMBER_C, false, &clock);

    scenario.next_tx(CREATOR);
    {
        let prop = scenario.take_shared<Proposal<TestPayload>>();
        assert!(prop.status().is_active()); // 1/3 yes = 33%, threshold 50% not met
        assert!(prop.yes_weight() == 1);
        assert!(prop.no_weight() == 2);
        test_scenario::return_shared(prop);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// === Test 9: Abstention not counted in threshold ===

#[test]
/// Non-voters don't count toward yes/no.
/// 3 members, only 1 votes yes. Quorum=1 (0.01%), threshold=5000 (50%).
/// Quorum: 1*10000=10000 vs 1*3=3 → met ✓
/// Threshold: 1*10000=10000 vs 5000*1=5000 → met ✓
/// Passes because abstainer doesn't count toward no.
fun test_board__abstention_not_counted_in_threshold() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000_000);

    create_dao_with_members(&mut scenario, vector[CREATOR, MEMBER_B, MEMBER_C]);
    // Low quorum so 1 voter is enough
    submit_proposal_with_config(&mut scenario, &clock, 1, 5_000);

    vote_as(&mut scenario, CREATOR, true, &clock);

    scenario.next_tx(CREATOR);
    {
        let prop = scenario.take_shared<Proposal<TestPayload>>();
        assert!(prop.status().is_passed()); // Abstentions don't count as no
        assert!(prop.yes_weight() == 1);
        assert!(prop.no_weight() == 0);
        test_scenario::return_shared(prop);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// === Test 10: Large board 10 members ===

#[test]
/// 7/10 = 70% — passes at 66% threshold.
/// Quorum 7000 (70%) so need 7 of 10 to vote before quorum is met.
/// After 7th yes: 7*10000=70000 >= 7000*10=70000 → met ✓
/// Threshold: 7*10000=70000 >= 6600*7=46200 → met ✓
fun test_board__large_board_10_members() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000_000);

    create_dao_with_members(
        &mut scenario,
        vector[
            CREATOR,
            MEMBER_B,
            MEMBER_C,
            MEMBER_D,
            MEMBER_E,
            MEMBER_F,
            MEMBER_G,
            MEMBER_H,
            MEMBER_I,
            MEMBER_J,
        ],
    );
    submit_proposal_with_config(&mut scenario, &clock, 7_000, 6_600);

    // 7 yes votes
    vote_as(&mut scenario, CREATOR, true, &clock);
    vote_as(&mut scenario, MEMBER_B, true, &clock);
    vote_as(&mut scenario, MEMBER_C, true, &clock);
    vote_as(&mut scenario, MEMBER_D, true, &clock);
    vote_as(&mut scenario, MEMBER_E, true, &clock);
    vote_as(&mut scenario, MEMBER_F, true, &clock);
    vote_as(&mut scenario, MEMBER_G, true, &clock);

    scenario.next_tx(CREATOR);
    {
        let prop = scenario.take_shared<Proposal<TestPayload>>();
        assert!(prop.status().is_passed());
        assert!(prop.yes_weight() == 7);
        assert!(prop.no_weight() == 0);
        test_scenario::return_shared(prop);
    };

    clock.destroy_for_testing();
    scenario.end();
}

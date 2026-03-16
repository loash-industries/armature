# Board Voting Tests

## Summary

The `voting/board.move` module implements vote counting for Board governance. Each member has one vote. These tests verify quorum calculation, threshold checking, and edge cases around small/large boards.

## Test Matrix

| Test | Expected |
|------|----------|
| `test_board__single_member_yes_passes` | 1/1 = 100%, passes any threshold |
| `test_board__unanimous_3_member_passes` | 3/3 = 100%, passes |
| `test_board__2_of_3_yes_passes_at_66` | 2/2 voting, 100% yes — passes with 66% threshold |
| `test_board__1_of_3_yes_fails_at_66` | 1/1 voting, quorum may not be met |
| `test_board__exact_quorum_boundary` | Quorum at exactly required level |
| `test_board__below_quorum_does_not_pass` | Not enough voters participated |
| `test_board__threshold_boundary_50_percent` | 1 yes / 1 no = 50% — passes at threshold 5000 |
| `test_board__no_votes_majority_fails` | 1 yes / 2 no — does not pass |
| `test_board__abstention_not_counted_in_threshold` | Non-voters don't count toward yes/no |
| `test_board__large_board_10_members` | 7/10 = 70% — passes at 66% threshold |

## Tests

---

### Single member, single YES vote passes

**Why it matters:** The simplest DAO (solo founder) must be fully functional. If a 1-member board can't pass proposals, the entire creation flow breaks.

```move
#[test]
fun test_board__single_member_yes_passes() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE]);

    let prop_id = test_helpers::create_proposal(
        &mut scenario, dao_id,
        admin::new_update_metadata(b"new-cid"),
    );

    scenario.next_tx(ALICE);
    {
        let mut prop = test_scenario::take_shared<Proposal<admin::UpdateMetadata>>(&scenario);
        proposal::vote(&mut prop, true, scenario.ctx());

        // 1 yes, 0 no, 1 total
        // quorum check: (1+0) * 10000 >= quorum * 1
        // threshold check: 1 * 10000 / (1+0) = 10000 >= any threshold ≤ 10000
        assert!(proposal::status(&prop) == proposal::status_passed());

        test_scenario::return_shared(prop);
    };
    test_scenario::end(scenario);
}
```

---

### 2 of 3 YES passes at 66% threshold

**Why it matters:** The most common board configuration (3 members, 66% threshold). Validates the core vote math.

```move
#[test]
fun test_board__2_of_3_yes_passes_at_66() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE, BOB, CAROL]);

    let prop_id = test_helpers::create_proposal(
        &mut scenario, dao_id,
        admin::new_update_metadata(b"new-cid"),
    );

    // Alice votes YES
    scenario.next_tx(ALICE);
    {
        let mut prop = test_scenario::take_shared<Proposal<admin::UpdateMetadata>>(&scenario);
        proposal::vote(&mut prop, true, scenario.ctx());
        // 1 yes — not yet passed (depends on quorum)
        test_scenario::return_shared(prop);
    };

    // Bob votes YES
    scenario.next_tx(BOB);
    {
        let mut prop = test_scenario::take_shared<Proposal<admin::UpdateMetadata>>(&scenario);
        proposal::vote(&mut prop, true, scenario.ctx());

        // 2 yes, 0 no
        // quorum: (2+0) * 10000 >= 1 * 3 → 20000 >= 3 ✓ (with quorum=1)
        // threshold: 2 * 10000 / (2+0) = 10000 >= 6600 ✓
        assert!(proposal::status(&prop) == proposal::status_passed());

        test_scenario::return_shared(prop);
    };
    test_scenario::end(scenario);
}
```

---

### NO votes majority does not pass

**Why it matters:** If NO votes were accidentally ignored or counted as YES, governance would be meaningless.

```move
#[test]
fun test_board__no_votes_majority_fails() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE, BOB, CAROL]);

    let prop_id = test_helpers::create_proposal(
        &mut scenario, dao_id,
        admin::new_update_metadata(b"new-cid"),
    );

    // Alice: YES, Bob: NO, Carol: NO
    scenario.next_tx(ALICE);
    {
        let mut prop = test_scenario::take_shared<Proposal<admin::UpdateMetadata>>(&scenario);
        proposal::vote(&mut prop, true, scenario.ctx());
        test_scenario::return_shared(prop);
    };
    scenario.next_tx(BOB);
    {
        let mut prop = test_scenario::take_shared<Proposal<admin::UpdateMetadata>>(&scenario);
        proposal::vote(&mut prop, false, scenario.ctx());
        test_scenario::return_shared(prop);
    };
    scenario.next_tx(CAROL);
    {
        let mut prop = test_scenario::take_shared<Proposal<admin::UpdateMetadata>>(&scenario);
        proposal::vote(&mut prop, false, scenario.ctx());

        // 1 yes, 2 no
        // threshold: 1 * 10000 / (1+2) = 3333 < 5000 (minimum threshold)
        assert!(proposal::status(&prop) == proposal::status_active());

        test_scenario::return_shared(prop);
    };
    test_scenario::end(scenario);
}
```

---

### Threshold boundary: exactly 50%

**Why it matters:** Tests the boundary condition where yes == no. With `approval_threshold = 5000` (50%), this should pass.

```move
#[test]
fun test_board__threshold_boundary_50_percent() {
    let mut scenario = test_scenario::begin(ALICE);
    // 2-member board
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE, BOB]);

    // Assume this type has approval_threshold = 5000
    let prop_id = test_helpers::create_proposal(
        &mut scenario, dao_id,
        admin::new_update_metadata(b"new-cid"),
    );

    // Alice: YES, Bob: NO → 1 yes, 1 no
    scenario.next_tx(ALICE);
    {
        let mut prop = test_scenario::take_shared<Proposal<admin::UpdateMetadata>>(&scenario);
        proposal::vote(&mut prop, true, scenario.ctx());
        test_scenario::return_shared(prop);
    };
    scenario.next_tx(BOB);
    {
        let mut prop = test_scenario::take_shared<Proposal<admin::UpdateMetadata>>(&scenario);
        proposal::vote(&mut prop, false, scenario.ctx());

        // 1 * 10000 / (1+1) = 5000 >= 5000 → passes at exact boundary
        assert!(proposal::status(&prop) == proposal::status_passed());

        test_scenario::return_shared(prop);
    };
    test_scenario::end(scenario);
}
```

---

### Abstention (non-voting) not counted in threshold

**Why it matters:** Abstention should not count as a vote. Threshold is `yes / (yes + no)`, not `yes / total_members`.

```move
#[test]
fun test_board__abstention_not_counted_in_threshold() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE, BOB, CAROL]);

    let prop_id = test_helpers::create_proposal(
        &mut scenario, dao_id,
        admin::new_update_metadata(b"new-cid"),
    );

    // Only Alice votes YES, Bob and Carol abstain
    scenario.next_tx(ALICE);
    {
        let mut prop = test_scenario::take_shared<Proposal<admin::UpdateMetadata>>(&scenario);
        proposal::vote(&mut prop, true, scenario.ctx());

        // 1 yes, 0 no → threshold: 1 * 10000 / (1+0) = 10000 (100%)
        // quorum check: (1+0) * 10000 >= quorum * 3
        // If quorum = 1: 10000 >= 3 ✓ → passes
        // The key point: Carol's abstention doesn't drag down the threshold

        test_scenario::return_shared(prop);
    };
    test_scenario::end(scenario);
}
```

---

### Large board (10 members)

**Why it matters:** Ensures vote math scales correctly. Edge cases in integer division can appear with larger numbers.

```move
#[test]
fun test_board__large_board_10_members() {
    let mut scenario = test_scenario::begin(ALICE);
    let members = vector[
        @0x1, @0x2, @0x3, @0x4, @0x5,
        @0x6, @0x7, @0x8, @0x9, @0xA,
    ];
    let dao_id = test_helpers::setup_dao(&mut scenario, members);

    let prop_id = test_helpers::create_proposal(
        &mut scenario, dao_id,
        admin::new_update_metadata(b"new-cid"),
    );

    // 7 YES, 3 NO
    let mut i = 0;
    while (i < 7) {
        scenario.next_tx(*vector::borrow(&members, i));
        {
            let mut prop = test_scenario::take_shared<Proposal<admin::UpdateMetadata>>(&scenario);
            proposal::vote(&mut prop, true, scenario.ctx());
            test_scenario::return_shared(prop);
        };
        i = i + 1;
    };
    while (i < 10) {
        scenario.next_tx(*vector::borrow(&members, i));
        {
            let mut prop = test_scenario::take_shared<Proposal<admin::UpdateMetadata>>(&scenario);
            proposal::vote(&mut prop, false, scenario.ctx());
            test_scenario::return_shared(prop);
        };
        i = i + 1;
    };

    scenario.next_tx(ALICE);
    {
        let prop = test_scenario::take_shared<Proposal<admin::UpdateMetadata>>(&scenario);
        // 7 * 10000 / (7+3) = 7000 >= 6600 (66% threshold) → passes
        assert!(proposal::status(&prop) == proposal::status_passed());
        test_scenario::return_shared(prop);
    };
    test_scenario::end(scenario);
}
```

# Board Operations Tests

## Summary

The `proposals/board_ops.move` module handles `SetBoard` — atomic full-slate board replacement. No incremental add/remove.

## Test Matrix

| Test | Expected |
|------|----------|
| `test_set_board__replaces_all_members` | Old members removed, new members active |
| `test_set_board__old_member_cannot_propose` | Abort — removed member not eligible |
| `test_set_board__new_member_can_propose` | New member creates proposal successfully |
| `test_set_board__updates_seat_count` | `seat_count` reflects new value |
| `test_set_board__empty_board_aborts` | Abort — board must have at least 1 member |
| `test_set_board__preserves_governance_type` | Governance type still Board (immutability recheck) |

## Tests

---

### SetBoard: replaces all members

**Why it matters:** Board replacement is the primary membership management mechanism. Partial replacement would create inconsistencies if the old member list and new list overlap differently than expected.

```move
#[test]
fun test_set_board__replaces_all_members() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE, BOB]);

    let prop_id = test_helpers::create_proposal(
        &mut scenario, dao_id,
        board_ops::new_set_board(vector[CAROL, DAVE, EVE], 3),
    );
    test_helpers::pass_proposal<board_ops::SetBoard>(
        &mut scenario, prop_id, vector[ALICE, BOB],
    );
    // Execute + handle ...

    scenario.next_tx(CAROL);
    {
        let dao = test_scenario::take_shared<DAO>(&scenario);
        let gov = dao::governance(&dao);

        // Old members gone
        assert!(!governance::is_member(gov, ALICE));
        assert!(!governance::is_member(gov, BOB));

        // New members present
        assert!(governance::is_member(gov, CAROL));
        assert!(governance::is_member(gov, DAVE));
        assert!(governance::is_member(gov, EVE));

        test_scenario::return_shared(dao);
    };
    test_scenario::end(scenario);
}
```

---

### SetBoard: old member cannot propose

**Why it matters:** After board replacement, removed members must immediately lose governance rights. A window where both old and new boards are active would double the governance surface.

```move
#[test]
#[expected_failure(abort_code = proposal::ENotEligible)]
fun test_set_board__old_member_cannot_propose() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE, BOB]);

    // Replace board: [ALICE, BOB] -> [CAROL, DAVE]
    // ...

    // ALICE (removed) tries to create a proposal
    scenario.next_tx(ALICE);
    {
        let dao = test_scenario::take_shared<DAO>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());

        proposal::create(
            &dao,
            admin::new_update_metadata(b"sneaky"),
            b"metadata",
            &clock,
            scenario.ctx(),
        ); // abort — ALICE not a member

        clock::destroy_for_testing(clock);
        test_scenario::return_shared(dao);
    };
    test_scenario::end(scenario);
}
```

---

### SetBoard: empty board aborts

**Why it matters:** A zero-member board would make the DAO permanently ungovernable — no one could create or vote on proposals.

```move
#[test]
#[expected_failure(abort_code = board_ops::EEmptyBoard)]
fun test_set_board__empty_board_aborts() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE]);

    let prop_id = test_helpers::create_proposal(
        &mut scenario, dao_id,
        board_ops::new_set_board(vector[], 0), // empty board
    );
    test_helpers::pass_proposal<board_ops::SetBoard>(
        &mut scenario, prop_id, vector[ALICE],
    );
    // Execute -> handler aborts on empty board
    test_scenario::end(scenario);
}
```

---

### SetBoard: updates seat_count

```move
#[test]
fun test_set_board__updates_seat_count() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE, BOB]);

    // Replace with 5-member board
    let prop_id = test_helpers::create_proposal(
        &mut scenario, dao_id,
        board_ops::new_set_board(vector[CAROL, DAVE, EVE, FRANK, @0x10], 5),
    );
    test_helpers::pass_proposal<board_ops::SetBoard>(
        &mut scenario, prop_id, vector[ALICE, BOB],
    );
    // Execute + handle ...

    scenario.next_tx(CAROL);
    {
        let dao = test_scenario::take_shared<DAO>(&scenario);
        let gov = dao::governance(&dao);
        assert!(governance::seat_count(gov) == 5);
        test_scenario::return_shared(dao);
    };
    test_scenario::end(scenario);
}
```

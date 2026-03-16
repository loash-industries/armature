# Privileged Submit Tests

## Summary

`privileged_submit` allows a controller DAO to bypass the SubDAO's governance and create proposals in `Passed` status directly. This is the mechanism behind board replacement, pause/unpause, and forced charter amendments. These tests verify the dual hot-potato pattern, access control, and status behavior.

## Test Matrix

| Test | Expected |
|------|----------|
| `test_privileged_submit__creates_proposal_in_passed_status` | Proposal status is Passed immediately |
| `test_privileged_submit__requires_subdao_control` | Abort without valid `SubDAOControl` |
| `test_privileged_submit__wrong_subdao_control_aborts` | Abort if `control.subdao_id != subdao.id` |
| `test_privileged_submit__dual_hot_potato_consumed` | Both controller's and child's `ExecutionRequest` consumed |
| `test_privileged_submit__can_set_board_on_subdao` | Board replaced instantly via privileged path |
| `test_privileged_submit__can_pause_subdao` | `controller_paused` set to true |
| `test_privileged_submit__control_returned_via_cap_loan` | `SubDAOControl` returned to parent vault |

## Tests

---

### Creates proposal in Passed status

**Requirement:** `privileged_submit` creates proposal in `Passed` status directly.

**Why it matters:** The controller's governance already approved the action. Requiring a second vote on the SubDAO would defeat the purpose of hierarchical control.

```move
#[test]
fun test_privileged_submit__creates_proposal_in_passed_status() {
    let mut scenario = test_scenario::begin(ALICE);
    let (parent_id, child_id) = test_helpers::setup_dao_with_subdao(&mut scenario);

    // Parent creates a proposal to SetBoard on the child via privileged_submit
    // Step 1: Parent proposal (e.g., "override child board") passes on parent
    // Step 2: Parent handler loans SubDAOControl
    // Step 3: privileged_submit creates a Passed proposal on child

    scenario.next_tx(ALICE);
    {
        // After privileged_submit:
        let child_prop = test_scenario::take_shared<Proposal<board_ops::SetBoard>>(&scenario);

        // Status is Passed (not Active — no voting needed)
        assert!(proposal::status(&child_prop) == proposal::status_passed());

        test_scenario::return_shared(child_prop);
    };
    test_scenario::end(scenario);
}
```

---

### Requires valid SubDAOControl

**Why it matters:** Without this check, any DAO could inject proposals into any other DAO. The `SubDAOControl` is the proof of authority.

```move
#[test]
#[expected_failure(abort_code = capability_vault::ENotController)]
fun test_privileged_submit__wrong_subdao_control_aborts() {
    let mut scenario = test_scenario::begin(ALICE);

    // Setup: parent_A controls child_A. parent_B controls child_B.
    // parent_A tries to privileged_submit on child_B using control_A
    // → abort because control_A.subdao_id != child_B.id

    test_scenario::end(scenario);
}
```

---

### Dual hot potato pattern

**Why it matters:** Two hot potatoes are alive simultaneously — the controller's `ExecutionRequest` and the child's `ExecutionRequest`. Both must be consumed in the same PTB for the transaction to succeed. This is the most complex transaction pattern in the protocol.

```move
#[test]
fun test_privileged_submit__dual_hot_potato_consumed() {
    let mut scenario = test_scenario::begin(ALICE);
    let (parent_id, child_id) = test_helpers::setup_dao_with_subdao(&mut scenario);

    // Full PTB sequence:
    scenario.next_tx(ALICE);
    {
        // 1. Execute parent's proposal → controller_req (hot potato #1)
        let mut parent_prop = test_scenario::take_shared<Proposal<SomeParentType>>(&scenario);
        let parent_dao = test_scenario::take_shared_by_id<DAO>(&scenario, parent_id);
        let parent_freeze = test_scenario::take_shared<EmergencyFreeze>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());

        let controller_req = proposal::execute(
            &mut parent_prop, &parent_dao, &parent_freeze, &clock, scenario.ctx(),
        );

        // 2. Loan SubDAOControl from parent vault
        let mut parent_vault = test_scenario::take_shared<CapabilityVault>(&scenario);
        let (control, cap_loan) = capability_vault::loan_cap<SubDAOControl, SomeParentType>(
            &mut parent_vault, control_id, &controller_req,
        );

        // 3. privileged_submit on child → creates Passed proposal
        let child_dao = test_scenario::take_shared_by_id<DAO>(&scenario, child_id);
        proposal::privileged_submit(
            &control,
            &child_dao,
            board_ops::new_set_board(vector[FRANK], 1),
            scenario.ctx(),
        );

        // 4. Execute child's auto-passed proposal → child_req (hot potato #2)
        let mut child_prop = test_scenario::take_shared<Proposal<board_ops::SetBoard>>(&scenario);
        let child_freeze = test_scenario::take_shared<EmergencyFreeze>(&scenario);
        let child_req = proposal::execute(
            &mut child_prop, &child_dao, &child_freeze, &clock, scenario.ctx(),
        );

        // 5. Handle child's proposal (SetBoard)
        board_ops::handle_set_board(child_req, &mut child_dao);
        // child_req consumed (hot potato #2 gone)

        // 6. Return SubDAOControl to parent vault
        capability_vault::return_cap(&mut parent_vault, control, cap_loan);

        // 7. Consume controller_req
        // (parent handler's consume function)
        // controller_req consumed (hot potato #1 gone)

        // Cleanup
        clock::destroy_for_testing(clock);
        test_scenario::return_shared(parent_prop);
        test_scenario::return_shared(parent_dao);
        test_scenario::return_shared(parent_freeze);
        test_scenario::return_shared(parent_vault);
        test_scenario::return_shared(child_prop);
        test_scenario::return_shared(child_dao);
        test_scenario::return_shared(child_freeze);
    };
    test_scenario::end(scenario);
}
```

---

### Can set board on SubDAO

**Why it matters:** This is the most common use of `privileged_submit` — replacing a compromised or inactive SubDAO board.

```move
#[test]
fun test_privileged_submit__can_set_board_on_subdao() {
    let mut scenario = test_scenario::begin(ALICE);
    let (parent_id, child_id) = test_helpers::setup_dao_with_subdao(&mut scenario);

    // Parent uses privileged_submit to replace child board [DAVE, EVE] → [FRANK]
    // ... (full privileged_submit sequence as above)

    scenario.next_tx(FRANK);
    {
        let child_dao = test_scenario::take_shared_by_id<DAO>(&scenario, child_id);
        let gov = dao::governance(&child_dao);

        assert!(!governance::is_member(gov, DAVE));
        assert!(!governance::is_member(gov, EVE));
        assert!(governance::is_member(gov, FRANK));

        test_scenario::return_shared(child_dao);
    };
    test_scenario::end(scenario);
}
```

---

### SubDAOControl returned via cap loan

**Why it matters:** The `SubDAOControl` is loaned, not extracted. After the privileged operation, it must be back in the parent's vault — otherwise the parent loses future control.

```move
#[test]
fun test_privileged_submit__control_returned_via_cap_loan() {
    let mut scenario = test_scenario::begin(ALICE);
    let (parent_id, child_id) = test_helpers::setup_dao_with_subdao(&mut scenario);

    // Execute full privileged_submit sequence
    // ...

    // After the PTB: SubDAOControl should still be in parent's vault
    scenario.next_tx(ALICE);
    {
        let parent_vault = test_scenario::take_shared<CapabilityVault>(&scenario);
        assert!(capability_vault::has_type<SubDAOControl>(&parent_vault));
        // The specific control for child_id still exists
        // ...
        test_scenario::return_shared(parent_vault);
    };
    test_scenario::end(scenario);
}
```

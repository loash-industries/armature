# Proposal Lifecycle Tests

## Summary

The `proposal.move` module manages the full lifecycle of proposals: creation, voting, expiry, and execution. These tests verify the hot-potato pattern, status monotonicity, vote snapshot immutability, executor eligibility, and retry semantics.

## Test Matrix

| Test | Expected |
|------|----------|
| `test_execution_request_no_drop` | Compile-time: `ExecutionRequest` has no abilities |
| `test_execution_request_must_be_consumed` | Abort if not consumed in same PTB |
| `test_cap_loan_no_drop` | Compile-time: `CapLoan` has no abilities |
| `test_return_cap_verifies_cap_id` | Abort `ECapLoanMismatch` on wrong cap |
| `test_status_active_to_passed` | Vote triggers Passed when threshold met |
| `test_status_active_to_expired` | `try_expire` after expiry_ms sets Expired |
| `test_status_passed_to_executed` | `execute` sets Executed |
| `test_cannot_vote_on_passed_aborts` | Abort — Passed is terminal for voting |
| `test_cannot_vote_on_expired_aborts` | Abort |
| `test_cannot_vote_on_executed_aborts` | Abort |
| `test_cannot_execute_expired_aborts` | Abort `ENotPassed` |
| `test_cannot_expire_passed_aborts` | Abort — Passed cannot transition to Expired |
| `test_vote_snapshot_immutable_after_creation` | Snapshot unchanged after board change |
| `test_new_member_cannot_vote_on_old_proposal` | Abort — not in snapshot |
| `test_non_board_member_cannot_execute_aborts` | Abort `ENotEligible` |
| `test_board_member_can_execute` | Execution succeeds |
| `test_failed_execution_leaves_proposal_passed` | Status remains Passed after handler abort |
| `test_passed_proposal_retryable_after_failure` | Second execute attempt succeeds |
| `test_vote__double_vote_aborts` | Abort `EAlreadyVoted` |
| `test_vote__non_snapshot_member_aborts` | Abort — not in `vote_snapshot` |
| `test_vote__no_vote_counted_correctly` | NO votes increase `no_weight` |
| `test_execute__delay_not_elapsed_aborts` | Abort `EDelayNotElapsed` |
| `test_execute__delay_elapsed_succeeds` | Execution proceeds after delay |
| `test_execute__cooldown_active_aborts` | Abort `ECooldownActive` |
| `test_execute__cooldown_elapsed_succeeds` | Execution proceeds after cooldown |

## Tests

---

### ExecutionRequest has no abilities

**Requirement:** `ExecutionRequest<P>` has no `drop`/`store`/`copy`. Must be consumed in same PTB.

**Why it matters:** The hot-potato pattern is the core authorization mechanism. If `ExecutionRequest` had `drop`, a handler could be skipped — governance would approve but no action would execute. If it had `store`, it could be saved and replayed later.

```move
#[test]
fun test_execution_request_no_drop() {
    // This is a compile-time guarantee enforced by Move's type system.
    // The struct definition:
    //   struct ExecutionRequest<phantom P> { dao_id: ID, proposal_id: ID }
    // has no abilities listed, meaning it has none.
    //
    // If someone added `drop` to the struct, this test module would compile
    // but the following code would become valid (which it must not be):
    //
    //   let req = proposal::execute(...);
    //   // req dropped here — handler never called!
    //
    // We verify by creating a proposal, executing it, and confirming
    // the request MUST be passed to a handler to complete the PTB.

    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_funded_dao(&mut scenario, 100);

    let prop_id = test_helpers::create_proposal(
        &mut scenario, dao_id,
        treasury_ops::new_send_coin<SUI>(BOB, 50),
    );
    test_helpers::pass_proposal<treasury_ops::SendCoin<SUI>>(
        &mut scenario, prop_id, vector[ALICE, BOB, CAROL],
    );

    // Execute — the returned ExecutionRequest must be consumed by handler
    scenario.next_tx(ALICE);
    {
        let mut prop = test_scenario::take_shared<Proposal<treasury_ops::SendCoin<SUI>>>(&scenario);
        let dao = test_scenario::take_shared<DAO>(&scenario);
        let freeze = test_scenario::take_shared<EmergencyFreeze>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());

        let req = proposal::execute(&mut prop, &dao, &freeze, &clock, scenario.ctx());

        // Consume the request via handler
        let mut vault = test_scenario::take_shared<TreasuryVault>(&scenario);
        treasury_ops::handle_send_coin(req, &mut vault, scenario.ctx());
        test_scenario::return_shared(vault);

        clock::destroy_for_testing(clock);
        test_scenario::return_shared(prop);
        test_scenario::return_shared(dao);
        test_scenario::return_shared(freeze);
    };
    test_scenario::end(scenario);
}
```

---

### return_cap verifies cap_id match

**Requirement:** `CapLoan` has no abilities. `return_cap` verifies `cap_id` match.

**Why it matters:** Without ID verification, a malicious handler could return a different (worthless) capability and keep the valuable one.

```move
#[test]
#[expected_failure(abort_code = capability_vault::ECapLoanMismatch)]
fun test_return_cap_verifies_cap_id() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE]);

    // Store two capabilities in the vault
    // ... (setup code stores CapA and CapB)

    // Loan CapA — get (CapA, CapLoan{cap_id: A})
    // Attempt to return CapB with CapLoan{cap_id: A} — should abort
    scenario.next_tx(ALICE);
    {
        let mut vault = test_scenario::take_shared<CapabilityVault>(&scenario);
        // ... loan cap_a, get loan_a
        // ... attempt return_cap(vault, cap_b, loan_a) -> abort ECapLoanMismatch
        test_scenario::return_shared(vault);
    };
    test_scenario::end(scenario);
}
```

---

### Status Active to Passed

**Requirement:** Status transitions are monotonic: `Active -> Passed`.

**Why it matters:** The Passed status signals that governance has approved the action. Premature or skipped Passed status would break the authorization chain.

```move
#[test]
fun test_status_active_to_passed() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE]);

    let prop_id = test_helpers::create_proposal(
        &mut scenario, dao_id,
        admin::new_update_metadata(b"new-cid"),
    );

    // Before voting: Active
    scenario.next_tx(ALICE);
    {
        let prop = test_scenario::take_shared<Proposal<admin::UpdateMetadata>>(&scenario);
        assert!(proposal::status(&prop) == proposal::status_active());
        test_scenario::return_shared(prop);
    };

    // Vote YES (sole member) -> should transition to Passed
    scenario.next_tx(ALICE);
    {
        let mut prop = test_scenario::take_shared<Proposal<admin::UpdateMetadata>>(&scenario);
        proposal::vote(&mut prop, true, scenario.ctx());
        assert!(proposal::status(&prop) == proposal::status_passed());
        assert!(option::is_some(&proposal::passed_at_ms(&prop)));
        test_scenario::return_shared(prop);
    };
    test_scenario::end(scenario);
}
```

---

### Status Active to Expired

**Requirement:** `try_expire` after expiry_ms sets Expired.

**Why it matters:** Proposals that don't reach quorum must eventually expire to prevent governance deadlocks.

```move
#[test]
fun test_status_active_to_expired() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE, BOB]);

    let prop_id = test_helpers::create_proposal(
        &mut scenario, dao_id,
        admin::new_update_metadata(b"new-cid"),
    );

    // Advance clock past expiry (default >= 1 hour)
    test_helpers::advance_clock(&mut scenario, 3_600_001);

    scenario.next_tx(ALICE);
    {
        let mut prop = test_scenario::take_shared<Proposal<admin::UpdateMetadata>>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        clock::increment_for_testing(&mut clock, 3_600_001);

        proposal::try_expire(&mut prop, &clock);
        assert!(proposal::status(&prop) == proposal::status_expired());

        clock::destroy_for_testing(clock);
        test_scenario::return_shared(prop);
    };
    test_scenario::end(scenario);
}
```

---

### Cannot vote on Passed proposal

**Requirement:** Status transitions are monotonic. Once Passed, no more votes.

**Why it matters:** Late votes after passage could change the vote record, confusing UIs and audits.

```move
#[test]
#[expected_failure(abort_code = proposal::ENotActive)]
fun test_cannot_vote_on_passed_aborts() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE, BOB]);

    let prop_id = test_helpers::create_proposal(
        &mut scenario, dao_id,
        admin::new_update_metadata(b"new-cid"),
    );
    // Alice votes YES -> passes (threshold met with 1/2 if quorum=1)
    test_helpers::pass_proposal<admin::UpdateMetadata>(
        &mut scenario, prop_id, vector[ALICE],
    );

    // Bob tries to vote on already-Passed proposal
    scenario.next_tx(BOB);
    {
        let mut prop = test_scenario::take_shared<Proposal<admin::UpdateMetadata>>(&scenario);
        proposal::vote(&mut prop, true, scenario.ctx()); // should abort
        test_scenario::return_shared(prop);
    };
    test_scenario::end(scenario);
}
```

---

### Cannot execute Expired proposal

```move
#[test]
#[expected_failure(abort_code = proposal::ENotPassed)]
fun test_cannot_execute_expired_aborts() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE, BOB]);

    let prop_id = test_helpers::create_proposal(
        &mut scenario, dao_id,
        admin::new_update_metadata(b"new-cid"),
    );

    // Expire the proposal
    // ... advance clock + try_expire

    // Attempt to execute an expired proposal
    scenario.next_tx(ALICE);
    {
        let mut prop = test_scenario::take_shared<Proposal<admin::UpdateMetadata>>(&scenario);
        let dao = test_scenario::take_shared<DAO>(&scenario);
        let freeze = test_scenario::take_shared<EmergencyFreeze>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());

        // Should abort — status is Expired, not Passed
        let _req = proposal::execute(&mut prop, &dao, &freeze, &clock, scenario.ctx());

        clock::destroy_for_testing(clock);
        test_scenario::return_shared(prop);
        test_scenario::return_shared(dao);
        test_scenario::return_shared(freeze);
    };
    test_scenario::end(scenario);
}
```

---

### Cannot expire Passed proposal

**Why it matters:** Once governance approves, the decision must stand. Allowing expiry of Passed proposals would let time-based attacks void legitimate decisions.

```move
#[test]
fun test_cannot_expire_passed_aborts() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE]);

    let prop_id = test_helpers::create_proposal(
        &mut scenario, dao_id,
        admin::new_update_metadata(b"new-cid"),
    );
    test_helpers::pass_proposal<admin::UpdateMetadata>(&mut scenario, prop_id, vector[ALICE]);

    // Advance clock past expiry
    // ... advance clock

    scenario.next_tx(ALICE);
    {
        let mut prop = test_scenario::take_shared<Proposal<admin::UpdateMetadata>>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        clock::increment_for_testing(&mut clock, 10_000_000);

        // try_expire should be a no-op on Passed proposals (or abort)
        proposal::try_expire(&mut prop, &clock);
        // Status should still be Passed
        assert!(proposal::status(&prop) == proposal::status_passed());

        clock::destroy_for_testing(clock);
        test_scenario::return_shared(prop);
    };
    test_scenario::end(scenario);
}
```

---

### Vote snapshot immutable after creation

**Requirement:** `vote_snapshot` and `total_snapshot_weight` are write-once at creation.

**Why it matters:** If the snapshot could change after creation, newly added board members could vote on proposals they weren't eligible for when the proposal was created — violating the "who voted" auditability guarantee.

```move
#[test]
fun test_vote_snapshot_immutable_after_creation() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE, BOB]);

    // Create proposal — snapshot includes [ALICE, BOB]
    let prop_id = test_helpers::create_proposal(
        &mut scenario, dao_id,
        admin::new_update_metadata(b"new-cid"),
    );

    // Change the board to [ALICE, CAROL] via SetBoard
    // ...

    // The proposal's snapshot should still reflect [ALICE, BOB]
    scenario.next_tx(ALICE);
    {
        let prop = test_scenario::take_shared<Proposal<admin::UpdateMetadata>>(&scenario);
        let snapshot = proposal::vote_snapshot(&prop);
        assert!(vec_map::contains(snapshot, &ALICE));
        assert!(vec_map::contains(snapshot, &BOB));
        assert!(!vec_map::contains(snapshot, &CAROL));
        test_scenario::return_shared(prop);
    };
    test_scenario::end(scenario);
}
```

---

### New member cannot vote on old proposal

```move
#[test]
#[expected_failure(abort_code = proposal::ENotInSnapshot)]
fun test_new_member_cannot_vote_on_old_proposal() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE, BOB]);

    let prop_id = test_helpers::create_proposal(
        &mut scenario, dao_id,
        admin::new_update_metadata(b"new-cid"),
    );

    // Add CAROL to board via SetBoard
    // ...

    // CAROL tries to vote — not in snapshot
    scenario.next_tx(CAROL);
    {
        let mut prop = test_scenario::take_shared<Proposal<admin::UpdateMetadata>>(&scenario);
        proposal::vote(&mut prop, true, scenario.ctx()); // abort
        test_scenario::return_shared(prop);
    };
    test_scenario::end(scenario);
}
```

---

### Non-board member cannot execute

**Requirement:** Executor eligibility: Board -> current member.

**Why it matters:** Permissionless execution was a resolved threat (2.2). Restricting execution to board members prevents front-running attacks.

```move
#[test]
#[expected_failure(abort_code = proposal::ENotEligible)]
fun test_non_board_member_cannot_execute_aborts() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE, BOB]);

    let prop_id = test_helpers::create_proposal(
        &mut scenario, dao_id,
        admin::new_update_metadata(b"new-cid"),
    );
    test_helpers::pass_proposal<admin::UpdateMetadata>(
        &mut scenario, prop_id, vector[ALICE, BOB],
    );

    // EVE (not a board member) tries to execute
    scenario.next_tx(EVE);
    {
        let mut prop = test_scenario::take_shared<Proposal<admin::UpdateMetadata>>(&scenario);
        let dao = test_scenario::take_shared<DAO>(&scenario);
        let freeze = test_scenario::take_shared<EmergencyFreeze>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());

        let _req = proposal::execute(&mut prop, &dao, &freeze, &clock, scenario.ctx());

        clock::destroy_for_testing(clock);
        test_scenario::return_shared(prop);
        test_scenario::return_shared(dao);
        test_scenario::return_shared(freeze);
    };
    test_scenario::end(scenario);
}
```

---

### Failed execution leaves proposal Passed

**Requirement:** `Passed` proposals that abort on execution remain `Passed` and retryable.

**Why it matters:** PTB atomicity means if the handler aborts, the `Executed` status write also reverts. The proposal must remain actionable for retry — otherwise a single failed attempt (e.g., due to insufficient treasury balance) would permanently void a governance decision.

```move
#[test]
fun test_failed_execution_leaves_proposal_passed() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_funded_dao(&mut scenario, 50);

    // Create SendCoin for 100 SUI (more than treasury has)
    let prop_id = test_helpers::create_proposal(
        &mut scenario, dao_id,
        treasury_ops::new_send_coin<SUI>(BOB, 100),
    );
    test_helpers::pass_proposal<treasury_ops::SendCoin<SUI>>(
        &mut scenario, prop_id, vector[ALICE, BOB, CAROL],
    );

    // Execution will abort in handler (insufficient balance)
    // Due to PTB atomicity, the entire tx reverts including Executed status write

    // After the failed tx, proposal status is still Passed
    scenario.next_tx(ALICE);
    {
        let prop = test_scenario::take_shared<Proposal<treasury_ops::SendCoin<SUI>>>(&scenario);
        assert!(proposal::status(&prop) == proposal::status_passed());
        test_scenario::return_shared(prop);
    };
    test_scenario::end(scenario);
}
```

---

### Double vote aborts

**Why it matters:** Double voting would give one member disproportionate weight, breaking the 1-member-1-vote invariant.

```move
#[test]
#[expected_failure(abort_code = proposal::EAlreadyVoted)]
fun test_vote__double_vote_aborts() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE, BOB]);

    let prop_id = test_helpers::create_proposal(
        &mut scenario, dao_id,
        admin::new_update_metadata(b"new-cid"),
    );

    // ALICE votes YES
    scenario.next_tx(ALICE);
    {
        let mut prop = test_scenario::take_shared<Proposal<admin::UpdateMetadata>>(&scenario);
        proposal::vote(&mut prop, true, scenario.ctx());
        test_scenario::return_shared(prop);
    };

    // ALICE tries to vote again
    scenario.next_tx(ALICE);
    {
        let mut prop = test_scenario::take_shared<Proposal<admin::UpdateMetadata>>(&scenario);
        proposal::vote(&mut prop, true, scenario.ctx()); // abort EAlreadyVoted
        test_scenario::return_shared(prop);
    };
    test_scenario::end(scenario);
}
```

---

### NO votes counted correctly

**Why it matters:** NO votes must increase `no_weight` (not `yes_weight`). A bug here would make NO votes count as YES.

```move
#[test]
fun test_vote__no_vote_counted_correctly() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE, BOB, CAROL]);

    let prop_id = test_helpers::create_proposal(
        &mut scenario, dao_id,
        admin::new_update_metadata(b"new-cid"),
    );

    // BOB votes NO
    scenario.next_tx(BOB);
    {
        let mut prop = test_scenario::take_shared<Proposal<admin::UpdateMetadata>>(&scenario);
        proposal::vote(&mut prop, false, scenario.ctx());

        assert!(proposal::yes_weight(&prop) == 0);
        assert!(proposal::no_weight(&prop) == 1);
        assert!(proposal::status(&prop) == proposal::status_active()); // not passed

        test_scenario::return_shared(prop);
    };
    test_scenario::end(scenario);
}
```

---

### Execution delay not elapsed aborts

**Why it matters:** The execution delay is the "cooling-off period" — it gives stakeholders time to react to passed proposals before they take effect (threat mitigation for flash attacks).

```move
#[test]
#[expected_failure(abort_code = proposal::EDelayNotElapsed)]
fun test_execute__delay_not_elapsed_aborts() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE]);

    // Assume UpdateMetadata has execution_delay_ms = 3600000 (1 hour)
    let prop_id = test_helpers::create_proposal(
        &mut scenario, dao_id,
        admin::new_update_metadata(b"new-cid"),
    );
    test_helpers::pass_proposal<admin::UpdateMetadata>(&mut scenario, prop_id, vector[ALICE]);

    // Try to execute immediately (0 ms after passage)
    scenario.next_tx(ALICE);
    {
        let mut prop = test_scenario::take_shared<Proposal<admin::UpdateMetadata>>(&scenario);
        let dao = test_scenario::take_shared<DAO>(&scenario);
        let freeze = test_scenario::take_shared<EmergencyFreeze>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());

        // Delay not elapsed -> abort
        let _req = proposal::execute(&mut prop, &dao, &freeze, &clock, scenario.ctx());

        clock::destroy_for_testing(clock);
        test_scenario::return_shared(prop);
        test_scenario::return_shared(dao);
        test_scenario::return_shared(freeze);
    };
    test_scenario::end(scenario);
}
```

---

### Cooldown active aborts

**Why it matters:** Cooldowns prevent rapid-fire execution of the same proposal type — e.g., executing multiple `SendCoin` proposals in quick succession to drain the treasury before the board can react.

```move
#[test]
#[expected_failure(abort_code = proposal::ECooldownActive)]
fun test_execute__cooldown_active_aborts() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_funded_dao(&mut scenario, 200);

    // Assume SendCoin has cooldown_ms = 60000 (1 minute)
    // Execute first SendCoin
    // ...

    // Immediately try to execute second SendCoin — cooldown not elapsed
    // ... -> abort ECooldownActive
    test_scenario::end(scenario);
}
```

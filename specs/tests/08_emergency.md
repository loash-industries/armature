# Emergency Freeze Tests

## Summary

The `emergency.move` module implements a circuit breaker that lets the `FreezeAdminCap` holder freeze specific proposal types. These tests verify freeze/unfreeze semantics, auto-expiry, and the immutability of protected types.

## Test Matrix

| Test | Expected |
|------|----------|
| `test_freeze__blocks_execution_of_frozen_type` | Abort `EFrozen` when executing frozen type |
| `test_freeze__does_not_block_unfrozen_types` | Other types execute normally |
| `test_freeze__requires_freeze_admin_cap` | Only cap holder can freeze |
| `test_freeze__sets_expiry` | `freeze_expiry_ms` = `now + max_freeze_duration_ms` |
| `test_unfreeze__cap_holder_can_unfreeze` | Cap holder removes freeze |
| `test_unfreeze__governance_can_unfreeze` | `UnfreezeProposalType` removes freeze |
| `test_auto_expiry__expired_freeze_treated_as_inactive` | Execution succeeds after expiry |
| `test_protected__transfer_freeze_admin_cannot_be_frozen` | Abort when attempting to freeze |
| `test_protected__unfreeze_proposal_type_cannot_be_frozen` | Abort when attempting to freeze |
| `test_freeze__emits_type_frozen_event` | `TypeFrozen` event emitted |

## Tests

---

### Freeze blocks execution of frozen type

**Why it matters:** This is the core circuit breaker. If a vulnerability is discovered in a proposal handler, the freeze admin can halt execution before damage is done.

```move
#[test]
#[expected_failure(abort_code = proposal::EFrozen)]
fun test_freeze__blocks_execution_of_frozen_type() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_funded_dao(&mut scenario, 100);

    // Freeze SendCoin<SUI>
    scenario.next_tx(ALICE);
    {
        let mut freeze = test_scenario::take_shared<EmergencyFreeze>(&scenario);
        let cap = test_scenario::take_from_sender<FreezeAdminCap>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());

        emergency::freeze_type<treasury_ops::SendCoin<SUI>>(&mut freeze, &cap, &clock);

        clock::destroy_for_testing(clock);
        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_shared(freeze);
    };

    // Create and pass a SendCoin proposal
    let prop_id = test_helpers::create_proposal(
        &mut scenario, dao_id,
        treasury_ops::new_send_coin<SUI>(BOB, 50),
    );
    test_helpers::pass_proposal<treasury_ops::SendCoin<SUI>>(
        &mut scenario, prop_id, vector[ALICE, BOB, CAROL],
    );

    // Attempt to execute — should abort because type is frozen
    scenario.next_tx(ALICE);
    {
        let mut prop = test_scenario::take_shared<Proposal<treasury_ops::SendCoin<SUI>>>(&scenario);
        let dao = test_scenario::take_shared<DAO>(&scenario);
        let freeze = test_scenario::take_shared<EmergencyFreeze>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());

        let _req = proposal::execute(&mut prop, &dao, &freeze, &clock, scenario.ctx());
        // ^ aborts EFrozen

        clock::destroy_for_testing(clock);
        test_scenario::return_shared(prop);
        test_scenario::return_shared(dao);
        test_scenario::return_shared(freeze);
    };
    test_scenario::end(scenario);
}
```

---

### Freeze does not affect other types

**Why it matters:** Freezing `SendCoin` should not block `UpdateMetadata`. Over-broad freezing would create a denial-of-service.

```move
#[test]
fun test_freeze__does_not_block_unfrozen_types() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE]);

    // Freeze SendCoin
    // ...

    // UpdateMetadata (unfrozen) should still execute
    let prop_id = test_helpers::create_proposal(
        &mut scenario, dao_id,
        admin::new_update_metadata(b"new-cid"),
    );
    test_helpers::pass_proposal<admin::UpdateMetadata>(&mut scenario, prop_id, vector[ALICE]);
    // Execute succeeds — no abort
    test_scenario::end(scenario);
}
```

---

### Auto-expiry: expired freeze treated as inactive

**Why it matters:** Auto-expiry prevents permanent lockout. A compromised or unavailable freeze admin cannot permanently disable governance.

```move
#[test]
fun test_auto_expiry__expired_freeze_treated_as_inactive() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_funded_dao(&mut scenario, 100);

    // Freeze SendCoin<SUI> at time 0
    // max_freeze_duration_ms = e.g. 86_400_000 (24 hours)
    // ...

    // Advance clock past freeze expiry
    test_helpers::advance_clock(&mut scenario, 86_400_001);

    // Create, pass, and execute SendCoin — should succeed (freeze expired)
    let prop_id = test_helpers::create_proposal(
        &mut scenario, dao_id,
        treasury_ops::new_send_coin<SUI>(BOB, 50),
    );
    test_helpers::pass_proposal<treasury_ops::SendCoin<SUI>>(
        &mut scenario, prop_id, vector[ALICE, BOB, CAROL],
    );

    // Execute succeeds — freeze expired, treated as inactive
    scenario.next_tx(ALICE);
    {
        let mut prop = test_scenario::take_shared<Proposal<treasury_ops::SendCoin<SUI>>>(&scenario);
        let dao = test_scenario::take_shared<DAO>(&scenario);
        let freeze = test_scenario::take_shared<EmergencyFreeze>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        clock::increment_for_testing(&mut clock, 86_400_001);

        let req = proposal::execute(&mut prop, &dao, &freeze, &clock, scenario.ctx());
        // No abort — freeze expired

        // Consume req via handler
        // ...

        clock::destroy_for_testing(clock);
        test_scenario::return_shared(prop);
        test_scenario::return_shared(dao);
        test_scenario::return_shared(freeze);
    };
    test_scenario::end(scenario);
}
```

---

### Protected types cannot be frozen

**Why it matters:** `TransferFreezeAdmin` and `UnfreezeProposalType` must be immune to freezing. Otherwise a malicious freeze admin could freeze the unfreeze mechanism, creating an irrecoverable lockout.

```move
#[test]
#[expected_failure(abort_code = emergency::EProtectedType)]
fun test_protected__transfer_freeze_admin_cannot_be_frozen() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE]);

    scenario.next_tx(ALICE);
    {
        let mut freeze = test_scenario::take_shared<EmergencyFreeze>(&scenario);
        let cap = test_scenario::take_from_sender<FreezeAdminCap>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());

        // Attempt to freeze TransferFreezeAdmin — should abort
        emergency::freeze_type<admin::TransferFreezeAdmin>(&mut freeze, &cap, &clock);

        clock::destroy_for_testing(clock);
        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_shared(freeze);
    };
    test_scenario::end(scenario);
}

#[test]
#[expected_failure(abort_code = emergency::EProtectedType)]
fun test_protected__unfreeze_proposal_type_cannot_be_frozen() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE]);

    scenario.next_tx(ALICE);
    {
        let mut freeze = test_scenario::take_shared<EmergencyFreeze>(&scenario);
        let cap = test_scenario::take_from_sender<FreezeAdminCap>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());

        emergency::freeze_type<admin::UnfreezeProposalType>(&mut freeze, &cap, &clock);

        clock::destroy_for_testing(clock);
        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_shared(freeze);
    };
    test_scenario::end(scenario);
}
```

---

### Governance unfreeze via UnfreezeProposalType

**Why it matters:** Even if the freeze admin is unavailable, governance can unfreeze types through the standard proposal process.

```move
#[test]
fun test_unfreeze__governance_can_unfreeze() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE, BOB, CAROL]);

    // Freeze SendCoin
    // ...

    // Create UnfreezeProposalType proposal targeting SendCoin<SUI>
    let prop_id = test_helpers::create_proposal(
        &mut scenario, dao_id,
        admin::new_unfreeze_proposal_type<treasury_ops::SendCoin<SUI>>(),
    );
    test_helpers::pass_proposal<admin::UnfreezeProposalType>(
        &mut scenario, prop_id, vector[ALICE, BOB, CAROL],
    );
    // Execute + handle → type unfrozen

    // Verify SendCoin is now executable
    scenario.next_tx(ALICE);
    {
        let freeze = test_scenario::take_shared<EmergencyFreeze>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        assert!(!emergency::is_frozen<treasury_ops::SendCoin<SUI>>(&freeze, &clock));
        clock::destroy_for_testing(clock);
        test_scenario::return_shared(freeze);
    };
    test_scenario::end(scenario);
}
```

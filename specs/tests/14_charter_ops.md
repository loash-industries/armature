# Charter Operations Tests

## Summary

The `proposals/charter_ops.move` module handles `AmendCharter` and `RenewCharterStorage`. These tests verify amendment execution semantics and the distinction between content changes and storage renewals.

> Note: Core charter invariant tests (version monotonicity, amendment records, renew semantics) are in `07_charter.md`. This file covers handler-specific behavior.

## Test Matrix

| Type | Test | Expected |
|------|------|----------|
| AmendCharter | `test_amend__updates_blob_id_and_hash` | `current_blob_id` and `content_hash` updated |
| AmendCharter | `test_amend__increments_version` | `version` goes from N to N+1 |
| AmendCharter | `test_amend__appends_amendment_record` | `amendment_history` grows by 1 |
| AmendCharter | `test_amend__validates_charter_belongs_to_dao` | Abort if `charter.dao_id != dao.id` |
| AmendCharter | `test_amend__emits_charter_amended_event` | `CharterAmended` event with correct fields |
| AmendCharter | `test_amend__preserves_previous_history` | Old records unchanged after new amendment |
| RenewCharterStorage | `test_renew__updates_blob_id_only` | `current_blob_id` changed |
| RenewCharterStorage | `test_renew__does_not_change_hash` | `content_hash` unchanged |
| RenewCharterStorage | `test_renew__does_not_change_version` | `version` unchanged |
| RenewCharterStorage | `test_renew__does_not_add_history_record` | `amendment_history.length` unchanged |

## Tests

---

### AmendCharter: updates blob ID and hash

**Why it matters:** The blob ID is how clients find the charter on Walrus. The hash is how they verify integrity. Both must update for the amendment to be meaningful.

```move
#[test]
fun test_amend__updates_blob_id_and_hash() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE, BOB, CAROL]);
    test_helpers::enable_proposal_type<charter_ops::AmendCharter>(&mut scenario, dao_id);

    let new_blob = b"walrus://charter_v2_with_revenue_rules";
    let new_hash = b"sha256-of-new-content-bytes";

    let prop_id = test_helpers::create_proposal(
        &mut scenario, dao_id,
        charter_ops::new_amend_charter(new_blob, new_hash, b"Add revenue distribution section"),
    );
    test_helpers::pass_proposal<charter_ops::AmendCharter>(
        &mut scenario, prop_id, vector[ALICE, BOB, CAROL],
    );
    // Execute + handle ...

    scenario.next_tx(ALICE);
    {
        let charter = test_scenario::take_shared<Charter>(&scenario);
        assert!(charter::current_blob_id(&charter) == new_blob);
        assert!(charter::content_hash(&charter) == new_hash);
        test_scenario::return_shared(charter);
    };
    test_scenario::end(scenario);
}
```

---

### AmendCharter: validates charter belongs to DAO

**Why it matters:** Without this check, a proposal on DAO A could amend DAO B's charter if both shared objects are included in the PTB.

```move
#[test]
#[expected_failure(abort_code = charter_ops::ECharterMismatch)]
fun test_amend__validates_charter_belongs_to_dao() {
    let mut scenario = test_scenario::begin(ALICE);

    // Create two DAOs
    let dao_a = test_helpers::setup_dao(&mut scenario, vector[ALICE]);
    let dao_b = test_helpers::setup_dao(&mut scenario, vector[BOB]);

    // Enable AmendCharter on dao_a
    test_helpers::enable_proposal_type<charter_ops::AmendCharter>(&mut scenario, dao_a);

    // Create AmendCharter proposal on dao_a
    // But in the handler, pass dao_b's charter object
    // → abort because charter.dao_id != dao_a.id

    test_scenario::end(scenario);
}
```

---

### AmendCharter: preserves previous history entries

**Why it matters:** Each amendment must append to the history, not overwrite it. The full audit trail must be preserved.

```move
#[test]
fun test_amend__preserves_previous_history() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE, BOB, CAROL]);
    test_helpers::enable_proposal_type<charter_ops::AmendCharter>(&mut scenario, dao_id);

    // Amendment 1: v1 → v2
    // ... (create, pass, execute)

    // Amendment 2: v2 → v3
    // ... (create, pass, execute)

    scenario.next_tx(ALICE);
    {
        let charter = test_scenario::take_shared<Charter>(&scenario);
        let history = charter::amendment_history(&charter);

        // Both records exist
        assert!(vector::length(history) == 2);

        // First record unchanged
        let r0 = vector::borrow(history, 0);
        assert!(charter::record_version(r0) == 2);

        // Second record appended
        let r1 = vector::borrow(history, 1);
        assert!(charter::record_version(r1) == 3);
        // r1.previous_blob_id == r0.new_blob_id (chain of custody)
        assert!(charter::record_previous_blob_id(r1) == charter::record_new_blob_id(r0));

        test_scenario::return_shared(charter);
    };
    test_scenario::end(scenario);
}
```

---

### RenewCharterStorage: updates blob ID without touching version or hash

**Why it matters:** Re-uploading expired Walrus content produces a new blob ID for the same content. Version and hash must not change — otherwise UIs would think the charter was amended when it wasn't.

```move
#[test]
fun test_renew__updates_blob_id_only() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE, BOB, CAROL]);
    test_helpers::enable_proposal_type<charter_ops::RenewCharterStorage>(&mut scenario, dao_id);

    // Record initial state
    let (initial_version, initial_hash, initial_blob);
    scenario.next_tx(ALICE);
    {
        let charter = test_scenario::take_shared<Charter>(&scenario);
        initial_version = charter::version(&charter);
        initial_hash = charter::content_hash(&charter);
        initial_blob = charter::current_blob_id(&charter);
        test_scenario::return_shared(charter);
    };

    // Renew storage with new blob ID
    let renewed_blob = b"walrus://charter_v1_renewed_2026";
    let prop_id = test_helpers::create_proposal(
        &mut scenario, dao_id,
        charter_ops::new_renew_charter_storage(renewed_blob),
    );
    test_helpers::pass_proposal<charter_ops::RenewCharterStorage>(
        &mut scenario, prop_id, vector[ALICE, BOB, CAROL],
    );
    // Execute + handle ...

    scenario.next_tx(ALICE);
    {
        let charter = test_scenario::take_shared<Charter>(&scenario);

        // Blob changed
        assert!(charter::current_blob_id(&charter) != initial_blob);
        assert!(charter::current_blob_id(&charter) == renewed_blob);

        // Version unchanged
        assert!(charter::version(&charter) == initial_version);

        // Hash unchanged
        assert!(charter::content_hash(&charter) == initial_hash);

        // No history record added
        assert!(vector::length(&charter::amendment_history(&charter)) == 0);

        test_scenario::return_shared(charter);
    };
    test_scenario::end(scenario);
}
```

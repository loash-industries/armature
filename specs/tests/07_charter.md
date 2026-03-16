# Charter Tests

## Summary

The `charter.move` module manages the on-chain reference to the DAO's constitutional document on Walrus. These tests verify version monotonicity, amendment history completeness, and the distinction between content amendments and storage renewals.

## Test Matrix

| Test | Expected |
|------|----------|
| `test_version_starts_at_one` | `charter.version == 1` after creation |
| `test_version_increments_on_amendment` | `version` goes from 1 to 2 after `AmendCharter` |
| `test_version_monotonic_across_multiple_amendments` | 1 -> 2 -> 3 -> 4 |
| `test_version_cannot_decrease` | No function allows decrementing version |
| `test_amendment_records_previous_blob_id` | `AmendmentRecord.previous_blob_id` matches prior charter |
| `test_amendment_records_new_blob_id` | `AmendmentRecord.new_blob_id` matches payload |
| `test_amendment_records_proposal_id` | `AmendmentRecord.proposal_id` matches the authorizing proposal |
| `test_amendment_history_grows` | `amendment_history` length increases by 1 per amendment |
| `test_renew_changes_blob_id_only` | `current_blob_id` changes, `content_hash` and `version` unchanged |
| `test_renew_does_not_add_amendment_record` | `amendment_history` length unchanged |

## Tests

---

### Version starts at 1

**Requirement:** `Charter.version` is monotonically increasing, starting at 1.

**Why it matters:** Version 0 would be ambiguous — is it "never set" or "original"? Starting at 1 gives the initial charter a clear identity.

```move
#[test]
fun test_version_starts_at_one() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE]);

    scenario.next_tx(ALICE);
    {
        let charter = test_scenario::take_shared<Charter>(&scenario);

        assert!(charter::version(&charter) == 1);
        assert!(charter::current_blob_id(&charter) == b"walrus://test_charter_v1");
        assert!(vector::length(&charter::amendment_history(&charter)) == 0);

        test_scenario::return_shared(charter);
    };
    test_scenario::end(scenario);
}
```

---

### Version increments on amendment

**Requirement:** Each `AmendCharter` execution increments `version` by 1.

**Why it matters:** If version didn't increment, you couldn't distinguish between charter versions — UIs and voters would not know whether they're reading the current or a stale charter.

```move
#[test]
fun test_version_increments_on_amendment() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE, BOB, CAROL]);

    // Enable AmendCharter (opt-in type)
    test_helpers::enable_proposal_type<charter_ops::AmendCharter>(&mut scenario, dao_id);

    // Propose and execute an amendment
    let prop_id = test_helpers::create_proposal(
        &mut scenario, dao_id,
        charter_ops::new_amend_charter(
            b"walrus://charter_v2",
            b"new-sha256-hash",
            b"Updated revenue distribution rules",
        ),
    );
    test_helpers::pass_proposal<charter_ops::AmendCharter>(
        &mut scenario, prop_id, vector[ALICE, BOB, CAROL],
    );
    // Execute + handle amendment ...

    scenario.next_tx(ALICE);
    {
        let charter = test_scenario::take_shared<Charter>(&scenario);

        assert!(charter::version(&charter) == 2);
        assert!(charter::current_blob_id(&charter) == b"walrus://charter_v2");

        test_scenario::return_shared(charter);
    };
    test_scenario::end(scenario);
}
```

---

### Version monotonic across multiple amendments

```move
#[test]
fun test_version_monotonic_across_multiple_amendments() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE, BOB, CAROL]);
    test_helpers::enable_proposal_type<charter_ops::AmendCharter>(&mut scenario, dao_id);

    // Three successive amendments
    // Amendment 1: version 1 -> 2
    // ... (create, pass, execute AmendCharter)
    // Amendment 2: version 2 -> 3
    // ... (create, pass, execute AmendCharter)
    // Amendment 3: version 3 -> 4
    // ... (create, pass, execute AmendCharter)

    scenario.next_tx(ALICE);
    {
        let charter = test_scenario::take_shared<Charter>(&scenario);
        assert!(charter::version(&charter) == 4);
        assert!(vector::length(&charter::amendment_history(&charter)) == 3);
        test_scenario::return_shared(charter);
    };
    test_scenario::end(scenario);
}
```

---

### Amendment records previous and new blob IDs

**Requirement:** `AmendCharter` records both previous and new blob IDs in `amendment_history`.

**Why it matters:** The amendment history is the on-chain audit trail. Without `previous_blob_id`, you couldn't reconstruct the charter's evolution without trusting an indexer.

```move
#[test]
fun test_amendment_records_previous_blob_id() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE, BOB, CAROL]);
    test_helpers::enable_proposal_type<charter_ops::AmendCharter>(&mut scenario, dao_id);

    // Execute amendment from v1 blob to v2 blob
    // ...

    scenario.next_tx(ALICE);
    {
        let charter = test_scenario::take_shared<Charter>(&scenario);
        let history = charter::amendment_history(&charter);
        let record = vector::borrow(history, 0);

        // Previous blob was the original
        assert!(charter::record_previous_blob_id(record) == b"walrus://test_charter_v1");
        // New blob is the amendment
        assert!(charter::record_new_blob_id(record) == b"walrus://charter_v2");
        // Version in record matches
        assert!(charter::record_version(record) == 2);

        test_scenario::return_shared(charter);
    };
    test_scenario::end(scenario);
}
```

---

### Amendment records proposal ID

**Why it matters:** Links each charter change to the specific governance decision that authorized it — critical for dispute resolution and audit.

```move
#[test]
fun test_amendment_records_proposal_id() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE, BOB, CAROL]);
    test_helpers::enable_proposal_type<charter_ops::AmendCharter>(&mut scenario, dao_id);

    let prop_id = test_helpers::create_proposal(
        &mut scenario, dao_id,
        charter_ops::new_amend_charter(b"walrus://v2", b"hash2", b"summary"),
    );
    test_helpers::pass_proposal<charter_ops::AmendCharter>(
        &mut scenario, prop_id, vector[ALICE, BOB, CAROL],
    );
    // Execute + handle ...

    scenario.next_tx(ALICE);
    {
        let charter = test_scenario::take_shared<Charter>(&scenario);
        let history = charter::amendment_history(&charter);
        let record = vector::borrow(history, 0);
        assert!(charter::record_proposal_id(record) == prop_id);
        test_scenario::return_shared(charter);
    };
    test_scenario::end(scenario);
}
```

---

### RenewCharterStorage changes blob ID only

**Requirement:** `RenewCharterStorage` changes `current_blob_id` without incrementing version.

**Why it matters:** Storage renewal is a maintenance operation, not a content change. Incrementing the version would falsely signal to voters and UIs that the charter content changed.

```move
#[test]
fun test_renew_changes_blob_id_only() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE, BOB, CAROL]);
    test_helpers::enable_proposal_type<charter_ops::RenewCharterStorage>(&mut scenario, dao_id);

    // Record initial state
    let initial_version;
    let initial_hash;
    scenario.next_tx(ALICE);
    {
        let charter = test_scenario::take_shared<Charter>(&scenario);
        initial_version = charter::version(&charter);
        initial_hash = charter::content_hash(&charter);
        test_scenario::return_shared(charter);
    };

    // Execute RenewCharterStorage with new blob ID
    let prop_id = test_helpers::create_proposal(
        &mut scenario, dao_id,
        charter_ops::new_renew_charter_storage(b"walrus://charter_v1_renewed"),
    );
    test_helpers::pass_proposal<charter_ops::RenewCharterStorage>(
        &mut scenario, prop_id, vector[ALICE, BOB, CAROL],
    );
    // Execute + handle ...

    scenario.next_tx(ALICE);
    {
        let charter = test_scenario::take_shared<Charter>(&scenario);

        // Blob ID changed
        assert!(charter::current_blob_id(&charter) == b"walrus://charter_v1_renewed");
        // Version unchanged
        assert!(charter::version(&charter) == initial_version);
        // Content hash unchanged
        assert!(charter::content_hash(&charter) == initial_hash);

        test_scenario::return_shared(charter);
    };
    test_scenario::end(scenario);
}
```

---

### Renew does not add amendment record

**Why it matters:** Amendment history tracks content changes. A storage renewal entry would pollute the history with false amendments.

```move
#[test]
fun test_renew_does_not_add_amendment_record() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE, BOB, CAROL]);
    test_helpers::enable_proposal_type<charter_ops::RenewCharterStorage>(&mut scenario, dao_id);

    // Execute RenewCharterStorage
    // ...

    scenario.next_tx(ALICE);
    {
        let charter = test_scenario::take_shared<Charter>(&scenario);
        // amendment_history length should still be 0
        assert!(vector::length(&charter::amendment_history(&charter)) == 0);
        test_scenario::return_shared(charter);
    };
    test_scenario::end(scenario);
}
```

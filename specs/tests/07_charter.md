# Charter Tests

## Summary

`charter.move` defines the `Charter` object: `{ id, dao_id, name, metadata_uri }`. Every DAO constructor creates and shares one from its `name` and `metadata_uri` arguments. The name never changes. The only mutator is `charter::update_metadata<P>(charter, new_metadata_uri, &ExecutionRequest<P>)`, which requires the `METADATA` bit and is reached through the `UpdateMetadata` proposal type (default display key "CharterUpdate", handler `admin_ops::execute_update_metadata`).

These tests verify charter creation, the metadata update and its checks, and the charter's removal with its DAO. The Walrus-backed charter with versions and amendment history described in `specs/05_charter.md` Part B is not implemented; its test list is kept at the end under **Planned (not implemented)**.

## Test Matrix

| Test | Expected | Where |
|------|----------|-------|
| `test_create_dao` | The charter is shared and carries the name passed to `dao::create` | `dao_tests` |
| `test_create_returning_vault_other_companions_are_shared` | Same for the package-internal constructor | `dao_tests` |
| `charter_update_lifecycle` | `metadata_uri` starts as the creation argument; two `UpdateMetadata` proposals (submit, vote, `ticket_from_vote`, `admin_ops::execute_update_metadata`) each replace it | `armature_proposals::charter_tests` |
| `charter_update_wrong_dao_aborts` | Executing DAO A's proposal against DAO B's charter: `admin_ops::ECharterDaoMismatch` | `armature_proposals::charter_tests` |
| `update_metadata_needs_metadata` | `charter::update_metadata` with every bit except `METADATA`: `proposal::EPermissionDenied` | `gate_tests` |
| `composite_update_metadata_step_e2e` | `UpdateMetadata` as a composite step updates `metadata_uri` | `armature_proposals::composite_tests` |
| `test_default_proposal_types` | `UpdateMetadata` is a default slot with display key "CharterUpdate" | `dao_tests` |
| `test_update_metadata_other_dao_request_aborts` | `charter::update_metadata` with a request for another DAO: `charter::EDaoMismatch` | planned |
| `test_update_metadata_emits_event` | `admin_ops::MetadataUpdated { dao_id, new_ipfs_cid }` | planned |
| `test_update_metadata_keeps_name` | After an update, `name` is unchanged | planned (no mutator writes `name`; structural) |
| `test_privileged_request_updates_subdao_metadata` | A controller's privileged request for the SubDAO passes the `METADATA` check | planned |
| `spawn_dao_and_destroy_origin_e2e` | `dao::destroy` deletes the charter with the other companions | `armature_proposals::migration_tests` |

## Tests

---

### Every DAO gets a charter with its name

**Requirement:** `dao::create`, `create_subdao(_configured)`, the tribe constructors and `tribe::create_wired_subdao` create a `Charter` with `dao_id` set to the new DAO and `name` / `metadata_uri` from their arguments, and share it; the DAO stores its ID (`dao.charter_id()`). An empty name aborts `dao::EInvalidName` before anything is created. `CreateSubDAO` and `SpawnDAO` payloads carry the new DAO's name and metadata URI. Anyone can read the charter (`charter::dao_id`, `name`, `metadata_uri`).

**Why it matters:** The charter is the DAO's public identity: the name and a pointer to the document that describes its purpose and rules.

```move
// From armature_proposals::charter_tests::charter_update_lifecycle
let dao = scenario.take_shared_by_id<DAO>(dao_id);
let charter = scenario.take_shared_by_id<Charter>(dao.charter_id());
assert!(charter.dao_id() == dao_id);
assert!(charter.metadata_uri() == &string::utf8(b"https://old-logo.png"));
```

(`charter_update_lifecycle` checks the URI and `dao_tests::test_create_dao` the name. No test asserts the `dao_id` back-reference directly; the update tests depend on it, since the handler compares it with the ticket's DAO.)

---

### UpdateMetadata replaces the metadata URI

**Requirement:** `UpdateMetadata { new_ipfs_cid: String }` is a framework type seeded on every DAO under the display key "CharterUpdate", with the fixed bit `METADATA` and a default config of 50% quorum, 50% threshold, 7-day expiry, no delay, no cooldown, composable. `admin_ops::execute_update_metadata(&mut charter, ticket)` checks the charter belongs to the ticket's DAO (`admin_ops::ECharterDaoMismatch`), calls `charter::update_metadata` with the payload's CID, emits `admin_ops::MetadataUpdated { dao_id, new_ipfs_cid }` and discharges the ticket. The URI is stored as given; it is not parsed or validated. The type can be submitted any number of times.

**Why it matters:** The metadata document can change as the DAO does, but only through a governance decision.

```move
// From armature_proposals::charter_tests::charter_update_lifecycle
scenario.next_tx(CREATOR);
{
    let dao = scenario.take_shared_by_id<DAO>(dao_id);
    board_voting::submit_proposal(
        &dao,
        option::some(string::utf8(b"Update logo to v1")),
        update_metadata::new(string::utf8(b"ipfs://QmNewHashV1")),
        &clock,
        scenario.ctx(),
    );
    test_scenario::return_shared(dao);
};
// ... CREATOR votes YES (1 of 2 meets the 50% quorum)
scenario.next_tx(CREATOR);
{
    let mut dao = scenario.take_shared_by_id<DAO>(dao_id);
    let proposal = scenario.take_shared<Proposal<UpdateMetadata>>();
    let mut charter = scenario.take_shared_by_id<Charter>(charter_id);
    let freeze = scenario.take_shared_by_id<EmergencyFreeze>(dao.emergency_freeze_id());
    let ticket = board_voting::ticket_from_vote(&mut dao, proposal, &freeze, &clock, scenario.ctx());
    admin_ops::execute_update_metadata(&mut charter, ticket);
    assert!(charter.metadata_uri() == &string::utf8(b"ipfs://QmNewHashV1"));
    test_scenario::return_shared(freeze);
    test_scenario::return_shared(charter);
    test_scenario::return_shared(dao);
};
```

Because the default slot must hold `METADATA` for `charter::update_metadata` to accept the request, this test also shows the seeded bit is right.

---

### The update is checked against the charter's DAO and the METADATA bit

**Requirement:** `charter::update_metadata<P>` aborts `charter::EDaoMismatch` unless the request is for the charter's DAO, then `proposal::EPermissionDenied` unless the request carries `METADATA` or is privileged (a controller override of that DAO). The handler's own check (`admin_ops::ECharterDaoMismatch`) runs first, so `charter::EDaoMismatch` is reached only by calling `charter::update_metadata` directly. Only `UpdateMetadata`'s handler module can reach its request (see `04_proposals.md`), so the new URI always comes from the approved payload.

**Why it matters:** A request of another type, or of another DAO, must not rewrite this DAO's public identity.

```move
// From armature_proposals::charter_tests::charter_update_wrong_dao_aborts
#[test, expected_failure(abort_code = armature::admin_ops::ECharterDaoMismatch)]
fun charter_update_wrong_dao_aborts() {
    // ... DAO A passes UpdateMetadata; DAO B's charter is taken by ID
    let ticket = board_voting::ticket_from_vote(&mut dao, proposal, &freeze, &clock, scenario.ctx());
    admin_ops::execute_update_metadata(&mut wrong_charter, ticket);
    // ...
}

// From gate_tests: every bit except METADATA
#[test, expected_failure(abort_code = proposal::EPermissionDenied)]
fun update_metadata_needs_metadata() {
    run!(|dao, _, _, charter, _, _| {
        let r = all_but(dao, permissions::metadata());
        charter.update_metadata(string::utf8(b"ipfs://x"), &r);
        abort 0
    });
}

#[test, expected_failure(abort_code = charter::EDaoMismatch)]
fun test_update_metadata_other_dao_request_aborts() {   // planned
    // ... DAO created; its charter taken by ID
    let req = proposal::new_execution_request_for_testing<Probe>(
        object::id_from_address(@0xD1FF),   // not the charter's DAO
        object::id_from_address(@0x1),
    );
    charter.update_metadata(string::utf8(b"ipfs://x"), &req);
    abort 0
}
```

---

### The name is fixed

**Requirement:** No function writes `Charter.name` after creation.

**Why it matters:** The name identifies the DAO in events, UIs and its successor's lineage; renaming would need a new DAO (`SpawnDAO`).

Structural: `charter.move` has no mutator for `name`. The planned `test_update_metadata_keeps_name` asserts `charter.name()` is unchanged after `charter_update_lifecycle`'s updates.

---

### The charter is destroyed with its DAO

**Requirement:** `dao::destroy` checks the charter passed is the DAO's own (`dao::ECharterIdMismatch`) and deletes it (`charter::destroy`, `public(package)`) along with the other companions.

**Why it matters:** A charter must not outlive its DAO pointing at a deleted `dao_id`.

Covered by `armature_proposals::migration_tests::spawn_dao_and_destroy_origin_e2e`; the ID check is in `02_dao_lifecycle.md` (planned `test_destroy_wrong_companion_aborts`).

---

## Planned (not implemented)

`specs/05_charter.md` Part B designs a Walrus-backed charter: a blob ID and content hash, a version starting at 1, an amendment history, and two proposal types, `AmendCharter` and `RenewCharterStorage`, with a `CharterAmended` event. None of these exist: no fields, accessors, types, handlers or events. The tests below would be written if that design is built; they have no code to run against and no snippets are given.

| Planned test | Would check |
|------|----------|
| `test_version_starts_at_one` | A new charter is at version 1 with an empty history |
| `test_version_increments_on_amendment` | Each executed `AmendCharter` adds 1 |
| `test_version_monotonic_across_multiple_amendments` | Three amendments give version 4 and three history records |
| `test_amendment_records_previous_blob_id` | The record keeps the previous and new blob IDs and the new version |
| `test_amendment_records_proposal_id` | The record keeps the authorizing proposal ID (the ticket's `ticket_proposal_id`, which for a single-PTB execution is the fresh ID from its events) |
| `test_amendment_history_grows` | One record per amendment |
| `test_renew_changes_blob_id_only` | `RenewCharterStorage` changes the blob ID, not the hash or version |
| `test_renew_does_not_add_amendment_record` | Renewal leaves the history unchanged |
| `test_amend_other_dao_charter_aborts` | Like `update_metadata`, a charter/DAO mismatch aborts |

Each planned write would need a new gated mutator in `armature::charter` that checks the charter's DAO and a permission bit, as `update_metadata` checks `METADATA`; `scripts/check_request_gates.py` would then require a denial test for it in `gate_tests`.

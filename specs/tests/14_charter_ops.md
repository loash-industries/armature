# Charter Operations Tests

## Summary

The only charter operation is **`UpdateMetadata`**. The on-chain `Charter` is the DAO's name plus a metadata URI (an IPFS CID of the document describing the DAO); nothing else about it is stored or versioned:

```move
public struct Charter has key, store { id: UID, dao_id: ID, name: String, metadata_uri: String }

public struct UpdateMetadata has copy, drop, store { new_ipfs_cid: String }
```

- `UpdateMetadata` is a framework type (`armature::update_metadata`), seeded on every DAO under the display key **"CharterUpdate"**, with the fixed bit `METADATA` and no approval floor. Its default config is quorum 5000, threshold 5000, delay 0, and it is composable.
- Handler: `admin_ops::execute_update_metadata(charter: &mut Charter, ticket: ExecutionTicket<UpdateMetadata>)`. It aborts with `admin_ops::ECharterDaoMismatch` unless the charter belongs to the ticket's DAO, then calls `charter::update_metadata<P>(charter, new_metadata_uri, &ExecutionRequest<P>)`, which checks the DAO again (`charter::EDaoMismatch`) and the `METADATA` bit (`proposal::EPermissionDenied`) and sets `metadata_uri`. Emits `admin_ops::MetadataUpdated { dao_id, new_ipfs_cid }`.
- `name` is set when the DAO is created (`dao::create`, the SubDAO and tribe constructors, a `CreateSubDAO` or `SpawnDAO` payload) and has no mutator. An empty name aborts creation with `dao::EInvalidName`.
- Readers: `charter::dao_id`, `name`, `metadata_uri`. Indexers follow changes through `MetadataUpdated`.

`AmendCharter`, `RenewCharterStorage`, `CharterAmended` and the Walrus-backed charter (`current_blob_id`, `content_hash`, `version`, `amendment_history`) were never implemented; their tests are kept only in the "Planned (not implemented)" section below. `specs/05_charter.md` describes both the implemented charter and the planned design.

Real suites: `packages/armature_proposals/tests/charter_tests.move` (2), plus tests cited from `gate_tests.move`, `composite_tests.move`, `dao_tests.move` and `tribe_tests.move`. Charter object creation and destruction are in `07_charter.md`.

## Test Matrix

| Test | Expected |
|------|----------|
| `charter_tests::charter_update_lifecycle` | `metadata_uri` goes "https://old-logo.png" → "ipfs://QmNewHashV1" → "ipfs://QmNewHashV2" through two CharterUpdate proposals |
| `charter_tests::charter_update_wrong_dao_aborts` | DAO B's charter passed with DAO A's ticket: Abort `admin_ops::ECharterDaoMismatch` |
| `gate_tests::update_metadata_needs_metadata` | `charter.update_metadata` with a request holding every bit except METADATA: Abort `proposal::EPermissionDenied` |
| `composite_tests::composite_update_metadata_step_e2e` | UpdateMetadata runs as a composite step |
| `dao_tests::test_default_proposal_types` | `type_display_key<UpdateMetadata>()` is "CharterUpdate" |
| `tribe_tests::create_tribe_configured_default_type_display_key_mismatch_aborts` | A creation-time override of UpdateMetadata under another display key: Abort `dao::EDisplayKeyMismatch` |
| `test_update_metadata__emits_metadata_updated` (planned) | `MetadataUpdated { dao_id, new_ipfs_cid }` emitted with the payload's CID |
| `test_update_metadata__name_unchanged` (planned) | `charter.name()` is unchanged after an update |
| `test_update_metadata__privileged_request_updates_subdao_charter` (planned) | `charter::update_metadata` with a privileged request for the SubDAO (`proposal::new_privileged_request_for_testing`) updates the SubDAO's charter: a privileged request passes the METADATA check |

## Tests

---

### UpdateMetadata: changes the metadata URI

**Why it matters:** The metadata URI is how clients find the DAO's description, logo and charter text. It must change only through an approved proposal, and repeat updates must keep working.

```move
// charter_tests::charter_update_lifecycle (first update)
let payload = update_metadata::new(string::utf8(b"ipfs://QmNewHashV1"));
board_voting::submit_proposal(&dao, option::some(string::utf8(b"Update logo to v1")), payload, &clock, scenario.ctx());
// ... CREATOR votes YES (1 of 2 meets quorum 5000) ...
let ticket = board_voting::ticket_from_vote(&mut dao, proposal, &freeze, &clock, scenario.ctx());
admin_ops::execute_update_metadata(&mut charter, ticket);
assert!(charter.metadata_uri() == &string::utf8(b"ipfs://QmNewHashV1"));
```

The test then submits, passes and executes a second update to "ipfs://QmNewHashV2".

---

### UpdateMetadata: validates the charter belongs to the DAO

**Why it matters:** A PTB can pass any shared `Charter`. Without this check, a proposal passed on DAO A could rewrite DAO B's charter.

```move
#[test, expected_failure(abort_code = armature::admin_ops::ECharterDaoMismatch)]
fun charter_update_wrong_dao_aborts() {
    // Two DAOs; update_metadata::new(string::utf8(b"ipfs://malicious")) passes on DAO A.
    ...
    let mut wrong_charter = scenario.take_shared_by_id<Charter>(dao_b_charter_id);
    let ticket = board_voting::ticket_from_vote(&mut dao, proposal, &freeze, &clock, scenario.ctx());
    admin_ops::execute_update_metadata(&mut wrong_charter, ticket); // aborts
    ...
}
```

`charter::update_metadata` repeats the check (`charter::EDaoMismatch`) for callers that reach it with their own handler.

---

### UpdateMetadata: requires the METADATA bit

**Why it matters:** `charter::update_metadata` is a public mutator that takes any `ExecutionRequest<P>`. Only requests of a type holding `METADATA` (UpdateMetadata's fixed bit) or a controller's privileged request may use it; a ticket for another type cannot rewrite the charter.

`gate_tests::update_metadata_needs_metadata` builds a request with `proposal::new_permitted_request_for_testing<Probe>(dao_id, id, permissions::all() ^ permissions::metadata())` and expects `proposal::EPermissionDenied`.

---

### UpdateMetadata as a composite step

**Why it matters:** UpdateMetadata is composable by default, so a DAO can change its metadata in the same vote as, for example, a board change.

`composite_tests::composite_update_metadata_step_e2e` runs a composite with one UpdateMetadata step through `composite::advance_step<UpdateMetadata>` and `admin_ops::execute_update_metadata`.

---

### Controller override of a SubDAO's metadata (planned)

**Requirement:** A privileged request for a SubDAO (from `controller::privileged_submit`) passes the METADATA check in `charter::update_metadata`, so a controller type that loans the `SubDAOControl` can rewrite the SubDAO's metadata URI.

**Why it matters:** This is the mechanism a parent would use to revert a SubDAO's charter change (demo Flow B, step 7). No first-party controller type does it today; see `16_integration_flows.md`.

```move
#[test]
fun test_update_metadata__privileged_request_updates_subdao_charter() { // (planned)
    // SubDAO created with dao::create_subdao + dao::share_subdao; its Charter is shared.
    let req = proposal::new_privileged_request_for_testing<UpdateMetadata>(subdao_id, @0x1.to_id());
    charter.update_metadata(string::utf8(b"ipfs://QmReverted"), &req);
    proposal::consume_execution_request_for_testing(req);
    assert!(charter.metadata_uri() == &string::utf8(b"ipfs://QmReverted"));
}
```

---

## Planned (not implemented): charter amendments

None of the following exists in the code: there is no `charter_ops` module, no `AmendCharter` or `RenewCharterStorage` payload, no `CharterAmended` event, no blob ID, hash, version or history on `Charter`, and no error constants for them. Implementing them needs new `Charter` fields and new gated mutators in `charter`. The tests below record the intended behaviour; expected aborts are described, not named, because no codes exist.

| Type | Test | Expected (intended) |
|------|------|---------------------|
| AmendCharter | `test_amend__updates_blob_id_and_hash` | `current_blob_id` and `content_hash` set from the payload |
| AmendCharter | `test_amend__increments_version` | `version` goes from N to N + 1 |
| AmendCharter | `test_amend__appends_amendment_record` | `amendment_history` grows by one record |
| AmendCharter | `test_amend__validates_charter_belongs_to_dao` | Charter of another DAO: abort |
| AmendCharter | `test_amend__emits_charter_amended_event` | `CharterAmended` with the old and new blob IDs and version |
| AmendCharter | `test_amend__preserves_previous_history` | Earlier records unchanged; each record's previous blob ID equals the prior record's new blob ID |
| RenewCharterStorage | `test_renew__updates_blob_id_only` | `current_blob_id` changes (same content re-uploaded to Walrus) |
| RenewCharterStorage | `test_renew__does_not_change_hash` | `content_hash` unchanged |
| RenewCharterStorage | `test_renew__does_not_change_version` | `version` unchanged |
| RenewCharterStorage | `test_renew__does_not_add_history_record` | `amendment_history` length unchanged |

**Why they would matter:** A blob ID locates the charter on Walrus and the hash lets clients verify it; amendments must be versioned and appended to history, while a storage renewal (same content, new blob) must not look like an amendment.

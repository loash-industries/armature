# 05 — Charter

## Overview

Every DAO has a Charter: its name and a pointer to a human-readable document that defines the organization's purpose, operating agreements and rules. Part A describes what is implemented: an on-chain `Charter` object holding the name and a metadata URI (an IPFS CID), changed by the `UpdateMetadata` proposal type. Part B describes the planned Walrus-backed charter with versioned, hash-verified amendments, which is **not implemented**.

---

# Part A — Implemented

## 1. Core Object: `Charter`

A separate shared object, following the same concurrent-access pattern as `TreasuryVault` and `CapabilityVault`. The `DAO` stores only a `charter_id: ID` reference to it.

```rust
struct Charter has key, store {
    id:           UID,
    dao_id:       ID,       // back-reference to the owning DAO
    name:         String,   // the DAO's name, set at creation
    metadata_uri: String,   // IPFS CID / URI of the DAO's metadata document
}
```

Accessors: `charter::dao_id`, `name`, `metadata_uri`.

### Design Decisions

- **Separate shared object.** The `Charter` is independently shared so that reads (anyone can read it) don't contend with writes or with other DAO operations.
- **Pointer, not content.** The chain stores only a URI. The document it points to (description, logo, charter text) lives off-chain; an IPFS CID is content-addressed, so the URI itself pins the content.
- **Name is fixed.** No mutator changes `name`.

## 2. Charter Creation

A `Charter` is created alongside the DAO by every DAO constructor, from the `name` and `metadata_uri` arguments (`dao::create`, the SubDAO constructors, `tribe::create_tribe(_configured)`, `tribe::create_wired_subdao`). An empty name aborts with `dao::EInvalidName`. A `CreateSubDAO` payload carries the new SubDAO's `name` and `metadata_uri`; a `SpawnDAO` payload carries the successor's.

## 3. Updating Metadata: `UpdateMetadata`

```rust
struct UpdateMetadata has copy, drop, store {
    new_ipfs_cid: String,
}
```

- Framework type, seeded on every DAO with the display key **`CharterUpdate`**; its fixed permission bit is `METADATA`.
- Handler: `admin_ops::execute_update_metadata(charter, ticket)`. It checks the charter belongs to the ticket's DAO (`admin_ops::ECharterDaoMismatch`) and calls `charter::update_metadata<P>(charter, new_metadata_uri, &ExecutionRequest<P>)`, which checks the DAO again (`charter::EDaoMismatch`) and requires `METADATA` (`proposal::EPermissionDenied`).
- Emits `admin_ops::MetadataUpdated { dao_id, new_ipfs_cid }`.
- Composable by default, so it can be a composite step.

Recommended governance parameters depend on how much the DAO's metadata matters to it. A DAO that treats the metadata document as its constitution should raise `UpdateMetadata`'s threshold, delay and cooldown with `UpdateProposalConfig`.

## 4. Reading the Charter

Anyone can read the `Charter` object (standard Sui RPC) and fetch the document at `metadata_uri`. No authorization is needed. Indexers can follow changes through `MetadataUpdated` events.

## 5. Metadata Document Format

The framework stores the URI and does not parse the document. It typically carries the DAO's display fields (description, logo) and, for DAOs that want one, a charter text. Recommended structure for the charter text, as structured markdown:

```markdown
# [DAO Name] Charter
Version: [N]
Ratified: [date]

## 1. Purpose
[Why this organization exists. Its mission and scope.]

## 2. Membership
[Who can be a member. How members join and leave.
 For SubDAOs: relationship to controller.]

## 3. Governance
[Governance model (Board).
 Decision-making procedures. Quorum and threshold philosophy.
 Which proposal types are enabled and why.]

## 4. Treasury
[How funds are received and spent.
 Budget allocation philosophy. Revenue distribution rules.]

## 5. Organizational Structure
[SubDAO relationships.
 Delegation of authority. Reporting lines.]

## 6. Amendment Procedure
[How this charter can be changed.
 Required thresholds, delays, and review periods.
 What cannot be amended (if anything).]

## 7. Dissolution
[Conditions under which the organization dissolves.
 Asset distribution upon dissolution.
 Successor designation.]
```

Structured markdown is human-readable, parseable by UIs, diff-friendly for review, and extensible.

## 6. Integration with DAO Lifecycle

| Lifecycle Event | Charter Impact |
|---|---|
| DAO creation (any constructor) | `Charter` created with the given `name` and `metadata_uri` |
| `CreateSubDAO` / tribe constructors | `Charter` created for each SubDAO from the payload or arguments |
| `UpdateMetadata` | `metadata_uri` replaced; `MetadataUpdated` emitted |
| `dao::destroy` | `Charter` destroyed alongside the other companion objects |

---

# Part B — Planned: Walrus-Backed Charter with Amendments (not implemented)

> **Status:** design only. None of the objects, types or events below exist. The whitepaper (v0.2) describes the implemented charter as "a name + IPFS metadata-URI pointer".

The goal is to make the charter a first-class governance artifact with a high-threshold amendment process and a verifiable on-chain history. The content would be stored on **Walrus** and referenced by blob ID and content hash.

## 7. Planned State

```rust
// Planned. Charter's struct layout is fixed by the published framework, so this state
// would live in dynamic fields on the Charter's UID or ship with a fresh framework publish.
current_blob_id:   String,                   // Walrus blob ID for current charter content
content_hash:      vector<u8>,               // SHA-256 hash of the charter content
version:           u64,                      // monotonically increasing version number
amendment_history: vector<AmendmentRecord>,  // chronological history of amendments

struct AmendmentRecord has copy, drop, store {
    version:          u64,          // version number after this amendment
    previous_blob_id: String,
    new_blob_id:      String,
    content_hash:     vector<u8>,   // hash of the new content
    proposal_id:      ID,           // the proposal (or single-PTB execution) that authorized it
    amended_at_ms:    u64,
}
```

- **Content hash for integrity.** Anyone can fetch the Walrus blob and verify `SHA-256(blob_content) == content_hash`.
- **Amendment history on-chain.** Anyone can reconstruct the charter's evolution without trusting an indexer.
- **Version monotonicity.** `version` starts at 1, increments by one per amendment, and never decreases or resets.

## 8. Planned Types

The charter's fields are private to the framework, so every planned write needs a new gated mutator in `armature::charter`. It would check the charter's DAO and a permission bit, as `update_metadata` checks `METADATA`. Under the placement rule in [`docs/package-boundaries.md`](../docs/package-boundaries.md), a type the framework seeds as a default slot must itself be a framework type.

### 8.1 `AmendCharter`

```rust
struct AmendCharter has drop, store {
    new_blob_id:  String,       // Walrus blob ID of the new charter content
    content_hash: vector<u8>,   // SHA-256 hash of the new charter content
    summary:      String,       // human-readable summary of what changed
}
```

On execution the handler would record an `AmendmentRecord` (`previous_blob_id = current_blob_id`, `proposal_id = ticket_proposal_id`, `version + 1`), update `current_blob_id`, `content_hash` and `version`, and emit a `CharterAmended` event.

Recommended parameters (configuration, not framework floors):

| Parameter | Recommended Value | Rationale |
|---|---|---|
| `approval_threshold` | `8000` (80%) | Constitutional changes should require near-unanimity |
| `execution_delay_ms` | `172_800_000` (48 hours) | Cooling-off period for review; also keeps it off the single-vote atomic path |
| `cooldown_ms` | `604_800_000` (7 days) | Prevent rapid-fire charter changes |
| `expiry_ms` | `1_209_600_000` (14 days) | Long voting window for major decisions |

Workflow: draft off-chain → upload to Walrus → compute `SHA-256` → propose `{ new_blob_id, content_hash, summary }` → voters fetch and verify the blob → vote → execute after the delay → anyone verifies `current_blob_id` against `content_hash`.

### 8.2 `RenewCharterStorage`

Walrus blobs have a finite storage duration. Renewal is off-chain; if a blob expires, anyone holding the content can re-upload it, and the unchanged `content_hash` verifies it.

```rust
struct RenewCharterStorage has drop, store {
    new_blob_id: String,   // new Walrus blob ID for the same content
}
```

The handler would update `current_blob_id` without changing `content_hash` or `version` and without adding an `AmendmentRecord`. The hash check is off-chain; the handler trusts governance approval. It could have lower thresholds than `AmendCharter`, since it does not change content. Historical blob IDs in `amendment_history` may point to expired blobs, so off-chain archival is recommended for long-lived DAOs.

## 9. Planned Lifecycle Impact

| Lifecycle Event | Charter Impact (planned) |
|---|---|
| DAO creation | Initial charter at `version = 1`, empty history |
| `CreateSubDAO` | Controller provides the SubDAO's initial charter content |
| `AmendCharter` | Charter updated, `version` incremented, `AmendmentRecord` added |
| `RenewCharterStorage` | `current_blob_id` updated, content unchanged |

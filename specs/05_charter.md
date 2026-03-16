# 05 — Charter Object and Walrus Integration

## Overview

Every DAO has a Charter — a human-readable constitutional document that defines the organization's purpose, operating agreements, membership rules, and amendment procedures. The Charter is stored on **Walrus** (Sui's decentralized blob storage) and referenced on-chain via a `Charter` shared object that tracks the current blob ID, content hash, version, and amendment history.

The Charter is not decorative metadata. It is a first-class governance artifact with its own high-threshold amendment process. Changing the Charter requires the same governance rigor as changing the organization's structure.

---

## 1. Core Object: `Charter`

A separate shared object, following the same concurrent-access pattern as `TreasuryVault` and `CapabilityVault`. The `DAO` stores only a `charter_id: ID` reference to it.

```rust
struct Charter has key {
    id:                UID,
    dao_id:            ID,                            // back-reference to the owning DAO
    current_blob_id:   String,                        // Walrus blob ID for current charter content
    content_hash:      vector<u8>,                    // SHA-256 hash of the charter content
    version:           u64,                           // monotonically increasing version number
    amendment_history: vector<AmendmentRecord>,       // chronological history of amendments
    created_at_ms:     u64,
}

struct AmendmentRecord has copy, drop, store {
    version:          u64,                // version number after this amendment
    previous_blob_id: String,             // blob ID of the previous version
    new_blob_id:      String,             // blob ID of the new version
    content_hash:     vector<u8>,         // hash of the new content
    proposal_id:      ID,                 // the AmendCharter proposal that authorized this change
    amended_at_ms:    u64,
}
```

### Design Decisions

- **Separate shared object.** Like `TreasuryVault`, the `Charter` is independently shared so that reads (anyone can read the charter) don't contend with writes (governance-authorized amendments) or with other DAO operations.
- **Content hash for integrity.** Anyone can fetch the Walrus blob and verify `SHA-256(blob_content) == charter.content_hash`. This prevents silent content replacement on Walrus (where blobs are content-addressed but could theoretically be re-uploaded with modifications under a new blob ID).
- **Amendment history on-chain.** The full history of blob ID transitions is stored on-chain, providing an immutable audit trail. Anyone can reconstruct the charter's evolution without trusting an indexer.
- **Version monotonicity.** `version` starts at 1 and increments on each amendment. It cannot decrease, skip, or be reset.

---

## 2. Charter Creation

A `Charter` is created alongside the DAO during `dao::create`. The creator provides the initial charter content:

1. The creator uploads the charter document to Walrus (off-chain, before the creation transaction).
2. The creation transaction includes the Walrus blob ID and the content hash.
3. `dao::create` creates the `Charter` shared object with `version = 1` and an empty `amendment_history`.
4. The DAO stores `charter_id: ID` referencing the new `Charter`.

For SubDAOs, the `CreateSubDAO` proposal payload includes charter parameters. The controller provides the initial charter for the new SubDAO.

---

## 3. Amending the Charter: `AmendCharter`

Charter amendments are high-stakes governance actions. They change the foundational rules of the organization.

```rust
struct AmendCharter has store {
    new_blob_id:    String,       // Walrus blob ID of the new charter content
    content_hash:   vector<u8>,   // SHA-256 hash of the new charter content
    summary:        String,       // human-readable summary of what changed
}
```

### 3.1 Recommended Governance Parameters

`AmendCharter` should be configured with conservative governance parameters:

| Parameter | Recommended Value | Rationale |
|---|---|---|
| `approval_threshold` | `8000` (80%) | Constitutional changes should require near-unanimity |
| `execution_delay_ms` | `172_800_000` (48 hours) | Long cooling-off period for stakeholder review |
| `cooldown_ms` | `604_800_000` (7 days) | Prevent rapid-fire charter changes |
| `expiry_ms` | `1_209_600_000` (14 days) | Long voting window for major decisions |

These are recommendations, not framework-enforced floors. Each DAO configures `AmendCharter` via `EnableProposalType` with its own `ProposalConfig`. The 66% floor on `EnableProposalType` provides a baseline guarantee.

### 3.2 Amendment Execution

On execution:
1. Assert `object::id(charter) == dao.charter_id`.
2. Record the current state in a new `AmendmentRecord`:
   - `previous_blob_id = charter.current_blob_id`
   - `new_blob_id = payload.new_blob_id`
   - `content_hash = payload.content_hash`
   - `proposal_id = req.proposal_id`
   - `amended_at_ms = clock.timestamp_ms()`
   - `version = charter.version + 1`
3. Push the `AmendmentRecord` to `charter.amendment_history`.
4. Update `charter.current_blob_id`, `charter.content_hash`, and `charter.version`.
5. Emit `CharterAmended` event.

### 3.3 Amendment Workflow (Off-Chain + On-Chain)

1. **Draft.** The proposer drafts the new charter content (or diff) off-chain.
2. **Upload.** The proposer uploads the new content to Walrus, receiving a blob ID.
3. **Hash.** The proposer computes `SHA-256(content)` locally.
4. **Propose.** The proposer creates an `AmendCharter` proposal with `{ new_blob_id, content_hash, summary }`.
5. **Review.** Voters fetch the blob from Walrus, verify `SHA-256(content) == content_hash`, and read the proposed changes.
6. **Vote.** Board members vote yes/no.
7. **Execute.** After passage and execution delay, a board member executes the proposal.
8. **Verify.** Anyone can verify the new charter: fetch `charter.current_blob_id` from Walrus, check `SHA-256(content) == charter.content_hash`.

---

## 4. Reading the Charter

The charter is readable by anyone:

1. Read `charter.current_blob_id` from the on-chain `Charter` object (standard Sui RPC).
2. Fetch the blob from Walrus using the blob ID.
3. Verify integrity: `SHA-256(blob_content) == charter.content_hash`.

No governance authorization is needed to read. The `Charter` is a shared object with publicly readable fields.

### 4.1 Historical Versions

Any previous version can be retrieved:
1. Read `charter.amendment_history` from the on-chain object.
2. Each `AmendmentRecord` contains the `previous_blob_id` and `new_blob_id`.
3. Fetch any historical blob from Walrus.

This provides full version history without an indexer.

---

## 5. Charter Content Format

Charters are stored as structured markdown with standard sections. This is a convention, not an on-chain enforcement — the framework stores the blob ID and hash but does not parse content.

### Recommended Structure

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

### Why Structured Markdown?

- **Human-readable.** Anyone can read the charter without special tooling.
- **Machine-parseable.** Standard sections enable UI rendering and comparison tooling.
- **Diff-friendly.** Structured markdown produces meaningful diffs for amendment review.
- **Extensible.** DAOs can add sections beyond the standard template without breaking parsers.

---

## 6. Storage Renewal

Walrus blobs have a finite storage duration. Charter content must be renewed before expiry to remain accessible.

### Considerations

- **Renewal is off-chain.** The protocol does not enforce renewal on-chain. If a blob expires, the content becomes inaccessible, but the on-chain `Charter` object (with its `content_hash`) remains.
- **Content hash provides recovery.** Even if a blob expires, anyone who has a copy of the charter content can re-upload it to Walrus. The new blob ID would differ, but the content hash can verify authenticity. A `RenewCharterStorage` proposal type could update `current_blob_id` without changing `content_hash` or incrementing `version`.
- **Amendment history preserves references.** Historical blob IDs in `amendment_history` may point to expired blobs. Off-chain archival (pinning services, IPFS backup) is recommended for long-lived DAOs.

### `RenewCharterStorage` Proposal Type

```rust
struct RenewCharterStorage has store {
    new_blob_id:  String,       // new Walrus blob ID for the same content
}
```

The handler:
1. Fetches the blob at `new_blob_id` and verifies `SHA-256(content) == charter.content_hash` (this verification is off-chain; on-chain, the handler trusts the proposer's assertion and governance approval).
2. Updates `charter.current_blob_id` without changing `content_hash` or `version`.
3. Does *not* add an `AmendmentRecord` — this is a storage operation, not a content change.

This proposal type can have lower governance thresholds than `AmendCharter` since it does not change the charter's content.

---

## 7. Integration with DAO Lifecycle

| Lifecycle Event | Charter Impact |
|---|---|
| `dao::create` | Initial `Charter` created with `version = 1` |
| `CreateSubDAO` | New `Charter` created for SubDAO with controller-provided content |
| `AmendCharter` | Charter updated, `version` incremented, `AmendmentRecord` added |
| `RenewCharterStorage` | `current_blob_id` updated, content unchanged |
| `dao::destroy` | `Charter` shared object destroyed alongside other DAO objects |

The Charter is a companion object to the DAO — created with it, destroyed with it, and governed by it throughout its lifecycle.

# Encrypted Tribe Participation: Keyspace × Armature Integration

## Overview

This document describes the integration of Keyspace's ACL-based encryption model into Armature's DAO framework under a **tribe participation** model. Tribes are DAOs whose board membership is the encryption access list. Encrypted content is shared via off-chain blobs (IPFS / Walrus); on-chain state tracks access control, epoch, and entry pointers.

No separate companion object is introduced. All encryption state lives directly on the `DAO` struct for the DAO or subDAO.

---

## Design Principles

- **Board = access list.** Tribe board members are encryption grantees. No separate `AdminCap` or `AllowList`.
- **Epoch tracks revocations.** `encrypt_epoch` increments automatically when a `SetBoard` execution removes members, signalling that prior entries must be re-encrypted.
- **All encryption operations are direct.** Any board member can call encryption functions in a single PTB — no proposal, voting round-trip, or `ExecutionRequest` required.
- **Entries indexed on-chain, capped at 32.** `entries: vector<ID>` provides a bounded on-chain index without off-chain event indexing. At most 32 `EncryptedEntry` objects per DAO at any time.
- **`seal_approve` reads live DAO state.** The Walrus Seal key server checks board membership directly on the DAO.

---

## DAO Struct Changes

Two fields added to the existing `DAO` struct in `dao.move`:

```move
public struct DAO has key, store {
  id: UID,
  status: DAOStatus,
  governance: GovernanceConfig,
  proposal_configs: VecMap<String, ProposalConfig>,
  enabled_proposal_types: VecSet<String>,
  last_executed_at: VecMap<String, u64>,
  treasury_id: ID,
  capability_vault_id: ID,
  charter_id: ID,
  emergency_freeze_id: ID,
  execution_paused: bool,
  controller_cap_id: Option<ID>,
  controller_paused: bool,

  // ── Encryption ────────────────────────────────────────────────
  encrypt_epoch: u64,   // increments on member removal; drives key rotation
  entries: vector<ID>,  // on-chain index of published EncryptedEntry IDs (max 32)
}
```

`encrypt_epoch` initialises to `0`. `entries` initialises to `vector[]`. For non-encrypting DAOs both are harmless zero/empty fields.

---

## New Object: `EncryptedEntry`

Defined in a new `encrypted_entry.move` module. Shared after creation.

```move
public struct EncryptedEntry has key, store {
  id: UID,
  dao_id: ID,
  location: String,     // ipfs:// or https:// pointing to AES-GCM ciphertext
  description: String,
  created_by: address,
  encrypt_epoch: u64,   // dao.encrypt_epoch at time of encryption
}
```

### Constants

```move
const MAX_ENTRIES: u64 = 32;
```

### Events

```move
public struct EntryPublished has copy, drop {
  entry_id: ID,
  dao_id: ID,
  location: String,
  created_by: address,
  encrypt_epoch: u64,
}
public struct EntryUpdated has copy, drop {
  entry_id: ID,
  dao_id: ID,
  new_location: String,
  encrypt_epoch: u64,
}
public struct EntryRemoved has copy, drop {
  entry_id: ID,
  dao_id: ID,
}
```

`EncryptionEpochRotated` is defined in `dao.move` (emitted from both `set_board_governance` and `rotate_encryption_epoch`):

```move
// in dao.move
public struct EncryptionEpochRotated has copy, drop {
  dao_id: ID,
  old_epoch: u64,
  new_epoch: u64,
}
```

---

## All Encryption Operations Are Direct (No Proposal Machinery)

All encryption functions are gated solely by board membership — no `ExecutionRequest`, no proposal object, no voting round-trip. This applies to epoch rotation and entry removal as well as publish/edit.

The rationale: these are operational key-hygiene actions, not governance decisions. Events provide the full audit trail. The `EmergencyFreeze` does not gate encryption operations.

For a DAO that wants multi-party consent on explicit epoch rotations or removals, the board can adopt an off-chain coordination policy; the on-chain enforcement remains unilateral by design.

---

## Encryption Functions

All functions assert `is_governance_member(dao, ctx.sender())` as their first authorization check.

### Member-direct: publish, edit, update

```move
/// Any board member publishes an encrypted entry.
/// Aborts if the entry cap (32) is already reached.
public fun publish_entry(
  dao: &mut DAO,
  location: String,
  description: String,
  ctx: &mut TxContext,
)
```
- Asserts `dao.status == Active`
- Asserts `is_governance_member(dao, ctx.sender())`
- Asserts `dao.entries.length() < MAX_ENTRIES`
- Creates and shares `EncryptedEntry` at current `dao.encrypt_epoch`
- Pushes entry ID into `dao.entries`
- Emits `EntryPublished`

```move
/// Re-encrypt a stale entry after an epoch increment.
/// Asserts the entry is stale (its epoch differs from the DAO's current epoch).
public fun update_entry(
  dao: &DAO,
  entry: &mut EncryptedEntry,
  new_location: String,
  ctx: &TxContext,
)
```
- Asserts `is_governance_member(dao, ctx.sender())`
- Asserts `entry.dao_id == dao.id()`
- Asserts `entry.encrypt_epoch != dao.encrypt_epoch` (must be stale)
- Updates location and epoch; emits `EntryUpdated`

```move
/// Update content within the same epoch (no key rotation).
public fun edit_entry(
  dao: &DAO,
  entry: &mut EncryptedEntry,
  new_location: String,
  ctx: &TxContext,
)
```
- Asserts `is_governance_member(dao, ctx.sender())`
- Asserts `entry.dao_id == dao.id()`
- Updates location only; emits `EntryUpdated`

### Member-direct: rotate epoch and remove entry

```move
/// Explicitly increment encrypt_epoch, marking all existing entries stale.
/// Use for out-of-band rotations (e.g. suspected key compromise, periodic hygiene).
/// The primary rotation path is automatic: SetBoard removal auto-increments the epoch.
public fun rotate_encryption_epoch(
  dao: &mut DAO,
  ctx: &TxContext,
)
```
- Asserts `dao.status == Active`
- Asserts `is_governance_member(dao, ctx.sender())`
- Increments `dao.encrypt_epoch`
- Emits `EncryptionEpochRotated`

```move
/// Remove an entry from the on-chain index and delete the object.
public fun remove_entry(
  dao: &mut DAO,
  entry: EncryptedEntry,
  ctx: &TxContext,
)
```
- Asserts `is_governance_member(dao, ctx.sender())`
- Asserts `entry.dao_id == dao.id()`
- Removes `entry.id` from `dao.entries`
- Destructs and deletes `EncryptedEntry`
- Emits `EntryRemoved`

### Walrus Seal integration

```move
/// Called by the Walrus Seal key server inside a PTB to gate decryption-key release.
/// id = dao UID bytes (32) || random nonce.
entry fun seal_approve(id: vector<u8>, dao: &DAO, ctx: &TxContext)
```
- Verifies `id[0..32] == object::id_to_bytes(&dao.id())`
- Asserts `is_governance_member(dao, ctx.sender())`

### New DAO accessors

```move
public fun encrypt_epoch(dao: &DAO): u64
public fun entries(dao: &DAO): &vector<ID>
public fun is_governance_member(dao: &DAO, addr: address): bool {
  governance::is_board_member(&dao.governance, addr)
}
```

Package-internal mutators (used by `encrypted_entry.move`):

```move
public(package) fun increment_encrypt_epoch(self: &mut DAO): (u64, u64)
public(package) fun push_entry(self: &mut DAO, entry_id: ID)
public(package) fun remove_entry_id(self: &mut DAO, target: ID)
```

---

## Automatic Epoch Rotation on Board Change

In `dao.move`'s `set_board_governance<P>()`, the old board member set is captured before the replacement. If any member was removed, `encrypt_epoch` is incremented automatically in the same execution:

```move
let old_members = *self.governance.board_members().keys();
self.governance.set_board(new_members);
if (any_member_removed(&old_members, &new_members)) {
  let old = self.encrypt_epoch;
  self.encrypt_epoch = old + 1;
  event::emit(EncryptionEpochRotated {
    dao_id: self.id(),
    old_epoch: old,
    new_epoch: self.encrypt_epoch,
  });
};
```

This is side-effectful on the `SetBoard` execution — no separate rotation needed after a membership change. `rotate_encryption_epoch` exists only for explicit out-of-band rotations (e.g. suspected key compromise, periodic security hygiene).

---

## Tribe Architecture

See [TRIBE_DAO_STRUCTURE.md](TRIBE_DAO_STRUCTURE.md) for the full object hierarchy, SubDAO relationships, creation flow, and governance boundaries.

### Encrypted entry lifecycle

1. **Publish** — member encrypts content locally, uploads blob, calls `publish_entry`; Seal ID = `dao_uid || nonce`
2. **Read** — authorised member calls `seal_approve` in a PTB; Seal releases key; member decrypts blob locally
3. **Edit** — member re-uploads, calls `edit_entry` (same epoch, no re-keying)
4. **Revocation** — `SetBoard` removes a member; `encrypt_epoch` auto-increments; Seal rejects old-epoch key requests for new entries
5. **Re-encrypt** — remaining members call `update_entry` per stale entry with new Seal ID at current epoch
6. **Remove** — board member calls `remove_entry` (single PTB, no proposal)

### Entry cap and rotation

Each DAO holds at most 32 `EncryptedEntry` objects. To publish a 33rd entry, an existing entry must first be removed via `remove_entry`. This bound keeps the DAO object size predictable and the `dao.entries` linear scan cost constant.

---

## Migration and SpinOut Considerations

### DAO migration (SpawnDAO / set_migrating)

When a DAO enters `Migrating` status and is eventually destroyed via `dao::destroy`, **`entries` must be empty**. The destroy function asserts `dao.entries.is_empty()`. The migration workflow:

1. Board executes `SetBoard`/`SpawnDAO` to enter `Migrating` status
2. Board members call `remove_entry` for each entry (at most 32 calls; entries are bounded)
3. Anyone calls `dao::destroy` to clean up all companion objects

The successor DAO starts with `encrypt_epoch: 0` and `entries: []`. Members re-encrypt content and publish to the new DAO. This is the correct security posture — a new DAO should have a fresh key epoch.

### SubDAO SpinOut

`SpinOutSubDAO` preserves the SubDAO object in place — `encrypt_epoch` and `entries` carry over to the now-independent DAO without any special handling.

### CreateSubDAO / SpawnDAO (new SubDAOs)

New SubDAOs always initialise with `encrypt_epoch: 0` and `entries: []`.

---

## No New Proposal Types

No new armature proposal types are introduced. `RotateEncryptionEpoch` and `RemoveEntry` are direct board-member functions, not governed operations. The encryption feature does not modify `DEFAULT_PROPOSAL_TYPES`, `SUBDAO_BLOCKED_TYPES`, or `UNDISABLEABLE_TYPES`.

---

## Module Change Summary

| File | Change |
|---|---|
| `dao.move` | Add `encrypt_epoch: u64`, `entries: vector<ID>` to `DAO`; add `EncryptionEpochRotated` event; add public accessors (`encrypt_epoch`, `entries`, `is_governance_member`) and package-internal mutators (`increment_encrypt_epoch`, `push_entry`, `remove_entry_id`); auto-rotate epoch in `set_board_governance` when members removed; assert `entries.is_empty()` in `destroy`; update all constructors |
| `governance.move` | Add `public(package) fun board_members()` accessor returning `&VecSet<address>` |
| `encrypted_entry.move` *(new)* | `EncryptedEntry` struct; `publish_entry`, `update_entry`, `edit_entry`, `rotate_encryption_epoch`, `remove_entry`, `seal_approve`; `EntryPublished`, `EntryUpdated`, `EntryRemoved` events; `MAX_ENTRIES = 32` constant |

Keyspace's `acl_encrypt.move` is **not ported** — its logic is fully subsumed. `seal_approve` is the only keyspace-origin pattern retained, adapted to read from `DAO` directly.

---

## Open Questions

1. **Direct / Weighted governance support for `is_governance_member`.** Currently the accessor delegates to `governance::is_board_member`, which only handles the `Board` variant. `Direct` and `Weighted` governance would need equivalent member enumeration before tribes can run on those governance models. Deferred.

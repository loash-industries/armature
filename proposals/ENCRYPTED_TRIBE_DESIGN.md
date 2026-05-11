# Encrypted Tribe Participation: Keyspace × Armature Integration

## Overview

This document describes the integration of Keyspace's ACL-based encryption model into Armature's DAO framework under a **tribe participation** model. Tribes are DAOs whose board membership is the encryption access list. Encrypted content is shared via off-chain blobs (IPFS / Walrus); on-chain state tracks access control, epoch, and entry pointers.

No separate companion object is introduced. All encryption state lives directly on the `DAO` struct for the DAO or subDAO

---

## Design Principles

- **Board = access list.** Tribe board members are encryption grantees. No separate `AdminCap` or `AllowList`.
- **Epoch tracks revocations.** `encrypt_epoch` increments automatically when a `SetBoard` execution removes members, signalling that prior entries must be re-encrypted.
- **Single-member unilateral execution.** Encryption operations default to a privileged path: any board member can propose and execute in a single PTB, with no quorum or voting round-trip required.
- **Entries indexed on-chain.** `entries: vector<ID>` provides a cheap on-chain index without off-chain event indexing.
- **`seal_approve` reads live DAO state.** The Walrus Seal key server checks board membership directly on the DAO.

---

## DAO Struct Changes

Two fields added to the existing `DAO` struct in `dao.move`:

```move
public struct DAO has key {
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
  entries: vector<ID>,  // on-chain index of published EncryptedEntry IDs
}
```

`encrypt_epoch` initialises to `0`. For non-encrypting DAOs it is a harmless zero field.

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
public struct EncryptionEpochRotated has copy, drop {
  dao_id: ID,
  old_epoch: u64,
  new_epoch: u64,
}
```

---

## Unilateral Execution Path ("Propose and Execute")

### The Problem

Standard armature governance requires: submit proposal (shared object created) → vote → execute. Because the proposal becomes a shared object, you cannot reference it in the same PTB that created it — Sui requires shared object IDs to be declared at PTB construction time. This makes atomic single-transaction "propose and execute" impossible through the standard path.

### The Solution

Armature already solves this in `controller.move` for SubDAO parent authority. The same mechanism applies here: `proposal::privileged_create<P>()` skips the voting lifecycle entirely, returning an `ExecutionRequest<P>` hot-potato directly. Since `ExecutionRequest` is not a shared object, it can be created and consumed within a single PTB.

A new function `encryption_execute<P>` in `board_voting.move` (or a dedicated `tribe_voting.move`) exposes this path, restricted to encryption-designated proposal types:

```move
/// Unilateral execution for encryption proposal types.
/// Any board member may call this; no proposal or voting round-trip required.
/// Returns a hot-potato ExecutionRequest consumable in the same PTB.
public fun encryption_execute<P>(
  dao: &mut DAO,
  freeze: &EmergencyFreeze,
  clock: &Clock,
  ctx: &mut TxContext,
): ExecutionRequest<P>
```

Internally:
1. Asserts `dao.status == Active`
2. Asserts `is_encryption_type<P>()` — the type is in the encryption whitelist
3. Asserts `!freeze.is_frozen(type_key_for<P>(), clock)`
4. Asserts `is_governance_member(dao, ctx.sender())`
5. Calls `proposal::privileged_create<P>(dao.id.to_inner(), ctx)` → `ExecutionRequest<P>`
6. Records `last_executed_at` for cooldown tracking
7. Returns the `ExecutionRequest<P>`

### Encryption-Designated Types

`is_encryption_type<P>()` whitelists:
- `RotateEncryptionEpoch`
- `RemoveEntry`

These types bypass voting by default. They can still be submitted through standard board voting if a DAO wants multi-party consent (e.g. a high-security tribe), but the default path is unilateral.

### PTB Flow (Single Board Member, Single Transaction)

```
Command 1: req = encryption_execute<RotateEncryptionEpoch>(dao, freeze, clock, ctx)
Command 2: rotate_encryption_epoch<RotateEncryptionEpoch>(dao, req, ctx)
```

```
Command 1: req = encryption_execute<RemoveEntry>(dao, freeze, clock, ctx)
Command 2: remove_entry<RemoveEntry>(dao, entry, req, ctx)
```

---

## Encryption Functions

### Member-direct (no proposal or execution request)

```move
/// Any board member publishes an encrypted entry.
public fun publish_entry(
  dao: &mut DAO,
  location: vector<u8>,
  description: vector<u8>,
  ctx: &mut TxContext,
)
```
- Asserts `is_governance_member(dao, ctx.sender())`
- Creates and shares `EncryptedEntry` at current `dao.encrypt_epoch`
- Pushes entry ID into `dao.entries`
- Emits `EntryPublished`

```move
/// Re-encrypt a stale entry after an epoch increment.
public fun update_entry(
  dao: &DAO,
  entry: &mut EncryptedEntry,
  new_location: vector<u8>,
  ctx: &TxContext,
)
```
- Asserts `is_governance_member(dao, ctx.sender())`
- Asserts `entry.dao_id == dao.id.to_inner()`
- Asserts `entry.encrypt_epoch != dao.encrypt_epoch` (must be stale)
- Updates location and epoch; emits `EntryUpdated`

```move
/// Update content within the same epoch (no key rotation).
public fun edit_entry(
  dao: &DAO,
  entry: &mut EncryptedEntry,
  new_location: vector<u8>,
  ctx: &TxContext,
)
```
- Asserts `is_governance_member(dao, ctx.sender())`
- Asserts `entry.dao_id == dao.id.to_inner()`
- Updates location only; emits `EntryUpdated`

### Execution-request-gated (via unilateral or standard governance)

```move
/// Explicitly increment encrypt_epoch, marking all existing entries stale.
public fun rotate_encryption_epoch<P>(
  dao: &mut DAO,
  req: ExecutionRequest<P>,
  ctx: &TxContext,
)
```
- Consumes `ExecutionRequest` via `proposal::finalize`
- Increments `dao.encrypt_epoch`
- Emits `EncryptionEpochRotated`

```move
/// Remove an entry from the on-chain index and delete the object.
public fun remove_entry<P>(
  dao: &mut DAO,
  entry: EncryptedEntry,
  req: ExecutionRequest<P>,
  ctx: &TxContext,
)
```
- Consumes `ExecutionRequest`
- Removes `entry.id` from `dao.entries`
- Destructs and deletes `EncryptedEntry`
- Emits `EntryRemoved`

### Walrus Seal integration

```move
/// Called by the Walrus Seal key server inside a PTB to gate decryption-key release.
/// id = dao UID bytes (32) || random nonce.
entry fun seal_approve(id: vector<u8>, dao: &DAO, ctx: &TxContext)
```
- Verifies `id[0..32] == object::uid_to_bytes(&dao.id)`
- Asserts `is_governance_member(dao, ctx.sender())`

### New DAO accessor

```move
public fun is_governance_member(dao: &DAO, addr: address): bool {
  governance::is_board_member(&dao.governance, addr)
}
```

---

## Automatic Epoch Rotation on Board Change

In `dao.move`'s `set_board_governance<P>()`, after replacing the board, diff the old and new member sets. If any member was removed, increment `encrypt_epoch` automatically in the same execution:

```move
if (any_removed(&old_members, &new_members)) {
  let old = dao.encrypt_epoch;
  dao.encrypt_epoch = old + 1;
  event::emit(EncryptionEpochRotated {
    dao_id: dao.id.to_inner(),
    old_epoch: old,
    new_epoch: dao.encrypt_epoch,
  });
};
```

This is side-effectful on the `SetBoard` execution — no separate `RotateEncryptionEpoch` proposal needed after a membership change. The `RotateEncryptionEpoch` proposal type exists only for explicit out-of-band rotations (e.g. suspected key compromise, periodic security rotation).

---

## New Proposal Types

| Type | Path | Trigger |
|---|---|---|
| `RotateEncryptionEpoch` | Unilateral by default; can use standard board voting | Explicit key rotation |
| `RemoveEntry` | Unilateral by default; can use standard board voting | Purge an entry |

Both are added to the default enabled proposal types. The `is_encryption_type<P>()` classifier routes them to `encryption_execute` instead of `authorize_execution`.

---

## Tribe Architecture

See [TRIBE_DAO_STRUCTURE.md](TRIBE_DAO_STRUCTURE.md) for the full object hierarchy, SubDAO relationships, creation flow, and governance boundaries.

### Encrypted entry lifecycle

1. **Publish** — member encrypts content locally, uploads blob, calls `publish_entry`; Seal ID = `dao_uid || nonce`
2. **Read** — authorised member calls `seal_approve` in a PTB; Seal releases key; member decrypts blob locally
3. **Edit** — member re-uploads, calls `edit_entry` (same epoch, no re-keying)
4. **Revocation** — `SetBoard` removes a member; `encrypt_epoch` auto-increments; Seal rejects old-epoch key requests for new entries
5. **Re-encrypt** — remaining members call `update_entry` per stale entry with new Seal ID at current epoch
6. **Remove** — board member calls `encryption_execute<RemoveEntry>` + `remove_entry` in one PTB

---

## Module Change Summary

| File | Change |
|---|---|
| `dao.move` | Add `encrypt_epoch: u64`, `entries: vector<ID>` to `DAO`; add `is_governance_member()` accessor; add `RotateEncryptionEpoch` + `RemoveEntry` to default types; auto-rotate epoch in `set_board_governance` when members removed; update `DAOCreated` event |
| `board_voting.move` | Add `encryption_execute<P>()` unilateral path; add `is_encryption_type<P>()` classifier |
| `encrypted_entry.move` *(new)* | `EncryptedEntry` struct; `publish_entry`, `update_entry`, `edit_entry`, `rotate_encryption_epoch`, `remove_entry`, `seal_approve`; all events |

Keyspace's `acl_encrypt.move` is **not ported** — its logic is fully subsumed. `seal_approve` is the only keyspace-origin pattern retained, adapted to read from `DAO` directly.

---

## Open Questions

1. **Direct / Weighted governance support for `is_governance_member`.** Currently the accessor delegates to `governance::is_board_member`, which only handles the `Board` variant. `Direct` and `Weighted` governance would need equivalent member enumeration before tribes can run on those governance models. Deferred.

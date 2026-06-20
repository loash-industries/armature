# Indexing Board Membership Events

This document covers every on-chain event that mutates a DAO's board and explains how to reconstruct full board state from the event stream.

## Event inventory

All board mutations emit exactly one event. The table below maps each proposal type to its event and source module.

| Proposal type | Event struct | Source module |
|---|---|---|
| DAO creation (all paths) | `DAOBoardInitialized` | `armature::dao` |
| `AddMember` | `MemberAdded` | `armature_proposals::member_ops` |
| `RemoveMember` | `MemberRemoved` | `armature_proposals::member_ops` |
| `BatchAddMembers` | `MembersBatchAdded` | `armature_proposals::member_ops` |
| `BatchRemoveMembers` | `MembersBatchRemoved` | `armature_proposals::member_ops` |
| `SetBoard` | `BoardUpdated` | `armature_proposals::board_ops` |
| `AutojoinDAO` (bypass, world bridge) | `MemberAutojoined` | `armature_world_bridge::autojoin_ops` |
| `ControllerBatchAddMembers` | `ControllerMembersBatchAdded` | `armature_proposals::subdao_ops` |
| `ControllerBatchRemoveMembers` | `ControllerMembersBatchRemoved` | `armature_proposals::subdao_ops` |

## Event field reference

```move
// armature::dao
DAOBoardInitialized { dao_id: ID, initial_members: vector<address> }

// armature_proposals::member_ops
MemberAdded          { dao_id: ID, member: address }
MemberRemoved        { dao_id: ID, member: address }
MembersBatchAdded    { dao_id: ID, added: vector<address>, skipped: vector<address> }
MembersBatchRemoved  { dao_id: ID, removed: vector<address> }

// armature_proposals::board_ops
BoardUpdated         { dao_id: ID, new_members: vector<address> }

// armature_world_bridge::autojoin_ops
MemberAutojoined     { dao_id: ID, member: address, owner_id: u32, character_id: ID }

// armature_proposals::subdao_ops
ControllerMembersBatchAdded   { controller_dao_id: ID, subdao_id: ID,
                                 added: vector<address>, skipped: vector<address> }
ControllerMembersBatchRemoved { controller_dao_id: ID, subdao_id: ID,
                                 removed: vector<address> }
```

## Reconstructing board state

Apply events in transaction order (checkpoint sequence, then within-transaction event sequence):

```
board: Map<ID, Set<address>> = {}

DAOBoardInitialized { dao_id, initial_members }
    → board[dao_id] = Set(initial_members)

MemberAdded { dao_id, member }
    → board[dao_id].add(member)

MemberRemoved { dao_id, member }
    → board[dao_id].remove(member)

MembersBatchAdded { dao_id, added, skipped }
    → board[dao_id].add_all(added)
    // `skipped` were already present — no mutation, logged for auditability

MembersBatchRemoved { dao_id, removed }
    → board[dao_id].remove_all(removed)

BoardUpdated { dao_id, new_members }
    → board[dao_id] = Set(new_members)   // full replacement

MemberAutojoined { dao_id, member, ... }
    → board[dao_id].add(member)

ControllerMembersBatchAdded { subdao_id, added, skipped, ... }
    → board[subdao_id].add_all(added)
    // key on subdao_id, not controller_dao_id

ControllerMembersBatchRemoved { subdao_id, removed, ... }
    → board[subdao_id].remove_all(removed)
    // key on subdao_id, not controller_dao_id
```

## Important indexing notes

**Controller events use `subdao_id`, not `dao_id`.** `ControllerMembersBatchAdded` and `ControllerMembersBatchRemoved` are emitted from the *controller* DAO's transaction context. The DAO whose board is actually mutated is identified by the `subdao_id` field. An indexer that only watches events keyed by `dao_id` will miss these — subscribe to all nine event types and route on the correct field.

**`MembersBatchAdded.skipped` is informational.** Addresses in `skipped` were already on the board at execution time. They are logged so the on-chain record reflects the full proposed batch, but they produce no state change.

**`BatchRemoveMembers` has no skip concept.** The framework aborts if any proposed address is not on the board, so `MembersBatchRemoved.removed` always equals the full proposed batch.

**`BoardUpdated` is a full replacement.** Do not diff — discard the previous board state for that DAO and seed from `new_members`.

**All creation paths emit `DAOBoardInitialized`.** Public entry points that create DAOs: `dao::create`, `dao::create_subdao`, `dao::create_subdao_configured`, `tribe::create_wired_subdao`, `tribe::create_tribe_configured`. The internal `public(package)` helpers (`create_returning_vault`, `create_returning_vault_configured`, `create_subdao_returning_vault`, `create_subdao_returning_vault_configured`) are called by proposal handlers (`CreateSubDAO`, `SpawnDAO`) and also emit the event. The preceding `DAOCreated` event carries companion object IDs but not member addresses; `DAOBoardInitialized` carries member addresses but not companion object IDs. Both events are emitted in the same transaction.

**`EncryptionEpochRotated` is not a membership event.** It fires whenever the encrypt epoch increments (on `BatchRemoveMembers`, `ControllerBatchRemoveMembers`, and `SetBoard` when members are removed). It does not add or remove any address.

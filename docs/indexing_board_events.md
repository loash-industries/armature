# Indexing Board Membership Events

This document covers every on-chain event that mutates an OU's board and explains how to reconstruct full board state from the event stream.

## Event inventory

All board mutations emit exactly one event. The table below maps each proposal type to its event and source module.

| Proposal type | Event struct | Source module |
|---|---|---|
| OU creation (all paths) | `OUBoardInitialized` | `armature::ou` |
| `AddMember` | `MemberAdded` | `armature_proposals::member_ops` |
| `RemoveMember` | `MemberRemoved` | `armature_proposals::member_ops` |
| `BatchAddMembers` | `MembersBatchAdded` | `armature_proposals::member_ops` |
| `BatchRemoveMembers` | `MembersBatchRemoved` | `armature_proposals::member_ops` |
| `SetBoard` | `BoardUpdated` | `armature_proposals::board_ops` |
| `AutojoinOU` (bypass, world bridge) | `MemberAutojoined` | `armature_world_bridge::autojoin_ops` |
| `ControllerBatchAddMembers` | `ControllerMembersBatchAdded` | `armature_proposals::subou_ops` |
| `ControllerBatchRemoveMembers` | `ControllerMembersBatchRemoved` | `armature_proposals::subou_ops` |

## Event field reference

```move
// armature::ou
OUBoardInitialized { ou_id: ID, initial_members: vector<address> }

// armature_proposals::member_ops
MemberAdded          { ou_id: ID, member: address }
MemberRemoved        { ou_id: ID, member: address }
MembersBatchAdded    { ou_id: ID, added: vector<address>, skipped: vector<address> }
MembersBatchRemoved  { ou_id: ID, removed: vector<address> }

// armature_proposals::board_ops
BoardUpdated         { ou_id: ID, new_members: vector<address> }

// armature_world_bridge::autojoin_ops
MemberAutojoined     { ou_id: ID, member: address, tribe_id: u32, character_id: ID }

// armature_proposals::subou_ops
ControllerMembersBatchAdded   { controller_ou_id: ID, subou_id: ID,
                                 added: vector<address>, skipped: vector<address> }
ControllerMembersBatchRemoved { controller_ou_id: ID, subou_id: ID,
                                 removed: vector<address> }
```

## Reconstructing board state

Apply events in transaction order (checkpoint sequence, then within-transaction event sequence):

```
board: Map<ID, Set<address>> = {}

OUBoardInitialized { ou_id, initial_members }
    → board[ou_id] = Set(initial_members)

MemberAdded { ou_id, member }
    → board[ou_id].add(member)

MemberRemoved { ou_id, member }
    → board[ou_id].remove(member)

MembersBatchAdded { ou_id, added, skipped }
    → board[ou_id].add_all(added)
    // `skipped` were already present — no mutation, logged for auditability

MembersBatchRemoved { ou_id, removed }
    → board[ou_id].remove_all(removed)

BoardUpdated { ou_id, new_members }
    → board[ou_id] = Set(new_members)   // full replacement

MemberAutojoined { ou_id, member, ... }
    → board[ou_id].add(member)

ControllerMembersBatchAdded { subou_id, added, skipped, ... }
    → board[subou_id].add_all(added)
    // key on subou_id, not controller_ou_id

ControllerMembersBatchRemoved { subou_id, removed, ... }
    → board[subou_id].remove_all(removed)
    // key on subou_id, not controller_ou_id
```

## Important indexing notes

**Controller events use `subou_id`, not `ou_id`.** `ControllerMembersBatchAdded` and `ControllerMembersBatchRemoved` are emitted from the *controller* OU's transaction context. The OU whose board is actually mutated is identified by the `subou_id` field. An indexer that only watches events keyed by `ou_id` will miss these — subscribe to all nine event types and route on the correct field.

**`MembersBatchAdded.skipped` is informational.** Addresses in `skipped` were already on the board at execution time. They are logged so the on-chain record reflects the full proposed batch, but they produce no state change.

**`BatchRemoveMembers` has no skip concept.** The framework aborts if any proposed address is not on the board, so `MembersBatchRemoved.removed` always equals the full proposed batch.

**`BoardUpdated` is a full replacement.** Do not diff — discard the previous board state for that OU and seed from `new_members`.

**All creation paths emit `OUBoardInitialized`.** Public entry points that create OUs: `ou::create`, `ou::create_subou`, `ou::create_subou_configured`, `tribe::create_wired_subou`, `tribe::create_tribe_configured`. The internal `public(package)` helpers (`create_returning_vault`, `create_returning_vault_configured`, `create_subou_returning_vault`, `create_subou_returning_vault_configured`) are called by proposal handlers (`CreateSubOU`, `SpawnOU`) and also emit the event. The preceding `OUCreated` event carries companion object IDs but not member addresses; `OUBoardInitialized` carries member addresses but not companion object IDs. Both events are emitted in the same transaction.

**`EncryptionEpochRotated` is not a membership event.** It fires whenever the encrypt epoch increments (on `BatchRemoveMembers`, `ControllerBatchRemoveMembers`, and `SetBoard` when members are removed). It does not add or remove any address.

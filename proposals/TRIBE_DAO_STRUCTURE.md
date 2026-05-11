# Tribe DAO Structure

## Overview

A tribe is a three-tier DAO hierarchy built on Armature's SubDAO model. The parent Tribe DAO owns and controls two SubDAOs — Officers and Members — each with their own board, encrypted entry index, and encryption epoch.

```
Tribe DAO (parent)
├── Officers SubDAO
└── Members SubDAO
```

---

## Object Hierarchy

### Tribe DAO (parent)

Created via `dao::create()`. Controls both SubDAOs through `SubDAOControl` capabilities stored in its `CapabilityVault`.

| Object | Type | Purpose |
|---|---|---|
| `DAO` | shared | Governance, proposal configs, encryption state |
| `TreasuryVault` | shared | Tribe-level treasury |
| `CapabilityVault` | shared | Holds `SubDAOControl` caps for Officers + Members SubDAOs |
| `Charter` | shared | Tribe name, description, image |
| `EmergencyFreeze` | shared | Freeze controls |
| `FreezeAdminCap` | owned (creator) | Emergency freeze authority |

### Officers SubDAO

Created via `dao::create_subdao()`. Board members are the tribe's officers; they have access to officer-scoped encrypted entries.

| Object | Type | Purpose |
|---|---|---|
| `DAO` | shared | Officer governance + `encrypt_epoch` + `entries` |
| `TreasuryVault` | shared | Officer-level treasury |
| `CapabilityVault` | shared | Officer capabilities |
| `Charter` | shared | Officers channel name, description, image |
| `EmergencyFreeze` | shared | Officer freeze controls |
| `FreezeAdminCap` | owned (officer admin) | Officer emergency freeze authority |

### Members SubDAO

Same structure as Officers SubDAO; board members are the tribe's general membership.

---

## Relationships

```
Tribe DAO
│  CapabilityVault
│  ├── SubDAOControl { subdao_id: officer_dao_id }
│  └── SubDAOControl { subdao_id: member_dao_id }
│
├── Officers SubDAO
│   controller_cap_id → SubDAOControl in Tribe CapabilityVault
│   encrypt_epoch: u64
│   entries: vector<ID> → [ EncryptedEntry, ... ]
│
└── Members SubDAO
    controller_cap_id → SubDAOControl in Tribe CapabilityVault
    encrypt_epoch: u64
    entries: vector<ID> → [ EncryptedEntry, ... ]
```

Each `EncryptedEntry` is a standalone shared object referencing its parent SubDAO by `dao_id`.

---

## Creation Flow

### Why Not 10 Steps

`create_subdao()` in `dao.move` requires **no `ExecutionRequest`** — it is a standalone public function returning an un-shared `(DAO, FreezeAdminCap)` by value. SubDAO creation is not gated behind governance voting. This collapses the full tribe setup to 2 PTBs at minimum, or 1 PTB with a convenience wrapper.

---

### Bare Flow (2 PTBs)

**PTB 1 — Create parent Tribe DAO**

```
dao::create(tribe_gov, name, description, image_url, ctx)
  → shares DAO + TreasuryVault + CapabilityVault + Charter + EmergencyFreeze
  → returns tribe_dao_id
  → emits DAOCreated { dao_id, capability_vault_id, treasury_id, ... }
```

Read `capability_vault_id` from the emitted `DAOCreated` event before constructing PTB 2.

**PTB 2 — Create both SubDAOs atomically**

`create_subdao()` returns un-shared DAO objects by value, so the entire chain runs in one PTB with no shared-object-ID problem:

```
(officer_dao, officer_freeze_cap) = dao::create_subdao(officer_gov, "Officers", ...)
(member_dao,  member_freeze_cap)  = dao::create_subdao(member_gov,  "Members",  ...)

officer_ctrl_id = capability_vault::create_subdao_control(parent_vault, &officer_dao, ctx)
member_ctrl_id  = capability_vault::create_subdao_control(parent_vault, &member_dao,  ctx)

dao::share_subdao(officer_dao, officer_ctrl_id)
dao::share_subdao(member_dao,  member_ctrl_id)

transfer(officer_freeze_cap, officer_admin_address)
transfer(member_freeze_cap,  member_admin_address)
```

Each `create_subdao()` call internally creates and shares the SubDAO's companion objects (`TreasuryVault`, `CapabilityVault`, `Charter`, `EmergencyFreeze`) and emits its own `DAOCreated` event.

---

### `create_tribe()` Convenience Function (1 PTB)

A new `tribe.move` module exposes a single entry point that performs the full three-tier setup inside one Move function body. Intermediate objects are Move-owned values (not yet shared), so there is no inter-PTB coordination needed — the `CapabilityVault` reference is available in the same function scope.

```move
/// Create a parent Tribe DAO with an Officers SubDAO and a Members SubDAO.
/// All companion objects are created and shared internally.
/// FreezeAdminCaps are transferred to the provided admin addresses.
/// Returns (tribe_dao_id, officer_dao_id, member_dao_id).
public fun create_tribe(
    tribe_gov:            &GovernanceTypeInit,
    officer_gov:          &GovernanceTypeInit,
    member_gov:           &GovernanceTypeInit,
    tribe_name:           String,
    officer_name:         String,
    member_name:          String,
    tribe_description:    String,
    officer_description:  String,
    member_description:   String,
    tribe_image_url:      String,
    officer_image_url:    String,
    member_image_url:     String,
    officer_freeze_admin: address,
    member_freeze_admin:  address,
    ctx: &mut TxContext,
): (ID, ID, ID)
```

**Internal steps (all in one Move function, one PTB):**

1. Create parent Tribe DAO and all companions via `dao::create(tribe_gov, ...)` — captures `tribe_dao_id` and the `CapabilityVault` reference directly
2. `dao::create_subdao(officer_gov, ...)` → `(officer_dao, officer_freeze_cap)` [un-shared]
3. `dao::create_subdao(member_gov, ...)` → `(member_dao, member_freeze_cap)` [un-shared]
4. `capability_vault::create_subdao_control(parent_vault, &officer_dao, ctx)` → `officer_ctrl_id`
5. `capability_vault::create_subdao_control(parent_vault, &member_dao, ctx)` → `member_ctrl_id`
6. `dao::share_subdao(officer_dao, officer_ctrl_id)`
7. `dao::share_subdao(member_dao, member_ctrl_id)`
8. Transfer `officer_freeze_cap` → `officer_freeze_admin`
9. Transfer `member_freeze_cap` → `member_freeze_admin`
10. Return `(tribe_dao_id, officer_dao_id, member_dao_id)`

All six companion `DAOCreated` events (one per DAO) are emitted during creation. The caller can derive every companion object ID from these events.

---

### PTB Summary

| Approach | PTBs | Notes |
|---|---|---|
| Bare (manual) | 2 | PTB 1 creates parent; PTB 2 creates both SubDAOs atomically |
| `create_tribe()` | 1 | Full hierarchy in one transaction; recommended path |

---

## Governance Boundaries

| Operation | Who | Path |
|---|---|---|
| Create tribe | Anyone | `create_tribe()` — no prior governance needed |
| Add/remove officer | Tribe DAO board | `SetBoard` proposal on Officers SubDAO (via parent `privileged_submit`) |
| Add/remove member | Tribe DAO board | `SetBoard` proposal on Members SubDAO (via parent `privileged_submit`) |
| Publish encrypted entry | Any SubDAO board member | `publish_entry()` — direct, no proposal |
| Edit encrypted entry | Any SubDAO board member | `edit_entry()` — direct, no proposal |
| Re-encrypt stale entry | Any SubDAO board member | `update_entry()` — direct, requires epoch mismatch |
| Rotate encryption epoch | Any SubDAO board member | `encryption_execute<RotateEncryptionEpoch>()` + `rotate_encryption_epoch()` — 1 PTB |
| Remove entry | Any SubDAO board member | `encryption_execute<RemoveEntry>()` + `remove_entry()` — 1 PTB |
| Dissolve SubDAO | Tribe DAO board | Governance proposal on parent |

Epoch rotation happens **automatically** as a side effect of any `SetBoard` execution that removes members — no separate rotation proposal required for the standard membership-change case.

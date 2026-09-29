# Tribe OU Structure

## Overview

A tribe is a three-tier OU hierarchy built on Armature's SubOU model. The parent Tribe OU owns and controls two SubOUs — Officers and Members — each with their own board, encrypted entry index, and encryption epoch.

```
Tribe OU (parent)
├── Officers SubOU
└── Members SubOU
```

---

## Object Hierarchy

### Tribe OU (parent)

Created via `ou::create()`. Controls both SubOUs through `SubOUControl` capabilities stored in its `CapabilityVault`.

| Object | Type | Purpose |
|---|---|---|
| `OU` | shared | Governance, proposal configs, encryption state |
| `TreasuryVault` | shared | Tribe-level treasury |
| `CapabilityVault` | shared | Holds `SubOUControl` caps for Officers + Members SubOUs |
| `Charter` | shared | Tribe name, description, image |
| `EmergencyFreeze` | shared | Freeze controls |
| `FreezeAdminCap` | owned (creator) | Emergency freeze authority |

### Officers SubOU

Created via `ou::create_subou()`. Board members are the tribe's officers; they have access to officer-scoped encrypted entries.

| Object | Type | Purpose |
|---|---|---|
| `OU` | shared | Officer governance + `encrypt_epoch` + `entries` |
| `TreasuryVault` | shared | Officer-level treasury |
| `CapabilityVault` | shared | Officer capabilities |
| `Charter` | shared | Officers channel name, description, image |
| `EmergencyFreeze` | shared | Officer freeze controls |
| `FreezeAdminCap` | owned (officer admin) | Officer emergency freeze authority |

### Members SubOU

Same structure as Officers SubOU; board members are the tribe's general membership.

---

## Relationships

```
Tribe OU
│  CapabilityVault
│  ├── SubOUControl { subou_id: officer_ou_id }
│  └── SubOUControl { subou_id: member_ou_id }
│
├── Officers SubOU
│   controller_cap_id → SubOUControl in Tribe CapabilityVault
│   encrypt_epoch: u64
│   entries: vector<ID> → [ EncryptedEntry, ... ]
│
└── Members SubOU
    controller_cap_id → SubOUControl in Tribe CapabilityVault
    encrypt_epoch: u64
    entries: vector<ID> → [ EncryptedEntry, ... ]
```

Each `EncryptedEntry` is a standalone shared object referencing its parent SubOU by `ou_id`.

---

## Creation Flow

### Why Not 10 Steps

`create_subou()` in `ou.move` requires **no `ExecutionRequest`** — it is a standalone public function returning an un-shared `(OU, FreezeAdminCap)` by value. SubOU creation is not gated behind governance voting. This collapses the full tribe setup to 2 PTBs at minimum, or 1 PTB with a convenience wrapper.

---

### Bare Flow (2 PTBs)

**PTB 1 — Create parent Tribe OU**

```
ou::create(tribe_gov, name, description, image_url, ctx)
  → shares OU + TreasuryVault + CapabilityVault + Charter + EmergencyFreeze
  → returns tribe_ou_id
  → emits OUCreated { ou_id, capability_vault_id, treasury_id, ... }
```

Read `capability_vault_id` from the emitted `OUCreated` event before constructing PTB 2.

**PTB 2 — Create both SubOUs atomically**

`create_subou()` returns un-shared OU objects by value, so the entire chain runs in one PTB with no shared-object-ID problem:

```
(officer_ou, officer_freeze_cap) = ou::create_subou(officer_gov, "Officers", ...)
(member_ou,  member_freeze_cap)  = ou::create_subou(member_gov,  "Members",  ...)

officer_ctrl_id = capability_vault::create_subou_control(parent_vault, &officer_ou, ctx)
member_ctrl_id  = capability_vault::create_subou_control(parent_vault, &member_ou,  ctx)

ou::share_subou(officer_ou, officer_ctrl_id)
ou::share_subou(member_ou,  member_ctrl_id)

transfer(officer_freeze_cap, officer_admin_address)
transfer(member_freeze_cap,  member_admin_address)
```

Each `create_subou()` call internally creates and shares the SubOU's companion objects (`TreasuryVault`, `CapabilityVault`, `Charter`, `EmergencyFreeze`) and emits its own `OUCreated` event.

---

### `create_tribe()` Convenience Function (1 PTB)

A new `tribe.move` module exposes a single entry point that performs the full three-tier setup inside one Move function body. Intermediate objects are Move-owned values (not yet shared), so there is no inter-PTB coordination needed — the `CapabilityVault` reference is available in the same function scope.

```move
/// Create a parent Tribe OU with an Officers SubOU and a Members SubOU.
/// All companion objects are created and shared internally.
/// FreezeAdminCaps are transferred to the provided admin addresses.
/// Returns (tribe_ou_id, officer_ou_id, member_ou_id).
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

1. Create parent Tribe OU and all companions via `ou::create(tribe_gov, ...)` — captures `tribe_ou_id` and the `CapabilityVault` reference directly
2. `ou::create_subou(officer_gov, ...)` → `(officer_ou, officer_freeze_cap)` [un-shared]
3. `ou::create_subou(member_gov, ...)` → `(member_ou, member_freeze_cap)` [un-shared]
4. `capability_vault::create_subou_control(parent_vault, &officer_ou, ctx)` → `officer_ctrl_id`
5. `capability_vault::create_subou_control(parent_vault, &member_ou, ctx)` → `member_ctrl_id`
6. `ou::share_subou(officer_ou, officer_ctrl_id)`
7. `ou::share_subou(member_ou, member_ctrl_id)`
8. Transfer `officer_freeze_cap` → `officer_freeze_admin`
9. Transfer `member_freeze_cap` → `member_freeze_admin`
10. Return `(tribe_ou_id, officer_ou_id, member_ou_id)`

All six companion `OUCreated` events (one per OU) are emitted during creation. The caller can derive every companion object ID from these events.

---

### PTB Summary

| Approach | PTBs | Notes |
|---|---|---|
| Bare (manual) | 2 | PTB 1 creates parent; PTB 2 creates both SubOUs atomically |
| `create_tribe()` | 1 | Full hierarchy in one transaction; recommended path |

---

## Governance Boundaries

| Operation | Who | Path |
|---|---|---|
| Create tribe | Anyone | `create_tribe()` — no prior governance needed |
| Add/remove officer | Tribe OU board | `SetBoard` proposal on Officers SubOU (via parent `privileged_submit`) |
| Add/remove member | Tribe OU board | `SetBoard` proposal on Members SubOU (via parent `privileged_submit`) |
| Publish encrypted entry | Any SubOU board member | `publish_entry()` — direct, no proposal |
| Edit encrypted entry | Any SubOU board member | `edit_entry()` — direct, no proposal |
| Re-encrypt stale entry | Any SubOU board member | `update_entry()` — direct, requires epoch mismatch |
| Rotate encryption epoch | Any SubOU board member | `encryption_execute<RotateEncryptionEpoch>()` + `rotate_encryption_epoch()` — 1 PTB |
| Remove entry | Any SubOU board member | `encryption_execute<RemoveEntry>()` + `remove_entry()` — 1 PTB |
| Dissolve SubOU | Tribe OU board | Governance proposal on parent |

Epoch rotation happens **automatically** as a side effect of any `SetBoard` execution that removes members — no separate rotation proposal required for the standard membership-change case.

# Tribe Creation Design

A **tribe** is the standard three-OU hierarchy in Armature: a parent **Tribe OU** governs two controlled SubOUs — an **Officers SubOU** and a **Members SubOU**. All three are created in a single transaction using `tribe::create_tribe` or `tribe::create_tribe_configured`. The configured variant accepts per-OU `ProposalConfig` overrides at construction time.

---

## Control Hierarchy

```
Tribe OU CapabilityVault
  └─ SubOUControl → Officers SubOU
                          └─ Officers SubOU CapabilityVault
                               └─ SubOUControl → Members SubOU
```

The Tribe OU holds a `SubOUControl` for the Officers SubOU inside its `CapabilityVault`. The Officers SubOU holds a `SubOUControl` for the Members SubOU inside its own vault. Control is one-directional and cannot be escalated upward.

---

## Objects Created

For each of the three OUs, the framework creates and shares the full companion object set:

| Object | Count | Notes |
|---|---|---|
| `OU` (shared) | 3 | Tribe, Officers, Members |
| `TreasuryVault` (shared) | 3 | One per OU |
| `CapabilityVault` (shared) | 3 | One per OU |
| `Charter` (shared) | 3 | One per OU |
| `EmergencyFreeze` (shared) | 3 | One per OU |
| `SubOUControl` (stored in vault) | 2 | Tribe→Officers, Officers→Members |
| `FreezeAdminCap` (owned) | 2 | Officers and Members admins; Tribe cap goes to tx sender |

The Tribe OU's `FreezeAdminCap` is transferred to `ctx.sender()`. The Officers and Members `FreezeAdminCap`s are transferred to the `officer_freeze_admin` and `member_freeze_admin` addresses provided by the caller.

---

## `create_tribe` — Default Config

```move
public fun create_tribe(
    tribe_board:   vector<address>,
    officers:      vector<address>,
    members:       vector<address>,
    tribe_name:    String,
    officer_name:  String,
    member_name:   String,
    tribe_description:   String,
    officer_description: String,
    member_description:  String,
    tribe_image_url:   String,
    officer_image_url: String,
    member_image_url:  String,
    officer_freeze_admin: address,
    member_freeze_admin:  address,
    ctx: &mut TxContext,
): (ID, ID, ID)  // (tribe_ou_id, officer_ou_id, member_ou_id)
```

All three OUs are built with **hardcoded default proposal configs** (50% quorum, 50% approval threshold, 7-day expiry, no delay, no cooldown). No runtime config tuning is possible via this entry point — use `create_tribe_configured` for that.

---

## `create_tribe_configured` — Per-OU Config Overrides

```move
public fun create_tribe_configured(
    // ... same identity params as create_tribe ...
    tribe_config_overrides:   VecMap<AsciiString, ProposalConfig>,
    officer_config_overrides: VecMap<AsciiString, ProposalConfig>,
    member_config_overrides:  VecMap<AsciiString, ProposalConfig>,
    ctx: &mut TxContext,
): (ID, ID, ID)
```

Each override map is applied **atomically at construction time**, before any OU is shared. This means governance configs are set correctly from genesis — there is no window during which an OU exists on-chain with wrong thresholds.

### Override semantics

For each entry `(type_key, config)` in an override map:

- If `type_key` is **already enabled** by default: its `ProposalConfig` is replaced. The existing `composable_allowed` flag is preserved (override cannot change composability at construction time).
- If `type_key` is **not yet enabled** and is not blocked: the type is inserted into both `proposal_configs` and `enabled_proposal_types`. This is how you enable non-default types at birth.
- If `type_key` is a **SubOU-blocked type** (for Officers/Members): the call aborts with `EBlockedProposalType`.
- If the override config sets `approval_threshold` below the **hardcoded floor** for the type: the call aborts with `EThresholdBelowMinimum`.

### Blocked types for SubOUs

The following types are excluded from the SubOU default config and cannot be added via overrides:

| Type | Reason |
|---|---|
| `SpawnOU` | Hierarchy-altering — SubOUs cannot spawn successors |
| `SpinOutSubOU` | Hierarchy-altering — SubOUs cannot self-emancipate |
| `CreateSubOU` | Hierarchy-altering — SubOUs cannot adopt children |
| `EnableBypassType` | Bypass-meta — would let a SubOU self-authorize external execution |
| `DisableBypassType` | Bypass-meta |

These restrictions are enforced by `apply_proposal_config_overrides` with `check_subou_blocked = true`. The parent Tribe OU uses `check_subou_blocked = false` because it legitimately has these types.

### Hardcoded threshold floors

| Type | Floor |
|---|---|
| `EnableProposalType` | 6 600 bps (66%) |
| `UpdateProposalConfig` | 8 000 bps (80%) |
| `EnableBypassType` | 8 000 bps (80%) |

An override that sets `approval_threshold` below these floors aborts immediately.

---

## Construction Sequence

```
create_tribe_configured(tribe_board, officers, members, ..., overrides)
  │
  ├─ governance::init_board(tribe_board) → tribe_gov
  ├─ governance::init_board(officers)    → officer_gov
  ├─ governance::init_board(members)     → member_gov
  │
  ├─ ou::create_returning_vault_configured(tribe_gov, tribe_overrides)
  │    → (tribe_ou_id, mut tribe_vault)        ← vault NOT shared yet
  │
  ├─ ou::create_subou_returning_vault_configured(officer_gov, officer_overrides)
  │    → (officer_ou, officer_freeze_cap, mut officer_vault)
  │
  ├─ ou::create_subou_configured(member_gov, member_overrides)
  │    → (member_ou, member_freeze_cap)         ← vault shared internally
  │
  ├─ capability_vault::new_subou_control(officer_ou_id)  → officer_ctrl
  │    capability_vault::store_cap_init(&mut tribe_vault, officer_ctrl)
  │
  ├─ capability_vault::new_subou_control(member_ou_id)   → member_ctrl
  │    capability_vault::store_cap_init(&mut officer_vault, member_ctrl)
  │
  ├─ capability_vault::share(tribe_vault)     ← now populated
  ├─ capability_vault::share(officer_vault)   ← now populated
  ├─ ou::share_subou(officer_ou, officer_ctrl_id)
  ├─ ou::share_subou(member_ou,  member_ctrl_id)
  │
  ├─ emergency::transfer_admin_cap(officer_freeze_cap, officer_freeze_admin)
  ├─ emergency::transfer_admin_cap(member_freeze_cap,  member_freeze_admin)
  │   (tribe FreezeAdminCap goes to ctx.sender via create_returning_vault_configured)
  │
  └─ return (tribe_ou_id, officer_ou_id, member_ou_id)
```

The key constraint is that the vaults for Tribe and Officers are **held un-shared** long enough to wire the `SubOUControl` objects into them. Only after wiring are the vaults shared. This is safe because all three creation functions are framework-internal (`public(package)`) except for `create_subou_configured`, which returns the OU un-shared for the same reason.

---

## Adding a SubOU Post-Hoc

After the tribe is live, the Tribe OU (or Officers SubOU) can add a new SubOU via the standard `CreateSubOU` proposal type, which calls `tribe::create_wired_subou`. That function requires an `ExecutionRequest` from the parent OU's governance:

```move
public fun create_wired_subou<P>(
    board: vector<address>,
    name: String,
    description: String,
    image_url: String,
    freeze_admin: address,
    parent_vault: &mut CapabilityVault,
    req: &ExecutionRequest<P>,
    config_overrides: VecMap<AsciiString, ProposalConfig>,
    ctx: &mut TxContext,
): ID
```

This is the incremental path: a vote passes on the controller OU, the execution ticket is used to authorize `store_cap` on the parent vault, and the new SubOU's `SubOUControl` is stored there. The override semantics are identical to `create_tribe_configured` — blocked types abort, floor thresholds are enforced.

---

## Common Config Patterns

### Fast-execution Officers OU (single operator)

Officers with a 1-member board where the sole officer should be able to execute operational proposals in one PTB:

```move
// officer_config_overrides
vec_map::from_keys_values(
    vector[b"SendCoin".to_ascii_string(), b"AddMember".to_ascii_string()],
    vector[
        proposal::new_config(5_000, 5_000, 0, 604_800_000, 0,         0),  // SendCoin: no delay
        proposal::new_config(5_000, 6_600, 0, 604_800_000, 86_400_000, 0), // AddMember: 24h delay
    ],
)
```

### Members OU with cooldown-gated joins

Rate-limit `AddMember` so the Members SubOU cannot be flooded in a single epoch:

```move
// member_config_overrides
vec_map::from_keys_values(
    vector[b"AddMember".to_ascii_string()],
    vector[
        proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 3_600_000), // 1h cooldown
    ],
)
```

### Enabling a non-default type at birth

Add `SendSmallPayment` (not in the default set) to the Officers OU so it can be used immediately without a separate `EnableProposalType` vote:

```move
// officer_config_overrides
vec_map::from_keys_values(
    vector[b"SendSmallPayment".to_ascii_string()],
    vector[
        proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0),
    ],
)
```

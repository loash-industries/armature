# Tribe Creation Design

A **tribe** is the standard three-DAO hierarchy in Armature: a parent **Tribe DAO** governs two controlled SubDAOs — an **Officers SubDAO** and a **Members SubDAO**. All three are created in a single transaction using `tribe::create_tribe` or `tribe::create_tribe_configured`. The configured variant accepts per-DAO `ProposalConfig` overrides at construction time.

---

## Control Hierarchy

```
Tribe DAO CapabilityVault
  └─ SubDAOControl → Officers SubDAO
                          └─ Officers SubDAO CapabilityVault
                               └─ SubDAOControl → Members SubDAO
```

The Tribe DAO holds a `SubDAOControl` for the Officers SubDAO inside its `CapabilityVault`. The Officers SubDAO holds a `SubDAOControl` for the Members SubDAO inside its own vault. Control is one-directional and cannot be escalated upward.

---

## Objects Created

For each of the three DAOs, the framework creates and shares the full companion object set:

| Object | Count | Notes |
|---|---|---|
| `DAO` (shared) | 3 | Tribe, Officers, Members |
| `TreasuryVault` (shared) | 3 | One per DAO |
| `CapabilityVault` (shared) | 3 | One per DAO |
| `Charter` (shared) | 3 | One per DAO |
| `EmergencyFreeze` (shared) | 3 | One per DAO |
| `SubDAOControl` (stored in vault) | 2 | Tribe→Officers, Officers→Members |
| `FreezeAdminCap` (owned) | 2 | Officers and Members admins; Tribe cap goes to tx sender |

The Tribe DAO's `FreezeAdminCap` is transferred to `ctx.sender()`. The Officers and Members `FreezeAdminCap`s are transferred to the `officer_freeze_admin` and `member_freeze_admin` addresses provided by the caller.

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
): (ID, ID, ID)  // (tribe_dao_id, officer_dao_id, member_dao_id)
```

All three DAOs are built with **hardcoded default proposal configs** (50% quorum, 50% approval threshold, 7-day expiry, no delay, no cooldown). No runtime config tuning is possible via this entry point — use `create_tribe_configured` for that.

---

## `create_tribe_configured` — Per-DAO Config Overrides

```move
public fun create_tribe_configured(
    // ... same identity params as create_tribe ...
    tribe_config_overrides:   VecMap<AsciiString, ProposalConfig>,
    officer_config_overrides: VecMap<AsciiString, ProposalConfig>,
    member_config_overrides:  VecMap<AsciiString, ProposalConfig>,
    ctx: &mut TxContext,
): (ID, ID, ID)
```

Each override map is applied **atomically at construction time**, before any DAO is shared. This means governance configs are set correctly from genesis — there is no window during which a DAO exists on-chain with wrong thresholds.

### Override semantics

For each entry `(type_key, config)` in an override map:

- If `type_key` is **already enabled** by default: its `ProposalConfig` is replaced. The existing `composable_allowed` flag is preserved (override cannot change composability at construction time).
- If `type_key` is **not yet enabled** and is not blocked: the type is inserted into both `proposal_configs` and `enabled_proposal_types`. This is how you enable non-default types at birth.
- If `type_key` is a **SubDAO-blocked type** (for Officers/Members): the call aborts with `EBlockedProposalType`.
- If the override config sets `approval_threshold` below the **hardcoded floor** for the type: the call aborts with `EThresholdBelowMinimum`.

### Blocked types for SubDAOs

The following types are excluded from the SubDAO default config and cannot be added via overrides:

| Type | Reason |
|---|---|
| `SpawnDAO` | Hierarchy-altering — SubDAOs cannot spawn successors |
| `SpinOutSubDAO` | Hierarchy-altering — SubDAOs cannot self-emancipate |
| `CreateSubDAO` | Hierarchy-altering — SubDAOs cannot adopt children |
| `EnableBypassType` | Bypass-meta — would let a SubDAO self-authorize external execution |
| `DisableBypassType` | Bypass-meta |

These restrictions are enforced by `apply_proposal_config_overrides` with `check_subdao_blocked = true`. The parent Tribe DAO uses `check_subdao_blocked = false` because it legitimately has these types.

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
  ├─ dao::create_returning_vault_configured(tribe_gov, tribe_overrides)
  │    → (tribe_dao_id, mut tribe_vault)        ← vault NOT shared yet
  │
  ├─ dao::create_subdao_returning_vault_configured(officer_gov, officer_overrides)
  │    → (officer_dao, officer_freeze_cap, mut officer_vault)
  │
  ├─ dao::create_subdao_configured(member_gov, member_overrides)
  │    → (member_dao, member_freeze_cap)         ← vault shared internally
  │
  ├─ capability_vault::new_subdao_control(officer_dao_id)  → officer_ctrl
  │    capability_vault::store_cap_init(&mut tribe_vault, officer_ctrl)
  │
  ├─ capability_vault::new_subdao_control(member_dao_id)   → member_ctrl
  │    capability_vault::store_cap_init(&mut officer_vault, member_ctrl)
  │
  ├─ capability_vault::share(tribe_vault)     ← now populated
  ├─ capability_vault::share(officer_vault)   ← now populated
  ├─ dao::share_subdao(officer_dao, officer_ctrl_id)
  ├─ dao::share_subdao(member_dao,  member_ctrl_id)
  │
  ├─ emergency::transfer_admin_cap(officer_freeze_cap, officer_freeze_admin)
  ├─ emergency::transfer_admin_cap(member_freeze_cap,  member_freeze_admin)
  │   (tribe FreezeAdminCap goes to ctx.sender via create_returning_vault_configured)
  │
  └─ return (tribe_dao_id, officer_dao_id, member_dao_id)
```

The key constraint is that the vaults for Tribe and Officers are **held un-shared** long enough to wire the `SubDAOControl` objects into them. Only after wiring are the vaults shared. This is safe because all three creation functions are framework-internal (`public(package)`) except for `create_subdao_configured`, which returns the DAO un-shared for the same reason.

---

## Adding a SubDAO Post-Hoc

After the tribe is live, the Tribe DAO (or Officers SubDAO) can add a new SubDAO via the standard `CreateSubDAO` proposal type, which calls `tribe::create_wired_subdao`. That function requires an `ExecutionRequest` from the parent DAO's governance:

```move
public fun create_wired_subdao<P>(
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

This is the incremental path: a vote passes on the controller DAO, the execution ticket is used to authorize `store_cap` on the parent vault, and the new SubDAO's `SubDAOControl` is stored there. The override semantics are identical to `create_tribe_configured` — blocked types abort, floor thresholds are enforced.

---

## Common Config Patterns

### Fast-execution Officers DAO (single operator)

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

### Members DAO with cooldown-gated joins

Rate-limit `AddMember` so the Members SubDAO cannot be flooded in a single epoch:

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

Add `SendSmallPayment` (not in the default set) to the Officers DAO so it can be used immediately without a separate `EnableProposalType` vote:

```move
// officer_config_overrides
vec_map::from_keys_values(
    vector[b"SendSmallPayment".to_ascii_string()],
    vector[
        proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0),
    ],
)
```

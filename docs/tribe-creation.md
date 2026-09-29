# Tribe Creation Design

A **tribe** is the standard three-OU hierarchy in Armature: a parent **Tribe OU** governs two controlled SubOUs — an **Officers SubOU** and a **Members SubOU**. All three are created in a single transaction.

There are two sets of constructors:

| Constructor | Package | Use |
|---|---|---|
| `tribe_setup::create_tribe` / `create_tribe_configured` | `armature_proposals` | **Recommended.** Also enables the controller types, so the Tribe OU and Officers can act on their SubOUs from creation. |
| `tribe::create_tribe` / `create_tribe_configured` | `armature_framework` | The bare structure. The controls exist but are unusable until each parent enables a controller type by vote. |

The configured variants accept per-OU proposal-type overrides at construction time.

---

## Control Hierarchy

```
Tribe OU CapabilityVault
  └─ SubOUControl → Officers SubOU
                          └─ Officers SubOU CapabilityVault
                               └─ SubOUControl → Members SubOU
```

The Tribe OU holds a `SubOUControl` for the Officers SubOU inside its `CapabilityVault`. The Officers SubOU holds a `SubOUControl` for the Members SubOU inside its own vault. Control is one-directional and cannot be escalated upward.

A parent uses its control through a controller proposal type from `armature_proposals`. `PauseSubOUExecution`, `UnpauseSubOUExecution`, `ControllerBatchAddMembers` and `ControllerBatchRemoveMembers` loan the `SubOUControl` from the vault, which needs `VAULT_BORROW` (`type_permissions::subou_control()`) with `SubOUControl` in the type's borrow scope (`type_permissions::subou_control_scope()`). `ReclaimCapFromSubOU` loans it the same way and also stores the reclaimed cap, so it needs `VAULT_BORROW | VAULT_STORE`. `TransferCapToSubOU` does not touch the `SubOUControl`: it extracts a cap from the parent's vault and hands it to the SubOU's vault, so it needs only `VAULT_EXTRACT` and has no borrow scope. The `VAULT_BORROW` and `VAULT_EXTRACT` bits put all of these types under the 80% permission floor. None of these types are enabled by default, and the framework cannot enable them because they live in `armature_proposals`. `tribe_setup` does.

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
| `FreezeAdminCap` (owned) | 3 | Tribe cap goes to tx sender; Officers and Members caps to the named admins |

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
    tribe_metadata_uri:   String,
    officer_metadata_uri: String,
    member_metadata_uri:  String,
    officer_freeze_admin: address,
    member_freeze_admin:  address,
    ctx: &mut TxContext,
): (ID, ID, ID)  // (tribe_ou_id, officer_ou_id, member_ou_id)
```

`tribe_setup::create_tribe` and `tribe::create_tribe` take the same arguments.

With `tribe::create_tribe`, all three OUs are built with **hardcoded default proposal configs** (50% quorum, 50% approval threshold, 7-day expiry, no delay, no cooldown). Types with a threshold floor (see [Hardcoded threshold floors](#hardcoded-threshold-floors)) get their floor as the default approval threshold instead of 50%, and `EnableBypassType` (Tribe OU only), `EnableProposalType` and `UpdateProposalConfig` default to an 80% quorum and a 100% threshold to meet their quorum rule, so every default config is usable as-is. No runtime config tuning is possible via this entry point — use `create_tribe_configured` for that.

`tribe_setup::create_tribe` adds these on the Tribe OU and the Officers SubOU, all at an 80% approval threshold (the floor for their bits):

| Type | Quorum |
|---|---|
| `ControllerBatchAddMembers`, `ControllerBatchRemoveMembers`, `PauseSubOUExecution` | 1 bps: one member can submit, vote and execute in one PTB |
| `UnpauseSubOUExecution`, `ReclaimCapFromSubOU`, `TransferCapToSubOU` | 50%: consensus |

`EnableProposalType` keeps the framework default on every OU: enabling a type needs YES from 80% of the whole board. The Members SubOU gets the plain defaults. See [tribe_configuration_proposals_config.md](tribe_configuration_proposals_config.md) for the policy behind these presets.

---

## `create_tribe_configured` — Per-OU Config Overrides

```move
public fun create_tribe_configured(
    // ... same identity params as create_tribe ...
    tribe_config_overrides:   vector<ProposalTypeInit>,
    officer_config_overrides: vector<ProposalTypeInit>,
    member_config_overrides:  vector<ProposalTypeInit>,
    ctx: &mut TxContext,
): (ID, ID, ID)
```

Build each entry with `ou::new_type_init<T>(display_key, config)`. The OU keys a type's slot by its Move type `T`; the display key is a label for events and UIs, unique per OU.

`tribe_setup::create_tribe_configured` applies its presets first and your overrides after them, so an override of a preset type replaces the preset's config.

Each override list is applied **atomically at construction time**, before any OU is shared. This means governance configs are set correctly from genesis — there is no window during which an OU exists on-chain with wrong thresholds.

### Override semantics

For each `ProposalTypeInit` for type `T`:

- If `T` is **already enabled** (by default or by a preset): its `ProposalConfig` is replaced. The display key must match the existing one (`EDisplayKeyMismatch` otherwise). The existing `composable_allowed` flag, permission bits and borrow scope are preserved; any bits or scope in the override config are ignored.
- If `T` is **not yet enabled** and is not blocked: its slot is added with the given config. This is how you enable non-default types at birth. The display key must be non-empty and unused on the OU (`EDisplayKeyTaken` otherwise). A framework type (`armature::*`) always gets its fixed permission bits (`ou::framework_permissions`): leave its config's bits at 0 or set exactly the fixed set, anything else aborts with `EFixedPermissions`. Any other type gets the bits and borrow scope in the config (`.with_permissions(…)`, `.with_borrow_scope(…)`; see `armature_proposals::type_permissions`).
- If `T` is a **SubOU-blocked type** (for Officers/Members): the call aborts with `EBlockedProposalType`.
- If the resulting config's `approval_threshold` is below the **hardcoded floor** for the type or its bits: the call aborts with `EThresholdBelowMinimum`. An `EnableBypassType` config that breaks its quorum rule aborts with `EBypassQuorumTooLow` (see below).

### Blocked types for SubOUs

The following types are excluded from the SubOU default config and cannot be added via overrides:

| Type | Reason |
|---|---|
| `SpawnOU` | Hierarchy-altering — SubOUs cannot spawn successors |
| `SpinOutSubOU` | Hierarchy-altering — SubOUs cannot self-emancipate |
| `CreateSubOU` | Hierarchy-altering — SubOUs cannot adopt children |
| `EnableBypassType` | Bypass-meta — would let a SubOU self-authorize external execution |
| `DisableBypassType` | Bypass-meta |

These restrictions are enforced by `ou::apply_type_overrides` with `check_subou_blocked = true`. The parent Tribe OU uses `check_subou_blocked = false` because it legitimately has these types.

### Hardcoded threshold floors

| Type | Floor |
|---|---|
| `EnableProposalType` | 8 000 bps (80%), and `quorum × approval_threshold ≥ 8 000 × 10 000` |
| `UpdateProposalConfig` | 8 000 bps (80%), and `quorum × approval_threshold ≥ 8 000 × 10 000` |
| `EnableBypassType` | 8 000 bps (80%), and `quorum × approval_threshold ≥ 8 000 × 10 000` |
| Any type whose permission bits include `TYPE_ADMIN`, `MIGRATE`, `TREASURY_WITHDRAW`, `VAULT_BORROW` or `VAULT_EXTRACT` | 8 000 bps (80%) |

The last row covers `DisableProposalType`, `DisableBypassType`, `SpawnOU`, `CreateSubOU`, `SpinOutSubOU` and `TransferAssets`, plus any non-framework type configured with one of those bits — including every controller and treasury type in `armature_proposals`. The per-type floor comes from `ou::min_approval_threshold_for_type` and the permission floor from `ou::permission_floor`.

An override that sets `approval_threshold` below these floors aborts immediately with `EThresholdBelowMinimum`. The default configs are raised to the same floors (`ou::config_for_type`), so `create_tribe` never produces a config that a floor check later rejects.

`EnableBypassType`, `EnableProposalType` and `UpdateProposalConfig` carry an extra quorum rule (`ou::EBypassQuorumTooLow` / `ou::EEnableQuorumTooLow` / `ou::EUpdateConfigQuorumTooLow` if broken): enabling a type or changing a type's config needs YES from 80% of the **whole board**, and any vote that meets quorum and threshold then has that much YES weight. For `EnableBypassType` this also matches its execution-time check. All three default to quorum 8 000, threshold 10 000: the proposal passes once 80% of the board has voted, all YES, but a single NO vote means it can never pass (it expires and must be resubmitted). The rule forces quorum ≥ 8 000, so one YES reaches quorum only on a 1-member board; on a larger board `submit_vote_execute` on any of them aborts with `EInsufficientVotingWeight`.

---

## Construction Sequence

```
tribe::create_tribe_configured(tribe_board, officers, members, ..., overrides)
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

`tribe_setup::create_tribe_configured` builds `controller presets ++ your overrides` for the Tribe and Officers lists, then calls this.

The key constraint is that the vaults for Tribe and Officers are **held un-shared** long enough to wire the `SubOUControl` objects into them. Only after wiring are the vaults shared. This is safe because the `*_returning_vault*` constructors are framework-internal (`public(package)`), and `create_subou_configured` returns the OU un-shared for the same reason.

---

## Adding a SubOU Post-Hoc

After the tribe is live, a parent can add a new SubOU with `tribe::create_wired_subou`, which requires an `ExecutionRequest` from the parent OU's governance carrying `VAULT_STORE` and `VAULT_EXTRACT` (the bits `CreateSubOU` holds):

```move
public fun create_wired_subou<P>(
    board: vector<address>,
    name: String,
    metadata_uri: String,
    freeze_admin: address,
    parent_vault: &mut CapabilityVault,
    req: &ExecutionRequest<P>,
    config_overrides: vector<ProposalTypeInit>,
    ctx: &mut TxContext,
): ID
```

This is the incremental path: a vote passes on the controller OU, the execution request authorizes `store_cap` on the parent vault, and the new SubOU's `SubOUControl` is stored there. The override semantics are identical to `create_tribe_configured` — blocked types abort, floor thresholds are enforced. The parent still needs controller types enabled to act on the new SubOU.

The framework's own `CreateSubOU` handler (`lifecycle_ops::execute_create_subou`) does not call `create_wired_subou`: it creates a SubOU with the default config and stores the new SubOU's `FreezeAdminCap` in the parent vault. To pass overrides or name a freeze admin, call `create_wired_subou` from the handler of your own proposal type `P`, taking the request from its ticket (`proposal::ticket_request`, which needs `P`'s permit). `P`'s config must hold `VAULT_STORE | VAULT_EXTRACT`, so it carries the 80% floor. `CreateSubOU` is SubOU-blocked, so the Officers SubOU cannot use that type.

---

## Common Config Patterns

The snippets below assume:

```move
use armature::add_member::AddMember;
use armature::ou;
use armature::proposal;
use armature_proposals::send_small_payment::SendSmallPayment;
use armature_proposals::type_permissions;
use sui::sui::SUI;
```

### Fast-execution Officers OU

Let one officer send small payments in one PTB, and hold officer-board changes behind a 24h delay:

```move
// officer_config_overrides
vector[
    // Not a default type: enabled at birth. Withdraws from the treasury, so it
    // needs treasury_spend() bits and the 80% floor.
    ou::new_type_init<SendSmallPayment<SUI>>(
        b"SendSmallPayment<SUI>".to_ascii_string(),
        proposal::new_config(1, 8_000, 0, 604_800_000, 0, 0)
            .with_permissions(type_permissions::treasury_spend()),
    ),
    // Default type: replaces its config; the display key must match.
    ou::new_type_init<AddMember>(
        b"AddMember".to_ascii_string(),
        proposal::new_config(5_000, 6_600, 0, 604_800_000, 86_400_000, 0), // 24h delay
    ),
]
```

A type with `execution_delay_ms > 0` cannot use `submit_vote_execute`.

### Members OU with cooldown-gated joins

Rate-limit `AddMember` so the Members SubOU cannot be flooded in a single epoch:

```move
// member_config_overrides
vector[
    ou::new_type_init<AddMember>(
        b"AddMember".to_ascii_string(),
        proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 3_600_000), // 1h cooldown
    ),
]
```

# 04 — SubOU Hierarchy

SubOUs model owned organizational units — departments, teams, project groups. The controller OU has authority over its SubOUs, analogous to a parent company's authority over its divisions.

> **Demo flow reference:** SubOU creation is demonstrated in Flow A Steps 4-7 and Flow B Steps 1-2. See [02 Demo Flows](02_demo_flows.md). The standard three-OU tribe (Tribe → Officers → Members) is described in [`docs/tribe-creation.md`](../docs/tribe-creation.md).

---

## 1. The `SubOUControl` Capability

```rust
struct SubOUControl has key, store {
    id:        UID,
    subou_id: ID,
}
```

Stored in the controller's `CapabilityVault`. Holding it lets the controller:
- **Mint privileged requests** on the SubOU with `controller::privileged_submit`. A privileged request passes every permission check on that SubOU, and it is the only request that `set_controller_paused` and `clear_controller` accept.
- **Extract capabilities** from the SubOU's vault with `controller::privileged_extract`.

Both call `controller::assert_registered_control`: `control.subou_id` must name the target OU (`EControlMismatch`) and the control must be the one recorded in the SubOU's `controller_cap_id` (`ENotController`). The controller can also push a capability into the SubOU's vault with `controller::receive_cap_from_controller`, which needs its own request (VAULT_EXTRACT) and checks that its vault holds the SubOU's registered control. The first-party types that use the control are proposed and voted on the **controller** OU. Each loans the `SubOUControl` from the controller's vault, which needs `VAULT_BORROW` with `SubOUControl` in the type's borrow scope:

| Type (package) | Effect on the SubOU |
|---|---|
| `ControllerBatchAddMembers` / `ControllerBatchRemoveMembers` (`armature_proposals`) | Add or remove up to 100 board members |
| `PauseSubOUExecution` / `UnpauseSubOUExecution` (`armature_proposals`) | Set or clear `controller_paused` |
| `ReclaimCapFromSubOU` (`armature_proposals`) | Move a capability from the SubOU's vault into the controller's |
| `SpinOutSubOU` (framework) | Grant independence (§6); destroys the `SubOUControl` |

The SubOU's `controller_cap_id: Option<ID>` records the `SubOUControl` that governs it, so the relationship is readable from the SubOU itself without inspecting vaults. While it is set, the SubOU is treated as controlled: it cannot enable the hierarchy-altering or bypass meta-types (§7).

---

## 2. SubOU Governance

All SubOUs use **Board governance**. A SubOU starts with the standard default proposal types except `EnableBypassType` and `DisableBypassType`, so its board runs day-to-day operations (and, unless the types are disabled or overridden at creation, its own membership changes) through ordinary Board voting. The controller can change the SubOU's board at any time through `ControllerBatchAddMembers` / `ControllerBatchRemoveMembers`, whatever the SubOU's own configuration.

---

## 3. Creating a SubOU

`CreateSubOU` is a framework type (`VAULT_STORE + VAULT_EXTRACT`, 80%), handled by `lifecycle_ops::execute_create_subou(vault, ticket, ctx)`:

```rust
struct CreateSubOU has drop, store {
    name:          String,
    initial_board: vector<address>,
    metadata_uri:  String,
}
```

On execution:
1. Create a new OU with Board governance and the SubOU default slots (no bypass meta-types), plus its treasury, capability vault, charter and emergency freeze.
2. Create a `SubOUControl` in the creator's `CapabilityVault` (`create_subou_control`).
3. Store the SubOU's `FreezeAdminCap` in the creator's `CapabilityVault`.
4. Share the SubOU with `controller_cap_id = some(control_id)` and emit `SubOUCreated`.

Other creation paths:
- `tribe::create_tribe` / `create_tribe_configured` build a Tribe OU, an Officers SubOU and a Members SubOU in one transaction. The Tribe's vault holds the Officers' `SubOUControl` and the Officers' vault holds the Members'. The SubOUs' `FreezeAdminCap`s go to the addresses the caller names, and `_configured` takes a per-OU list of `ProposalTypeInit` overrides.
- `tribe::create_wired_subou<P>(board, name, metadata_uri, freeze_admin, parent_vault, &req, overrides, ctx)` creates one SubOU under an existing parent from inside a handler. The parent's request must carry `VAULT_STORE + VAULT_EXTRACT`. The `FreezeAdminCap` goes to `freeze_admin`.

Creation-time overrides that name a SubOU-blocked type abort with `EBlockedProposalType`.

---

## 4. Controller Delegation

The controller may move a `SubOUControl` into one of its own SubOUs' vaults with `TransferCapToSubOU` (`VAULT_EXTRACT`, 80%), creating multi-level hierarchies:

```
Org
├── Engineering SubOU (holds SubOUControl for Frontend)
│   └── Frontend SubOU
├── Marketing SubOU
└── Operations SubOU
```

`TransferCapToSubOU` moves any capability type. The handler checks that the target vault belongs to the OU named in the payload (`target_subou`) and deposits through `controller::receive_cap_from_controller`, so the target must be a SubOU whose registered `SubOUControl` sits in the sender's vault (`controller::ENotController` otherwise). Capabilities therefore only flow to the sender's direct SubOUs.

---

## 5. Reclaim

`ReclaimCapFromSubOU` returns a delegated capability in one handler: loan the `SubOUControl`, `controller::privileged_extract` the capability from the SubOU's vault, `store_cap` it in the controller's vault, return the control.

To also stop the SubOU and change its board, the controller can execute `PauseSubOUExecution`, `ControllerBatchRemoveMembers` / `ControllerBatchAddMembers`, `ReclaimCapFromSubOU` and `UnpauseSubOUExecution` in one PTB. They can run as separately passed proposals, or as steps of one composite if those types are composable in the controller's config. The SubOU is paused for zero real time.

The controller's proposals are visible while its board votes on them. A controller that cannot afford that warning window can run them through `submit_vote_execute` if its configs allow single-vote execution (no delay; quorum met by one vote).

---

## 6. Spinout

`SpinOutSubOU` (framework, `VAULT_BORROW` scoped to `SubOUControl` + `VAULT_EXTRACT`, 80%) makes the SubOU independent. Its payload names the SubOU, the control, the SubOU's `FreezeAdminCap`, and the configs to give the three hierarchy types:

```rust
struct SpinOutSubOU has drop, store {
    subou_id:              ID,
    control_cap_id:         ID,
    freeze_admin_cap_id:    ID,
    spawn_ou_config:       ProposalConfig,
    spin_out_subou_config: ProposalConfig,
    create_subou_config:   ProposalConfig,
}
```

`lifecycle_ops::execute_spin_out_subou` loans the control and uses a privileged request on the SubOU to:
1. Clear `controller_cap_id` and `controller_paused`.
2. Enable `SpawnOU`, `SpinOutSubOU` and `CreateSubOU` with the payload's configs.

It then returns the control, moves the SubOU's `FreezeAdminCap` from the controller's vault into the SubOU's own vault, destroys the `SubOUControl`, and emits `SubOUSpunOut`. The `FreezeAdminCap` must be in the controller's vault, which is where `CreateSubOU` puts it. The spun-out OU can later enable the bypass meta-types by its own 80% vote. This is irreversible.

---

## 7. Composability Invariants

These invariants keep the organizational graph well-formed:

| Invariant | Rationale |
|---|---|
| An OU with a controller cannot enable `SpawnOU`, `SpinOutSubOU`, `CreateSubOU`, `EnableBypassType` or `DisableBypassType`, at creation or through the `EnableProposalType` / `EnableBypassType` handlers | Prevents unilateral independence, hierarchy manipulation, and self-granted no-vote execution. The check lives in those handlers and in the creation path; `ou::enable_proposal_type` itself checks only `TYPE_ADMIN`, so it does not bind a privileged request or a type the SubOU has granted `TYPE_ADMIN` |
| `controller_cap_id` is set when the SubOU is shared and cleared at spinout | On-chain record of the control relationship |
| A SubOU records at most one controller (`controller_cap_id` is a single `Option<ID>`) | Single controller per SubOU |
| `privileged_submit` and `privileged_extract` require the `SubOUControl` whose `subou_id` is the target OU and whose ID is the target's `controller_cap_id` | Control is bound to one SubOU; a forged or spun-out control is refused |
| `controller_paused` is set or cleared only by a privileged request (`ou::assert_controller`) | Controller-exclusive pause authority |
| When `controller_paused == true`, the SubOU's vote, atomic and bypass paths abort | Execution freeze; the controller's privileged path still runs so it can unpause |
| `SpinOutSubOU` clears `controller_paused` to `false` | Clean independence |

The framework's creation paths only ever produce trees: each new SubOU's control is minted into its creator's vault. The framework does not check the graph afterwards. A `TransferCapToSubOU` vote can move a `SubOUControl` into the vault of any SubOU the sender controls, so keeping the graph acyclic is a governance rule, not an enforced one.

---

## 8. Composability Summary

An OU is a node in a directed graph. Edges are capability objects stored in vaults. The direction of an edge encodes the power relationship:

- **Downward edge** (`SubOUControl` in controller's vault) — ownership and authority over a child OU.

```
                    ┌──────────────────────┐
                    │  Tribe A             │
                    │  (OU)               │
                    └─────┬────────┬───────┘
                          │        │
                 SubOUCtl│        │SubOUCtl
                          │        │
                    ┌─────▼──┐  ┌──▼─────────┐
                    │Logistics│  │ Security    │
                    │(SubOU) │  │ (SubOU)    │
                    └─────┬───┘  └─────────────┘
                          │
                 SubOUCtl│
                          │
                    ┌─────▼─────┐
                    │ Fleet Ops  │
                    └────────────┘
```

The protocol does not impose a single organizational topology. Any directed acyclic graph of OUs connected by `SubOUControl` edges works, subject to the invariants above. The same framework that governs a 3-person startup can scale to a multi-department organization — the primitives compose.

> **Lateral composition** (multi-membership via independent capabilities) and **upward composition** (federations) are stretch features. See [stretch/07 Lateral Composition](stretch/07_lateral_composition.md) and [stretch/01 Federation](stretch/01_federation.md).

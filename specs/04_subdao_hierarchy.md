# 04 — SubDAO Hierarchy

SubDAOs model owned organizational units — departments, teams, project groups. The controller DAO has authority over its SubDAOs, analogous to a parent company's authority over its divisions.

> **Demo flow reference:** SubDAO creation is demonstrated in Flow A Steps 4-7 and Flow B Steps 1-2. See [02 Demo Flows](02_demo_flows.md). The standard three-DAO tribe (Tribe → Officers → Members) is described in [`docs/tribe-creation.md`](../docs/tribe-creation.md).

---

## 1. The `SubDAOControl` Capability

```rust
struct SubDAOControl has key, store {
    id:        UID,
    subdao_id: ID,
}
```

Stored in the controller's `CapabilityVault`. Holding it lets the controller:
- **Mint privileged requests** on the SubDAO with `controller::privileged_submit`. A privileged request passes every permission check on that SubDAO, and it is the only request that `set_controller_paused` and `clear_controller` accept.
- **Extract capabilities** from the SubDAO's vault with `controller::privileged_extract`.

Both call `controller::assert_registered_control`: `control.subdao_id` must name the target DAO (`EControlMismatch`) and the control must be the one recorded in the SubDAO's `controller_cap_id` (`ENotController`). The controller can also push a capability into the SubDAO's vault with `controller::receive_cap_from_controller`, which needs its own request (VAULT_EXTRACT) and checks that its vault holds the SubDAO's registered control. The first-party types that use the control are proposed and voted on the **controller** DAO. Each loans the `SubDAOControl` from the controller's vault, which needs `VAULT_BORROW` with `SubDAOControl` in the type's borrow scope:

| Type (package) | Effect on the SubDAO |
|---|---|
| `ControllerBatchAddMembers` / `ControllerBatchRemoveMembers` (`armature_proposals`) | Add or remove up to 100 board members |
| `PauseSubDAOExecution` / `UnpauseSubDAOExecution` (`armature_proposals`) | Set or clear `controller_paused` |
| `ReclaimCapFromSubDAO` (`armature_proposals`) | Move a capability from the SubDAO's vault into the controller's |
| `SpinOutSubDAO` (framework) | Grant independence (§6); destroys the `SubDAOControl` |

The SubDAO's `controller_cap_id: Option<ID>` records the `SubDAOControl` that governs it, so the relationship is readable from the SubDAO itself without inspecting vaults. While it is set, the SubDAO is treated as controlled: it cannot enable the hierarchy-altering or bypass meta-types (§7).

---

## 2. SubDAO Governance

All SubDAOs use **Board governance**. A SubDAO starts with the standard default proposal types except `EnableBypassType` and `DisableBypassType`, so its board runs day-to-day operations (and, unless the types are disabled or overridden at creation, its own membership changes) through ordinary Board voting. The controller can change the SubDAO's board at any time through `ControllerBatchAddMembers` / `ControllerBatchRemoveMembers`, whatever the SubDAO's own configuration.

---

## 3. Creating a SubDAO

`CreateSubDAO` is a framework type (`VAULT_STORE + VAULT_EXTRACT`, 80%), handled by `lifecycle_ops::execute_create_subdao(vault, ticket, ctx)`:

```rust
struct CreateSubDAO has drop, store {
    name:          String,
    initial_board: vector<address>,
    metadata_uri:  String,
}
```

On execution:
1. Create a new DAO with Board governance and the SubDAO default slots (no bypass meta-types), plus its treasury, capability vault, charter and emergency freeze.
2. Create a `SubDAOControl` in the creator's `CapabilityVault` (`create_subdao_control`).
3. Store the SubDAO's `FreezeAdminCap` in the creator's `CapabilityVault`.
4. Share the SubDAO with `controller_cap_id = some(control_id)` and emit `SubDAOCreated`.

Other creation paths:
- `tribe::create_tribe` / `create_tribe_configured` build a Tribe DAO, an Officers SubDAO and a Members SubDAO in one transaction. The Tribe's vault holds the Officers' `SubDAOControl` and the Officers' vault holds the Members'. The SubDAOs' `FreezeAdminCap`s go to the addresses the caller names, and `_configured` takes a per-DAO list of `ProposalTypeInit` overrides.
- `tribe::create_wired_subdao<P>(board, name, metadata_uri, freeze_admin, parent_vault, &req, overrides, ctx)` creates one SubDAO under an existing parent from inside a handler. The parent's request must carry `VAULT_STORE + VAULT_EXTRACT`. The `FreezeAdminCap` goes to `freeze_admin`.

Creation-time overrides that name a SubDAO-blocked type abort with `EBlockedProposalType`.

---

## 4. Controller Delegation

The controller may move a `SubDAOControl` into one of its own SubDAOs' vaults with `TransferCapToSubDAO` (`VAULT_EXTRACT`, 80%), creating multi-level hierarchies:

```
Top-Level DAO
├── Engineering SubDAO (holds SubDAOControl for Frontend)
│   └── Frontend SubDAO
├── Marketing SubDAO
└── Operations SubDAO
```

`TransferCapToSubDAO` moves any capability type. The handler checks that the target vault belongs to the DAO named in the payload (`target_subdao`) and deposits through `controller::receive_cap_from_controller`, so the target must be a SubDAO whose registered `SubDAOControl` sits in the sender's vault (`controller::ENotController` otherwise). Capabilities therefore only flow to the sender's direct SubDAOs.

---

## 5. Reclaim

`ReclaimCapFromSubDAO` returns a delegated capability in one handler: loan the `SubDAOControl`, `controller::privileged_extract` the capability from the SubDAO's vault, `store_cap` it in the controller's vault, return the control.

To also stop the SubDAO and change its board, the controller can execute `PauseSubDAOExecution`, `ControllerBatchRemoveMembers` / `ControllerBatchAddMembers`, `ReclaimCapFromSubDAO` and `UnpauseSubDAOExecution` in one PTB. They can run as separately passed proposals, or as steps of one composite if those types are composable in the controller's config. The SubDAO is paused for zero real time.

The controller's proposals are visible while its board votes on them. A controller that cannot afford that warning window can run them through `submit_vote_execute` if its configs allow single-vote execution (no delay; quorum met by one vote).

---

## 6. Spinout

`SpinOutSubDAO` (framework, `VAULT_BORROW` scoped to `SubDAOControl` + `VAULT_EXTRACT`, 80%) makes the SubDAO independent. Its payload names the SubDAO, the control, the SubDAO's `FreezeAdminCap`, and the configs to give the three hierarchy types:

```rust
struct SpinOutSubDAO has drop, store {
    subdao_id:              ID,
    control_cap_id:         ID,
    freeze_admin_cap_id:    ID,
    spawn_dao_config:       ProposalConfig,
    spin_out_subdao_config: ProposalConfig,
    create_subdao_config:   ProposalConfig,
}
```

`lifecycle_ops::execute_spin_out_subdao` loans the control and uses a privileged request on the SubDAO to:
1. Clear `controller_cap_id` and `controller_paused`.
2. Enable `SpawnDAO`, `SpinOutSubDAO` and `CreateSubDAO` with the payload's configs.

It then returns the control, moves the SubDAO's `FreezeAdminCap` from the controller's vault into the SubDAO's own vault, destroys the `SubDAOControl`, and emits `SubDAOSpunOut`. The `FreezeAdminCap` must be in the controller's vault, which is where `CreateSubDAO` puts it. The spun-out DAO can later enable the bypass meta-types by its own 80% vote. This is irreversible.

---

## 7. Composability Invariants

These invariants keep the organizational graph well-formed:

| Invariant | Rationale |
|---|---|
| A DAO with a controller cannot enable `SpawnDAO`, `SpinOutSubDAO`, `CreateSubDAO`, `EnableBypassType` or `DisableBypassType`, at creation or through the `EnableProposalType` / `EnableBypassType` handlers | Prevents unilateral independence, hierarchy manipulation, and self-granted no-vote execution. The check lives in those handlers and in the creation path; `dao::enable_proposal_type` itself checks only `TYPE_ADMIN`, so it does not bind a privileged request or a type the SubDAO has granted `TYPE_ADMIN` |
| `controller_cap_id` is set when the SubDAO is shared and cleared at spinout | On-chain record of the control relationship |
| A SubDAO records at most one controller (`controller_cap_id` is a single `Option<ID>`) | Single controller per SubDAO |
| `privileged_submit` and `privileged_extract` require the `SubDAOControl` whose `subdao_id` is the target DAO and whose ID is the target's `controller_cap_id` | Control is bound to one SubDAO; a forged or spun-out control is refused |
| `controller_paused` is set or cleared only by a privileged request (`dao::assert_controller`) | Controller-exclusive pause authority |
| When `controller_paused == true`, the SubDAO's vote, atomic and bypass paths abort | Execution freeze; the controller's privileged path still runs so it can unpause |
| `SpinOutSubDAO` clears `controller_paused` to `false` | Clean independence |

The framework's creation paths only ever produce trees: each new SubDAO's control is minted into its creator's vault. The framework does not check the graph afterwards. A `TransferCapToSubDAO` vote can move a `SubDAOControl` into the vault of any SubDAO the sender controls, so keeping the graph acyclic is a governance rule, not an enforced one.

---

## 8. Composability Summary

A DAO is a node in a directed graph. Edges are capability objects stored in vaults. The direction of an edge encodes the power relationship:

- **Downward edge** (`SubDAOControl` in controller's vault) — ownership and authority over a child DAO.

```
                    ┌──────────────────────┐
                    │  Tribe A             │
                    │  (DAO)               │
                    └─────┬────────┬───────┘
                          │        │
                 SubDAOCtl│        │SubDAOCtl
                          │        │
                    ┌─────▼──┐  ┌──▼─────────┐
                    │Logistics│  │ Security    │
                    │(SubDAO) │  │ (SubDAO)    │
                    └─────┬───┘  └─────────────┘
                          │
                 SubDAOCtl│
                          │
                    ┌─────▼─────┐
                    │ Fleet Ops  │
                    └────────────┘
```

The protocol does not impose a single organizational topology. Any directed acyclic graph of DAOs connected by `SubDAOControl` edges works, subject to the invariants above. The same framework that governs a 3-person startup can scale to a multi-department organization — the primitives compose.

> **Lateral composition** (multi-membership via independent capabilities) and **upward composition** (federations) are stretch features. See [stretch/07 Lateral Composition](stretch/07_lateral_composition.md) and [stretch/01 Federation](stretch/01_federation.md).

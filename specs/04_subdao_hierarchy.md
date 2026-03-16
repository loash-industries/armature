# 04 — SubDAO Hierarchy

SubDAOs model owned organizational units — departments, teams, project groups. The controller DAO has full authority over its SubDAOs, analogous to a parent company's authority over its divisions.

> **Demo flow reference:** SubDAO creation is demonstrated in Flow A Steps 4-7 and Flow B Steps 1-2. See [02 Demo Flows](02_demo_flows.md).

---

## 1. The `SubDAOControl` Capability

```rust
struct SubDAOControl has key, store {
    id:        UID,
    subdao_id: ID,
}
```

Stored in the controller's `CapabilityVault`. Grants the controller the ability to:
- **Replace the SubDAO's board** instantly via `privileged_submit` + `SetBoard`.
- **Pause all execution** on the SubDAO via `PauseSubDAOExecution`.
- **Reclaim any capability** from the SubDAO's vault via `ReclaimCapFromSubDAO`.
- **Spin out** the SubDAO to independence via `SpinOutSubDAO` (destroys the `SubDAOControl`).

The SubDAO's `controller_cap_id: Option<ID>` field references the `SubDAOControl` that governs it. This provides on-chain verification without requiring vault inspection.

---

## 2. SubDAO Governance

All SubDAOs use **Board governance**. Board membership is managed exclusively by the controller — the SubDAO's board cannot change its own composition. The board governs day-to-day operations (treasury sends, proposal configs, etc.) through standard Board voting.

---

## 3. Creating a SubDAO

`CreateSubDAO` payload:
```rust
struct CreateSubDAO has store {
    initial_board:     vector<address>,
    seat_count:        u8,
    metadata_ipfs:     String,
    enabled_proposals: vector<TypeName>,
    charter_blob_id:   String,           // initial charter on Walrus
    charter_hash:      vector<u8>,       // SHA-256 of charter content
}
```

On execution:
1. Create new DAO with Board governance, `controller_cap_id = some(control_id)`.
2. Exclude `SpawnDAO`, `SpinOutSubDAO`, `CreateSubDAO` from enabled proposals.
3. Create `SubDAOControl` and store in creator's `CapabilityVault`.
4. Create `Charter` for the SubDAO.

---

## 4. Controller Delegation

The controller may transfer a `SubDAOControl` to one of its own SubDAOs via `TransferCapToSubDAO`, creating multi-level hierarchies:

```
Top-Level DAO
├── Engineering SubDAO (holds SubDAOControl for Frontend)
│   └── Frontend SubDAO
├── Marketing SubDAO
└── Operations SubDAO
```

Capabilities can only flow **downward** — to DAOs the transferring DAO directly controls. The constraint is enforced by requiring the transferring DAO to hold the target's `SubDAOControl`.

---

## 5. Atomic Reclaim

If a SubDAO acts against the controller's interests, the controller can reclaim any delegated capability in a single PTB:

1. `PauseSubDAOExecution` — freezes all execution on the SubDAO
2. `SetBoard` — replaces the compromised board
3. `privileged_extract` — extracts the target capability from the SubDAO's vault
4. `UnpauseSubDAOExecution` — unfreezes the SubDAO

The SubDAO is paused for zero real time. There is no window for preemptive action.

---

## 6. Spinout

`SpinOutSubDAO` destroys the `SubDAOControl`, clears the SubDAO's `controller_cap_id`, and enables hierarchy-altering proposal types (`SpawnDAO`, `CreateSubDAO`, `SpinOutSubDAO`). The SubDAO becomes fully independent and self-governing. This is irreversible.

---

## 7. Composability Invariants

These invariants keep the organizational graph well-formed:

| Invariant | Rationale |
|---|---|
| Controlled SubDAO cannot enable `SpawnDAO`, `SpinOutSubDAO`, `CreateSubDAO` | Prevents unilateral independence or hierarchy manipulation |
| `controller_cap_id` set at creation, cleared at spinout | Direct on-chain reference to control relationship |
| Only one `SubDAOControl` per SubDAO ID | Prevents conflicting controllers |
| `controller_paused`: set/cleared only via `privileged_submit` with valid `SubDAOControl` | Controller-exclusive pause authority |
| When `controller_paused == true`, `proposal::execute` aborts for all types | Complete execution freeze |
| `SpinOutSubDAO` clears `controller_paused` to `false` | Clean independence |
| The SubDAOControl graph must be acyclic | Prevents mutual-replacement deadlocks |
| Each SubDAO has at most one controller | Single `SubDAOControl` per SubDAO ID |

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

The protocol does not impose a single organizational topology. Any directed acyclic graph of DAOs connected by `SubDAOControl` edges is valid, subject to the invariants above. This means the same framework that governs a 3-person startup can scale to a multi-department organization — the primitives compose.

> **Lateral composition** (multi-membership via independent capabilities) and **upward composition** (federations) are stretch features. See [stretch/07 Lateral Composition](stretch/07_lateral_composition.md) and [stretch/01 Federation](stretch/01_federation.md).

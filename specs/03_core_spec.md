# 03 — Core Technical Specification

> **Scope**: This document covers only hackathon-scope features. For federation, project funding, direct/weighted governance, and other post-hackathon features, see the [stretch features index](stretch/00_index.md).

## 1. Core Objects

### 1.1 `DAO`

The root shared object. All governance, treasury, capability, and charter references are stored here.

```rust
struct DAO has key {
    id:                  UID,
    governance:          GovernanceConfig,
    treasury_id:         ID,                         // → TreasuryVault (separate shared object)
    capabilities_id:     ID,                         // → CapabilityVault (separate shared object)
    charter_id:          ID,                         // → Charter (separate shared object)
    emergency_freeze_id: ID,                         // → EmergencyFreeze (separate shared object)
    enabled_proposals:   VecSet<TypeName>,
    proposal_configs:    Table<TypeName, ProposalConfig>,
    last_executed_ms:    Table<TypeName, u64>,        // cooldown tracking
    controller_cap_id:   Option<ID>,                  // SubDAOControl that governs this DAO (none = independent)
    controller_paused:   bool,                        // when true, all execution blocked
    status:              DAOStatus,
    metadata_ipfs:       String,                     // IPFS CID for DAO metadata
    created_at_ms:       u64,
}

DAOStatus = Active | Migrating { successor_dao_id: ID }
```

**Separate shared objects:** `TreasuryVault`, `CapabilityVault`, `Charter`, and `EmergencyFreeze` are independently shared. The `DAO` stores only their object IDs. This enables concurrent access: treasury deposits, proposal voting, and capability operations proceed in parallel without serializing behind a single lock.

### 1.2 `TreasuryVault`

Multi-coin treasury. Stores `Balance<T>` via dynamic fields keyed by `TypeName`.

```rust
struct TreasuryVault has key {
    id:         UID,
    dao_id:     ID,
    coin_types: VecSet<TypeName>,   // registry of coin types with non-zero balances
    // dynamic fields: TypeName -> Balance<T>
}
```

**API:**
- `deposit<T>(vault, coin)` — permissionless. First deposit uses `dynamic_field::add`; subsequent deposits use `borrow_mut` + `balance::join`.
- `withdraw<T, P>(vault, amount, &ExecutionRequest<P>, ctx) → Coin<T>` — `public(friend)`, requires governance authorization.
- `claim_coin<T>(vault, Receiving<Coin<T>>)` — permissionless recovery of directly-transferred coins.
- `balance<T>(vault) → u64` — read-only query.

Zero-balance withdrawals remove the dynamic field and `TypeName` from `coin_types`.

### 1.3 `CapabilityVault`

Stores arbitrary `key + store` capabilities via dynamic object fields keyed by object ID.

```rust
struct CapabilityVault has key {
    id:        UID,
    dao_id:    ID,
    cap_types: VecSet<TypeName>,
    cap_ids:   VecMap<TypeName, vector<ID>>,
    // dynamic object fields: ID -> C (where C: key + store)
}
```

**API:**
- `store_cap_init<C>(vault, cap)` — `public(friend)`, DAO initialization only.
- `store_cap<C, P>(vault, cap, &ExecutionRequest<P>)` — governance-gated storage.
- `borrow_cap<C, P>(vault, cap_id, &ExecutionRequest<P>) → &C` — immutable borrow.
- `borrow_cap_mut<C, P>(vault, cap_id, &ExecutionRequest<P>) → &mut C` — mutable borrow.
- `loan_cap<C, P>(vault, cap_id, &ExecutionRequest<P>) → (C, CapLoan)` — temporary extraction with guaranteed return.
- `return_cap<C>(vault, cap, loan)` — consumes `CapLoan`, re-stores capability.
- `extract_cap<C, P>(vault, cap_id, &ExecutionRequest<P>) → C` — permanent removal (migration/destruction only).
- `privileged_extract<C>(vault, cap_id, &SubDAOControl) → C` — controller reclaim, `public(friend)`.
- `contains(vault, cap_id) → bool`, `ids_for_type(vault, type_name) → &vector<ID>` — queries.

### 1.4 `Charter`

Constitutional document reference. See [05 Charter](05_charter.md) for full design.

```rust
struct Charter has key {
    id:                UID,
    dao_id:            ID,
    current_blob_id:   String,                    // Walrus blob ID
    content_hash:      vector<u8>,                // SHA-256 of content
    version:           u64,
    amendment_history: vector<AmendmentRecord>,
    created_at_ms:     u64,
}
```

### 1.5 `EmergencyFreeze`

Circuit breaker for proposal execution. Managed via governance proposals that loan the `FreezeAdminCap` from the `CapabilityVault`.

```rust
struct EmergencyFreeze has key {
    id:                     UID,
    dao_id:                 ID,
    frozen_types:           VecSet<TypeName>,
    freeze_expiry_ms:       Table<TypeName, u64>,
    max_freeze_duration_ms: u64,
}

struct FreezeAdminCap has key, store {
    id:        UID,
    freeze_id: ID,
}
```

`FreezeAdminCap` is stored in the DAO's `CapabilityVault` at creation — it is **never wallet-owned**. Freeze and unfreeze are exercised through governance proposals that `loan_cap` the capability.

- Freeze: governance proposal loans `FreezeAdminCap`, calls `emergency::freeze_type`. Expiry = `now + max_freeze_duration_ms`.
- Unfreeze: governance proposal (`UnfreezeProposalType`) or any proposal that loans the cap.
- Auto-expiry: expired freezes are treated as inactive.
- `TransferFreezeAdmin` and `UnfreezeProposalType` **cannot** be frozen.

### 1.6 `SubDAOControl`

```rust
struct SubDAOControl has key, store {
    id:        UID,
    subdao_id: ID,
}
```

Stored in controller's `CapabilityVault`. One per SubDAO. Enables `privileged_submit`, board replacement, pause, and capability reclaim. See [04 SubDAO Hierarchy](04_subdao_hierarchy.md) for full design.

### 1.7 Hot Potatoes

```rust
struct ExecutionRequest<phantom P> { dao_id: ID, proposal_id: ID }
// abilities: none

struct CapLoan { cap_id: ID, type_name: TypeName, dao_id: ID, vault_id: ID }
// abilities: none
```

Both must be consumed in the same PTB they are created.

---

## 2. Module Architecture

The system is split across three Move packages with distinct upgrade cadences:

```
dao-framework/                  -- core package, stable, rarely upgraded
├── dao.move                    // DAO object, creation, config reads, destroy
├── governance.move             // GovernanceConfig enum and helpers
├── governance_config/
│   └── board.move              // Board governance: eligibility, vote-count
├── treasury.move               // TreasuryVault: deposit, withdraw, balance, claim
├── capability_vault.move       // CapabilityVault: store, borrow, loan, extract, privileged_extract
├── charter.move                // Charter: creation, reads, amendment handler support
├── proposal.move               // Proposal<P>: create, vote, expire, execute dispatch
└── emergency.move              // EmergencyFreeze: freeze_type, unfreeze_type, is_frozen

dao-proposals/                  -- builtin proposal set, upgradable independently
├── admin_ops.move              // UpdateProposalConfig, EnableProposalType, DisableProposalType,
│                               //   UpdateMetadata, TransferFreezeAdmin, UnfreezeProposalType
├── treasury_ops.move           // SendCoin<T>, SendCoinToDAO<T>
├── board_ops.move              // SetBoard
├── subdao_ops.move             // CreateSubDAO, SpinOutSubDAO, TransferCapToSubDAO,
│                               //   ReclaimCapFromSubDAO, PauseSubDAOExecution, UnpauseSubDAOExecution
└── charter_ops.move            // AmendCharter, RenewCharterStorage

demo-proposals/                 -- example extension package, shows third-party extensibility
└── ...                         // Custom proposal types demonstrating the open type system
```

**Why three packages?**

- **`dao-framework`** contains the core objects, proposal engine, and governance primitives. It defines the `ExecutionRequest<P>` hot potato and the `Proposal<P>` generic — but is agnostic to any concrete proposal type. This package should be stable and upgraded infrequently.
- **`dao-proposals`** depends on `dao-framework` and houses the builtin proposal types (admin, treasury, board, subdao, charter). Because proposals are typed via `P: store`, this package can be upgraded independently to add, fix, or refine proposal handlers without touching core.
- **`demo-proposals`** depends on `dao-framework` (and optionally `dao-proposals`) to demonstrate that **any third-party package** can define new proposal types. This showcases the open extensibility model — a DAO can `EnableProposalType` for types defined outside the builtin set.

### Module Dependency Rules

- `proposal.move` depends on `governance.move` and nothing in `dao-proposals/`.
- Modules in `dao-proposals/` depend on `dao-framework` (`proposal.move`, `treasury.move`, `capability_vault.move`, etc.) — never on each other.
- `governance_config/` modules depend only on `governance.move`.
- `dao.move` depends on all other `dao-framework` modules and is the only public entry-point module for DAO creation.
- `demo-proposals/` depends on `dao-framework`; it must not depend on `dao-proposals/` internals (only on public types if reusing payloads).

---

## 3. Governance Model: Board (Hackathon Scope)

Governance model is a sealed enum set at creation. The governance **type** is immutable; the governance **state** is mutable through authorized proposals.

```rust
GovernanceConfig has store =
    | Board    { members: VecSet<address>, seat_count: u8 }
```

> Direct and Weighted governance variants are stretch features — see [stretch/02 Governance Models](stretch/02_governance_models.md).

- **Proposer eligibility:** Current board members only.
- **Vote counting:** Each member has one vote. Pass condition: `(yes + no) * 10000 >= quorum * member_count` AND `yes * 10000 / (yes + no) >= approval_threshold`.
- **Recommended:** `quorum = 1` (effectively disabled for small boards), `approval_threshold` carries the decision logic.
- **`SetBoard`:** Atomic full-slate board replacement. No incremental add/remove.

---

## 4. Proposal System

### 4.1 `ProposalConfig`

```rust
struct ProposalConfig has copy, drop, store {
    quorum:             u16,   // basis points [1, 10000]
    approval_threshold: u16,   // basis points [5000, 10000]
    propose_threshold:  u64,   // min weight/role to submit
    expiry_ms:          u64,   // ≥ 3,600,000 (1 hour)
    execution_delay_ms: u64,   // ≥ 0 (0 = immediate)
    cooldown_ms:        u64,   // ≥ 0 (0 = no cooldown)
}
```

### 4.2 `Proposal<P>`

```rust
struct Proposal<P: store> has key {
    id:                    UID,
    dao_id:                ID,
    proposer:              address,
    metadata_ipfs:         String,
    payload:               P,
    vote_snapshot:         VecMap<address, u64>,
    total_snapshot_weight: u64,
    votes_cast:            VecMap<address, bool>,
    yes_weight:            u64,
    no_weight:             u64,
    config:                ProposalConfig,    // snapshot at creation
    created_at_ms:         u64,
    passed_at_ms:          Option<u64>,
    status:                ProposalStatus,
}

ProposalStatus = Active | Passed | Executed | Expired
```

### 4.3 Lifecycle

1. **Create** — `proposal::create<P>(dao, payload, metadata, ctx)`. Asserts type enabled, proposer eligible, builds vote snapshot.
2. **Vote** — `proposal::vote<P>(proposal, vote, ctx)`. Records vote, checks pass condition. If met, `status = Passed`.
3. **Expire** — `proposal::try_expire<P>(proposal, clock)`. If past `expiry_ms` and still `Active`, set `Expired`.
4. **Execute** — `proposal::execute<P>(proposal, dao, freeze, clock, ctx) → ExecutionRequest<P>`.
   - Asserts `status == Passed`.
   - Asserts `dao.status == Active`.
   - Asserts `controller_paused == false` (exempt for pause/unpause types).
   - Asserts not frozen (or freeze expired). `TransferFreezeAdmin` and `UnfreezeProposalType` exempt.
   - Asserts `execution_delay_ms` elapsed since `passed_at_ms`.
   - Asserts `cooldown_ms` elapsed since last execution of this type.
   - Asserts executor is eligible (board member for Board governance).
   - Sets `status = Executed`, updates `last_executed_ms`.
   - Returns `ExecutionRequest<P>` hot potato.

**Status transitions:** `Active → Passed/Expired`, `Passed → Executed`. One-directional, irreversible.

**Retry on failure:** If a handler aborts, the PTB reverts (including the `Executed` write). Proposal remains `Passed` and can be retried.

### 4.4 `privileged_submit` (Controller Bypass)

When a controller DAO executes a proposal that targets a SubDAO:
1. Controller's handler calls `loan_cap` to extract `SubDAOControl` + `CapLoan`.
2. Calls `privileged_submit<P>(control, subdao, payload, ctx)` — creates proposal in `Passed` status directly.
3. SubDAO's handler consumes the SubDAO's `ExecutionRequest`.
4. `SubDAOControl` returned via `return_cap`.
5. Controller's `ExecutionRequest` consumed.

Two hot potatoes alive simultaneously in the same PTB.

---

## 5. Hackathon Proposal Type Registry

18 proposal types across 5 modules.

### 5.1 Admin & Governance (`admin.move`)

| # | Type | Default | Safety Rail |
|---|---|---|---|
| 1 | `UpdateProposalConfig` | ✅ | 80% floor when self-referential |
| 2 | `EnableProposalType` | ✅ | 66% floor; SubDAO blocklist for hierarchy types |
| 3 | `DisableProposalType` | ✅ | Cannot disable itself, `EnableProposalType`, `TransferFreezeAdmin`, `UnfreezeProposalType` |
| 4 | `UpdateMetadata` | ✅ | — |
| 5 | `TransferFreezeAdmin` | ✅ | Cannot be frozen or disabled |
| 6 | `UnfreezeProposalType` | ✅ | Cannot be frozen or disabled |

### 5.2 Treasury (`treasury_ops.move`)

| # | Type | Default |
|---|---|---|
| 7 | `SendCoin<T>` | ✅ |
| 8 | `SendCoinToDAO<T>` | ⬜ opt-in |

### 5.3 Board (`board_ops.move`)

| # | Type | Default |
|---|---|---|
| 9 | `SetBoard` | ✅ (Board only) |

### 5.4 SubDAO & Hierarchy (`subdao_ops.move`)

| # | Type | Default |
|---|---|---|
| 10 | `CreateSubDAO` | ⬜ opt-in |
| 11 | `SpinOutSubDAO` | ⬜ opt-in |
| 12 | `TransferCapToSubDAO` | ⬜ opt-in |
| 13 | `ReclaimCapFromSubDAO` | ⬜ opt-in |
| 14 | `PauseSubDAOExecution` | 🔒 `privileged_submit` only |
| 15 | `UnpauseSubDAOExecution` | 🔒 `privileged_submit` only |

### 5.5 Charter (`charter_ops.move`)

| # | Type | Default |
|---|---|---|
| 16 | `AmendCharter` | ⬜ opt-in (recommended 80% threshold) |
| 17 | `RenewCharterStorage` | ⬜ opt-in (lower threshold OK) |

### 5.6 Freeze Config (`admin.move`)

| # | Type | Default |
|---|---|---|
| 18 | `UpdateFreezeConfig` | ⬜ opt-in |

---

## 6. Consolidated Invariants

### Governance

| Invariant |
|---|
| Governance type is immutable. |
| Governance state mutations are `public(friend)`, callable only from handler code. |
| `proposal::create<P>` aborts if `TypeName::get<P>()` not in `enabled_proposals`. |
| `EnableProposalType` cannot be disabled. `DisableProposalType` cannot disable itself. |
| `UpdateProposalConfig` self-referential: 80% floor at execution. |
| `EnableProposalType`: 66% floor at execution. |
| `ProposalConfig` validation: `quorum ∈ [1, 10000]`, `approval_threshold ∈ [5000, 10000]`, `expiry_ms ≥ 3,600,000`. |

### Proposals

| Invariant |
|---|
| `ExecutionRequest<P>` has no `drop`/`store`/`copy`. Must be consumed in same PTB. |
| `CapLoan` has no `drop`/`store`/`copy`. `return_cap` verifies `cap_id` match. |
| Status transitions are monotonic: `Active → Passed/Expired`, `Passed → Executed`. |
| `vote_snapshot` and `total_snapshot_weight` are write-once at creation. |
| Executor eligibility: Board → current member. |
| `Passed` proposals that abort on execution remain `Passed` and retryable. |

### Treasury

| Invariant |
|---|
| `withdraw` is `public(friend)`, requires `ExecutionRequest`. |
| `coin_types` exactly reflects non-zero `Balance<T>` dynamic fields. |
| No `Balance<T>` with value zero may exist. Zero-balance withdrawal removes both field and registry entry. |

### Capability Vault

| Invariant |
|---|
| All vault access (borrow, loan, extract) requires `ExecutionRequest`. |
| `cap_types` reflects stored types. `cap_ids` maps types to complete ID lists. |
| `loan_cap` does NOT update registries (ID considered "held" during loan). |
| `privileged_extract` requires `&SubDAOControl` and asserts `control.subdao_id == vault.dao_id`. |

### SubDAO

| Invariant |
|---|
| Controlled SubDAO cannot enable `SpawnDAO`, `SpinOutSubDAO`, `CreateSubDAO`. |
| `controller_cap_id` set at creation, cleared at spinout. |
| Only one `SubDAOControl` per SubDAO ID. |
| `controller_paused`: set/cleared only via `privileged_submit` with valid `SubDAOControl`. |
| When `controller_paused == true`, `proposal::execute` aborts for all types. |
| `SpinOutSubDAO` clears `controller_paused` to `false`. |

### Charter

| Invariant |
|---|
| `Charter.version` is monotonically increasing. |
| `AmendCharter` records both previous and new blob IDs in `amendment_history`. |
| `RenewCharterStorage` changes `current_blob_id` without incrementing version. |

### DAO Lifecycle

| Invariant |
|---|
| `DAOStatus` transitions: `Active → Migrating`. No path back. |
| While `Migrating`, only `TransferAssets` can be created/executed. |
| `dao::destroy` requires `Migrating` status AND empty vaults. |
| After destruction, in-flight proposals are unexecutable (DAO object gone). |

---

## 7. Events

All state-changing operations emit events for indexer consumption. Key events:

| Event | Emitter | Key Fields |
|---|---|---|
| `DAOCreated` | `dao::create` | `dao_id`, governance model, `charter_id`, `treasury_id` |
| `ProposalCreated` | `proposal::create` | `dao_id`, `proposal_id`, `TypeName`, proposer |
| `VoteCast` | `proposal::vote` | `proposal_id`, voter, vote, yes_weight, no_weight |
| `ProposalPassed` | `proposal::vote` | `proposal_id`, `passed_at_ms` |
| `ProposalExecuted` | `proposal::execute` | `proposal_id`, executor |
| `ProposalExpired` | `proposal::try_expire` | `proposal_id` |
| `SubDAOCreated` | `CreateSubDAO` handler | `parent_dao_id`, `subdao_id`, `control_id` |
| `SubDAOSpunOut` | `SpinOutSubDAO` handler | `controller_dao_id`, `subdao_id` |
| `CharterAmended` | `AmendCharter` handler | `dao_id`, `charter_id`, `version`, `new_blob_id` |
| `CoinClaimed` | `treasury::claim_coin` | `vault_id`, coin type, amount |
| `TypeFrozen` | `emergency::freeze_type` | `freeze_id`, `TypeName`, expiry |
| `TypeUnfrozen` | `emergency::unfreeze_type` | `freeze_id`, `TypeName` |
| `CapabilityTransferred` | `TransferCapToSubDAO` | `from_vault`, `to_vault`, `cap_id`, `TypeName` |
| `CapabilityReclaimed` | `ReclaimCapFromSubDAO` | `from_vault`, `to_vault`, `cap_id`, `TypeName` |

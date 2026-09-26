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
- `withdraw<T, P>(vault, amount, &ExecutionRequest<P>, ctx) → Coin<T>` — requires a request for this DAO carrying `TREASURY_WITHDRAW` (§4.5). `withdraw_multicoin<P>` is gated the same way.
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
Every request-taking function asserts the vault belongs to the request's DAO, then the request's permission bits (§4.5):

- `store_cap_init<C>(vault, cap)` — `public(package)`, DAO initialization only.
- `store_cap<C, P>(vault, cap, &ExecutionRequest<P>)` — requires `VAULT_STORE`.
- `borrow_cap<C, P>(vault, cap_id, &ExecutionRequest<P>) → &C` — immutable borrow, requires `VAULT_BORROW`.
- `borrow_cap_mut<C, P>(vault, cap_id, &ExecutionRequest<P>) → &mut C` — mutable borrow, requires `VAULT_BORROW`.
- `loan_cap<C, P>(vault, cap_id, &ExecutionRequest<P>) → (C, CapLoan)` — temporary extraction with guaranteed return, requires `VAULT_BORROW`.
- `return_cap<C>(vault, cap, loan)` — consumes `CapLoan`, re-stores capability.
- `extract_cap<C, P>(vault, cap_id, &ExecutionRequest<P>) → C` — permanent removal, requires `VAULT_EXTRACT`. `create_subdao_control` / `destroy_subdao_control` also require `VAULT_EXTRACT`.
- `receive_cap<C, P>(vault, cap, &ExecutionRequest<P>)` — cross-DAO receive; requires `VAULT_EXTRACT` on the **sending** DAO's request and does not check the receiving DAO. `receive_cap_authorized<C, Send, Recv>` also requires `VAULT_STORE` on a request from the receiving DAO.
- `borrow_external_cap<P>(vault, dao_id, cap_id) → &ExternalExecutionCap<P>` — ungated; the cap is bearer authority for bypass execution (see the bypass caveat in §4.5).
- `privileged_extract<C>(vault, cap_id, &SubDAOControl) → C` — controller reclaim, authorized by the `SubDAOControl`.
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
struct ExecutionRequest<phantom P> {
    dao_id:      ID,
    proposal_id: ID,
    permissions: u64,   // P's slot bits when the request was minted
    privileged:  bool,  // true only for controller::privileged_submit
}
// abilities: none

struct CapLoan { cap_id: ID, type_name: TypeName, dao_id: ID, vault_id: ID }
// abilities: none
```

Both must be consumed in the same PTB they are created. An `ExecutionRequest` authorizes only the mutations its `permissions` name, or any mutation on its SubDAO if `privileged` (§4.5).

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
    composable_allowed: bool,  // may appear as a composite step; default false
    permissions:        u64,   // armature::permissions bits; default 0 (deny)
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

1. **Create** — `board_voting::submit_proposal<P>(dao, metadata, payload, clock, ctx)`. Asserts type enabled, proposer is a board member, config meets submission floors; records the roster version as the vote snapshot.
2. **Vote** — `board_voting::vote<P>(proposal, dao, approve, clock, ctx)`. Voter must have been a member at the snapshot; voting closes at `created_at_ms + expiry_ms`. If the pass condition is met, `status = Passed`.
3. **Expire** — `proposal::delete_expired_proposal<P>(proposal, clock)`. Anyone may delete an `Active` proposal past its voting period, or a `Passed` one whose execution window (`passed_at + execution_delay_ms + expiry_ms`) has closed.
4. **Execute** — `board_voting::ticket_from_vote<P>(dao, proposal, freeze, clock, ctx) → ExecutionTicket<P>`.
   - Asserts `status == Passed`, `dao.status == Active` (or `Migrating` for `TransferAssets`), type still enabled.
   - Asserts `controller_paused == false` and execution not paused.
   - Asserts `P` not frozen. `TransferFreezeAdmin` and `UnfreezeProposalType` cannot be frozen.
   - Asserts `execution_delay_ms` elapsed and the execution window open.
   - Asserts `cooldown_ms` elapsed since last execution of this type.
   - Asserts executor is a current board member.
   - Deletes the `Proposal`, emits `ProposalExecuted`, updates `last_executed_ms`.
   - Returns a ticket holding the payload and an `ExecutionRequest<P>` whose `permissions` are `P`'s slot bits **now** (at execution, not submission).
5. **Handle** — the type's handler calls gated mutators with `ticket.ticket_request()`; each aborts `EPermissionDenied` unless the request holds its bit. `ticket.discharge()` ends the PTB.

The single-PTB paths (`submit_vote_execute`, `ticket_from_cap`, `composite::advance_step`) create no `Proposal` object but mint the request the same way: its bits are read from `P`'s slot at mint time.

**Status transitions:** `Active → Passed` is the only stored transition. Execution and expiry delete the proposal (`ProposalExecuted` / `ProposalExpired` events).

**Retry on failure:** If a handler aborts, the PTB reverts (including the deletion). Proposal remains `Passed` and can be retried while its execution window is open.

### 4.4 `privileged_submit` (Controller Bypass)

When a controller DAO executes a proposal that targets a SubDAO:
1. Controller's handler calls `loan_cap` to extract `SubDAOControl` + `CapLoan`.
2. Calls `privileged_submit<P>(control, subdao, type_key, metadata, payload, ctx)` — no `Proposal` object; returns a SubDAO `ExecutionRequest<P>` with `privileged = true` and `permissions = 0`.
3. SubDAO mutators accept the privileged request whatever its bits; `set_controller_paused` and `clear_controller` accept **only** privileged requests.
4. `SubDAOControl` returned via `return_cap`.
5. Controller's `ExecutionRequest` consumed.

Two hot potatoes alive simultaneously in the same PTB. The controller's own request must carry `VAULT_BORROW` to loan the `SubDAOControl` in step 1.

### 4.5 Permissions

`ProposalConfig.permissions` names the DAO-wide mutations a type's requests may perform. Deny-by-default.

| Bit | Floor | Guards |
|---|---|---|
| `BOARD_ADD` | — | `add_board_member(s)_governance` |
| `BOARD_REMOVE` | — | `remove_board_member(s)_governance` |
| `BOARD_SET` | — | `set_board_governance` |
| `TYPE_ADMIN` | 80% | `enable_proposal_type`, `disable_proposal_type`, `update_proposal_config` |
| `PAUSE` | — | `set_execution_paused` |
| `MIGRATE` | 80% | `set_migrating` |
| `METADATA` | — | `charter::update_metadata` |
| `TREASURY_WITHDRAW` | 80% | `treasury_vault::withdraw`, `withdraw_multicoin` |
| `VAULT_STORE` | — | `store_cap`; receiver side of `receive_cap_authorized` |
| `VAULT_BORROW` | 80% | `borrow_cap`, `borrow_cap_mut`, `loan_cap` |
| `VAULT_EXTRACT` | 80% | `extract_cap`, `create/destroy_subdao_control`, sender side of `receive_cap(_authorized)` |
| `FREEZE` | — | `governance_unfreeze_type`, `update_freeze_duration`, `unfreeze_all`, `add/remove_freeze_exempt_type` |

- **Check.** Mutators in `dao` call `dao::assert_permitted(bits, req)` (DAO id, then bits). The vault, charter, emergency and tribe modules cannot import `dao`, so they check their own `dao_id` and then `proposal::assert_permitted(req, bits)`. Denial aborts `proposal::EPermissionDenied` (21). A privileged request passes every bit check.
- **Floors.** `dao::permission_floor(bits)` is 80% if the config holds `TYPE_ADMIN`, `MIGRATE`, `TREASURY_WITHDRAW`, `VAULT_BORROW` or `VAULT_EXTRACT`. `dao` enforces it, together with the per-type floors (80% for `EnableProposalType`, `UpdateProposalConfig`, `EnableBypassType`), on every config it stores (`EThresholdBelowMinimum`).
- **Fixed framework bits.** Framework payload types (`dao::is_framework_type`) always hold exactly `dao::framework_permissions`; a config naming other bits aborts `EFixedPermissions` (23). Table: `packages/armature_framework/internal_workings.md` §9.1.
- **Grants.** Only `EnableProposalType`, `EnableBypassType` or `UpdateProposalConfig` requests (all 80%), or a privileged request, may change a type's bits (`EPermissionChangeNotAllowed`, 19). Grants are standalone-only: composites refuse grant steps (`EUseTypedStep`, `EGrantInComposite`). Other types get bits from their enabling config; `armature_proposals::type_permissions` lists what each built-in type needs.
- **Mint time.** Requests carry the bits their slot held when minted, so a grant or revocation applies from the next execution.
- **Bypass caveat.** A bypass type's bits are usable by anyone who can build its payload: `borrow_external_cap` is public and `ticket_from_cap` does not check the sender. A bypass-enabled `MintAllowance<T>` (public constructor) is therefore open minting — ARMATURE-31, not yet fixed. Bypass types should keep their payload constructors private.

---

## 5. Hackathon Proposal Type Registry

18 proposal types across 5 modules.

### 5.1 Admin & Governance (`admin.move`)

| # | Type | Default | Safety Rail |
|---|---|---|---|
| 1 | `UpdateProposalConfig` | ✅ | 80% floor; may change bits |
| 2 | `EnableProposalType` | ✅ | 80% floor; may grant bits; SubDAO blocklist for hierarchy types |
| 3 | `DisableProposalType` | ✅ | 80% floor (`TYPE_ADMIN`); cannot disable itself, `EnableProposalType`, the bypass meta-types, `TransferFreezeAdmin`, `UnfreezeProposalType` |
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
| `EnableProposalType`, `UpdateProposalConfig`, `EnableBypassType`: 80% floor on every stored config (`dao::min_approval_threshold_for_type`). |
| Every stored config meets `dao::permission_floor(permissions)`. |
| `ProposalConfig` validation: `quorum ∈ [1, 10000]`, `approval_threshold ∈ [5000, 10000]`, `expiry_ms ≥ 3,600,000`. |

### Proposals

| Invariant |
|---|
| `ExecutionRequest<P>` has no `drop`/`store`/`copy`. Must be consumed in same PTB. |
| `ExecutionRequest.permissions` equals `P`'s slot bits at mint time; `privileged` is true only from `controller::privileged_submit`. |
| `CapLoan` has no `drop`/`store`/`copy`. `return_cap` verifies `cap_id` match. |
| Status transitions are monotonic: `Active → Passed`; execution and expiry delete the proposal. |
| `vote_snapshot` and `total_snapshot_weight` are write-once at creation. |
| Executor eligibility: Board → current member. |
| `Passed` proposals that abort on execution remain `Passed` and retryable. |

### Permissions

| Invariant |
|---|
| Every framework mutator taking an `ExecutionRequest` checks the request's DAO, then its bits (or `privileged`); CI (`scripts/check_request_gates.py`) fails on an ungated one. |
| `set_controller_paused` / `clear_controller` accept only privileged requests (`dao::ENotPrivileged`). |
| Framework types hold exactly `dao::framework_permissions`; no config changes them. |
| Only `EnableProposalType`, `EnableBypassType`, `UpdateProposalConfig` or a privileged request change a type's bits; never inside a composite. |
| Composite steps do not pool bits: each step's request carries its own type's bits. |
| A bypass type's bits are exercisable by anyone who can construct its payload (ARMATURE-31). |

### Treasury

| Invariant |
|---|
| `withdraw` / `withdraw_multicoin` require a request of this DAO carrying `TREASURY_WITHDRAW`. |
| `coin_types` exactly reflects non-zero `Balance<T>` dynamic fields. |
| No `Balance<T>` with value zero may exist. Zero-balance withdrawal removes both field and registry entry. |

### Capability Vault

| Invariant |
|---|
| Store requires `VAULT_STORE`; borrow and loan require `VAULT_BORROW`; extract and SubDAOControl create/destroy require `VAULT_EXTRACT`. `borrow_external_cap` is the only ungated read of a stored cap. |
| `cap_types` reflects stored types. `cap_ids` maps types to complete ID lists. |
| `loan_cap` does NOT update registries (ID considered "held" during loan). |
| `privileged_extract` requires `&SubDAOControl` and asserts `control.subdao_id == vault.dao_id`. |

### SubDAO

| Invariant |
|---|
| Controlled SubDAO cannot enable `SpawnDAO`, `SpinOutSubDAO`, `CreateSubDAO`. |
| `controller_cap_id` set at creation, cleared at spinout. |
| Only one `SubDAOControl` per SubDAO ID. |
| `controller_paused`: set/cleared only via a privileged request from `privileged_submit` with valid `SubDAOControl` (`dao::assert_controller`). |
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
| `ProposalExpired` | `proposal::delete_expired_proposal` | `proposal_id` |
| `SubDAOCreated` | `CreateSubDAO` handler | `parent_dao_id`, `subdao_id`, `control_id` |
| `SubDAOSpunOut` | `SpinOutSubDAO` handler | `controller_dao_id`, `subdao_id` |
| `CharterAmended` | `AmendCharter` handler | `dao_id`, `charter_id`, `version`, `new_blob_id` |
| `CoinClaimed` | `treasury::claim_coin` | `vault_id`, coin type, amount |
| `TypeFrozen` | `emergency::freeze_type` | `freeze_id`, `TypeName`, expiry |
| `TypeUnfrozen` | `emergency::unfreeze_type` | `freeze_id`, `TypeName` |
| `CapabilityTransferred` | `TransferCapToSubDAO` | `from_vault`, `to_vault`, `cap_id`, `TypeName` |
| `CapabilityReclaimed` | `ReclaimCapFromSubDAO` | `from_vault`, `to_vault`, `cap_id`, `TypeName` |

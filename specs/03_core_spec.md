# 03 — Core Technical Specification

> **Scope**: This document describes the framework as implemented in `packages/armature_framework` and the first-party extension packages. Features that are designed but not built (federation, Walrus-backed charters, charter parametrization, other governance models) are in the [stretch features index](stretch/00_index.md). Per-function detail lives in [`internal_workings.md`](../packages/armature_framework/internal_workings.md); per-type bits and floors in [`docs/proposal-types.md`](../docs/proposal-types.md); package placement in [`docs/package-boundaries.md`](../docs/package-boundaries.md).

## 1. Core Objects

### 1.1 `DAO`

The root shared object. It holds the governance roster, lifecycle flags and the IDs of its companion objects.

```rust
struct DAO has key, store {
    id:                  UID,
    status:              DAOStatus,
    governance:          GovernanceConfig,            // table-backed board roster (§3)
    treasury_id:         ID,                          // → TreasuryVault (separate shared object)
    capability_vault_id: ID,                          // → CapabilityVault (separate shared object)
    charter_id:          ID,                          // → Charter (separate shared object)
    emergency_freeze_id: ID,                          // → EmergencyFreeze (separate shared object)
    execution_paused:    bool,                        // set via the PAUSE bit
    controller_cap_id:   Option<ID>,                  // SubDAOControl that governs this DAO (none = independent)
    controller_paused:   bool,                        // when true, all execution blocked
    encrypt_epoch:       u64,                         // Seal key epoch; bumps on any member removal
    entries:             vector<ID>,                  // EncryptedEntry index, at most 32
}

DAOStatus = Active | Migrating { successor_dao_id: ID }
```

**Separate shared objects:** `TreasuryVault`, `CapabilityVault`, `Charter`, and `EmergencyFreeze` are independently shared. The `DAO` stores only their object IDs. This enables concurrent access: treasury deposits, proposal voting, and capability operations proceed in parallel without serializing behind a single lock.

**Proposal-type registry.** The registry is not stored on the root. Each enabled type is one dynamic field on the DAO's `UID`, keyed by the payload's canonical `TypeName` (`type_name::with_defining_ids<P>()`):

```rust
TypeSlot { name: TypeName }  →  ProposalType {
    display_key:      ascii::String,   // human label, unique per DAO, no authority
    config:           ProposalConfig,
    last_executed_ms: Option<u64>,     // cooldown tracking
}
DisplayKey { key: ascii::String }  →  TypeName   // reverse index for admin paths
```

- The payload type `P` selects the slot on every submission and execution path, so a payload can never be submitted under another type's config and no caller-supplied type key exists to spoof.
- Display keys label types in events and in admin payloads that name a type (`UpdateProposalConfig.target_type_key`, `DisableProposalType.type_key`, `DisableBypassType.type_key`); `dao::type_for_display_key` resolves them.
- The root stays a few hundred bytes however many types are enabled, so the hot path writes the root plus one slot.
- Registry changes emit `TypeSlotAdded`, `TypeSlotRemoved` and `TypeSlotConfigUpdated`, carrying the full type name, display key and config. They fire for the default slots at creation too.
- Construction-time slot overrides are `ProposalTypeInit` values built with `dao::new_type_init<T>(display_key, config)`.

Type-state (per-type persistent data such as `SmallPaymentState` or an autojoin allowlist) is another dynamic field on the DAO, keyed by the owning type's bare `TypeName`.

### 1.2 `TreasuryVault`

Multi-coin treasury. Coin balances are dynamic fields keyed by coin type name; multicoin balances (the `multicoin` package) are a two-level dynamic-object-field tree.

```rust
struct TreasuryVault has key, store {
    id:                         UID,
    dao_id:                     ID,
    coin_types:                 VecSet<ascii::String>,  // coin types with a non-zero balance
    multicoin_collection_count: u64,
    // dynamic fields:        coin type name -> Balance<T>
    // dynamic object fields: CollectionKey { collection_id } -> CollectionRecord
    //                        --AssetKey { asset_id }--> MultiCoinBalance
}
```

**API:**
- `deposit<T>(vault, coin, ctx)` — permissionless. A zero-value coin is destroyed as a no-op.
- `withdraw<T, P>(vault, amount, &ExecutionRequest<P>, ctx) → Coin<T>` — requires a request for this DAO carrying `TREASURY_WITHDRAW` (§4.5). `withdraw_multicoin<P>` is gated the same way.
- `deposit_multicoin(vault, balance, ctx)` — permissionless.
- `claim_coin<T>(vault, Receiving<Coin<T>>, ctx)` — permissionless recovery of coins transferred directly to the vault's address.
- `balance<T>`, `multicoin_balance`, `collection_item_count`, `is_empty` — read-only queries.

A withdrawal that empties a balance removes the dynamic field and the `coin_types` entry. Events: `CoinDeposited`, `CoinWithdrawn`, `CoinClaimed`, `MultiCoinDeposited`, `MultiCoinWithdrawn`.

### 1.3 `CapabilityVault`

Stores arbitrary `key + store` capabilities as dynamic object fields keyed by object ID.

```rust
struct CapabilityVault has key, store {
    id:          UID,
    dao_id:      ID,
    cap_types:   VecSet<ascii::String>,
    cap_ids:     VecSet<ID>,
    ids_by_type: VecMap<ascii::String, vector<ID>>,
    // dynamic object fields: ID -> C (where C: key + store)
}
```

**API:**
Every request-taking function asserts the vault belongs to the request's DAO, then the request's permission bits (§4.5):

- `store_cap_init<C>(vault, cap)` — `public(package)`, DAO initialization only.
- `store_cap<C, P>(vault, cap, &ExecutionRequest<P>)` — requires `VAULT_STORE`.
- `borrow_cap<C, P>(vault, cap_id, &ExecutionRequest<P>) → &C` — immutable borrow; requires `VAULT_BORROW` and `C` in the request's `borrow_scope`.
- `borrow_cap_mut<C, P>(vault, cap_id, &ExecutionRequest<P>) → &mut C` — mutable borrow; same checks.
- `loan_cap<C, P>(vault, cap_id, &ExecutionRequest<P>) → (C, CapLoan)` — temporary extraction with guaranteed return; same checks.
- `return_cap<C>(vault, cap, loan)` — consumes `CapLoan`, checks the cap ID and vault ID, re-stores the capability.
- `extract_cap<C, P>(vault, cap_id, &ExecutionRequest<P>) → C` — permanent removal, requires `VAULT_EXTRACT`. `create_subdao_control` / `destroy_subdao_control` also require `VAULT_EXTRACT`.
- `receive_cap<C, P>(vault, cap, &ExecutionRequest<P>)` — cross-DAO receive; requires `VAULT_EXTRACT` on the **sending** DAO's request and does not check the receiving DAO. `receive_cap_authorized<C, Send, Recv>` also requires `VAULT_STORE` on a request from the receiving DAO.
- `borrow_external_cap<P>(vault, dao_id, cap_id) → &ExternalExecutionCap<P>` — ungated read. The cap is the DAO's opt-in to bypass execution, not a bearer credential: only `P`'s own module can mint a bypass ticket with it (§4.7).
- `privileged_extract<C>(vault, cap_id, &SubDAOControl) → C` — controller reclaim; checks `control.subdao_id == vault.dao_id`.
- `contains(vault, cap_id)`, `ids_for_type<C>(vault) → vector<ID>`, `cap_types`, `cap_ids`, `is_empty` — queries.

### 1.4 `Charter`

The DAO's name and a pointer to its off-chain metadata. See [05 Charter](05_charter.md).

```rust
struct Charter has key, store {
    id:           UID,
    dao_id:       ID,
    name:         String,
    metadata_uri: String,   // IPFS CID / URI of the DAO's metadata document
}
```

The only mutator is `charter::update_metadata<P>(charter, new_metadata_uri, &ExecutionRequest<P>)`, which requires `METADATA` and is reached through the `UpdateMetadata` proposal type (default display key `CharterUpdate`). A Walrus-backed charter with versioned amendments is a design, not implemented.

### 1.5 `EmergencyFreeze`

Circuit breaker for proposal execution, keyed by Move type.

```rust
struct EmergencyFreeze has key, store {
    id:                     UID,
    dao_id:                 ID,
    frozen_types:           VecMap<TypeName, u64>,   // TypeName -> expiry_ms
    max_freeze_duration_ms: u64,                     // default 7 days
    freeze_exempt_types:    VecSet<TypeName>,
}

struct FreezeAdminCap has key, store {
    id:     UID,
    dao_id: ID,
}
```

**Custody.** `dao::create` transfers the `FreezeAdminCap` to the creator. The tribe constructors send each SubDAO's cap to the address named for it, and `tribe::create_wired_subdao` to `freeze_admin`. A SubDAO created by a `CreateSubDAO` proposal has its cap stored in the parent's `CapabilityVault`; `SpinOutSubDAO` moves it into the spun-out DAO's own vault.

- **Freeze:** the cap holder calls `emergency::freeze_type<P>(freeze, &cap, clock)` directly; no proposal is involved. Expiry = `now + max_freeze_duration_ms`; freezing an already-frozen type refreshes its expiry.
- **Unfreeze:** the cap holder calls `unfreeze_type<P>(freeze, &cap)`, or governance passes `UnfreezeProposalType`. `TransferFreezeAdmin` unfreezes every type and hands the cap to a new admin; its handler takes the cap by value, so the executing PTB must supply it.
- **Auto-expiry:** a freeze whose expiry has passed is treated as inactive.
- **Keyed by type:** entries use the payload's canonical `TypeName`, the same key as the registry, so freezing `PlaceLimitOrder<CRED>` blocks only that instantiation. `assert_not_frozen<P>` runs on the two-PTB, atomic, bypass and composite-step paths.
- **Governance changes** (unfreeze a type, change the max duration, unfreeze all, edit the exempt set) require the `FREEZE` bit.
- **Mandatory exemptions:** `TransferFreezeAdmin` and `UnfreezeProposalType` can never be frozen or removed from the exempt set. They are matched by the framework's own struct types, so a same-named type in another package gets no exemption.

### 1.6 `SubDAOControl`

```rust
struct SubDAOControl has key, store {
    id:        UID,
    subdao_id: ID,
}
```

Stored in the controller's `CapabilityVault`. The framework's creation paths (`CreateSubDAO`, `tribe::create_tribe(_configured)`, `tribe::create_wired_subdao`) mint one per SubDAO and record its ID in the SubDAO's `controller_cap_id`. Holding it enables `controller::privileged_submit` and `capability_vault::privileged_extract`; both check that `control.subdao_id` names the target DAO. See [04 SubDAO Hierarchy](04_subdao_hierarchy.md).

### 1.7 Hot Potatoes

```rust
struct ExecutionRequest<phantom P> {
    dao_id:       ID,
    proposal_id:  ID,
    permissions:  u64,               // P's slot bits when the request was minted
    borrow_scope: vector<TypeName>,  // P's slot borrow scope when the request was minted
    privileged:   bool,              // true only for controller::privileged_submit
}

struct ExecutionTicket<P> {          // what handlers receive
    request:  ExecutionRequest<P>,
    payload:  P,
    closeout: Closeout,              // Standalone { proposal_id, yes_weight, total_snapshot_weight } | Composite | External
}

struct CapLoan { cap_id: ID, vault_id: ID }
// abilities: none (all three)
```

All must be consumed in the PTB that created them. An `ExecutionRequest` authorizes only the mutations its `permissions` name, borrows only the cap types in its `borrow_scope`, or does anything on its SubDAO if `privileged` (§4.5). Other hot potatoes: `composite::Pipeline` (§4.8), `lifecycle_ops::AssetTransfer` (`TransferAssets`), `upgrade_ops::PendingUpgrade` (`ProposeUpgrade`).

---

## 2. Module Architecture

The system is split across Move packages with distinct upgrade cadences. The placement rule, and why the package boundary is the trust boundary, is in [`docs/package-boundaries.md`](../docs/package-boundaries.md).

```
armature_framework/  (armature::)            -- kernel; not touched after a release
├── dao.move                // DAO object, type registry, gated DAO mutators, creation, destroy
├── governance.move         // Board roster: Table of members, tenures, roster_version
├── proposal.move           // ProposalConfig, Proposal<P>, ExecutionRequest/Ticket, ExternalExecutionCap
├── board_voting.move       // submit_proposal, vote, ticket_from_vote(_readonly), submit_vote_execute(_readonly)
├── external_execution.move // ticket_from_cap(_readonly); EnableBypassType / DisableBypassType handlers
├── composite.move          // CompositeFrame + Pipeline
├── controller.move         // privileged_submit / privileged_consume (SubDAOControl override)
├── permissions.move        // permission bits
├── treasury_vault.move     // TreasuryVault
├── capability_vault.move   // CapabilityVault, CapLoan, SubDAOControl
├── charter.move            // Charter
├── emergency.move          // EmergencyFreeze, FreezeAdminCap
├── tribe.move              // create_tribe(_configured), create_wired_subdao
├── encrypted_entry.move    // Seal-encrypted entries for board members
├── spend_guard.move        // rolling-epoch spend limit building block
├── utils.move              // bps math, saturating_add
├── types/                  // the 20 framework payload types (SetBoard, AddMember, …, CompositePayload)
└── handlers/               // admin_ops, board_ops, member_ops, lifecycle_ops, freeze_ops

armature_proposals/  (armature_proposals::)  -- first-party extension; asset operations
├── treasury/               // SendCoin, SendCoinToDAO, SendSmallPayment, SendBatchMulticoinTo{Address,DAO}; treasury_ops
├── currency/               // AdoptCurrency, MintCoin, MintAllowance, ConfigureMintAllowance, BurnCoin, ReturnCurrencyCap; currency_ops
├── subdao/                 // TransferCapToSubDAO, ReclaimCapFromSubDAO, Pause/UnpauseSubDAOExecution, ControllerBatch{Add,Remove}Members; subdao_ops
├── upgrade/                // ProposeUpgrade; upgrade_ops
└── type_permissions.move   // the bits and borrow scope each type needs when enabled

armature_world_bridge/  (armature_world_bridge::)  -- first-party extension; EVE Frontier integration
└── autojoin/               // AutojoinDAO (bypass self-join), ConfigureAutojoin, tribe allowlist

armature_external_type_tests/                -- test-only fixture, never published
└── rebalance.move          // Rebalance<T>: the third-party template
```

**Why this split?**

- **`armature_framework`** holds the objects, the execution engine, the permission model, and every payload type that changes who may do what: the type registry (Enable/Disable/UpdateProposalConfig, bypass meta-types), board membership, DAO lifecycle and cap custody (SpawnDAO, CreateSubDAO, SpinOutSubDAO, TransferAssets), charter metadata, freeze governance, and composites. The framework names these types (fixed bits, undisableable and SubDAO-blocked sets, default slots), so they cannot live anywhere else.
- **`armature_proposals`** holds asset operations inside an authority graph already set: treasury spends, currency custody and minting, SubDAO control, upgrades. It is mechanically a third-party package. The framework gives it no `public(package)` access and no special treatment, and a DAO grants its types bits by vote like any other.
- **`armature_world_bridge`** holds EVE Frontier integration. `AutojoinDAO` is a bypass type whose mint entry authenticates the joiner by character ownership and a tribe allowlist.
- **`armature_external_type_tests`** shows that any package can define proposal types: `Rebalance<T>` is enabled by vote through the production handlers and executed on every path.

A type's package is a one-way door: a type's identity is its defining package, so moving it later creates a new type that every DAO must re-enable.

### Module Dependency Rules

- `proposal.move` depends on `governance.move`, `permissions.move` and `utils.move`, and on nothing in extension packages.
- `dao.move` constructs the treasury, capability vault, charter and freeze, so those modules cannot import it. They check requests with `proposal::assert_permitted` against their own `dao_id`; `dao`'s own mutators use `dao::assert_permitted`.
- Framework handlers live in `sources/handlers/`, beside the framework types in `sources/types/`. Only the framework can mint those types' `Permit`s.
- Extension handlers live beside their payload types, in the same package, because spending a ticket takes `std::internal::Permit<P>`.
- Extension packages depend on `armature_framework` only. Nothing in the framework depends on an extension.

---

## 3. Governance Model: Board

Board is the only governance model. The roster is mutable through authorized proposals.

```rust
struct GovernanceConfig has store {
    members:        Table<address, Member>,   // kept after a member leaves
    member_count:   u64,
    roster_version: u64,                      // +1 per membership change (a batch counts once)
}
struct Member has drop, store { tenures: vector<Tenure> }
struct Tenure has copy, drop, store { joined: u64, left: Option<u64> }   // roster versions

GovernanceTypeInit = InitBoard { initial_members: vector<address> }
```

- The roster lives in a `Table`, so the DAO root does not grow with the board.
- Every member records the versions at which they joined and left. A proposal records the roster version current at its creation (`snapshot_version`) instead of copying the roster.
- **Proposer eligibility:** current board members only.
- **Voter eligibility:** a member at the proposal's `snapshot_version` (`governance::was_member_at`). Members added later cannot vote; members removed later still can.
- **Executor eligibility:** current board members (vote path).
- **Vote counting:** each member has one vote (`BOARD_MEMBER_VOTE_WEIGHT = 1`). Pass condition: `(yes + no) > 0` AND `(yes + no) * 10000 >= quorum * total_snapshot_weight` AND `yes * 10000 >= approval_threshold * (yes + no)`, where `total_snapshot_weight` is the member count at creation.
- **Membership changes:** `SetBoard { to_add, to_remove }` applies an add/remove diff as one roster change (the roster table cannot be enumerated, so there is no full-slate replacement). `AddMember` / `RemoveMember` change one address. `BatchAddMembers` adds up to 100 and skips existing members; `BatchRemoveMembers` removes atomically. The board can never become empty. Any removal increments `encrypt_epoch`.

> Direct and Weighted governance were removed from the code. A weighted model would need each member's weight at every past roster version, which this layout does not keep. See [stretch/02 Governance Models](stretch/02_governance_models.md).

---

## 4. Proposal System

### 4.1 `ProposalConfig`

```rust
struct ProposalConfig has copy, drop, store {
    quorum:             u16,               // basis points [1, 10000]
    approval_threshold: u16,               // basis points [5000, 10000]
    propose_threshold:  u64,               // min proposer weight (board members have 1)
    expiry_ms:          u64,               // ≥ 3,600,000 (1 hour); voting period and execution window length
    execution_delay_ms: u64,               // ≥ 0 (0 = immediate)
    cooldown_ms:        u64,               // ≥ 0 (0 = no cooldown)
    composable_allowed: bool,              // may appear as a composite step; default false
    permissions:        u64,               // armature::permissions bits; default 0 (deny)
    borrow_scope:       vector<TypeName>,  // cap types a VAULT_BORROW request may reach; default empty
}
```

Build with `proposal::new_config(quorum, approval_threshold, propose_threshold, expiry_ms, execution_delay_ms, cooldown_ms)` and the builders `with_composable_allowed`, `with_permissions` and `with_borrow_scope`. There is no upper bound on `expiry_ms` or `execution_delay_ms`: deadlines saturate at `u64::MAX`, which means "never expires". The `admin_ops` and `external_execution` handlers refuse a config that combines `cooldown_ms > 0` with `composable_allowed = true` (`EComposableCooldownConflict`). Creation-time overrides of already-seeded types keep the seeded `composable_allowed` and do not run that check.

Default slots start at quorum 50%, threshold 50% (raised to the type's floors, §4.5), 7-day expiry, no delay, no cooldown, and the type's fixed bits.

### 4.2 `Proposal<P>`

```rust
struct Proposal<P: store> has key {
    id:                    UID,
    dao_id:                ID,
    type_key:              ascii::String,     // display key at submission (label only)
    proposer:              address,
    metadata_ipfs:         Option<String>,
    payload:               P,
    snapshot_version:      u64,               // roster version at creation
    total_snapshot_weight: u64,               // member count at creation
    votes_cast:            VecMap<address, bool>,
    yes_weight:            u64,
    no_weight:             u64,
    config:                ProposalConfig,    // snapshot of the slot's config at creation
    created_at_ms:         u64,
    passed_at_ms:          Option<u64>,
    status:                ProposalStatus,
}

ProposalStatus = Active | Passed
```

A `Proposal` exists only on the two-PTB vote path (and for a composite). Execution and expiry delete it; `Executed` and `Expired` are not stored statuses but the `ProposalExecuted` and `ProposalExpired` events.

### 4.3 Lifecycle (two-PTB vote path)

1. **Create** — `board_voting::submit_proposal<P>(dao, metadata_ipfs, payload, clock, ctx)`. Asserts `P` is enabled, the DAO is `Active` (or `Migrating` for `TransferAssets`), the proposer is a board member, and the config meets submission floors; records the roster version as the vote snapshot and shares the `Proposal<P>`.
2. **Vote** — `board_voting::vote<P>(proposal, dao, approve, clock, ctx)`. The voter must have been a member at the snapshot; voting closes at `created_at_ms + expiry_ms` (`EVotingClosed`). If the pass condition is met, `status = Passed`.
3. **Expire** — `proposal::delete_expired_proposal<P>(proposal, clock)`. Anyone may delete an `Active` proposal past its voting period, or a `Passed` one whose execution window (`passed_at + execution_delay_ms + expiry_ms`) has closed. The storage rebate goes to that transaction's gas payer.
4. **Execute** — `board_voting::ticket_from_vote<P>(dao, proposal, freeze, clock, ctx) → ExecutionTicket<P>`, taking the proposal by value.
   - Asserts `status == Passed`, `dao.status == Active` (or `Migrating` for `TransferAssets`), type still enabled.
   - Asserts `controller_paused == false` and execution not paused.
   - Asserts `P` not frozen. `TransferFreezeAdmin` and `UnfreezeProposalType` cannot be frozen.
   - Asserts `execution_delay_ms` elapsed and the execution window open.
   - Asserts `cooldown_ms` elapsed since last execution of this type.
   - Asserts executor is a current board member.
   - Deletes the `Proposal`, emits `ProposalExecuted`, updates the slot's `last_executed_ms`.
   - Returns a ticket holding the payload and an `ExecutionRequest<P>` whose `permissions` and `borrow_scope` are `P`'s slot values **now** (at execution, not submission).
   - `ticket_from_vote_readonly` takes `&DAO` and records nothing; it requires `cooldown_ms == 0` on both the slot and the snapshot.
5. **Handle** — only `P`'s handler can spend or close the ticket. `ticket_request(permit)` and `discharge(permit)` take `std::internal::Permit<P>`, which only the module defining `P` can mint; a package whose handlers live beside the type exposes it as `public(package) fun permit()`. The handler reads the arguments for each gated mutator from the payload; each mutator aborts `EPermissionDenied` unless the request holds its bit. `discharge` closes the ticket.

   A ticket holder therefore cannot pass the request to a mutator with arguments of their own choosing (a larger `amount`, another recipient, other board members, another cap). Permission bits bound what a type's handler may touch; the permit binds who may spend the request, and so which arguments it is spent with.

**Status transitions:** `Active → Passed` is the only stored transition. Execution and expiry delete the proposal (`ProposalExecuted` / `ProposalExpired` events).

**Retry on failure:** If a handler aborts, the PTB reverts (including the deletion). The proposal remains `Passed` and can be retried while its execution window is open.

**Execution paths.** Every path mints the request from `P`'s slot at mint time:

| Path | Entry point | `Proposal` object | Bits | `privileged` | Section |
|---|---|---|---|---|---|
| Two-PTB vote | `ticket_from_vote(_readonly)` | shared, deleted on execution | slot | false | §4.3 |
| Atomic single vote | `submit_vote_execute(_readonly)` | none (events only) | slot | false | §4.6 |
| Bypass | `ticket_from_cap(_readonly)` | none (events only) | slot | false | §4.7 |
| Composite step | `composite::advance_step<P>` | one `Proposal<CompositePayload>` | the step type's slot | false | §4.8 |
| Controller override | `controller::privileged_submit` | none (events only) | 0 | true | §4.4 |

### 4.4 `privileged_submit` (Controller Override)

When a controller DAO executes a proposal that targets a SubDAO:
1. The controller's handler calls `loan_cap` to take the `SubDAOControl` and a `CapLoan`. The controller's own request must carry `VAULT_BORROW` with `SubDAOControl` in its borrow scope.
2. It calls `privileged_submit<P>(control, subdao, type_key, metadata_ipfs, payload, ctx)` (`P: store + drop`). This creates no `Proposal` object: it emits `ProposalCreated`, `ProposalPayloadCreated` and `ProposalExecuted` (no `ProposalPassed`) and returns a SubDAO `ExecutionRequest<P>` with `privileged = true`, no bits and an empty scope. `type_key` is a free-form label here, since `P` may have no slot on the SubDAO.
3. SubDAO mutators accept the privileged request whatever its bits; `set_controller_paused` and `clear_controller` accept **only** privileged requests.
4. The handler closes the request with `controller::privileged_consume(req, &control)` and returns the `SubDAOControl` with `return_cap`.
5. The controller's own ticket is discharged.

Two hot potatoes are alive at once in the same PTB: the controller's ticket and the SubDAO's privileged request.

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
| `VAULT_BORROW` | 80% | `borrow_cap`, `borrow_cap_mut`, `loan_cap`, limited to the cap types in the config's `borrow_scope` (`EBorrowScopeDenied`, 22) |
| `VAULT_EXTRACT` | 80% | `extract_cap`, `create/destroy_subdao_control`, sender side of `receive_cap(_authorized)` |
| `FREEZE` | — | `governance_unfreeze_type`, `update_freeze_duration`, `unfreeze_all`, `add/remove_freeze_exempt_type` |

- **Check.** Mutators in `dao` call `dao::assert_permitted(bits, req)` (DAO id, then bits). The vault, charter, emergency and tribe modules cannot import `dao`, so they check their own `dao_id` and then `proposal::assert_permitted(req, bits)`. Denial aborts `proposal::EPermissionDenied` (21). A privileged request passes every bit check. Type-state accessors (`init_type_state`, `borrow_type_state_mut`, `remove_type_state`) are scoped to the request's own `P` and need no bit.
- **Floors.** `dao::permission_floor(bits)` is 80% if the config holds `TYPE_ADMIN`, `MIGRATE`, `TREASURY_WITHDRAW`, `VAULT_BORROW` or `VAULT_EXTRACT`. `dao` enforces it, together with the per-type floors (80% for `EnableProposalType`, `UpdateProposalConfig`, `EnableBypassType`), on every config it stores (`EThresholdBelowMinimum`).
- **Fixed framework bits.** Framework payload types (`dao::is_framework_type`) always hold exactly `dao::framework_permissions`; a config naming other bits aborts `EFixedPermissions` (23). Table: `packages/armature_framework/internal_workings.md` §9.1.
- **Grants.** Only `EnableProposalType`, `EnableBypassType` or `UpdateProposalConfig` requests (all 80%), or a privileged request, may change a type's bits (`EPermissionChangeNotAllowed`, 19). Grants are standalone-only: composites refuse grant steps (`EUseTypedStep`, `EGrantInComposite`). Other types get bits from their enabling config; `armature_proposals::type_permissions` lists what each built-in type needs.
- **Mint time.** Requests carry the bits their slot held when minted, so a grant or revocation applies from the next execution.
- **Borrow scope.** `ProposalConfig.borrow_scope` lists the capability types a `VAULT_BORROW` request may borrow or loan (deny-by-default, empty borrows nothing). It is copied into the request at mint time, checked by the vault after the bit, fixed for framework types (`dao::framework_borrow_scope`), and changed only under the grant rules above (a scope change counts as a VAULT_BORROW grant; never in a composite).
- **Bypass-safe bits.** A bypass ticket is never minted for a type holding `TYPE_ADMIN`, `MIGRATE`, `VAULT_EXTRACT` or `FREEZE` (`external_execution::bypass_forbidden_bits`, `EBypassForbiddenBits` 15): `ticket_from_cap` checks the slot on every mint, and `EnableBypassType` refuses a payload config holding them. A framework type's fixed bits are applied after that enable-time check, so bypass-enabling one that holds a forbidden bit (e.g. `SpawnDAO`) succeeds but can never mint.
- **Bypass authorization.** `borrow_external_cap` is public and `ticket_from_cap` does not check the sender, but it takes `Permit<P>`: only `P`'s module can mint a bypass ticket, so that module's mint entry is the authorization point. `MintAllowance<T>` is minted only by `currency_ops::mint_allowance_bypass`, gated by the `ConfigureMintAllowance<T>` allowlist (ARMATURE-31). Placement rules: `docs/package-boundaries.md`.

### 4.6 Atomic Single-Vote Execution (`submit_vote_execute`)

`board_voting::submit_vote_execute<P>(dao, metadata_ipfs, payload, freeze, clock, ctx) → ExecutionTicket<P>` submits, casts the proposer's YES vote and executes in one PTB. It is meant for operational types on boards where one member's vote passes on its own.

- **No object.** No `Proposal` is created, owned or shared. The proposal ID is minted from `ctx.fresh_object_address()`, and the events a shared proposal would emit over its life are the audit record, in order: `ProposalCreated`, `ProposalPayloadCreated`, `VoteCast`, `ProposalPassed`, `ProposalExecuted`.
- **Checks.** Everything `submit_proposal` and `ticket_from_vote` check: DAO status, `P` enabled, proposer is a current member, the EnableProposalType floor, propose threshold, not controller-paused, not frozen, not execution-paused, cooldown elapsed. In addition:
  - `execution_delay_ms` must be 0 (`EDelayForbidsAtomicExecution`).
  - The proposer's single vote must pass quorum and threshold against the current member count (`EInsufficientVotingWeight`). Threshold is always met by 1 YES and 0 NO; quorum is met when `quorum * member_count <= 10000`.
- **Ticket.** A `Standalone` ticket with `yes_weight = 1` and `total_snapshot_weight = member_count`, so handler floor checks (such as `EnableBypassType`'s 80% on actual weights) behave as on the two-PTB path.
- **Read-only variant.** `submit_vote_execute_readonly` takes `&DAO` and records no last-executed time, so it requires `cooldown_ms == 0` (`ECooldownRequiresMutableDAO`). A PTB that reaches the DAO only through read-only entry points can pass it as an immutable shared input: no write lock, so concurrent single-vote executions do not contend on the DAO.
- **Trade-off.** The path removes the window between submission and execution in which other members can vote NO and the freeze admin can react. Governance-sensitive types should be configured with `execution_delay_ms > 0` so they cannot take it. This is a configuration recommendation; default configs have no delay.

### 4.7 Bypass Execution (`ticket_from_cap`)

A DAO opts a type into execution without a vote by passing `EnableBypassType`, which enables the type and stores an `ExternalExecutionCap<P>` in its vault (80% on the actual vote weights; not available on SubDAOs). `DisableBypassType` extracts and destroys the cap and disables the type.

`external_execution::ticket_from_cap<P>(cap, dao, freeze, metadata_ipfs, payload, permit: Permit<P>, clock, ctx) → ExecutionTicket<P>`:
- Checks the cap is for this DAO, the DAO is `Active`, `P` is enabled, execution and controller are not paused, the slot holds no bypass-forbidden bits, `P` is not frozen, and the cooldown has elapsed. It checks neither the sender nor board membership.
- Creates no `Proposal`; emits `ExternalExecutionCreated`, `ProposalCreated`, `ProposalPayloadCreated`, `ProposalExecuted`. Returns an `External` ticket carrying the slot's bits and scope.
- Takes `Permit<P>`, so only `P`'s module can call it. The type's mint entry runs its own authorization before minting: `autojoin_ops::autojoin` checks character ownership and a tribe allowlist; `currency_ops::mint_allowance_bypass` checks a minter allowlist and per-call cap. The ticket never leaves those functions.
- `ticket_from_cap_readonly` takes `&DAO` and requires `cooldown_ms == 0`.

### 4.8 Composite Proposals

A composite bundles up to 16 typed steps under one vote.

1. `composite::new_frame(dao_id, ctx)`, then `add_step<P>(frame, dao, payload)` per step. A step's type must be enabled and `composable_allowed`; `CompositePayload` cannot nest. `EnableProposalType` and `UpdateProposalConfig` steps must use `add_enable_proposal_type_step` / `add_update_proposal_config_step`, which refuse any change to bits or scope.
2. `submit_composite(dao, frame, metadata_ipfs, clock, ctx)` seals and shares the frame and creates a `Proposal<CompositePayload>`. Its quorum, approval threshold, execution delay and cooldown are the max across the `Composite` slot and every step's config; propose threshold and expiry come from the `Composite` slot. `EnableProposalType` and `UpdateProposalConfig` steps force at least 80%.
3. After the vote passes, `ticket_from_vote<CompositePayload>` → `begin_pipeline(dao, frame, ticket) → Pipeline`.
4. `advance_step<P>(dao, frame, pipeline, freeze, clock) → (ExecutionTicket<P>, Pipeline)` for each step in order, passing each ticket to that type's ordinary handler. Each step is freeze-checked, and its ticket carries only its own type's bits and scope: bits never pool across steps. Steps are not checked against their type's cooldown (`begin_pipeline` records a last-executed snapshot that nothing reads); cooldown-bearing types are meant to stay out of composites through the exclusion in §4.1. Each step does record its type's execution time.
5. `finalize_pipeline(pipeline)`. Afterwards anyone can call `delete_exhausted_frame(frame)` for the storage rebate.

---

## 5. Proposal Type Registry

About 40 types across three packages. Bits and floors per type: [`docs/proposal-types.md`](../docs/proposal-types.md).

**Default** = seeded on every new DAO (✅), seeded on independent DAOs but not SubDAOs (✅*), or opt-in (⬜). **Undisableable** types cannot be removed by `DisableProposalType`. **SubDAO-blocked** types cannot be enabled on a DAO that has a controller.

### 5.1 Type Registry and Bypass (framework, `admin_ops` / `external_execution`)

| Type | Default | Safety rail |
|---|---|---|
| `EnableProposalType` | ✅ | 80% floor; may grant bits; pins the Move type; undisableable |
| `DisableProposalType` | ✅ | 80% floor (`TYPE_ADMIN`); undisableable; cannot disable the undisableable types |
| `UpdateProposalConfig` | ✅ | 80% floor; may change bits and scope; cannot change a framework type's bits |
| `EnableBypassType` | ✅* | 80% floor on actual vote weights; refuses bypass-forbidden bits; undisableable; SubDAO-blocked |
| `DisableBypassType` | ✅* | 80% floor (`TYPE_ADMIN`); undisableable; SubDAO-blocked |

### 5.2 Board and Metadata (framework, `board_ops` / `member_ops` / `admin_ops`)

| Type | Default |
|---|---|
| `SetBoard` | ✅ |
| `AddMember`, `RemoveMember` | ✅ |
| `BatchAddMembers`, `BatchRemoveMembers` | ✅ |
| `UpdateMetadata` (display key `CharterUpdate`) | ✅ |

### 5.3 Freeze Governance (framework, `freeze_ops`)

| Type | Default | Safety rail |
|---|---|---|
| `TransferFreezeAdmin` | ✅ | Cannot be frozen or disabled; unfreezes all on transfer |
| `UnfreezeProposalType` | ✅ | Cannot be frozen or disabled |
| `UpdateFreezeConfig` | ⬜ | Fixed `FREEZE` |
| `UpdateFreezeExemptTypes` | ⬜ | Fixed `FREEZE`; cannot remove the mandatory exemptions |

### 5.4 Lifecycle and Hierarchy (framework, `lifecycle_ops`)

| Type | Default | Safety rail |
|---|---|---|
| `CreateSubDAO` | ⬜ | 80%; SubDAO-blocked |
| `SpinOutSubDAO` | ⬜ | 80%; SubDAO-blocked; borrow scope fixed to `SubDAOControl` |
| `SpawnDAO` | ⬜ | 80%; SubDAO-blocked; moves the DAO to `Migrating` |
| `TransferAssets` | ⬜ | 80%; the only type allowed while `Migrating`; ≤ 50 assets |
| `CompositePayload` (display key `Composite`) | ✅ | No bits; see §4.8 |

### 5.5 Treasury (`armature_proposals::treasury_ops`)

| Type | Default |
|---|---|
| `SendCoin<T>`, `SendCoinToDAO<T>` | ⬜ |
| `SendSmallPayment<T>` (rolling-epoch cap in type-state) | ⬜ |
| `SendBatchMulticoinToAddress`, `SendBatchMulticoinToDAO` | ⬜ |

All hold `TREASURY_WITHDRAW`, so every config for them needs 80%.

### 5.6 Currency (`armature_proposals::currency_ops`)

| Type | Default |
|---|---|
| `AdoptCurrency<T>` | ⬜ |
| `MintCoin<T>`, `MintAllowance<T>` (bypass-capable) | ⬜ |
| `ConfigureMintAllowance<T>` (minter allowlist for the `MintAllowance<T>` bypass) | ⬜ |
| `BurnCoin<T>`, `ReturnCurrencyCap<T>` | ⬜ |

### 5.7 SubDAO Control (`armature_proposals::subdao_ops`)

Proposed on the controller DAO; the SubDAO-side effect runs on a privileged request (§4.4).

| Type | Default |
|---|---|
| `TransferCapToSubDAO`, `ReclaimCapFromSubDAO` | ⬜ |
| `PauseSubDAOExecution`, `UnpauseSubDAOExecution` | ⬜ |
| `ControllerBatchAddMembers`, `ControllerBatchRemoveMembers` | ⬜ |

### 5.8 Upgrade (`armature_proposals::upgrade_ops`)

| Type | Default |
|---|---|
| `ProposeUpgrade` (loans the `UpgradeCap`; `commit_upgrade` returns it in the same PTB) | ⬜ |

### 5.9 World Bridge (`armature_world_bridge`)

| Type | Default |
|---|---|
| `AutojoinDAO` (bypass; `BOARD_ADD` only) | ⬜ |
| `ConfigureAutojoin` (tribe allowlist and kill switch in type-state) | ⬜ |

---

## 6. Consolidated Invariants

### Governance

| Invariant |
|---|
| Board is the only governance model; the roster is mutated only by `dao` mutators gated on `BOARD_ADD`, `BOARD_REMOVE` or `BOARD_SET` (or a privileged request). |
| `roster_version` increases by one per membership change; a former member's entry is kept, closed. |
| A voter must have been a member at the proposal's `snapshot_version`; the executor on the vote path must be a current member. |
| The board is never empty. |
| Any member removal increments `encrypt_epoch`. |
| Submission, execution and bypass paths select the type's slot by `P`; a type without a slot aborts `ETypeNotEnabled`. |
| Display keys are non-empty and unique per DAO. |
| `DisableProposalType`'s handler refuses to disable `EnableProposalType`, `DisableProposalType`, `EnableBypassType`, `DisableBypassType`, `TransferFreezeAdmin` or `UnfreezeProposalType` (`admin_ops::EUndisableableType`). `dao::disable_proposal_type` itself checks only `TYPE_ADMIN`. |
| `EnableProposalType`, `UpdateProposalConfig`, `EnableBypassType`: 80% floor on every stored config (`dao::min_approval_threshold_for_type`). |
| Every stored config meets `dao::permission_floor(permissions)`. |
| `ProposalConfig` validation: `quorum ∈ [1, 10000]`, `approval_threshold ∈ [5000, 10000]`, `expiry_ms ≥ 3,600,000`. |

### Proposals

| Invariant |
|---|
| `ExecutionRequest<P>` and `ExecutionTicket<P>` have no `drop`/`store`/`copy`. They must be consumed in the same PTB. |
| Only `P`'s defining module (or its package via a `public(package)` permit helper) can spend or close an `ExecutionTicket<P>` or mint a bypass ticket for `P`. |
| `ExecutionRequest.permissions` and `borrow_scope` equal `P`'s slot values at mint time; `privileged` is true only from `controller::privileged_submit`. |
| `CapLoan` has no abilities. `return_cap` verifies the cap ID and vault ID. |
| The only stored status transition is `Active → Passed`; execution and expiry delete the proposal. |
| `snapshot_version`, `total_snapshot_weight` and `config` are write-once at creation. |
| Votes are refused after `created_at_ms + expiry_ms`; a passed proposal executes only within `passed_at + execution_delay_ms + expiry_ms`. Deadlines saturate. |
| `Passed` proposals whose handler aborts remain `Passed` and retryable within their window. |
| Single-PTB executions (atomic, bypass, controller) create no `Proposal` object and emit the lifecycle events under a fresh ID. |
| The atomic path requires `execution_delay_ms == 0`; read-only entry points require `cooldown_ms == 0`. |

### Permissions

| Invariant |
|---|
| Every framework mutator taking an `ExecutionRequest` checks its bits (or `privileged`), and the request's DAO against its target. The exceptions to the DAO check are `capability_vault::receive_cap` and the sending request of `receive_cap_authorized`: for a cross-DAO move the sending DAO's request is the authority. CI (`scripts/check_request_gates.py`) fails on an ungated mutator. |
| `borrow_cap`, `borrow_cap_mut` and `loan_cap` also require the cap type in the request's `borrow_scope` (or `privileged`). |
| `set_controller_paused` / `clear_controller` accept only privileged requests (`dao::ENotPrivileged`). |
| Framework types hold exactly `dao::framework_permissions` and `dao::framework_borrow_scope`; no config changes them. |
| Only `EnableProposalType`, `EnableBypassType`, `UpdateProposalConfig` or a privileged request change a type's bits or scope; never inside a composite. |
| Composite steps do not pool bits: each step's request carries its own type's bits and scope. |
| No bypass ticket is minted for a slot holding `TYPE_ADMIN`, `MIGRATE`, `VAULT_EXTRACT` or `FREEZE` (checked at every `ticket_from_cap`); `EnableBypassType` also refuses a payload config holding them. |

### Treasury

| Invariant |
|---|
| `withdraw` / `withdraw_multicoin` require a request of this DAO carrying `TREASURY_WITHDRAW`. |
| `coin_types` exactly reflects non-zero `Balance<T>` dynamic fields. |
| No `Balance<T>` with value zero may exist. Zero-balance withdrawal removes both field and registry entry. |

### Capability Vault

| Invariant |
|---|
| Store requires `VAULT_STORE`; borrow and loan require `VAULT_BORROW` plus scope; extract and SubDAOControl create/destroy require `VAULT_EXTRACT`. `borrow_external_cap` is the only ungated read of a stored cap. |
| `cap_types`, `cap_ids` and `ids_by_type` reflect the stored caps. |
| `loan_cap` does NOT update registries (ID considered "held" during loan). |
| `privileged_extract` requires `&SubDAOControl` and asserts `control.subdao_id == vault.dao_id`. |

### SubDAO

| Invariant |
|---|
| A DAO with a controller cannot enable `SpawnDAO`, `SpinOutSubDAO`, `CreateSubDAO`, `EnableBypassType` or `DisableBypassType` at creation (`dao::EBlockedProposalType`) or through the `EnableProposalType` / `EnableBypassType` handlers (`ESubDAOBlockedType`). `dao::enable_proposal_type` itself checks only `TYPE_ADMIN`, so a privileged request, or a type the SubDAO has granted `TYPE_ADMIN`, is not bound by the list. |
| `controller_cap_id` is set when the SubDAO is shared and cleared at spin-out. |
| `privileged_submit` requires a `&SubDAOControl` whose `subdao_id` is the target DAO (`EControlMismatch`) and an `Active` target. |
| `controller_paused` is set or cleared only by a privileged request (`dao::assert_controller`). |
| When `controller_paused == true`, the SubDAO's vote, atomic and bypass paths abort; only the controller's privileged path still runs (so it can unpause). |
| `SpinOutSubDAO` clears `controller_paused` to `false`. |

### Charter

| Invariant |
|---|
| `charter::update_metadata` requires a request of the charter's DAO carrying `METADATA`. |

### Emergency Freeze

| Invariant |
|---|
| Only the `FreezeAdminCap` holder for this DAO can freeze a type; a freeze lasts at most `max_freeze_duration_ms`. |
| `TransferFreezeAdmin` and `UnfreezeProposalType` are always freeze-exempt and cannot be removed from the exempt set. |
| Governance changes to the freeze require `FREEZE`. |

### DAO Lifecycle

| Invariant |
|---|
| `DAOStatus` transitions: `Active → Migrating`. No path back. |
| While `Migrating`, only `TransferAssets` can be submitted or executed; the bypass path requires `Active`. |
| `dao::destroy` requires `Migrating` status, matching companion objects, empty vaults, an empty frozen-type map and no encrypted entries. It is permissionless. |
| After destruction, in-flight proposals are unexecutable (DAO object gone). |

---

## 7. Events

All state-changing operations emit events for indexer consumption. Proposals executed on a single-PTB path exist only as events. Key events:

| Event | Emitter | Key Fields |
|---|---|---|
| `DAOCreated` | `dao` constructors | `dao_id`, `treasury_id`, `capability_vault_id`, `charter_id`, `emergency_freeze_id`, `creator` |
| `DAOBoardInitialized` | `dao` constructors | `dao_id`, `initial_members` |
| `TypeSlotAdded` / `TypeSlotConfigUpdated` | `dao` | `dao_id`, `type_name`, `display_key`, `config` (incl. bits and scope) |
| `TypeSlotRemoved` | `dao` | `dao_id`, `type_name`, `display_key` |
| `ProposalCreated` | `proposal` (every path) | `proposal_id`, `dao_id`, `type_key` (display key), `proposer`, `metadata_ipfs` |
| `ProposalPayloadCreated` | `proposal` (every path) | `proposal_id`, `dao_id`, `payload_bcs` |
| `VoteCast` | `proposal` (vote, atomic) | `proposal_id`, `dao_id`, `voter`, `approve`, `weight` |
| `ProposalPassed` | `proposal` (vote, atomic) | `proposal_id`, `dao_id`, `yes_weight`, `no_weight` |
| `ProposalExecuted` | `proposal` (every path) | `proposal_id`, `dao_id`, `executor` |
| `ProposalExpired` | `proposal::delete_expired_proposal` | `proposal_id`, `dao_id` |
| `ExternalExecutionCreated` | `external_execution::ticket_from_cap` | `dao_id`, `type_key`, `submitter` |
| `BypassEnabled` / `BypassDisabled` | `external_execution` | `dao_id`, `type_key`, `cap_id` |
| `CompositeSubmitted` | `composite::submit_composite` | `frame_id`, `dao_id`, `step_count`, `proposer` |
| `BoardUpdated` | `board_ops` (SetBoard) | `dao_id`, `added`, `removed` |
| `MemberAdded` / `MemberRemoved` / `MembersBatchAdded` / `MembersBatchRemoved` | `member_ops` | `dao_id`, member(s); batch add reports `added` and `skipped` |
| `SubDAOCreated` | `lifecycle_ops` (CreateSubDAO) | `controller_dao_id`, `subdao_id`, `control_cap_id` |
| `SubDAOSpunOut` | `lifecycle_ops` (SpinOutSubDAO) | `controller_dao_id`, `subdao_id` |
| `SuccessorDAOSpawned` | `lifecycle_ops` (SpawnDAO) | `origin_dao_id`, `successor_dao_id` |
| `AssetsTransferInitiated` | `lifecycle_ops` (TransferAssets) | `dao_id`, `target_dao_id`, `coin_count`, `cap_count` |
| `DAODestroyed` | `dao::destroy` | `dao_id`, `successor_dao_id` |
| `MetadataUpdated` | `admin_ops` (UpdateMetadata) | `dao_id`, `new_ipfs_cid` |
| `CoinDeposited` / `CoinWithdrawn` / `CoinClaimed` | `treasury_vault` | `vault_id`, `dao_id`, `coin_type`, `amount`, actor |
| `TypeFrozen` | `emergency::freeze_type` | `dao_id`, `type_name`, `expiry_ms` |
| `TypeUnfrozen` | `emergency` (any unfreeze) | `dao_id`, `type_name` |
| `FreezeExemptTypeAdded` / `FreezeExemptTypeRemoved` | `emergency` | `dao_id`, `type_name` |
| `FreezeAdminTransferred` | `freeze_ops` (TransferFreezeAdmin) | `dao_id`, `new_admin` |
| `CapTransferredToSubDAO` | `subdao_ops` (TransferCapToSubDAO) | `dao_id`, `cap_id`, `target_vault` |
| `CapReclaimedFromSubDAO` | `subdao_ops` (ReclaimCapFromSubDAO) | `dao_id`, `cap_id`, `subdao_id` |
| `EncryptionEpochRotated` | `dao` | `dao_id`, `old_epoch`, `new_epoch` |

`type_name` fields carry the full canonical type string, as in `TypeSlotAdded`; `type_key` fields carry the display key.

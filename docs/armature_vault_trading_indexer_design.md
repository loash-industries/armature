# Armature Vault + Trading Indexer — Design (geyser-indexer-framework)

## 1. Overview

Nothing indexes the armature protocol today. The canonical indexer going forward is the geyser-indexer-framework–based `indexer-geyser` crate in `triex-book`, which currently indexes only the TriexBook DEX, warehouse receipts, multicoin, and world contracts — it has **no** armature coverage at all. This doc defines the armature indexing work needed to build:

1. **A DEX API** letting organizations trade items (multicoin/warehouse-receipt assets) against quote currencies, scoped by DAO.
2. **Private location data sharing with ACLs** — the `armature_vault::keyspace` module is an event-sourced, role-gated encrypted-entry system built for exactly this, but today it is served by scanning GraphQL events live on every request.

This work has three parts, all landing as new pipelines in `indexer-geyser` (same framework and conventions as its existing handlers): foundational **core** coverage of `armature_framework`/`armature_proposals` (DAO registry, membership, proposals, votes, treasury — §4.1, build first), plus two new pipelines — **`armature_vault`** and **`armature_trading`** (§4.2/§4.3). Together they supply the event catalog, schema, and API surface needed to retire the ad-hoc event-scanning code currently in `triex-app-api` and add DEX endpoints currently missing from `etl-api`.

### Why this is needed now (confirmed gaps)

`triex-app-api` has explicit `@todo:add-indexer` markers doing live on-chain scans in the request path:

- [`src/routes/api/v1/organizations/$tribeId/proposals.ts`](../../../triex/triex-app-api/src/routes/api/v1/organizations/$tribeId/proposals.ts) — scans `ProposalCreated` events via RPC on every call (solved by this doc's core `armature_proposals` coverage in §4.1; should be migrated alongside the vault/trading routes).
- [`src/routes/api/v1/ssu/$ssuId/dao-vaults.ts`](../../../triex/triex-app-api/src/routes/api/v1/ssu/$ssuId/dao-vaults.ts) — scans `armature_vault` GraphQL events for DAO vault discovery, no persisted state.
- [`src/routes/api/v1/acl/accessible.ts`](../../../triex/triex-app-api/src/routes/api/v1/acl/accessible.ts) — scans `keyspace::KeyspaceCreated` / `AccessGranted` / `AccessRevoked` on every request to answer "which ACLs can this user see."

`etl-api` already indexes TriexBook fills/orders/trades (Postgres-backed, `/v1/account/:balanceMgrId/*`, `/v1/trades/recent`, `/v1/pools/*`) but has **no DAO-scoping**: no way to answer "show me org X's open orders" or "org X's trade history" without a `balance_manager_id → dao_id` mapping, which doesn't exist anywhere today. It also has zero coverage of `armature-vault` (receipt vaults, ACLs, keyspaces).

---

## 2. Data products

| Pipeline | New data products |
|---|---|
| `armature_vault` | DAO receipt-vault registry, vault ACL state (current + audit log), asset balances per vault, keyspace registry, keyspace ACL state, encrypted-entry registry (location pointers) |
| `armature_trading` | DAO ↔ BalanceManager mapping, DAO-scoped order index, DAO-scoped fill/trade history, treasury↔book settlement audit trail (deposits, sweeps) |

Both pipelines follow `indexer-geyser`'s existing handler pattern (one `Processor` + `SequentialHandler` per handler): they read Move events from `CheckpointEnvelope`, decode via BCS, and maintain Postgres tables. `armature_trading` additionally cross-references `etl-api`'s existing TriexBook order/fill tables (see §7) rather than re-indexing raw order-book mechanics.

---

## 3. Architecture

All armature pipelines are added to the `indexer-geyser` binary as additional `SequentialHandler` pipelines, registered in `main.rs` alongside its existing TriexBook/warehouse/world handlers and listed in `config.rs::PIPELINE_NAMES`. The framework's `INCLUDE_HANDLER_IDS` / `EXCLUDE_HANDLER_IDS` env vars (already used by `indexer-geyser` via `IndexerConfig::handler_filter()`) let a fresh instance backfill just the armature handlers — starting from each armature package's publish checkpoint rather than a full chain backfill — without reprocessing TriexBook history.

```
                   ┌────────────────────────────────┐
                   │   geyser-indexer-framework      │
                   │  (NATS JetStream / HTTP store)  │
                   └──────────────┬───────────────────┘
                                  │ CheckpointEnvelope
                                  ▼
    ┌────────────────────────────────────────────────────────────────┐
    │  indexer-geyser (existing handlers, unchanged)                 │
    │   • TriexBook DEX (orders, fills, pools, balances)             │
    │   • warehouse receipts, multicoin, world / character           │
    ├────────────────────────────────────────────────────────────────┤
    │  NEW: armature_core / _proposals / _treasury (SEQUENTIAL)      │
    │   • daos, dao_members, subdao_edges                            │
    │   • proposals, votes                                           │
    │   • treasury_txns                                              │
    ├────────────────────────────────────────────────────────────────┤
    │  NEW: armature_vault    (SEQUENTIAL — ACL state is mutable)    │
    │   • dao_receipt_vaults, vault_asset_balances, vault_acl        │
    │   • keyspaces, keyspace_acl, encrypted_entries                 │
    ├────────────────────────────────────────────────────────────────┤
    │  NEW: armature_trading  (SEQUENTIAL — balance-manager mapping) │
    │   • trading_accounts (dao_id ↔ balance_manager_id ↔ pool caps) │
    │   • dao_book_deposits, dao_book_sweeps (treasury↔book audit)   │
    │   • dao_order_index (dao-scoped pointer into etl-api orders)   │
    └────────────────────────────────────────────────────────────────┘
```

### Why sequential for both

**`armature_vault`**: ACL state (`VecMap<Role, vector<Principal>>`) is diffed, not appended — `AclGrantedEvent`/`AclRevokedEvent` and `AccessGranted`/`AccessRevoked` mutate a current-state table (`vault_acl`, `keyspace_acl`). A concurrent pipeline would race two grant/revoke events for the same vault landing in different checkpoints out of order. Additionally, `EntryUpdated` vs `EntryEdited` disambiguation depends on comparing the event's epoch against the keyspace's *currently committed* `version` — another read-after-committed-write dependency. Same reasoning as the `armature_core` pipeline's board-diffing logic (§4.1).

**`armature_trading`**: `trading_accounts` (DAO ↔ BalanceManager) must exist before any order/deposit/sweep event referencing that BalanceManager can be attributed to a DAO, and `SetupTradingAccount` can be followed by a deposit in the same checkpoint. Sequential guarantees insert-then-reference ordering within one transaction, matching the `armature_core` `daos`-before-`proposals` pattern (§4.1).

Event volume for both is governance-gated (every trading action is a DAO proposal execution) — far below raw DEX throughput — so sequential processing is not a bottleneck here either.

---

## 4. Event catalog

### 4.1 Core armature coverage (armature_framework / armature_proposals / armature_world_bridge) — build first

Foundational coverage the vault and trading pipelines depend on: `armature_vault` `Ou` principals resolve against `dao_members`, and every trading event resolves to a `dao_id` via the same membership/registry state. These map to three sequential pipelines — `armature_core` (`daos`, `dao_members`, `subdao_edges`), `armature_proposals` (`proposals`, `votes`), and `armature_treasury` (`treasury_txns`) — that must be implemented **before, or alongside,** §4.2/§4.3. The event catalog below is the input to that work.

| Module | Events |
|---|---|
| `armature::proposal` | `ProposalCreated`, `ProposalPayloadCreated`, `VoteCast`, `ProposalPassed`, `ProposalExecuted`, `ProposalExpired` |
| `armature::dao` | `DAOCreated`, `DAOBoardInitialized`, `EncryptionEpochRotated`, `DAODestroyed` |
| `armature::treasury_vault` | `CoinDeposited`, `CoinWithdrawn`, `CoinClaimed`, `MultiCoinDeposited`, `MultiCoinWithdrawn` |
| `armature::emergency` | `TypeFrozen`, `TypeUnfrozen`, `FreezeExemptTypeAdded`, `FreezeExemptTypeRemoved` |
| `armature::external_execution` | `ExternalExecutionCreated`, `BypassEnabled`, `BypassDisabled` |
| `armature::encrypted_entry` | `EntryPublished`, `EntryUpdated`, `EntryRemoved` *(DAO-level entries — distinct from `armature_vault::keyspace` entries, see §4.2)* |
| `armature::composite` | `CompositeSubmitted` |
| `armature_proposals::member_ops` | `MemberAdded`, `MemberRemoved`, `MembersBatchAdded`, `MembersBatchRemoved` |
| `armature_proposals::board_ops` | `BoardUpdated` |
| `armature_proposals::admin_ops` | `ProposalTypeEnabled`, `ProposalTypeDisabled`, `ProposalConfigUpdated`, `MetadataUpdated` |
| `armature_proposals::security_ops` | `FreezeAdminTransferred`, `FreezeConfigUpdated` |
| `armature_proposals::subdao_ops` | `SubDAOCreated`, `SubDAOExecutionPaused/Unpaused`, `SuccessorDAOSpawned`, `SubDAOSpunOut`, `CapTransferredToSubDAO`, `CapReclaimedFromSubDAO`, `ControllerMembersBatchAdded/Removed`, `AssetsTransferInitiated` |
| `armature_proposals::treasury_ops` | `CoinSent`, `SmallPaymentSent`, `CoinSentToDAO`, `BatchMulticoinSentToAddress/DAO` |
| `armature_proposals::currency_ops` | `CurrencyAdopted`, `CoinMinted`, `CoinBurned`, `CurrencyCapReturned` |
| `armature_proposals::upgrade_ops` | `UpgradeAuthorized` |
| `armature_world_bridge::autojoin_ops` | `MemberAutojoined` |

**Relevant non-event structures for the new pipelines:**
- `armature::proposal::ExecutionTicket<P>` / `ExecutionRequest<P>` — hot-potato pattern every trading proposal handler consumes; not itself indexed, but its presence is why every trading event is attributable to a `dao_id` and `proposal_id`.
- `armature::capability_vault::CapabilityVault` — holds `TradeCap`/`DepositCap`/`WithdrawCap` for a DAO's trading account; no events emitted by this module, so cap issuance must be inferred from `SetupTradingAccount` proposal execution in `armature_trading`.
- `armature::dao::DAO.governance` / `is_governance_member()` — used by `armature_vault::acl::Principal::Ou` satisfaction; not indexed directly, the `dao_members` table (§4.1) answers this.

### 4.2 NEW: `armature-vault` package

#### Module `armature_vault::dao_receipt_vault`

| Event | Fields | Fires when |
|---|---|---|
| `VaultInitializedEvent` | `vault_id: ID`, `registrant_dao_id: ID`, `storage_unit_id: ID`, `collection_id: ID` | `initialize_dao_vault[_v2]` |
| `VaultDeinitializedEvent` | `vault_id: ID`, `registrant_dao_id: ID`, `by: address` | `deinitialize_dao_vault` — ACL cleared, registry slot freed |
| `DepositEvent` | `vault_id: ID`, `collection_id: ID`, `asset_id: u64`, `amount: u64`, `depositor: address` | `deposit_receipt`, amount > 0 |
| `WithdrawEvent` | `vault_id: ID`, `collection_id: ID`, `asset_id: u64`, `amount: u64`, `withdrawer: address` | `withdraw_receipt`, amount > 0 |
| `AclGrantedEvent` | `vault_id: ID`, `role: Role`, `principal: Principal`, `by: address` | `grant` / `grant_edit_ou` / vault init — only on real state change |
| `AclRevokedEvent` | `vault_id: ID`, `role: Role`, `principal: Principal`, `by: address` | `revoke` — only on real state change |

`Role = Deposit | Withdraw | Edit`. `Principal = Player { addr: address } | Ou { dao_id: ID }` (shared with keyspace, `armature_vault::acl`). `Edit` role only accepts `Ou` principals (enforced on-chain) so an indexed vault's admin set is always DAO-shaped, never a bare wallet.

Non-event objects worth mirroring for lookups: `DaoReceiptVault { id, storage_unit_id, collection_id, acl, non_empty_assets, registrant_dao_id }`, keyed for discovery by `VaultKey { storage_unit_id, registrant_dao_id }` via a shared `DaoReceiptVaultRegistry`. Per-asset balances live as dynamic object fields keyed by `asset_id`, not as events — the indexer maintains running balances by summing `DepositEvent`/`WithdrawEvent` deltas rather than reading DOFs.

#### Module `armature_vault::keyspace` (private location data + generic encrypted-entry ACL)

| Event | Fields | Fires when |
|---|---|---|
| `KeyspaceCreated` | `id: ID`, `creator: Principal`, `name: String`, `registrant_dao_id: Option<ID>` | `create_keyspace` (personal) / `create_keyspace_for_dao` (org-linked) |
| `AccessGranted` | `keyspace_id: ID`, `role: Role`, `principal: Principal`, `by: address` | `grant` / `multi_grant` / keyspace init |
| `AccessRevoked` | `keyspace_id: ID`, `role: Role`, `principal: Principal`, `by: address` | `revoke` / `multi_revoke` — Read revocation bumps `keyspace.version` |
| `EntryPublished` | `entry_id: ID`, `keyspace_id: ID`, `uri: String`, `created_by: address` | `publish_entry` — `uri` is a Walrus/IPFS pointer to the AES-GCM blob; epoch = keyspace version at publish |
| `EntryUpdated` | `entry_id: ID`, `keyspace_id: ID`, `new_uri: String`, `new_epoch: u64`, `by: address` | `update_entry` — re-encryption (epoch bump; blob re-encrypted for new Read set) |
| `EntryEdited` | `entry_id: ID`, `keyspace_id: ID`, `new_uri: String`, `by: address` | `edit_entry` — content change, same epoch, no key rotation |
| `EntryDescriptionEdited` | `entry_id: ID`, `keyspace_id: ID`, `new_description: String`, `by: address` | `edit_description` — metadata only |

`Role = Grant | Read | Write` (Grant = admin ACL, Read = decryption gate via `seal_approve`, Write = publish/edit). This is the module that should back "private location data sharing with ACLs" end to end: `Keyspace.version` is bumped on every `Read` membership change, and comparing an `EncryptedEntry.epoch` against the current `keyspace.version` is exactly how the indexer (and any re-encryption worker) detects stale entries needing rotation. The module is explicitly designed to be fully event-sourced — no object reads are required to reconstruct state, which maps cleanly onto a sequential indexer pipeline.

### 4.3 NEW: `armature-trading` package

`armature-trading` is a thin governance layer: every trading action is an `armature_proposals`-style proposal handler (in `trading_ops.move`) that consumes an `ExecutionTicket<P>` and calls into the shared **TriexBook** DEX (multicoin order book + `BalanceManager`) on behalf of a DAO's treasury. Proposal payload types (all `has drop, store`, executed via handlers):

1. `SetupTradingAccount` — create `BalanceManager` + `TradeCap`/`DepositCap`/`WithdrawCap`, stored in the DAO's `CapabilityVault` (once per DAO)
2. `DepositCoinToBook<T>` — `TreasuryVault` → `BalanceManager`
3. `DepositMulticoinToBook` — `TreasuryVault` multicoin item → `BalanceManager`
4. `DepositFromDaoVaultToBook` — `armature_vault::DaoReceiptVault` item → `BalanceManager` (org-ACL-gated release, connects §4.2's vault ACLs into trading)
5. `PlaceLimitOrder<QuoteAsset>` / `CancelOrder<QuoteAsset>` — order placement/cancellation on `MultiCoinPool`
6. `SweepCoinToTreasury<T>` / `SweepMulticoinToTreasury` — `BalanceManager` → `TreasuryVault`

Because every trading action routes through a proposal handler, **every trading event carries (or is directly attributable to) a `dao_id`** — that attribution is exactly what's missing from `etl-api` today.

#### Events (module names per TriexBook / TreasuryVault / multicoin — package paths TBD at deploy, confirm exact module names against `armature-trading/packages` before implementation)

| Event | Fields (key ones) | Purpose for indexer |
|---|---|---|
| `OrderPlaced` | `order_id`, `pool_id`, `balance_manager_id`, `price`, `quantity`, `is_bid`, `order_type` | New resting order — join `balance_manager_id → dao_id` via `trading_accounts` |
| `OrderFilled` | `maker_order_id`, `taker_order_id`, `maker_balance_manager_id`, `taker_balance_manager_id`, `price`, `base_qty`, `quote_qty` | Trade execution — both counterparties resolved to `dao_id` (or player) via `trading_accounts` |
| `OrderCanceled` / `OrderExpired` / `OrderModified` / `OrderFullyFilled` | `order_id`, `balance_manager_id`, ... | Order lifecycle terminal/partial states |
| `MultiCoinPoolCreated<QuoteAsset>` / `PoolCreated<Base, Quote>` | `pool_id`, asset/collection identifiers | Market discovery |
| `BalanceManagerEvent` / `BalanceEvent` / `MultiCoinBalanceEvent` | `balance_manager_id`, `owner`, amounts | Settlement into `BalanceManager`; `owner` disambiguates `Player` vs DAO-derived address |
| `CoinDeposited` / `CoinWithdrawn` / `MultiCoinDeposited` / `MultiCoinWithdrawn` (TreasuryVault) | `vault_id`, `dao_id`, amounts | Covered by the `armature_treasury` pipeline (§4.1) for plain treasury ops — trading-triggered deposits/sweeps additionally get a `dao_book_deposits`/`dao_book_sweeps` row tying them to the trading flow |
| `MintEvent` / `BurnEvent` / `TransferEvent` / `SplitEvent` / `JoinEvent` (multicoin) | `collection_id`, `asset_id`, `amount` | Item-level accounting for multicoin assets moving in/out of vaults and the book |

**Design decision**: `armature_trading` pipeline does **not** re-index raw `OrderPlaced`/`OrderFilled` mechanics — `etl-api` already does this for the shared TriexBook (`/v1/account/:balanceMgrId/*`, `/v1/fills/*`). Instead, the new pipeline indexes only the **DAO-attribution layer**:
- `trading_accounts`: `dao_id ↔ balance_manager_id` (from `SetupTradingAccount` execution)
- `dao_book_deposits` / `dao_book_sweeps`: treasury↔book movements, for org-scoped audit trail
- A thin `dao_order_index` view/table mapping `(dao_id) → balance_manager_id`, letting an API layer join into etl-api's existing order/fill tables for `GET /v1/orgs/:orgId/{orders,trades}` without duplicating book state.

---

## 5. Schema (new tables, additive to `indexer-geyser`'s `crates/schema` migration set)

```sql
-- =====================================================================
-- armature_vault: DAO receipt vaults
-- =====================================================================
CREATE TABLE IF NOT EXISTS dao_receipt_vaults (
    vault_id             BYTEA  PRIMARY KEY,
    registrant_dao_id    BYTEA  NOT NULL,
    storage_unit_id      BYTEA  NOT NULL,
    collection_id        BYTEA  NOT NULL,
    status                TEXT  NOT NULL DEFAULT 'active', -- 'active'|'deinitialized'
    created_at_cp        BIGINT NOT NULL,
    deinit_at_cp         BIGINT
);
CREATE INDEX IF NOT EXISTS dao_receipt_vaults_by_dao ON dao_receipt_vaults (registrant_dao_id);
CREATE INDEX IF NOT EXISTS dao_receipt_vaults_by_ssu ON dao_receipt_vaults (storage_unit_id);

-- Running per-asset balance, derived from Deposit/Withdraw deltas
CREATE TABLE IF NOT EXISTS vault_asset_balances (
    vault_id   BYTEA  NOT NULL REFERENCES dao_receipt_vaults(vault_id),
    asset_id   NUMERIC(20,0) NOT NULL,
    balance    NUMERIC(39,0) NOT NULL DEFAULT 0,
    PRIMARY KEY (vault_id, asset_id)
);

-- Current ACL state (Deposit/Withdraw/Edit), maintained by diffing grant/revoke
CREATE TABLE IF NOT EXISTS vault_acl (
    vault_id       BYTEA NOT NULL REFERENCES dao_receipt_vaults(vault_id),
    role           TEXT  NOT NULL, -- 'deposit'|'withdraw'|'edit'
    principal_kind TEXT  NOT NULL, -- 'player'|'ou'
    principal_addr BYTEA,          -- set when principal_kind='player'
    principal_dao  BYTEA,          -- set when principal_kind='ou'
    granted_by     BYTEA NOT NULL,
    granted_at_cp  BIGINT NOT NULL,
    PRIMARY KEY (vault_id, role, principal_kind, principal_addr, principal_dao)
);
CREATE INDEX IF NOT EXISTS vault_acl_by_principal_addr ON vault_acl (principal_addr) WHERE principal_addr IS NOT NULL;
CREATE INDEX IF NOT EXISTS vault_acl_by_principal_dao  ON vault_acl (principal_dao)  WHERE principal_dao  IS NOT NULL;

-- Append-only ACL audit log (grants AND revokes)
CREATE TABLE IF NOT EXISTS vault_acl_history (
    vault_id       BYTEA  NOT NULL,
    checkpoint     BIGINT NOT NULL,
    event_index    INTEGER NOT NULL,
    action         TEXT   NOT NULL, -- 'grant'|'revoke'
    role           TEXT   NOT NULL,
    principal_kind TEXT   NOT NULL,
    principal_addr BYTEA,
    principal_dao  BYTEA,
    by_addr        BYTEA  NOT NULL,
    PRIMARY KEY (vault_id, checkpoint, event_index)
);

-- =====================================================================
-- armature_vault: keyspaces (private / location-data ACL)
-- =====================================================================
CREATE TABLE IF NOT EXISTS keyspaces (
    keyspace_id       BYTEA  PRIMARY KEY,
    creator_kind      TEXT   NOT NULL, -- 'player'|'ou'
    creator_addr      BYTEA,
    creator_dao       BYTEA,
    name              TEXT   NOT NULL,
    registrant_dao_id BYTEA,           -- NULL for personal keyspaces
    version           BIGINT NOT NULL DEFAULT 0, -- bumped on Read ACL change; drives re-encryption
    created_at_cp     BIGINT NOT NULL
);
CREATE INDEX IF NOT EXISTS keyspaces_by_registrant_dao ON keyspaces (registrant_dao_id) WHERE registrant_dao_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS keyspace_acl (
    keyspace_id    BYTEA NOT NULL REFERENCES keyspaces(keyspace_id),
    role           TEXT  NOT NULL, -- 'grant'|'read'|'write'
    principal_kind TEXT  NOT NULL, -- 'player'|'ou'
    principal_addr BYTEA,
    principal_dao  BYTEA,
    granted_by     BYTEA NOT NULL,
    granted_at_cp  BIGINT NOT NULL,
    PRIMARY KEY (keyspace_id, role, principal_kind, principal_addr, principal_dao)
);
CREATE INDEX IF NOT EXISTS keyspace_acl_by_principal_addr ON keyspace_acl (principal_addr) WHERE principal_addr IS NOT NULL;
CREATE INDEX IF NOT EXISTS keyspace_acl_by_principal_dao  ON keyspace_acl (principal_dao)  WHERE principal_dao  IS NOT NULL;
-- Powers GET /v1/users/:addr/keyspaces and GET /v1/orgs/:orgId/keyspaces directly,
-- replacing triex-app-api's live GraphQL scan in acl/accessible.ts.

CREATE TABLE IF NOT EXISTS encrypted_entries (
    entry_id     BYTEA  PRIMARY KEY,
    keyspace_id  BYTEA  NOT NULL REFERENCES keyspaces(keyspace_id),
    uri          TEXT   NOT NULL,
    description  TEXT   NOT NULL DEFAULT '',
    created_by   BYTEA  NOT NULL,
    epoch        BIGINT NOT NULL,   -- keyspace.version at last (re-)encryption
    created_at_cp BIGINT NOT NULL,
    updated_at_cp BIGINT
);
CREATE INDEX IF NOT EXISTS encrypted_entries_by_keyspace ON encrypted_entries (keyspace_id);
-- Stale-entry detection for re-encryption workers:
--   SELECT * FROM encrypted_entries e JOIN keyspaces k USING (keyspace_id)
--   WHERE e.epoch < k.version;

-- =====================================================================
-- armature_trading: DAO attribution layer over shared TriexBook state
-- =====================================================================
CREATE TABLE IF NOT EXISTS trading_accounts (
    dao_id             BYTEA  PRIMARY KEY,
    balance_manager_id BYTEA  NOT NULL UNIQUE,
    trade_cap_id       BYTEA,
    deposit_cap_id     BYTEA,
    withdraw_cap_id    BYTEA,
    created_at_cp      BIGINT NOT NULL
);
CREATE INDEX IF NOT EXISTS trading_accounts_by_bm ON trading_accounts (balance_manager_id);
-- Primary join point for etl-api: resolve balance_manager_id -> dao_id
-- to scope /v1/account/:balanceMgrId/* results by organization.

CREATE TABLE IF NOT EXISTS dao_book_deposits (
    dao_id         BYTEA  NOT NULL REFERENCES trading_accounts(dao_id),
    checkpoint     BIGINT NOT NULL,
    event_index    INTEGER NOT NULL,
    source         TEXT   NOT NULL, -- 'treasury'|'dao_vault'
    asset_kind     TEXT   NOT NULL, -- 'coin'|'multicoin'
    coin_type      TEXT,
    collection_id  BYTEA,
    asset_id       NUMERIC(20,0),
    amount         NUMERIC(39,0) NOT NULL,
    proposal_id    BYTEA  NOT NULL,
    PRIMARY KEY (dao_id, checkpoint, event_index)
);

CREATE TABLE IF NOT EXISTS dao_book_sweeps (
    dao_id         BYTEA  NOT NULL REFERENCES trading_accounts(dao_id),
    checkpoint     BIGINT NOT NULL,
    event_index    INTEGER NOT NULL,
    asset_kind     TEXT   NOT NULL, -- 'coin'|'multicoin'
    coin_type      TEXT,
    collection_id  BYTEA,
    asset_id       NUMERIC(20,0),
    amount         NUMERIC(39,0) NOT NULL,
    proposal_id    BYTEA  NOT NULL,
    PRIMARY KEY (dao_id, checkpoint, event_index)
);
```

The DDL above uses `BYTEA` for addresses/IDs and `NUMERIC(39,0)` for `u64` amounts, with `IF NOT EXISTS` everywhere, forward-only status columns, and `ON CONFLICT DO NOTHING` on all append-only inserts in the committer. **Reconcile before implementing:** `indexer-geyser`'s existing tables (`crates/schema`) store Sui IDs/addresses as `TEXT` (hex strings) and amounts as `BIGINT`, not `BYTEA`/`NUMERIC` — pick one convention and apply it consistently. New tables land as additive migrations in `crates/schema` alongside `001_init.sql`.

---

## 6. Rust processor/committer sketch

Follows `indexer-geyser`'s existing handler pattern exactly — one module per handler under `src/handlers/`, each with a `Processor` impl (pure BCS extraction) and a `SequentialHandler` impl (the committer, via the crate's `sequential_handler!` macro), registered in `main.rs` behind `should_register()` and listed in `config.rs::PIPELINE_NAMES`:

```rust
pub struct ArmatureVaultProcessor {
    pub vault_pkgs: HashSet<String>,
}

#[async_trait]
impl Processor for ArmatureVaultProcessor {
    const NAME: &'static str = "armature_vault";
    type Value = VaultUpdate; // enum: VaultInitialized, VaultDeinitialized, Deposit, Withdraw,
                              //       AclGranted, AclRevoked, KeyspaceCreated, AccessGranted,
                              //       AccessRevoked, EntryPublished, EntryUpdated, EntryEdited, ...
    async fn process(&self, cp: &CheckpointEnvelope) -> Result<Vec<VaultUpdate>> {
        // filter cp.events by ty.package in self.vault_pkgs, match (module, name)
        // decode via bcs_utils::decode_event, mirroring field order from §4.2
    }
}

// SequentialHandler<Store = PgStore> with VaultBatch { vaults, balances, acl_grants,
// acl_revokes, keyspaces, keyspace_acl, entries } — commit() upserts vaults/keyspaces
// first (FK ordering), then applies ACL diffs and balance deltas in event_index order.
```

```rust
pub struct ArmatureTradingProcessor {
    pub trading_pkgs: HashSet<String>,
}

#[async_trait]
impl Processor for ArmatureTradingProcessor {
    const NAME: &'static str = "armature_trading";
    type Value = TradingUpdate; // enum: AccountSetup, BookDeposit, BookSweep
    async fn process(&self, cp: &CheckpointEnvelope) -> Result<Vec<TradingUpdate>> {
        // filter to trading_ops execute_* events + TreasuryVault deposit/withdraw events
        // that originate from a trading proposal (correlate by proposal_id in same tx)
    }
}
```

New package sets are added to `config.rs::PackageSets` and resolved through the same `<GROUP>_{MAINNET,TESTNET}_PACKAGE_IDS` env-var pattern the crate already uses for `TRIEXBOOK_*` / `WAREHOUSE_*` / `MULTICOIN_*` (via the `resolve()` helper): `ARMATURE_FRAMEWORK_*`, `ARMATURE_VAULT_*`, `ARMATURE_TRADING_*` — each comma-separated, listing every package ID across upgrades.

---

## 7. API design

Two consumers: `triex-app-api` (retire GraphQL-scan TODOs) and `etl-api` (add DAO scoping to existing DEX endpoints + serve new vault/keyspace data). Recommend exposing the new tables via `etl-api` (it already owns the Postgres-backed DEX API and Redis caching layer) rather than growing `indexer-geyser` into a second API service.

### New endpoints (etl-api)

```
# Vaults
GET /v1/orgs/:orgId/vaults                  # dao_receipt_vaults WHERE registrant_dao_id
GET /v1/vaults/:vaultId                     # vault detail + balances
GET /v1/vaults/:vaultId/acl                 # current ACL (vault_acl)
GET /v1/vaults/:vaultId/acl/history         # audit log (vault_acl_history)

# Keyspaces / private location data
GET /v1/keyspaces/:keyspaceId               # keyspace detail incl. version
GET /v1/keyspaces/:keyspaceId/entries       # entries + epoch (client compares to version)
GET /v1/users/:addr/keyspaces               # accessible keyspaces for a Player principal
GET /v1/orgs/:orgId/keyspaces               # keyspaces where registrant_dao_id = orgId

# Trading (DAO-scoped; joins into existing etl-api order/fill tables via trading_accounts)
GET /v1/orgs/:orgId/trading-account         # balance_manager_id + cap IDs
GET /v1/orgs/:orgId/orders                  # -> trading_accounts.balance_manager_id -> existing open_orders query
GET /v1/orgs/:orgId/trades                  # -> existing /v1/account/:balanceMgrId/trades, DAO-scoped
GET /v1/orgs/:orgId/book-activity           # dao_book_deposits + dao_book_sweeps, merged/paginated
```

### Retires in triex-app-api

- `acl/accessible.ts` → `GET /v1/users/:addr/keyspaces` (removes per-request GraphQL scan)
- `ssu/$ssuId/dao-vaults.ts` → `GET /v1/orgs/:orgId/vaults` or a new `GET /v1/ssu/:ssuId/vaults` filtered view

---

## 8. Rollout plan

1. **Schema migration**: add §5 tables to `indexer-geyser`'s `crates/schema` migration set, additive-only, no changes to existing tables (resolve the `TEXT`/`BIGINT` vs `BYTEA`/`NUMERIC` convention from §5 first).
2. **Core armature pipelines (§4.1)**: implement `armature_core`, `armature_proposals`, `armature_treasury` first — the vault and trading work depends on `dao_members`/`daos` for `Ou`-principal and `dao_id` resolution. Deploy with `INCLUDE_HANDLER_IDS=armature_core,armature_proposals,armature_treasury` from each package's publish checkpoint.
3. **`armature_vault` pipeline**: implement + deploy with `INCLUDE_HANDLER_IDS=armature_vault` against `START_CHECKPOINT` at the vault package-publish checkpoint (the package is new, so this starts from package genesis rather than a full chain backfill).
4. **`armature_trading` pipeline**: same pattern; depends on `armature_vault` for `DepositFromDaoVaultToBook` attribution but can deploy independently since vault linkage is best-effort (nullable FK).
5. **etl-api endpoints**: build against the new tables once backfill reaches chain tip; ship behind existing feature-flag mechanism (`GET /api/v1/flags` in triex-app-api).
6. **triex-app-api migration**: swap the `@todo:add-indexer` routes to call the new etl-api endpoints; delete GraphQL-scan code paths.
7. **Confirm exact module/event names for `armature-trading`** against the actual Move source at implementation time — this doc's §4.3 event field names are reconstructed from proposal-handler call sites and TriexBook conventions, not literal struct definitions (unlike §4.2, which is verbatim from source).

## 9. Open questions

- Does `DepositFromDaoVaultToBook` emit its own event, or only the underlying vault `WithdrawEvent` + book `MultiCoinBalanceEvent`? Determines whether `dao_book_deposits.source = 'dao_vault'` rows need correlation-by-transaction rather than a direct event match.
- Should `keyspace` entries used for location data get a dedicated `entry_kind` discriminator (location vs. generic), or is that purely an off-chain (post-decryption) concern? Currently the Move layer treats all entries uniformly.
- `armature::encrypted_entry` (DAO-level, §4.1) and `armature_vault::keyspace` (§4.2) are two separate encrypted-entry systems with similar shapes — confirm with the vault team whether both need indexing or whether `armature::encrypted_entry` is legacy/unused now that `keyspace` exists.

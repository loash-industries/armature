# Armature Indexer — Phase 1 Integration Plan (triex-book `indexer-geyser`)

Concrete build plan for the first slice of armature indexing inside `triex-book/crates/indexer-geyser`. Companion to [`armature_indexer_handler_inventory.md`](./armature_indexer_handler_inventory.md) (full handler catalog) and [`armature_vault_trading_indexer_design.md`](./armature_vault_trading_indexer_design.md) (event catalog + schema).

## Scope

Five product capabilities, plus one prerequisite registry and shared plumbing:

| # | Capability | Handler(s) / mechanism |
|---|---|---|
| 0 | *(prereq)* DAO registry | `daos` handler |
| 1 | Org membership — "DAOs I belong to" | `dao_membership` handler |
| 2 | Org edges — subDAO / successor graph | `subdao_edges` handler |
| 3 | Trading-account mapping — `balance_manager_id → dao_id` | **SQL view** over existing `balance_manager_created` |
| 4 | Treasury transactions — deposits/withdraws, coin-type interned | `treasury_txns` handler |
| 5 | ACLs by **player address** | `vault_acl` + `keyspace_acl` handlers |

New pipelines: `daos`, `dao_membership`, `subdao_edges`, `treasury_txns`, `vault_acl`, `keyspace_acl` (6). `PIPELINE_NAMES` goes `23 → 29`. Trading accounts is a view — no pipeline, no watermark.

## Key findings driving the design

1. **Trading-account mapping needs no event handler.** `armature_trading::trading_ops::execute_setup_trading_account` (trading_ops.move:64-85) emits **no event** — it calls `balance_manager::new_with_custom_owner_and_caps(dao_owner, …)` where `dao_owner = dao_id` cast to `address`. The existing `balance_manager_created` handler already stores `balance_manager_id` + `owner`, and `owner == dao_id` byte-for-byte. So the mapping is a join, served as a view.
2. **Membership / edges / ACL are last-writer-wins, not summable.** Unlike `multicoin_ownership` (commutative `SUM` of deltas), add/remove and grant/revoke depend on order. The ledger carries `(checkpoint, event_index, leg)` and the materialized table is recomputed with `DISTINCT ON … ORDER BY … DESC`.
3. **`bcs::from_bytes` decodes Move enums into serde enums by variant order** (confirmed in `geyser-indexer-framework::bcs_utils::decode_event`). So `Principal`/`Role` become `#[derive(Deserialize)]` enums with variants in Move-source order.
4. **The `assets` table already exists** (`asset_type text PK, name, symbol, decimals, …`). Treasury `coin_type` is interned there behind a serial surrogate (decision below).

## Resolved decisions

- **Package IDs → `config.rs` defaults.** Add four new `const TESTNET_*_PACKAGES` arrays following the existing `TESTNET_PACKAGES` / `TESTNET_MULTICOIN_PACKAGES` pattern, plus `resolve()`-based env overrides `ARMATURE_<GROUP>_{MAINNET,TESTNET}_PACKAGE_IDS`. Candidate testnet IDs (⚠️ **verify against the current `testnet_stillness` deploy — a redeploy just landed; `ui/.env.testnet` may be stale, and framework/proposals currently share an ID there**):
  - `armature_framework`: `0x37993147567b6fee75a274b8a34da67eb81647f2ed6890ae6502d3d038f6d9f0`
  - `armature_proposals`: `0x37993147567b6fee75a274b8a34da67eb81647f2ed6890ae6502d3d038f6d9f0`
  - `armature_world_bridge`: source from deploy (world-contracts `0xd12a…` in `ui/.env.testnet` is a *different* package)
  - `armature_vault`: source from deploy
  Each array lists **every** package ID across upgrades (events can carry any historical package in `event_type.package`).
- **Coin-type interning.** Add a serial surrogate to `assets` and store the narrow int in `treasury_txns` instead of repeating the full type string in every row (space saving). See Item 4.
- **Trading-account cap IDs are dropped from the view** — they are *never* event-derivable (see "The cap-id question" below), so an always-null column is pointless. If caps are needed later, a separate `trading_account_caps` table populated by a chain scan of the DAO's `CapabilityVault` dynamic fields is the path.

### The cap-id question

The cap columns would be null in **every** row, not just some — there is no scenario where the view has them:
- `execute_setup_trading_account` emits no event at all.
- The only event the mapping is derived from — `BalanceManagerEvent` — carries just `balance_manager_id` + `owner`, no caps.
- The `TradeCap`/`DepositCap`/`WithdrawCap` objects exist only as dynamic fields inside the DAO's `CapabilityVault`, discoverable solely by a `getDynamicFields`/`getObject` chain read.

So: omit them from the view; add a chain-scan enrichment table only if a caller actually needs cap IDs.

## Shared plumbing (do once)

**`config.rs`**
- Add `armature_framework`, `armature_proposals`, `armature_world_bridge`, `armature_vault` to `PackageSets` + `package_sets()`, each with a `const TESTNET_*_PACKAGES` default and an `ARMATURE_*_{MAINNET,TESTNET}_PACKAGE_IDS` `resolve()` override.
- Extend `PIPELINE_NAMES` to 29 and update the `pipeline_names_match_registered_handlers` test with the six new `Handler::NAME`s.

**`types.rs`** — add, all `#[derive(Debug, Clone, Deserialize)]`, IDs/addresses as `[u8;32]`, `vector<address>` as `Vec<[u8;32]>`, `ascii::String`/`String` as `String`:
```rust
// shared enums (variant order = Move source order)
#[derive(Debug, Clone, Deserialize)] pub enum Principal { Player { addr: [u8;32] }, Ou { dao_id: [u8;32] } }
#[derive(Debug, Clone, Deserialize)] pub enum VaultRole { Deposit, Withdraw, Edit }
#[derive(Debug, Clone, Deserialize)] pub enum KeyspaceRole { Grant, Read, Write }

// armature_framework::dao
pub struct DAOCreated { /* fields per dao.move:163 */ }
pub struct DAODestroyed { /* … */ }
// armature_framework::treasury_vault
pub struct CoinDeposited   { pub vault_id:[u8;32], pub dao_id:[u8;32], pub coin_type:String, pub amount:u64, pub depositor:[u8;32] }
pub struct CoinWithdrawn   { pub vault_id:[u8;32], pub dao_id:[u8;32], pub coin_type:String, pub amount:u64, pub recipient:[u8;32] }
pub struct CoinClaimed     { pub vault_id:[u8;32], pub dao_id:[u8;32], pub coin_type:String, pub amount:u64, pub claimer:[u8;32] }
pub struct MultiCoinDeposited { pub vault_id:[u8;32], pub dao_id:[u8;32], pub collection_id:[u8;32], pub asset_id:u64, pub amount:u64, pub depositor:[u8;32] }
pub struct MultiCoinWithdrawn { pub vault_id:[u8;32], pub dao_id:[u8;32], pub collection_id:[u8;32], pub asset_id:u64, pub amount:u64, pub recipient:[u8;32] }
// armature_proposals::member_ops
pub struct MemberAdded   { pub dao_id:[u8;32], pub member:[u8;32] }
pub struct MemberRemoved { pub dao_id:[u8;32], pub member:[u8;32] }
pub struct MembersBatchAdded   { pub dao_id:[u8;32], pub added:Vec<[u8;32]>, pub skipped:Vec<[u8;32]> }
pub struct MembersBatchRemoved { pub dao_id:[u8;32], pub removed:Vec<[u8;32]> }
// armature_world_bridge::autojoin_ops
pub struct MemberAutojoined { pub dao_id:[u8;32], pub member:[u8;32], pub tribe_id:u32, pub character_id:[u8;32] }
// armature_proposals::subdao_ops
pub struct SubDAOCreated       { pub controller_dao_id:[u8;32], pub subdao_id:[u8;32], pub control_cap_id:[u8;32] }
pub struct SuccessorDAOSpawned { pub origin_dao_id:[u8;32], pub successor_dao_id:[u8;32] }
pub struct SubDAOSpunOut       { pub controller_dao_id:[u8;32], pub subdao_id:[u8;32] }
// armature_vault::dao_receipt_vault
pub struct AclGrantedEvent { pub vault_id:[u8;32], pub role:VaultRole, pub principal:Principal, pub by:[u8;32] }
pub struct AclRevokedEvent { pub vault_id:[u8;32], pub role:VaultRole, pub principal:Principal, pub by:[u8;32] }
// armature_vault::keyspace
pub struct AccessGranted { pub keyspace_id:[u8;32], pub role:KeyspaceRole, pub principal:Principal, pub by:[u8;32] }
pub struct AccessRevoked { pub keyspace_id:[u8;32], pub role:KeyspaceRole, pub principal:Principal, pub by:[u8;32] }
```
Plus `is_type_in(ty, pkgs, module, name)` match arms — module names: `dao`, `treasury_vault`, `member_ops`, `autojoin_ops`, `subdao_ops`, `dao_receipt_vault`, `keyspace`.

**`main.rs`** — register the six handlers behind `should_register()`, passing the relevant package set(s). `dao_membership` takes both `armature_proposals` and `armature_world_bridge` sets (like `multicoin_ownership` takes two).

**Schema** — one additive migration in `crates/schema`, `TEXT` for IDs, `BIGINT` for amounts (crate convention; not the design doc's `BYTEA`/`NUMERIC`).

## Per-item plan

### Item 0 — `daos` registry *(prerequisite)* — [state]
- **Events** (`armature_framework::dao`): `DAOCreated`, `DAOBoardInitialized`, `EncryptionEpochRotated`, `DAODestroyed`.
- **Table**
  ```sql
  CREATE TABLE IF NOT EXISTS daos (
      dao_id           text PRIMARY KEY,
      board_id         text,
      encryption_epoch bigint,
      status           text NOT NULL DEFAULT 'active', -- 'active'|'destroyed'
      name             text,
      created_at_cp    bigint NOT NULL,
      last_checkpoint  bigint NOT NULL
  );
  ```
  Upsert on `dao_id`; `DAODestroyed` sets `status='destroyed'`.

### Item 1 — org membership (`dao_membership`) — [state]
- **Events**: `member_ops::{MemberAdded,MemberRemoved,MembersBatchAdded,MembersBatchRemoved}`, `autojoin_ops::MemberAutojoined`. Batch events flatten to one row per member (`leg` = position; `skipped` ignored).
- **Tables**
  ```sql
  CREATE TABLE IF NOT EXISTS dao_membership_events (
      event_digest text NOT NULL, leg smallint NOT NULL,
      dao_id text NOT NULL, member text NOT NULL, is_add boolean NOT NULL,
      checkpoint bigint NOT NULL, event_index integer NOT NULL,
      PRIMARY KEY (event_digest, leg)
  );
  CREATE TABLE IF NOT EXISTS dao_members (
      dao_id text NOT NULL, member_addr text NOT NULL,
      is_member boolean NOT NULL, last_checkpoint bigint NOT NULL,
      PRIMARY KEY (dao_id, member_addr)
  );
  CREATE INDEX IF NOT EXISTS dao_members_by_addr ON dao_members (member_addr) WHERE is_member;
  ```
- **Commit** (`multicoin_ownership` transaction shape): insert ledger `ON CONFLICT DO NOTHING`; recompute only touched `(dao_id, member)` keys:
  ```sql
  INSERT INTO dao_members (dao_id, member_addr, is_member, last_checkpoint)
  SELECT DISTINCT ON (e.dao_id, e.member) e.dao_id, e.member, e.is_add,
         e.checkpoint
  FROM dao_membership_events e
  JOIN (SELECT DISTINCT * FROM UNNEST($1::text[], $2::text[]) AS k(dao_id, member)) k
    ON e.dao_id = k.dao_id AND e.member = k.member
  ORDER BY e.dao_id, e.member, e.checkpoint DESC, e.event_index DESC, e.leg DESC
  ON CONFLICT (dao_id, member_addr) DO UPDATE
    SET is_member = EXCLUDED.is_member, last_checkpoint = EXCLUDED.last_checkpoint;
  ```
- **Query**: `SELECT dao_id FROM dao_members WHERE member_addr = $1 AND is_member;`

### Item 2 — org edges (`subdao_edges`) — [state]
- **Events**: `SubDAOCreated{controller_dao_id, subdao_id, control_cap_id}` (add `control` edge), `SubDAOSpunOut{controller_dao_id, subdao_id}` (remove `control` edge), `SuccessorDAOSpawned{origin_dao_id, successor_dao_id}` (add `succession` edge). Optionally `SubDAOExecution{Paused,Unpaused}` → `status`.
- **Tables**: ledger `subdao_edge_events(event_digest, leg, parent_dao, child_dao, edge_kind text, action text, control_cap_id text NULL, checkpoint, event_index, PK(event_digest,leg))`; materialized `subdao_edges(parent_dao, child_dao, edge_kind, control_cap_id, status text, last_checkpoint, PK(parent_dao, child_dao, edge_kind))`. Same last-writer-wins recompute as Item 1, keyed by `(parent_dao, child_dao, edge_kind)`.
- **Queries**: children `WHERE parent_dao=$1 AND edge_kind='control' AND status='active'`; successor `WHERE parent_dao=$1 AND edge_kind='succession'`.

### Item 3 — trading-account mapping — **SQL view (no handler)**
```sql
CREATE OR REPLACE VIEW trading_accounts AS
SELECT bmc.owner AS dao_id, bmc.balance_manager_id
FROM balance_manager_created bmc
WHERE EXISTS (SELECT 1 FROM daos d WHERE d.dao_id = bmc.owner);
```
- **Query**: `SELECT dao_id FROM trading_accounts WHERE balance_manager_id = $1;` (and the reverse for a DAO's BM). Depends on Item 0. Caps omitted (see "The cap-id question").
- **How the mapping exists without a dedicated event**: `execute_setup_trading_account` sets `owner = req.req_dao_id().to_address()` (trading_ops.move:76) and calls `new_with_custom_owner_and_caps` → `new_with_custom_owner`, which emits `BalanceManagerEvent { balance_manager_id, owner }` (balance_manager.move:150-159). That event is already indexed into `balance_manager_created`, so `owner == dao_id` byte-for-byte is the join.
- ⚠️ **Provisional owner derivation**: trading_ops.move:72-76 carries a `TODO(owner)` — "Using req DAO id -> address as a placeholder." If the DAO's on-chain address derivation changes (e.g. to a canonical/derived address rather than the raw `dao_id`), the `owner = daos.dao_id` join breaks and the view must switch to whatever the new derivation is. Re-confirm at implementation time.

### Item 4 — treasury transactions (`treasury_txns`) — [log] + coin-type interning
- **Events** (`treasury_vault`): `CoinDeposited`, `CoinWithdrawn`, `CoinClaimed` (coin) and `MultiCoinDeposited`, `MultiCoinWithdrawn` (multicoin).
- **Schema** — intern coin types behind a serial in `assets`, reference the int from txns:
  ```sql
  ALTER TABLE assets ADD COLUMN IF NOT EXISTS asset_seq integer GENERATED BY DEFAULT AS IDENTITY;
  CREATE UNIQUE INDEX IF NOT EXISTS assets_asset_seq_key ON assets (asset_seq);

  CREATE TABLE IF NOT EXISTS treasury_txns (
      event_digest  text PRIMARY KEY,
      digest text NOT NULL, sender text NOT NULL,
      checkpoint bigint NOT NULL, checkpoint_timestamp_ms bigint NOT NULL, package text NOT NULL,
      dao_id text NOT NULL, vault_id text NOT NULL,
      direction  text NOT NULL,            -- 'deposit'|'withdraw'|'claim'
      asset_kind text NOT NULL,            -- 'coin'|'multicoin'
      asset_seq     integer,               -- FK assets(asset_seq); set for coin rows
      collection_id text, asset_id bigint, -- set for multicoin rows
      amount        bigint NOT NULL,
      counterparty  text NOT NULL          -- depositor / recipient / claimer
  );
  CREATE INDEX IF NOT EXISTS treasury_txns_by_dao ON treasury_txns (dao_id, checkpoint);
  ```
- **Commit**: for coin rows, get-or-create the `asset_seq` per distinct `coin_type` in the batch, then bulk-insert txns with the resolved `asset_seq`:
  ```sql
  -- 1) intern unknown coin types (placeholder metadata; curation backfills name/symbol/decimals)
  INSERT INTO assets (asset_type, name, symbol, decimals)
  SELECT DISTINCT ct, ct, '', 0 FROM UNNEST($1::text[]) AS t(ct)
  ON CONFLICT (asset_type) DO NOTHING;
  -- 2) UNNEST-insert treasury_txns, joining assets to map coin_type -> asset_seq
  --    (multicoin rows pass NULL coin_type and carry collection_id/asset_id instead)
  ```
  `coin_type` must be **normalized to `assets.asset_type`'s canonical form** before interning — pin down whether that's `0x2::sui::SUI` (short) or the padded 64-hex form (open item below).
- **Query**: `SELECT t.*, a.symbol, a.decimals FROM treasury_txns t LEFT JOIN assets a ON a.asset_seq = t.asset_seq WHERE t.dao_id = $1 ORDER BY t.checkpoint DESC;`

### Item 5 — ACLs by player address (`vault_acl` + `keyspace_acl`) — [state] ×2
- **Events**: `dao_receipt_vault::{AclGrantedEvent,AclRevokedEvent}` (role `VaultRole`); `keyspace::{AccessGranted,AccessRevoked}` (role `KeyspaceRole`). Decode `Principal` → `Player{addr}`→(`'player'`,addr,NULL) / `Ou{dao_id}`→(`'ou'`,NULL,dao_id).
- **Tables** (two mirrored sets): ledger `*_acl_events(event_digest, leg, resource_id, role text, action text /* grant|revoke */, principal_kind text, principal_addr text, principal_dao text, by_addr text, checkpoint, event_index, PK(event_digest,leg))`; materialized `vault_acl` / `keyspace_acl(resource_id, role, principal_kind, principal_addr, principal_dao, granted_by, last_checkpoint, PK(resource_id, role, principal_kind, principal_addr, principal_dao))`, last-writer-wins (grant = present, revoke = absent). Index `principal_addr WHERE principal_kind='player'`.
- **Query (player-only, as requested)**:
  ```sql
  SELECT 'vault'    AS kind, resource_id, role FROM vault_acl
    WHERE principal_kind='player' AND principal_addr=$1
  UNION ALL
  SELECT 'keyspace' AS kind, resource_id, role FROM keyspace_acl
    WHERE principal_kind='player' AND principal_addr=$1;
  ```
- **`ou:` expansion deferred** — later add `OR principal_dao IN (SELECT dao_id FROM dao_members WHERE member_addr=$1 AND is_member)`, which is why Item 1 lands first.

## Sequencing

1. **Plumbing** — config package sets + env, `types.rs` structs/enums, schema migration.
2. **Item 0 `daos`** → **Item 3 view** (trivial once 0 exists).
3. **Items 1, 2, 4, 5** — independent, parallelizable.
4. Backfill each with `INCLUDE_HANDLER_IDS=<name>` from the relevant armature package publish checkpoint.

## Per-handler wiring checklist

1. `src/handlers/<name>.rs`: `Processor` (BCS extraction) + `SequentialHandler` via `sequential_handler!`.
2. `pub mod` + `pub use` in `src/handlers/mod.rs`.
3. Event structs / enums + `is_type_in` arms in `src/types.rs`.
4. Package set(s) in `config.rs::PackageSets`; add to `PIPELINE_NAMES` + its test.
5. Register in `main.rs` behind `should_register()`.
6. Migration in `crates/schema`.

## Open items

- **Exact `testnet_stillness` package IDs** for all four sets (redeploy just landed; verify — do not trust `ui/.env.testnet` blindly).
- **`coin_type` canonical form** in `assets.asset_type` (short vs padded) — drives the Item 4 normalization step.
- ~~Placeholder rows in `assets` vs. a dedicated `coin_types` table~~ — **resolved**: reuse `assets`, interning unknown coin types with `name=coin_type, symbol='', decimals=0`; curation backfills real metadata later.

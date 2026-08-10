# Armature Indexer — Handler Inventory (triex-book `indexer-geyser`)

Companion to [`armature_vault_trading_indexer_design.md`](./armature_vault_trading_indexer_design.md) and its [addendum](./armature_vault_trading_indexer_design_addendum.md). This document enumerates the full set of handlers needed to index the armature protocol inside the geyser-indexer-framework–based `indexer-geyser` crate (`triex-book`), derived from the event catalog in §4.1–4.3 of the design doc.

The crate has **no armature coverage today** — all existing handlers are TriexBook DEX / warehouse / multicoin / world. Everything below is new.

## Idempotency shapes

Every handler follows one of three patterns already established in the crate. Because the geyser committer advances its watermark in a **separate statement** from the data write, checkpoint redelivery is always possible — so each pattern is designed to make replay a no-op.

| Tag | Pattern | Reference handler | Use when |
|---|---|---|---|
| **[state]** | Current-state materialize: append raw events to a ledger keyed by `(event_digest, leg)`, then recompute the state table as **latest-action-wins** (or a forward-only status machine) with an absolute write for only the keys touched this batch. | `multicoin_ownership.rs` (materialized side) | ACLs, membership, registries, status machines, config — anything mutable/diffed. |
| **[log]** | Append-only: `UNNEST` bulk insert with `ON CONFLICT DO NOTHING`. | `balances.rs` | Immutable audit trails, event ledgers. |
| **[balance]** | Delta-ledger + running total: append signed deltas to a ledger, recompute `SUM(delta)` per key as an absolute write. | `multicoin_ownership.rs` | Running balances derived from deposit/withdraw deltas. |

---

## `armature_core` (armature_framework)

| Handler | Events | Shape | Table / notes |
|---|---|---|---|
| `daos` | `DAOCreated`, `DAOBoardInitialized`, `EncryptionEpochRotated`, `DAODestroyed` | **[state]** | `daos(dao_id, board_id, encryption_epoch, status, name/metadata)`. Registry to join names/status onto everything else. `EncryptionEpochRotated` updates a column, not a new row. |
| `dao_membership` | `member_ops::MemberAdded/MemberRemoved/MembersBatchAdded/MembersBatchRemoved`; `autojoin_ops::MemberAutojoined`; optionally `dao::DAODestroyed` to tombstone | **[state]** | Ledger `dao_membership_events(event_digest, leg, dao_id, member, is_add, checkpoint, ...)` → materialize `dao_members(dao_id, member_addr, is_member)` latest-action-wins per `(dao_id, member)` ordered by `(checkpoint, event_index)`. Query: `SELECT dao_id FROM dao_members WHERE member_addr = $addr AND is_member`. See [caveat: non-board governance](#caveats). |
| `treasury_txns` | `treasury_vault::CoinDeposited/CoinWithdrawn/CoinClaimed/MultiCoinDeposited/MultiCoinWithdrawn`; fold in `treasury_ops::CoinSent/SmallPaymentSent/CoinSentToDAO/BatchMulticoinSentToAddress/DAO` as outbound rows | **[log]** (+ optional **[balance]**) | Append-only ledger. For cheap "current treasury holdings", add a `[balance]` companion summing deltas per `(dao_id, coin_type)`. |
| `emergency_freezes` | `emergency::TypeFrozen/TypeUnfrozen/FreezeExemptTypeAdded/FreezeExemptTypeRemoved` | **[state]** | Current set of frozen types + exemptions per DAO (diff, latest-wins). |
| `external_executions` | `external_execution::ExternalExecutionCreated/BypassEnabled/BypassDisabled` | **[state]** | Only if the API needs it — otherwise defer. |
| `dao_encrypted_entries` | `encrypted_entry::EntryPublished/EntryUpdated/EntryRemoved` (DAO-level, distinct from keyspace) | **[state]** | ⚠️ Confirm-first — see design doc §9 open question on whether this legacy DAO-level entry system is still used. |
| `composites` | `composite::CompositeSubmitted` | **[log]** | Low value; audit only. |

## `armature_proposals`

| Handler | Events | Shape | Table / notes |
|---|---|---|---|
| `proposals` | `proposal::ProposalCreated/ProposalPayloadCreated/ProposalPassed/ProposalExecuted/ProposalExpired` | **[state]** | Forward-only status machine (`active→passed→executed` / `active→expired`). `controller::privileged_submit` goes `active→executed` with **no `ProposalPassed`** — transition logic must not assume `passed` was ever seen. |
| `votes` | `proposal::VoteCast` | **[state]** or **[log]** | If a member can re-cast, materialize latest-wins per `(proposal_id, voter)`; if votes are immutable, plain **[log]**. Confirm against source. |
| `subdao_edges` | `subdao_ops::SubDAOCreated/SuccessorDAOSpawned/SubDAOSpunOut/CapTransferredToSubDAO/CapReclaimedFromSubDAO/ControllerMembersBatchAdded/Removed/SubDAOExecutionPaused/Unpaused/AssetsTransferInitiated` | **[state]** | Parent↔child DAO graph + cap custody + pause status. Feeds the lifecycle re-pointing handler below. |
| `dao_proposal_config` | `admin_ops::ProposalTypeEnabled/Disabled/ProposalConfigUpdated/MetadataUpdated` | **[state]** | Per-DAO enabled proposal types + config + metadata. `MetadataUpdated` could instead patch the `daos` row. |
| `dao_currencies` | `currency_ops::CurrencyAdopted/CoinMinted/CoinBurned/CurrencyCapReturned` | **[state]** (registry) + **[log]** (mint/burn) | Adopted-currency registry per DAO; mint/burn as an append-only ledger. |
| `security_config` | `security_ops::FreezeAdminTransferred/FreezeConfigUpdated` | **[state]** | Small; can fold into `daos`. |
| `upgrade_authorizations` | `upgrade_ops::UpgradeAuthorized` | **[log]** | Audit only. |

## `armature_vault`

| Handler | Events | Shape | Table / notes |
|---|---|---|---|
| `dao_receipt_vaults` | `dao_receipt_vault::VaultInitializedEvent/VaultDeinitializedEvent` | **[state]** | Registry (status, storage_unit, collection, registrant_dao). Must land **before** `vault_acl`/`vault_asset_balances` (FK). |
| `vault_asset_balances` | `dao_receipt_vault::DepositEvent/WithdrawEvent` | **[balance]** | Sum signed deltas per `(vault_id, asset_id)` — exactly the `multicoin_ownership` pattern. |
| `vault_acl` | `dao_receipt_vault::AclGrantedEvent/AclRevokedEvent` (Role = `Deposit`\|`Withdraw`\|`Edit`) | **[state]** | Ledger keyed by `(event_digest, leg)` → materialize `vault_acl` latest-action-wins per `(vault_id, role, principal_kind, principal_addr, principal_dao)`. Decode `Principal` enum: `Player{addr}` → `principal_kind='player'`, `Ou{dao_id}` → `principal_kind='ou'`. |
| `keyspaces` | `keyspace::KeyspaceCreated` + version bumps from `AccessGranted/AccessRevoked(role=Read)` | **[state]** | Registry **plus** the `version` counter. Version is reconstructed by counting Read-role ACL changes (`keyspace.move:239-241`), so this handler observes the same grant/revoke stream `keyspace_acl` does. |
| `keyspace_acl` | `keyspace::AccessGranted/AccessRevoked` (Role = `Grant`\|`Read`\|`Write`) | **[state]** | Same shape as `vault_acl`, keyed by `(keyspace_id, role, principal_kind, principal_addr, principal_dao)`. |
| `encrypted_entries` | `keyspace::EntryPublished/EntryUpdated/EntryEdited/EntryDescriptionEdited` | **[state]** | Latest-wins per `entry_id` (uri, description, epoch). Powers stale-entry detection: `WHERE entry.epoch < keyspace.version`. |

## `armature_trading`

| Handler | Events | Shape | Table / notes |
|---|---|---|---|
| `trading_accounts` | `SetupTradingAccount` execution | **[state]** | `dao_id ↔ balance_manager_id` + cap IDs. The join key for DAO-scoping etl-api's existing order/fill tables. |
| `dao_book_deposits` | trading-proposal treasury/vault→book deposits | **[log]** | Correlated by `proposal_id`/tx (see design doc §9). |
| `dao_book_sweeps` | book→treasury sweeps | **[log]** | |

> **Design decision (unchanged from §4.3):** `armature_trading` does **not** re-index raw `OrderPlaced`/`OrderFilled` mechanics — the crate's existing TriexBook handlers already own that. This pipeline only indexes the DAO-attribution layer.

---

## Cross-cutting handler

**`dao_lifecycle_repointing`** — reacts to `DAODestroyed`, `SuccessorDAOSpawned`, `SubDAOSpunOut` and rewrites *dependent* `Ou`-principal rows: `trading_accounts`, `keyspaces`, and every `vault_acl`/`keyspace_acl` row where `principal_dao = <old dao>` re-points to the successor (or is tombstoned). Without it, a destroyed/succeeded DAO leaves dangling `Ou` grants that effective-access queries would still resolve against stale membership. The governance events already exist — this is index-side reaction, not a new on-chain event. (Design doc addendum §3.)

## The two motivating queries

These are what the handlers above are meant to serve idempotently.

**Query 1 — "all DAOs I belong to":** backed by `dao_membership`.
```sql
SELECT dao_id FROM dao_members WHERE member_addr = $addr AND is_member;
```

**Query 2 — "all ACLs I have access to" (player + ou):** a query-time UNION over `vault_acl`/`keyspace_acl` that **depends on `dao_members`**, because an `Ou` principal grants access to every governance member of that DAO (`acl.move:32-33`, `is_governance_member`).
```sql
-- direct player grants
WHERE principal_kind = 'player' AND principal_addr = $addr
UNION
-- inherited via DAO membership
WHERE principal_kind = 'ou' AND principal_dao IN
  (SELECT dao_id FROM dao_members WHERE member_addr = $addr AND is_member);
```
`dao_members` is a hard dependency of the ACL query; the `ou`/`player` expansion is a JOIN, not a handler.

## Caveats

- **Non-board governance is invisible.** `Direct`/`Weighted` membership emits no membership events (addendum §2.1), so `dao_membership` only sees board-governed DAOs. Either scope the `Ou` expansion to board-governed DAOs explicitly, or get init/config events added on-chain — otherwise Query 2's `Ou → dao_members` expansion silently under-returns.
- **Effective access is a live join, never a cached flatten.** A `MemberAdded` to an OU silently changes who can access a vault/keyspace with no vault event firing (addendum §1.3). Serve `vault_acl ⋈ dao_members` at query time.

## Critical path vs. direct chain reads

Sui answers two kinds of reads cheaply on its own: **fetch object `O` by its ID** (`getObject`) and **read `O`'s dynamic fields**. It *cannot* cheaply answer **reverse lookups** ("which objects reference value `V`?") or **replay history** ("every event matching a filter"). Those are the only things an indexer is strictly needed for.

So a handler is on the **critical path** only when it serves a reverse lookup or a historical/aggregate query. Handlers that merely mirror a single object's current forward state — readable by that object's own ID — are **enrichment/cache**: they can be deferred and served by a direct RPC read (optionally cached), or dropped entirely. The three motivating access patterns are all reverse lookups, which is exactly why they need the indexer:

- *"fetch orgs and roles I am a part of"* → reverse `member_addr → DAOs` → `dao_membership` (+ `daos` for role/name)
- *"fetch org and role for a trading account's `balance_manager_id`"* → reverse `balance_manager_id → dao_id` → `trading_accounts`
- *"fetch ACL encrypted entries I have access to"* → reverse `principal → entries`, expanded through membership → `keyspace_acl` + `encrypted_entries` + `dao_membership`

### On the critical path — indexer is the only way to answer these

| Handler | Fetchable on-chain by ID? | Why the indexer is required |
|---|---|---|
| `dao_membership` | ❌ | Reverse `member_addr → DAOs`; no on-chain reverse index exists. |
| `trading_accounts` | ❌ | Reverse `balance_manager_id → dao_id`; the mapping exists nowhere on-chain in reverse. |
| `vault_acl` | ⚠️ partial | Forward `vault_id → ACL` is an on-chain `VecMap`; the reverse `principal → vaults` index is not. |
| `keyspace_acl` | ⚠️ partial | Same — reverse `principal → keyspaces` (the `Ou`/`player` access query). |
| `encrypted_entries` | ⚠️ partial | Entry detail by `entry_id` is on-chain; "entries a principal can access" is a reverse + membership expansion. |
| `dao_receipt_vaults` | ⚠️ partial | Vault detail by `vault_id` is on-chain; org → vaults discovery is a reverse scan (the `dao-vaults.ts` scan being retired). |
| `keyspaces` | ⚠️ partial | Keyspace detail by id is on-chain; org → keyspaces discovery is reverse, and `version` reconstruction needs event history. |
| `proposals` | ⚠️ partial | A single proposal's status by id is on-chain; DAO → proposals listing + status history is reverse/aggregate (the `proposals.ts` scan). |
| `treasury_txns` | ❌ | Historical ledger — only *current* balances are on-chain, not the movement history. |
| `dao_book_deposits` / `dao_book_sweeps` | ❌ | Historical treasury↔book audit trail. |
| `votes` | ⚠️ partial | A current tally may live on the proposal object; per-voter history is event-sourced. |
| `subdao_edges` | ⚠️ partial | Parent/child pointers are on the objects; "list a DAO's children/successors" is a reverse traversal. |
| `dao_lifecycle_repointing` | n/a | Maintains correctness of the reverse `Ou`-principal indexes above; no equivalent on-chain read. |

### Not on the critical path — fetchable directly from chain (indexer optional / defer)

These mirror a single object's current forward state, readable by that object's own ID. Serve them with a direct `getObject`/dynamic-field read (optionally cached) rather than a handler, unless you specifically want them denormalized for cheap joins.

| Handler | Fetchable on-chain by ID? | How to get it without the indexer |
|---|---|---|
| `daos` | ✅ | `getObject(dao_id)`. Indexer copy only enriches reverse-lookup results with name/status/role cheaply. |
| `vault_asset_balances` | ✅ | Per-asset balances are dynamic object fields on the vault; read by `vault_id`. |
| `dao_proposal_config` | ✅ | Config lives on the DAO object; read by `dao_id`. |
| `emergency_freezes` | ✅ | Frozen-type set lives on the DAO/registry object. |
| `security_config` | ✅ | On the DAO object. |
| `external_executions` | ✅ | On the proposal/DAO object. |
| `dao_currencies` | ✅ | Adopted-currency registry is on the DAO object. *(Mint/burn **history** is not — split that ledger out only if an endpoint needs it.)* |
| `dao_encrypted_entries` | ✅ | Entry detail by id; and confirm-first anyway (design doc §9). |
| `composites` | ❌ (event-only) | History exists only as events, but low product value — audit-only, defer. |
| `upgrade_authorizations` | ❌ (event-only) | Same — audit-only, defer. |

## Build priority

1. **Required for the two queries + stated API goals:** `daos`, `dao_membership`, `proposals`, `subdao_edges`, `dao_receipt_vaults` + `vault_asset_balances` + `vault_acl`, `keyspaces` + `encrypted_entries` + `keyspace_acl`, `trading_accounts`, `dao_book_deposits`/`dao_book_sweeps`, `treasury_txns`, plus `dao_lifecycle_repointing`.
2. **Governance completeness:** `votes`, `dao_proposal_config`, `dao_currencies`, `emergency_freezes`.
3. **Defer / confirm-first:** `dao_encrypted_entries` (§9 open question), `external_executions`, `composites`, `upgrade_authorizations`, `security_config`.

## Wiring checklist (per handler)

Each handler, regardless of pipeline:

1. Module under `src/handlers/<name>.rs` with a `Processor` impl (pure BCS extraction) + a `SequentialHandler` impl via the `sequential_handler!` macro.
2. Event structs + a serde-decodable `Principal`/`Role` enum added to `src/types.rs`; `is_type_in` module/struct matches.
3. New package sets in `config.rs::PackageSets`, resolved via `ARMATURE_FRAMEWORK_*` / `ARMATURE_VAULT_*` / `ARMATURE_TRADING_*` `{MAINNET,TESTNET}_PACKAGE_IDS` env vars (same `resolve()` pattern as `TRIEXBOOK_*`).
4. Register in `main.rs` behind `should_register()`; add the `Processor::NAME` to `config.rs::PIPELINE_NAMES` and its matching test.
5. Additive migration in `crates/schema` (reconcile the `TEXT`/`BIGINT` vs `BYTEA`/`NUMERIC` convention per design doc §5).

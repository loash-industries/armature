# Armature Vault + Trading Indexer — Design Addendum (gap analysis)

Companion to [`armature_vault_trading_indexer_design.md`](./armature_vault_trading_indexer_design.md). This addendum records gaps found by cross-checking the design against the actual Move event definitions in `armature-vault`, `armature-trading`, and their dependencies (`triexbook`, `world-contracts`, `warehouse-receipts`, `multicoin`), plus what `etl-api` already indexes.

**Verification basis:** unlike §4.3 of the base doc (which reconstructed trading event names from call sites), the findings below are read directly from source. Event structs and field orders cited here are verbatim.

---

## 0. Framing decision — rely on native TriexBook events, don't replicate

Every TriexBook event already carries `balance_manager_id`, and `etl-api`'s `order_fills` table already stores both `maker_balance_manager_id` and `taker_balance_manager_id`. DAO-scoped orders/trades/fills therefore reduce to **native events + one join key**: `balance_manager_id → dao_id`.

**Consequence for the base doc:** §4.3's `OrderPlaced` / `OrderFilled` / `OrderCanceled` / `OrderExpired` / `OrderModified` / `OrderFullyFilled` catalog is redundant and should be cut. The `armature_trading` pipeline shrinks to (a) the DAO↔BalanceManager mapping and (b) optional proposal-linkage correlation — everything else is a join into `etl-api`'s existing native-event tables.

---

## 1. CRITICAL — `trading_accounts` has no source event

The base doc (§4.3, §5) says the `dao_id ↔ balance_manager_id` mapping comes "from `SetupTradingAccount` execution." It does not exist:

- `SetupTradingAccount` is an empty struct — `public struct SetupTradingAccount has drop, store {}` ([setup_trading_account.move](../../armature-trading/packages/armature_trading/sources/setup_trading_account.move)).
- **`armature-trading` emits zero events in the entire package.**
- Today `etl-api` recovers the mapping with a **live per-DAO `CapabilityVault` dynamic-field scan** (`orgs.service.ts`) — the exact request-path RPC scan this indexer is meant to retire.

### Fix (no new contract event required)

In `trading_ops::execute_setup_trading_account` the BalanceManager is created with `owner = req.req_dao_id().to_address()` — a **deterministic** derivation ([trading_ops.move](../../armature-trading/packages/armature_trading/sources/trading_ops.move)). TriexBook's native event already carries this:

```move
public struct BalanceManagerEvent has copy, drop {
    balance_manager_id: ID,
    owner: address,
}
```

Build `trading_accounts` by matching `BalanceManagerEvent.owner` against `to_address()` of every known `dao_id` (the existing pipeline already has all DAO IDs from `DAOCreated`). Because `dao_id` is an object ID, the derived address is not controllable as a real wallet, so the match is unambiguous.

**Caveat:** the three cap IDs (`TradeCap` / `DepositCap` / `WithdrawCap`) are **not** in any event. If UX needs them, that still requires an object read or a new emitted event. Decide before building.

**Recommended alternative if cap IDs are needed:** add a real `SetupTradingAccount` event to `armature-trading` emitting `{ dao_id, balance_manager_id, trade_cap_id, deposit_cap_id, withdraw_cap_id }`. This is the only place a new on-chain event is genuinely warranted.

---

## 2. Organization indexer gaps (members / roles / proposals)

### 2.1 Non-board governance is invisible to the indexer
`GovernanceConfig` has three variants — `Board { members }`, `Direct { voters, weights }`, `Weighted { delegates, weights }` ([governance.move:14](../packages/armature_framework/sources/governance.move#L14)). But `DAOBoardInitialized` and all of `member_ops` only touch `Board`. For a `Direct`/`Weighted` DAO the voters/delegates and their **weights** never appear in any event — not even at creation. If org UX must show members & roles for those DAOs, there is no event source.

**Action:** emit init/config events for `Direct`/`Weighted` membership, or explicitly scope the indexer to board-governed DAOs only.

### 2.2 `AutojoinAllowlistUpdated` missing from the catalog
Emitted by [configure_autojoin.move:111](../packages/armature_world_bridge/sources/autojoin/configure_autojoin.move#L111) with `{ dao_id, added, removed, enabled }`. Governs which tribes may autojoin an org — relevant to membership UX. The base doc §4.1 lists only `MemberAutojoined`.

### 2.3 "Roles" model clarification
There is no arbitrary RBAC on-chain. Effective roles = board membership + `is_governance_member` (OU) + vault/keyspace ACL principals. UX should be designed around these, not a generic role table.

---

## 3. Vault / ACL / item-management gaps

### 3.1 No SSU / world linkage indexed
DAO receipt vaults are keyed by `storage_unit_id`, and the endpoint to be retired (`ssu/$ssuId/dao-vaults.ts`) is **SSU-scoped**. Nothing indexes `world`'s `StorageUnitCreatedEvent` or `ExtensionAuthorized/RevokedEvent` ([storage_unit.move](../../../world-contracts/contracts/world/sources/assemblies/storage_unit.move)). Without an SSU registry, the SSU-keyed vault query cannot be served.

### 3.2 Item semantics are unindexed
`vault_asset_balances` tracks `asset_id` deltas but nothing records what an `asset_id` / `collection_id` *is*. Item lifecycle lives in:
- **warehouse_receipts**: `ReceiptMintedEvent`, `ReceiptRedeemedEvent`, `VaultInitializedEvent` ([receipt.move](../../../packages/warehouse-receipts/packages/contracts/sources/receipt.move))
- **tribe_vault**: `TribeVaultInitializedEvent`, `TribeVaultDepositEvent`, `TribeVaultWithdrawEvent`
- **multicoin**: `MintEvent`, `BurnEvent`, `SplitEvent`, `JoinEvent`, `TransferEvent`

The base doc marks multicoin "TBD" and omits warehouse_receipts entirely. "Item management" UX needs at least a collection/receipt registry.

### 3.3 Effective ACL access requires a live join no vault event triggers
`vault_acl` / `keyspace_acl` store `Ou { dao_id }` principals ([acl.move:10](../../armature-vault/packages/armature_vault/sources/acl.move#L10)). Answering "which users can decrypt/withdraw" expands `Ou → dao_members`. A `MemberAdded` to an OU **silently changes who can access a vault/keyspace** with no vault event firing. The indexer must serve effective-access as a live join (`vault_acl ⋈ dao_members`) and must not cache a flattened member list. The base doc's schema stores the principal but never states this expansion rule.

---

## 4. Cross-cutting gaps

### 4.1 Proposal → order/trade correlation has no field
Native `OrderPlaced` carries `balance_manager_id` + `trader`, not `proposal_id`. Recovering "this order came from proposal X" requires **same-transaction-digest correlation** (`ProposalExecuted` ⋈ `OrderPlaced`), built at index time — not back-fillable cheaply. `composite` / `privileged_submit` proposals can place **multiple orders in one tx**, making the correlation ambiguous. Decide whether this linkage is required before building.

### 4.2 Deposit/sweep attribution and the `dao_vault` source flag
(Extends base doc Open Q9.) Native `BalanceEvent` / `MultiCoinBalanceEvent` already attribute deposits to a BM (→ dao), so `dao_book_deposits` / `dao_book_sweeps` may be derivable from native events alone — **except** distinguishing "from treasury" vs "from dao_vault" and tying to `proposal_id`, since `DepositFromDaoVaultToBook` emits nothing of its own. Both require tx-digest correlation.

### 4.3 No reconciliation for fold-from-events state
`etl-api` already has a documented production bug (`OPEN_ORDERS_PHANTOM_CANCEL_BUG.md`) where one dropped checkpoint stranded an order permanently — there is no reconciliation against chain state. The new **mutable-state** tables (`vault_acl`, `keyspace_acl`, `vault_asset_balances`) inherit this fragility: a lost `AclRevoked` / `WithdrawEvent` corrupts state permanently. Add periodic object-state reconciliation for these tables; the base plan has none.

### 4.4 Destroy / spin-out cascades
The base doc handles `VaultDeinitialized` but not what `DAODestroyed`, `SuccessorDAOSpawned`, or `SubDAOSpunOut` do to that DAO's `trading_accounts`, keyspaces, and OU-principal ACL rows (which should re-point to the successor). The governance events already exist; the indexer must react to them.

### 4.5 Fees / rebates absent for org P&L
If org trading UX shows net performance: `OrderFilled` carries `taker_fee` / `maker_fee`; separate `CredBurned` / `MultiCoinCredBurned` (maker credits) and `PoolFeesDeposited` / `PoolFeesWithdrawn` events exist. None are mentioned in the base doc. Confirm `etl-api` indexes these if P&L matters.

---

## 5. Net effect on the base design

| Base doc section | Change |
|---|---|
| §4.3 event catalog | Cut the `OrderPlaced/Filled/Canceled/...` list — use native TriexBook events + BM→dao join |
| §5 `trading_accounts` | Source is `BalanceManagerEvent.owner == dao_id.to_address()`, **not** `SetupTradingAccount` (which emits nothing); add cap-id note |
| New: SSU registry | Index `world` `StorageUnitCreatedEvent` + extension auth/revoke for the SSU-scoped vault view |
| New: item/collection registry | Index warehouse_receipts + multicoin item lifecycle events |
| New: non-board governance | Emit or explicitly scope out `Direct`/`Weighted` membership |
| New: ACL expansion rule | Document `vault_acl ⋈ dao_members` effective-access join |
| New: reconciliation | Periodic object-state reconciliation for mutable-state tables |
| New: cascade handling | React to `DAODestroyed` / successor / spin-out for trading + vault + keyspace ownership |

The trading pipeline shrinks to a derived `balance_manager_id ↔ dao_id` mapping plus optional tx-digest proposal correlation. The real missing coverage is on the org/vault side: non-board governance (§2.1), SSU/world linkage (§3.1), item/receipt semantics (§3.2), the OU→member ACL expansion rule (§3.3), and reconciliation for mutable state (§4.3).

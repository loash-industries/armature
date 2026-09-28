# Treasury Vault Tests

## Summary

`treasury_vault.move` holds a DAO's coins. Each coin type's `Balance<T>` is a dynamic field keyed by the type's name string (`type_name::with_original_ids<T>().into_string()`), and `coin_types` lists the types with a non-zero balance. Multicoin balances live in a two-level dynamic-object-field tree: a `CollectionRecord` per collection, holding a `MultiCoinBalance` per asset ID. Deposits and claims are permissionless; withdrawals need an `ExecutionRequest` for the vault's DAO carrying `TREASURY_WITHDRAW`.

These tests verify the withdrawal gate, the registry's sync with the balances, zero-balance cleanup, permissionless deposits and claims, multicoin bookkeeping, and the emptiness checks `dao::destroy` relies on. The spending handlers (`SendCoin`, `SendCoinToDAO`, `SendSmallPayment`, batch multicoin) are in `11_treasury_ops.md`.

## Test Matrix

**Withdrawals**

| Test | Expected | Where |
|------|----------|-------|
| `test_withdraw_with_valid_request_succeeds` | A request for the vault's DAO holding the bit withdraws 400 of 1000 | `treasury_vault_tests` |
| `withdraw_needs_treasury_withdraw` | Every bit except `TREASURY_WITHDRAW`: `proposal::EPermissionDenied` | `gate_tests` |
| `withdraw_multicoin_needs_treasury_withdraw` | Same for `withdraw_multicoin` | `gate_tests` |
| `bypass_ticket_cannot_withdraw_from_treasury` | A request of a type holding no bits: `proposal::EPermissionDenied` | `armature_external_type_tests::external_type_lifecycle_tests` |
| `test_withdraw_other_dao_request_aborts` | A request for another DAO: `treasury_vault::EDAOIdMismatch` | planned |
| `test_withdraw_insufficient_balance_aborts` | 200 from 100: `treasury_vault::EInsufficientBalance` | `treasury_vault_tests` |
| `test_withdraw_unknown_coin_type_aborts` | A type never deposited: `treasury_vault::EInsufficientBalance` | planned |
| `send_coin_e2e` | `SendCoin<SUI>` voted and executed through its handler debits the treasury and pays the recipient | `armature_proposals::treasury_ops_tests` |
| `send_coin_insufficient_balance_aborts` | The handler's withdrawal aborts `treasury_vault::EInsufficientBalance` | `armature_proposals::treasury_ops_tests` |

**Registry and cleanup**

| Test | Expected | Where |
|------|----------|-------|
| `test_deposit_first_coin_adds_to_registry` | `coin_types` gains the type; balance 1000 | `treasury_vault_tests` |
| `test_deposit_second_coin_type_adds_to_registry` | Two types listed, two balances | `treasury_vault_tests` |
| `test_deposit_same_type_joins_balance` | 1000 + 500 = 1500 with one registry entry | `treasury_vault_tests` |
| `test_partial_withdraw_preserves_field` | 300 of 1000: type still listed, balance 700 | `treasury_vault_tests` |
| `test_coin_types_reflects_non_zero_balances` | 999 of 1000: 1 left, type still listed | `treasury_vault_tests` |
| `test_withdraw_exact_balance_removes_field` | Withdrawing the whole balance removes the type from `coin_types` | `treasury_vault_tests` |
| `test_withdraw_exact_balance_removes_dynamic_field` | ... and the balance field; `balance<SUI>()` returns 0 | `treasury_vault_tests` |
| `test_balance_empty_vault_returns_zero` | No field: `balance` returns 0 | `treasury_vault_tests` |
| `test_balance_after_deposit_returns_correct` | `balance` returns the deposited amount | `treasury_vault_tests` |

**Deposits and claims**

| Test | Expected | Where |
|------|----------|-------|
| `test_deposit_permissionless` | A non-member deposits | `treasury_vault_tests` |
| `test_deposit_zero_amount` | A zero-value coin is destroyed; nothing registered | `treasury_vault_tests` |
| `test_claim_coin_recovers_direct_transfer` | A coin transferred to the vault's address is received into the balance | `treasury_vault_tests` |
| `test_claim_coin_multiple_types` | SUI then USDC claimed; both balances kept | `treasury_vault_tests` |
| `test_treasury_events` | `CoinDeposited`, `CoinWithdrawn`, `CoinClaimed` carry the vault and DAO IDs, type string and amount | planned |

**Multicoin**

| Test | Expected | Where |
|------|----------|-------|
| `test_deposit_first_item_creates_collection` | A `CollectionRecord` is created; collection count 1, item count 1 | `treasury_vault_multicoin_tests` |
| `test_deposit_same_asset_joins_balance` | Same asset deposited twice: one balance | `treasury_vault_multicoin_tests` |
| `test_deposit_second_asset_same_collection` | Item count 2 in one collection | `treasury_vault_multicoin_tests` |
| `test_deposit_second_collection_tracked_separately` | Collection count 2 | `treasury_vault_multicoin_tests` |
| `test_deposit_zero_is_noop`, `test_deposit_permissionless` | As for coins | `treasury_vault_multicoin_tests` |
| `test_withdraw_partial_preserves_dofs` | Balance reduced; asset and collection kept | `treasury_vault_multicoin_tests` |
| `test_withdraw_exact_removes_asset_dof` | Asset removed; item count decremented | `treasury_vault_multicoin_tests` |
| `test_withdraw_last_asset_removes_collection` | Last asset removed: `CollectionRecord` deleted, collection count 0 | `treasury_vault_multicoin_tests` |
| `test_withdraw_last_asset_leaves_sibling_collection_intact` | Other collections untouched | `treasury_vault_multicoin_tests` |
| `test_withdraw_excess_aborts`, `test_withdraw_missing_collection_aborts`, `test_withdraw_missing_asset_in_collection_aborts` | `treasury_vault::EInsufficientBalance` | `treasury_vault_multicoin_tests` |
| `test_multicoin_balance_missing_collection_returns_zero`, `test_multicoin_balance_missing_asset_returns_zero`, `test_collection_item_count_missing_returns_zero` | Queries on missing entries return 0 | `treasury_vault_multicoin_tests` |
| `test_multi_deposit_proposal`, `test_multi_deposit_proposal_accumulates_on_repeat`, `test_multi_withdraw_proposal`, `test_multi_withdraw_proposal_full_drain` | Several collections deposited or withdrawn under one request | `treasury_vault_multicoin_tests` |

**Emptiness and destruction**

| Test | Expected | Where |
|------|----------|-------|
| `test_is_empty_false_with_only_multicoin` | `is_empty` counts multicoin collections too | `treasury_vault_multicoin_tests` |
| `test_is_empty_true_after_full_multicoin_withdrawal` | Empty again after draining | `treasury_vault_multicoin_tests` |
| `test_destroy_empty_succeeds_on_empty_vault` | `destroy_empty` deletes a fresh vault | `treasury_vault_tests` |
| `test_destroy_empty_aborts_on_non_empty_vault` | A coin balance left: `treasury_vault::EVaultNotEmpty` | `treasury_vault_tests` |
| `test_destroy_empty_aborts_with_multicoin_assets` | A multicoin balance left: `treasury_vault::EVaultNotEmpty` | `treasury_vault_multicoin_tests` |

## Tests

---

### Withdraw requires TREASURY_WITHDRAW on a request for the vault's DAO

**Requirement:** `treasury_vault::withdraw<T, P>(vault, amount, &ExecutionRequest<P>, ctx): Coin<T>` and `withdraw_multicoin<P>(vault, collection_id, asset_id, amount, &req, ctx)` are public but need a request, and only framework code mints requests. Each checks the request's DAO against the vault's (`treasury_vault::EDAOIdMismatch`), then the bit (`proposal::EPermissionDenied` unless the request carries `TREASURY_WITHDRAW` or is privileged). The bit is fixed on `TransferAssets`; extension types get it when enabled at 80% (`armature_proposals::type_permissions::treasury_spend()`). The handler reads the amount and recipient from the approved payload, since only `P`'s module can reach the request (see `04_proposals.md`).

**Why it matters:** Without this gate anyone could drain the treasury, and without the bit check any approved request, of any type, could.

```move
// From treasury_vault_tests::test_withdraw_with_valid_request_succeeds
let mut vault = scenario.take_shared<TreasuryVault>();
vault.deposit(coin::mint_for_testing<SUI>(1000, scenario.ctx()), scenario.ctx());

let req = proposal::new_execution_request_for_testing<TestProposal>(vault.dao_id(), object::id_from_address(@0x2));
let withdrawn = vault.withdraw<SUI, TestProposal>(400, &req, scenario.ctx());
assert!(withdrawn.value() == 400);
assert!(vault.balance<SUI>() == 600);

proposal::consume(req);
transfer::public_transfer(withdrawn, CREATOR);
test_scenario::return_shared(vault);
```

```move
// From gate_tests: every bit except TREASURY_WITHDRAW
#[test, expected_failure(abort_code = proposal::EPermissionDenied)]
fun withdraw_needs_treasury_withdraw() {
    run!(|dao, treasury, _, _, _, ctx| {
        let r = all_but(dao, permissions::treasury_withdraw());
        let coin = treasury.withdraw<SUI, Probe>(1, &r, ctx);
        abort 0
    });
}

#[test, expected_failure(abort_code = treasury_vault::EDAOIdMismatch)]
fun test_withdraw_other_dao_request_aborts() {   // planned
    // ... vault holding 1000 SUI
    let req = proposal::new_execution_request_for_testing<TestProposal>(
        object::id_from_address(@0xD1FF),   // not the vault's DAO
        object::id_from_address(@0x2),
    );
    let coin = vault.withdraw<SUI, TestProposal>(1, &req, scenario.ctx());
    abort 0
}
```

---

### coin_types mirrors the non-zero balances

**Requirement:** A first deposit of `T` adds a `Balance<T>` field and inserts `T`'s name into `coin_types`; later deposits join the balance. A withdrawal that leaves a positive balance keeps both; one that empties the balance removes the field and the registry entry. `balance<T>` returns 0 when there is no field.

**Why it matters:** `coin_types` is how clients and `TransferAssets` payloads learn what the treasury holds without scanning dynamic fields, and `dao::destroy` uses it to decide the treasury is empty. A stale entry would show a phantom balance and block destruction.

```move
// From treasury_vault_tests::test_withdraw_exact_balance_removes_field
let mut vault = scenario.take_shared<TreasuryVault>();
vault.deposit(coin::mint_for_testing<SUI>(1000, scenario.ctx()), scenario.ctx());

let req = create_test_execution_request<TestProposal>(&vault);
let withdrawn = vault.withdraw<SUI, TestProposal>(1000, &req, scenario.ctx());

let sui = std::type_name::with_original_ids<SUI>().into_string();
assert!(!vault.coin_types().contains(&sui));
assert!(vault.coin_types().length() == 0);
assert!(vault.balance<SUI>() == 0);
```

---

### Deposits are permissionless

**Requirement:** `deposit<T>(vault, coin, ctx)` needs no request; anyone may call it. A zero-value coin is destroyed and nothing is registered. `deposit_multicoin(vault, balance, ctx)` behaves the same for multicoin balances.

**Why it matters:** DAOs receive revenue, grants and payments from anyone without a governance round.

```move
// From treasury_vault_tests::test_deposit_permissionless
scenario.next_tx(NON_MEMBER);
{
    let mut vault = scenario.take_shared<TreasuryVault>();
    vault.deposit(coin::mint_for_testing<SUI>(500, scenario.ctx()), scenario.ctx());
    assert!(vault.balance<SUI>() == 500);
    test_scenario::return_shared(vault);
};
```

---

### Insufficient balance aborts

**Requirement:** `withdraw` aborts `treasury_vault::EInsufficientBalance` if the type has no balance field or its balance is below `amount`; `withdraw_multicoin` does the same when the collection, the asset or the amount is missing.

**Why it matters:** A clear abort before any mutation, so an approved but underfunded payment fails cleanly and can be retried after a deposit (the proposal stays Passed; see `04_proposals.md`).

```move
#[test, expected_failure(abort_code = treasury_vault::EInsufficientBalance)]
fun test_withdraw_insufficient_balance_aborts() {
    // ... vault holding 100 SUI
    let req = create_test_execution_request<TestProposal>(&vault);
    let withdrawn = vault.withdraw<SUI, TestProposal>(200, &req, scenario.ctx());
    // unreachable
}
```

---

### claim_coin recovers directly transferred coins

**Requirement:** `claim_coin<T>(vault, Receiving<Coin<T>>, ctx)` is permissionless. It receives a coin that was transferred to the vault's address (`transfer::public_transfer(coin, vault_address)`), emits `CoinClaimed` and deposits it. The coin can only go into the vault.

**Why it matters:** Coins sent to the vault's address instead of through `deposit` would otherwise be stuck.

```move
// From treasury_vault_tests::test_claim_coin_recovers_direct_transfer
scenario.next_tx(CREATOR);
{
    let coin = coin::mint_for_testing<SUI>(50_000, scenario.ctx());
    transfer::public_transfer(coin, vault_id.to_address());
};

scenario.next_tx(CREATOR);
{
    let mut vault = scenario.take_shared<TreasuryVault>();
    assert!(vault.balance<SUI>() == 0);
    let ticket = test_scenario::most_recent_receiving_ticket<coin::Coin<SUI>>(&vault_id);
    vault.claim_coin<SUI>(ticket, scenario.ctx());
    assert!(vault.balance<SUI>() == 50_000);
    test_scenario::return_shared(vault);
};
```

---

### Multicoin balances

**Requirement:** `deposit_multicoin` creates a `CollectionRecord` for a new collection (incrementing `multicoin_collection_count`) and a `MultiCoinBalance` for a new asset (incrementing the record's `item_count`), or joins an existing balance. `withdraw_multicoin` splits the balance, removes the asset when it reaches zero, and removes the record when its last asset goes. `multicoin_balance` and `collection_item_count` return 0 for missing entries.

**Why it matters:** The records are the enumeration path for off-chain readers (dynamic fields of the vault, then of each record), and `is_empty` depends on the collection count.

```move
// From treasury_vault_multicoin_tests::test_withdraw_last_asset_removes_collection
let bal = multicoin::create_balance_for_testing(coll(COLL_A), ASSET_SWORD, 5, scenario.ctx());
vault.deposit_multicoin(bal, scenario.ctx());

let req = make_req(&vault);
let withdrawn = vault.withdraw_multicoin(coll(COLL_A), ASSET_SWORD, 5, &req, scenario.ctx());
assert!(vault.multicoin_collection_count() == 0);
assert!(vault.collection_item_count(coll(COLL_A)) == 0);
assert!(vault.multicoin_balance(coll(COLL_A), ASSET_SWORD) == 0);
```

---

### Emptiness and destroy_empty

**Requirement:** `is_empty` is true when `coin_types` is empty and there are no multicoin collections. `destroy_empty` (`public(package)`, called by `dao::destroy`) aborts `treasury_vault::EVaultNotEmpty` otherwise.

**Why it matters:** Destroying a treasury that still holds balances would burn them.

```move
#[test, expected_failure(abort_code = treasury_vault::EVaultNotEmpty)]
fun test_destroy_empty_aborts_on_non_empty_vault() {
    let mut scenario = test_scenario::begin(CREATOR);
    scenario.next_tx(CREATOR);
    {
        let mut vault = treasury_vault::new(object::id_from_address(@0xDA0), scenario.ctx());
        vault.deposit(coin::mint_for_testing<SUI>(100, scenario.ctx()), scenario.ctx());
        treasury_vault::destroy_empty(vault);
    };
    scenario.end();
}
```

---

### Treasury events (planned)

**Requirement:** `deposit` emits `CoinDeposited { vault_id, dao_id, coin_type, amount, depositor }` (not for a zero-value coin); `withdraw` emits `CoinWithdrawn { vault_id, dao_id, coin_type, amount, recipient }`, where `recipient` is the transaction sender (the executor), not the handler's payee; `claim_coin` emits `CoinClaimed { …, claimer }` and then `CoinDeposited`. The multicoin functions emit `MultiCoinDeposited` / `MultiCoinWithdrawn` with the same `recipient` rule.

**Why it matters:** Indexers build treasury history from these events. No test reads them today.

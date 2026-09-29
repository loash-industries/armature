# Treasury Vault Tests

## Summary

`treasury_vault.move` holds an OU's coins. Each coin type's `Balance<T>` is a dynamic field keyed by the type's name string (`type_name::with_original_ids<T>().into_string()`), and `coin_types` lists the types with a non-zero balance. Deposits and claims are permissionless; withdrawals need an `ExecutionRequest` for the vault's OU carrying `TREASURY_WITHDRAW`.

These tests verify the withdrawal gate, the registry's sync with the balances, zero-balance cleanup, permissionless deposits and claims, and the emptiness checks `ou::destroy` relies on. The spending handlers (`SendCoin`, `SendCoinToOU`, `SendSmallPayment`) are in `11_treasury_ops.md`.

## Test Matrix

**Withdrawals**

| Test | Expected | Where |
|------|----------|-------|
| `test_withdraw_with_valid_request_succeeds` | A request for the vault's OU holding the bit withdraws 400 of 1000 | `treasury_vault_tests` |
| `withdraw_needs_treasury_withdraw` | Every bit except `TREASURY_WITHDRAW`: `proposal::EPermissionDenied` | `gate_tests` |
| `bypass_ticket_cannot_withdraw_from_treasury` | A request of a type holding no bits: `proposal::EPermissionDenied` | `armature_external_type_tests::external_type_lifecycle_tests` |
| `test_withdraw_other_ou_request_aborts` | A request for another OU: `treasury_vault::EOUIdMismatch` | planned |
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
| `test_treasury_events` | `CoinDeposited`, `CoinWithdrawn`, `CoinClaimed` carry the vault and OU IDs, type string and amount | planned |

**Emptiness and destruction**

| Test | Expected | Where |
|------|----------|-------|
| `test_destroy_empty_succeeds_on_empty_vault` | `destroy_empty` deletes a fresh vault | `treasury_vault_tests` |
| `test_destroy_empty_aborts_on_non_empty_vault` | A coin balance left: `treasury_vault::EVaultNotEmpty` | `treasury_vault_tests` |

## Tests

---

### Withdraw requires TREASURY_WITHDRAW on a request for the vault's OU

**Requirement:** `treasury_vault::withdraw<T, P>(vault, amount, &ExecutionRequest<P>, ctx): Coin<T>` is public but needs a request, and only framework code mints requests. It checks the request's OU against the vault's (`treasury_vault::EOUIdMismatch`), then the bit (`proposal::EPermissionDenied` unless the request carries `TREASURY_WITHDRAW` or is privileged). The bit is fixed on `TransferAssets`; extension types get it when enabled at 80% (`armature_proposals::type_permissions::treasury_spend()`). The handler reads the amount and recipient from the approved payload, since only `P`'s module can reach the request (see `04_proposals.md`).

**Why it matters:** Without this gate anyone could drain the treasury, and without the bit check any approved request, of any type, could.

```move
// From treasury_vault_tests::test_withdraw_with_valid_request_succeeds
let mut vault = scenario.take_shared<TreasuryVault>();
vault.deposit(coin::mint_for_testing<SUI>(1000, scenario.ctx()), scenario.ctx());

let req = proposal::new_execution_request_for_testing<TestProposal>(vault.ou_id(), object::id_from_address(@0x2));
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
    run!(|ou, treasury, _, _, _, ctx| {
        let r = all_but(ou, permissions::treasury_withdraw());
        let coin = treasury.withdraw<SUI, Probe>(1, &r, ctx);
        abort 0
    });
}

#[test, expected_failure(abort_code = treasury_vault::EOUIdMismatch)]
fun test_withdraw_other_ou_request_aborts() {   // planned
    // ... vault holding 1000 SUI
    let req = proposal::new_execution_request_for_testing<TestProposal>(
        object::id_from_address(@0xD1FF),   // not the vault's OU
        object::id_from_address(@0x2),
    );
    let coin = vault.withdraw<SUI, TestProposal>(1, &req, scenario.ctx());
    abort 0
}
```

---

### coin_types mirrors the non-zero balances

**Requirement:** A first deposit of `T` adds a `Balance<T>` field and inserts `T`'s name into `coin_types`; later deposits join the balance. A withdrawal that leaves a positive balance keeps both; one that empties the balance removes the field and the registry entry. `balance<T>` returns 0 when there is no field.

**Why it matters:** `coin_types` is how clients and `TransferAssets` payloads learn what the treasury holds without scanning dynamic fields, and `ou::destroy` uses it to decide the treasury is empty. A stale entry would show a phantom balance and block destruction.

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

**Requirement:** `deposit<T>(vault, coin, ctx)` needs no request; anyone may call it. A zero-value coin is destroyed and nothing is registered.

**Why it matters:** OUs receive revenue, grants and payments from anyone without a governance round.

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

**Requirement:** `withdraw` aborts `treasury_vault::EInsufficientBalance` if the type has no balance field or its balance is below `amount`.

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

### Emptiness and destroy_empty

**Requirement:** `is_empty` is true when `coin_types` is empty. `destroy_empty` (`public(package)`, called by `ou::destroy`) aborts `treasury_vault::EVaultNotEmpty` otherwise.

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

**Requirement:** `deposit` emits `CoinDeposited { vault_id, ou_id, coin_type, amount, depositor }` (not for a zero-value coin); `withdraw` emits `CoinWithdrawn { vault_id, ou_id, coin_type, amount, recipient }`, where `recipient` is the transaction sender (the executor), not the handler's payee; `claim_coin` emits `CoinClaimed { …, claimer }` and then `CoinDeposited`.

**Why it matters:** Indexers build treasury history from these events. No test reads them today.

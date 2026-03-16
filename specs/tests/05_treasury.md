# Treasury Vault Tests

## Summary

The `treasury.move` module manages multi-coin storage via dynamic fields keyed by `TypeName`. These tests verify that withdrawals require governance authorization, the `coin_types` registry stays in sync, and zero-balance cleanup is enforced.

## Test Matrix

| Test | Expected |
|------|----------|
| `test_withdraw_requires_execution_request` | `withdraw` is `public(friend)` — cannot be called externally |
| `test_withdraw_with_valid_request_succeeds` | Authorized withdrawal returns correct coin |
| `test_deposit_first_coin_adds_to_registry` | `coin_types` contains the new type |
| `test_deposit_second_coin_type_adds_to_registry` | Both types in `coin_types` |
| `test_deposit_same_type_joins_balance` | Balance increases, `coin_types` unchanged |
| `test_coin_types_reflects_non_zero_balances` | After partial withdraw, type still in registry |
| `test_withdraw_exact_balance_removes_field` | `coin_types` no longer contains the type |
| `test_withdraw_exact_balance_removes_dynamic_field` | Dynamic field gone, balance query returns 0 |
| `test_partial_withdraw_preserves_field` | Type still in registry, balance reduced |
| `test_deposit__permissionless` | Non-member can deposit |
| `test_deposit__zero_amount` | Zero-value deposit is a no-op or handled gracefully |
| `test_withdraw__insufficient_balance_aborts` | Abort `EInsufficientBalance` |
| `test_claim_coin__recovers_direct_transfer` | Coin sent to vault address recovered |
| `test_claim_coin__emits_event` | `CoinClaimed` event with correct fields |
| `test_balance__empty_vault_returns_zero` | No dynamic field -> balance is 0 |
| `test_balance__after_deposit_returns_correct` | Balance matches deposited amount |

## Tests

---

### Withdraw requires ExecutionRequest

**Requirement:** `withdraw` is `public(friend)`, requires `ExecutionRequest`.

**Why it matters:** Without this gate, anyone could drain the treasury. The `ExecutionRequest` proves governance approved the withdrawal.

```move
#[test]
fun test_withdraw_with_valid_request_succeeds() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_funded_dao(&mut scenario, 100);

    // Create, pass, execute SendCoin<SUI> for 50
    let prop_id = test_helpers::create_proposal(
        &mut scenario, dao_id,
        treasury_ops::new_send_coin<SUI>(BOB, 50),
    );
    test_helpers::pass_proposal<treasury_ops::SendCoin<SUI>>(
        &mut scenario, prop_id, vector[ALICE, BOB, CAROL],
    );

    scenario.next_tx(ALICE);
    {
        let mut prop = test_scenario::take_shared<Proposal<treasury_ops::SendCoin<SUI>>>(&scenario);
        let dao = test_scenario::take_shared<DAO>(&scenario);
        let freeze = test_scenario::take_shared<EmergencyFreeze>(&scenario);
        let mut vault = test_scenario::take_shared<TreasuryVault>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());

        let req = proposal::execute(&mut prop, &dao, &freeze, &clock, scenario.ctx());

        // Handler withdraws — this proves withdraw works with valid request
        let coin = treasury::withdraw<SUI, treasury_ops::SendCoin<SUI>>(
            &mut vault, 50, &req, scenario.ctx(),
        );
        assert!(coin::value(&coin) == 50);

        // Transfer to recipient
        transfer::public_transfer(coin, BOB);

        // Consume hot potato
        treasury_ops::consume_request(req);

        clock::destroy_for_testing(clock);
        test_scenario::return_shared(prop);
        test_scenario::return_shared(dao);
        test_scenario::return_shared(freeze);
        test_scenario::return_shared(vault);
    };

    // Verify balance decreased
    test_helpers::assert_balance<SUI>(&mut scenario, /* vault_id */, 50);
    test_scenario::end(scenario);
}
```

---

### First deposit adds type to registry

**Requirement:** `coin_types` exactly reflects non-zero `Balance<T>` dynamic fields.

**Why it matters:** The `coin_types` registry is the only way to enumerate what coins the treasury holds without scanning all dynamic fields. Missing entries would make coins invisible to UIs.

```move
#[test]
fun test_deposit_first_coin_adds_to_registry() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE]);

    scenario.next_tx(ALICE);
    {
        let mut vault = test_scenario::take_shared<TreasuryVault>(&scenario);

        // Before deposit: coin_types is empty
        assert!(!treasury::has_coin_type<SUI>(&vault));

        let coin = coin::mint_for_testing<SUI>(100, scenario.ctx());
        treasury::deposit(&mut vault, coin);

        // After deposit: SUI is in coin_types
        assert!(treasury::has_coin_type<SUI>(&vault));
        assert!(treasury::balance<SUI>(&vault) == 100);

        test_scenario::return_shared(vault);
    };
    test_scenario::end(scenario);
}
```

---

### Second coin type added correctly

```move
#[test]
fun test_deposit_second_coin_type_adds_to_registry() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE]);

    // Define a test coin type
    // struct USDC has drop {}

    scenario.next_tx(ALICE);
    {
        let mut vault = test_scenario::take_shared<TreasuryVault>(&scenario);

        let sui_coin = coin::mint_for_testing<SUI>(100, scenario.ctx());
        treasury::deposit(&mut vault, sui_coin);

        let usdc_coin = coin::mint_for_testing<USDC>(200, scenario.ctx());
        treasury::deposit(&mut vault, usdc_coin);

        // Both types in registry
        assert!(treasury::has_coin_type<SUI>(&vault));
        assert!(treasury::has_coin_type<USDC>(&vault));
        assert!(treasury::balance<SUI>(&vault) == 100);
        assert!(treasury::balance<USDC>(&vault) == 200);

        test_scenario::return_shared(vault);
    };
    test_scenario::end(scenario);
}
```

---

### Same-type deposit joins balance

```move
#[test]
fun test_deposit_same_type_joins_balance() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE]);

    scenario.next_tx(ALICE);
    {
        let mut vault = test_scenario::take_shared<TreasuryVault>(&scenario);

        let coin1 = coin::mint_for_testing<SUI>(100, scenario.ctx());
        treasury::deposit(&mut vault, coin1);

        let coin2 = coin::mint_for_testing<SUI>(50, scenario.ctx());
        treasury::deposit(&mut vault, coin2);

        // Balance is joined, not overwritten
        assert!(treasury::balance<SUI>(&vault) == 150);

        test_scenario::return_shared(vault);
    };
    test_scenario::end(scenario);
}
```

---

### Zero-balance withdrawal removes field and registry entry

**Requirement:** No `Balance<T>` with value zero may exist. Zero-balance withdrawal removes both the dynamic field and the `TypeName` from `coin_types`.

**Why it matters:** Stale zero-balance entries would cause `coin_types` to grow unboundedly and mislead UIs into showing phantom balances.

```move
#[test]
fun test_withdraw_exact_balance_removes_field() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_funded_dao(&mut scenario, 100);

    // Execute SendCoin for exactly 100 SUI (full balance)
    // ... (create, pass, execute proposal, withdraw 100)

    scenario.next_tx(ALICE);
    {
        let vault = test_scenario::take_shared<TreasuryVault>(&scenario);

        // coin_types no longer contains SUI
        assert!(!treasury::has_coin_type<SUI>(&vault));

        // balance query returns 0
        assert!(treasury::balance<SUI>(&vault) == 0);

        test_scenario::return_shared(vault);
    };
    test_scenario::end(scenario);
}
```

---

### Partial withdrawal preserves field

**Why it matters:** Only full withdrawal should remove the entry — partial withdrawal must keep it.

```move
#[test]
fun test_partial_withdraw_preserves_field() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_funded_dao(&mut scenario, 100);

    // Withdraw 50 of 100 SUI
    // ...

    scenario.next_tx(ALICE);
    {
        let vault = test_scenario::take_shared<TreasuryVault>(&scenario);

        // Type still in registry
        assert!(treasury::has_coin_type<SUI>(&vault));
        assert!(treasury::balance<SUI>(&vault) == 50);

        test_scenario::return_shared(vault);
    };
    test_scenario::end(scenario);
}
```

---

### Deposit is permissionless

**Why it matters:** Anyone should be able to contribute to a DAO's treasury — this is how DAOs receive funding, revenue, and donations without governance overhead.

```move
#[test]
fun test_deposit__permissionless() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE]);

    // EVE (not a board member) deposits
    scenario.next_tx(EVE);
    {
        let mut vault = test_scenario::take_shared<TreasuryVault>(&scenario);
        let coin = coin::mint_for_testing<SUI>(100, scenario.ctx());
        treasury::deposit(&mut vault, coin);
        assert!(treasury::balance<SUI>(&vault) == 100);
        test_scenario::return_shared(vault);
    };
    test_scenario::end(scenario);
}
```

---

### Insufficient balance aborts

**Why it matters:** Prevents underflow. Without this, the handler could extract more coins than exist, which would panic at the Balance level anyway — but a clear error is better.

```move
#[test]
#[expected_failure(abort_code = treasury::EInsufficientBalance)]
fun test_withdraw__insufficient_balance_aborts() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_funded_dao(&mut scenario, 50);

    // Attempt to withdraw 100 from a vault with only 50
    // ... (create SendCoin for 100, pass, execute -> handler aborts)
    test_scenario::end(scenario);
}
```

---

### claim_coin recovers directly-transferred coins

**Why it matters:** Users might accidentally send `Coin<T>` directly to the vault's address (via `transfer::public_transfer`) instead of using `deposit`. `claim_coin` recovers these.

```move
#[test]
fun test_claim_coin__recovers_direct_transfer() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE]);

    // Directly transfer a coin to the vault's address (not via deposit)
    scenario.next_tx(ALICE);
    {
        let vault = test_scenario::take_shared<TreasuryVault>(&scenario);
        let vault_addr = object::id_address(&vault);
        let coin = coin::mint_for_testing<SUI>(75, scenario.ctx());
        transfer::public_transfer(coin, vault_addr);
        test_scenario::return_shared(vault);
    };

    // Claim the coin
    scenario.next_tx(ALICE);
    {
        let mut vault = test_scenario::take_shared<TreasuryVault>(&scenario);
        let receiving = /* Receiving<Coin<SUI>> from the transfer */;
        treasury::claim_coin<SUI>(&mut vault, receiving);

        // Balance now reflects the claimed coin
        assert!(treasury::balance<SUI>(&vault) == 75);
        assert!(treasury::has_coin_type<SUI>(&vault));

        test_scenario::return_shared(vault);
    };
    test_scenario::end(scenario);
}
```

---

### Balance of empty vault returns zero

```move
#[test]
fun test_balance__empty_vault_returns_zero() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE]);

    scenario.next_tx(ALICE);
    {
        let vault = test_scenario::take_shared<TreasuryVault>(&scenario);
        // No deposits made — balance should be 0
        assert!(treasury::balance<SUI>(&vault) == 0);
        test_scenario::return_shared(vault);
    };
    test_scenario::end(scenario);
}
```

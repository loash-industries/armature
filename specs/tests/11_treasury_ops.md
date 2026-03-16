# Treasury Operations Tests

## Summary

The `proposals/treasury_ops.move` module handles `SendCoin<T>` and `SendCoinToDAO<T>`. These tests verify that treasury withdrawals go to the correct recipients and that cross-DAO deposits work.

## Test Matrix

| Type | Test | Expected |
|------|------|----------|
| SendCoin | `test_send_coin__transfers_to_recipient` | Recipient receives the coin |
| SendCoin | `test_send_coin__reduces_treasury_balance` | Treasury balance decreases by amount |
| SendCoin | `test_send_coin__insufficient_balance_aborts` | Abort `EInsufficientBalance` |
| SendCoin | `test_send_coin__generic_coin_type` | Works with non-SUI coin types |
| SendCoin | `test_send_coin__emits_no_extra_events` | Only standard proposal events emitted |
| SendCoinToDAO | `test_send_coin_to_dao__deposits_into_target_treasury` | Target DAO treasury balance increases |
| SendCoinToDAO | `test_send_coin_to_dao__reduces_source_treasury` | Source treasury decreases |

## Tests

---

### SendCoin: transfers to recipient

**Why it matters:** This is the primary spending mechanism. If the coin goes to the wrong address, funds are lost.

```move
#[test]
fun test_send_coin__transfers_to_recipient() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_funded_dao(&mut scenario, 100);

    let prop_id = test_helpers::create_proposal(
        &mut scenario, dao_id,
        treasury_ops::new_send_coin<SUI>(EVE, 30),
    );
    test_helpers::pass_proposal<treasury_ops::SendCoin<SUI>>(
        &mut scenario, prop_id, vector[ALICE, BOB, CAROL],
    );
    // Execute + handle: withdraw 30 SUI, transfer to EVE

    // Verify EVE received the coin
    scenario.next_tx(EVE);
    {
        let coin = test_scenario::take_from_sender<Coin<SUI>>(&scenario);
        assert!(coin::value(&coin) == 30);
        test_scenario::return_to_sender(&scenario, coin);
    };

    // Verify treasury reduced
    test_helpers::assert_balance<SUI>(&mut scenario, /* vault_id */, 70);
    test_scenario::end(scenario);
}
```

---

### SendCoin: insufficient balance aborts

**Why it matters:** Prevents the handler from attempting an impossible withdrawal, which would panic at the Balance level. A clear error message is better than a cryptic Move abort.

```move
#[test]
#[expected_failure(abort_code = treasury::EInsufficientBalance)]
fun test_send_coin__insufficient_balance_aborts() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_funded_dao(&mut scenario, 50);

    // Try to send 100 when only 50 available
    let prop_id = test_helpers::create_proposal(
        &mut scenario, dao_id,
        treasury_ops::new_send_coin<SUI>(EVE, 100),
    );
    test_helpers::pass_proposal<treasury_ops::SendCoin<SUI>>(
        &mut scenario, prop_id, vector[ALICE, BOB, CAROL],
    );
    // Execute → handler tries withdraw(100) with balance 50 → abort
    test_scenario::end(scenario);
}
```

---

### SendCoin: works with generic coin type

**Why it matters:** The treasury is multi-coin. `SendCoin<T>` must work with any coin type, not just SUI.

```move
#[test]
fun test_send_coin__generic_coin_type() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE, BOB, CAROL]);

    // Deposit USDC into treasury
    scenario.next_tx(ALICE);
    {
        let mut vault = test_scenario::take_shared<TreasuryVault>(&scenario);
        let coin = coin::mint_for_testing<USDC>(500, scenario.ctx());
        treasury::deposit(&mut vault, coin);
        test_scenario::return_shared(vault);
    };

    // Enable SendCoin<USDC> if not default, or assume it's parameterized
    // Create and pass SendCoin<USDC> proposal for 200
    let prop_id = test_helpers::create_proposal(
        &mut scenario, dao_id,
        treasury_ops::new_send_coin<USDC>(EVE, 200),
    );
    test_helpers::pass_proposal<treasury_ops::SendCoin<USDC>>(
        &mut scenario, prop_id, vector[ALICE, BOB, CAROL],
    );
    // Execute + handle

    // EVE receives 200 USDC
    scenario.next_tx(EVE);
    {
        let coin = test_scenario::take_from_sender<Coin<USDC>>(&scenario);
        assert!(coin::value(&coin) == 200);
        test_scenario::return_to_sender(&scenario, coin);
    };
    test_scenario::end(scenario);
}
```

---

### SendCoinToDAO: deposits into target DAO treasury

**Why it matters:** This enables inter-DAO transfers — funding SubDAOs, paying parent DAOs, etc. The coin must arrive in the target's `TreasuryVault`, not as a loose object.

```move
#[test]
fun test_send_coin_to_dao__deposits_into_target_treasury() {
    let mut scenario = test_scenario::begin(ALICE);
    let (parent_id, child_id) = test_helpers::setup_dao_with_subdao(&mut scenario);

    // Fund parent treasury
    scenario.next_tx(ALICE);
    {
        let mut vault = test_scenario::take_shared<TreasuryVault>(&scenario);
        let coin = coin::mint_for_testing<SUI>(200, scenario.ctx());
        treasury::deposit(&mut vault, coin);
        test_scenario::return_shared(vault);
    };

    // Enable SendCoinToDAO on parent
    test_helpers::enable_proposal_type<treasury_ops::SendCoinToDAO<SUI>>(&mut scenario, parent_id);

    // Send 80 SUI from parent to child treasury
    let prop_id = test_helpers::create_proposal(
        &mut scenario, parent_id,
        treasury_ops::new_send_coin_to_dao<SUI>(child_id, 80),
    );
    test_helpers::pass_proposal<treasury_ops::SendCoinToDAO<SUI>>(
        &mut scenario, prop_id, vector[ALICE, BOB, CAROL],
    );
    // Execute + handle: withdraw from parent, deposit into child

    // Verify child treasury increased
    scenario.next_tx(ALICE);
    {
        let child_vault = test_scenario::take_shared_by_id<TreasuryVault>(&scenario, /* child_vault_id */);
        assert!(treasury::balance<SUI>(&child_vault) == 80);
        test_scenario::return_shared(child_vault);
    };
    test_scenario::end(scenario);
}
```

# Treasury Operations Tests

## Summary

`armature_proposals::treasury_ops` handles the three treasury spend types:

| Type | Handler | Event |
|------|---------|-------|
| `SendCoin<T> { recipient, amount }` | `execute_send_coin<T>(vault, ticket, ctx)` | `CoinSent` |
| `SendCoinToOU<T> { recipient_treasury, amount }` | `execute_send_coin_to_ou<T>(source_vault, target_vault, ticket, ctx)` | `CoinSentToOU` |
| `SendSmallPayment<T> { recipient, amount }` | `execute_send_small_payment<T>(ou, vault, ticket, clock, ctx)` | `SmallPaymentSent` |

None is a default type. Each needs `TREASURY_WITHDRAW` (`type_permissions::treasury_spend()`), so every config enabling it must have `approval_threshold >= 8000` (`ou::permission_floor`); a type enabled without the bit aborts `proposal::EPermissionDenied` when its handler withdraws. Generic types get one slot per instantiation: `SendCoin<SUI>` and `SendCoin<USDC>` are enabled, configured and frozen separately.

Every handler checks that the source vault belongs to the ticket's OU (`treasury_ops::EVaultOUMismatch`); the OU-to-OU handler also checks that the target vault is the payload's `recipient_treasury` (`treasury_ops::ETargetVaultMismatch`). Withdrawals go through `treasury_vault::withdraw`, which checks the vault's OU (`treasury_vault::EOUIdMismatch`), the bit and the balance (`treasury_vault::EInsufficientBalance`), and emits `CoinWithdrawn`. Deposits into a target vault are permissionless.

`TREASURY_WITHDRAW` covers every coin at any amount; the amount is bounded by the handler (the payload's `amount`, and `SendSmallPayment`'s epoch cap). Only `treasury_ops` can spend these tickets (`Permit<P>`), so the recipient and amount always come from the approved payload.

The real tests enable types with the `ou.test_enable_type` seam, which skips the vote and the floors; on a live OU they are enabled by an 80% `EnableProposalType` vote or a creation-time `ProposalTypeInit`. Real suites: `packages/armature_proposals/tests/treasury_ops_tests.move` (9). Currency types that mint into or burn from the treasury (`MintCoin`, `BurnCoin`, …) are in `currency_ops_tests.move` and listed in `17_coverage_summary.md`; the `TreasuryVault` module itself is in `05_treasury.md`.

## Test Matrix

| Type | Test | Expected |
|------|------|----------|
| SendCoin | `send_coin_e2e` | Treasury 1,000,000 → 800,000; recipient receives a 200,000 coin |
| SendCoin | `send_coin_insufficient_balance_aborts` | Balance 100, amount 500: Abort `treasury_vault::EInsufficientBalance` |
| SendCoin | `lifecycle_tests::medium_enterprise_lifecycle` (step 10) | `SendCoin<USDC>` on a SubOU pays 100,000; generic coin type works |
| SendCoin | `composite_tests::composite_send_coin_step_e2e` | SendCoin runs as a composite step |
| SendCoin | `composite_tests::composite_send_coin_step_cannot_add_member` | A SendCoin step's request cannot add a member: Abort `proposal::EPermissionDenied` |
| SendCoin | `test_send_coin__foreign_vault_aborts` (planned) | Another OU's vault: Abort `treasury_ops::EVaultOUMismatch` |
| SendCoin | `test_send_coin__without_treasury_withdraw_aborts` (planned) | Slot enabled without the bit: Abort `proposal::EPermissionDenied` (mutator level: `gate_tests::withdraw_needs_treasury_withdraw`) |
| SendCoin | `test_send_coin__emits_coin_sent` (planned) | `CoinSent { ou_id, coin_type, amount, recipient }` and `treasury_vault::CoinWithdrawn` |
| SendCoinToOU | `send_coin_to_ou_e2e` | Source 1,000,000 → 700,000; target 0 → 300,000 |
| SendCoinToOU | `send_coin_to_ou_target_mismatch_aborts` | Source and target vaults swapped: Abort `treasury_ops::EVaultOUMismatch` |
| SendCoinToOU | `lifecycle_tests::medium_enterprise_lifecycle` (step 9) | Parent sends 500,000 USDC to a SubOU treasury |
| SendCoinToOU | `composite_tests::composite_send_coin_to_ou_step_e2e` | Runs as a composite step |
| SendCoinToOU | `test_send_coin_to_ou__wrong_target_treasury_aborts` (planned) | Target vault ≠ `recipient_treasury`: Abort `treasury_ops::ETargetVaultMismatch` |
| SendSmallPayment | `basic_payment_within_cap_succeeds` | 5,000 of a 10,000 cap (1% of 1,000,000); state lazily created with `epoch_spend` 5,000 |
| SendSmallPayment | `payment_exceeding_cap_aborts` | 8,000 then 5,000 in one epoch: Abort `treasury_ops::EExceedsDailyCap` |
| SendSmallPayment | `epoch_rollover_resets_spend_tracking` | After 24 h: `epoch_spend` = 5,000, cap recomputed from the balance at rollover (9,910) |
| SendSmallPayment | `multiple_coin_types_independent_state` | `SendSmallPayment<SUI>` and `<USDC>` keep separate state (caps 10,000 and 5,000) |
| SendSmallPayment | `lifecycle_tests::small_startup_lifecycle` | Payments before and after a board change |
| SendSmallPayment | `zero_balance_blocks_payments` | Submits and votes only; does not execute (see below) |
| SendSmallPayment | `test_small_payment__zero_balance_aborts` (planned) | Balance 0: the new state's cap is 0, so any amount aborts `treasury_ops::EExceedsDailyCap` |

Unqualified names are in `treasury_ops_tests.move`.

## Tests

---

### SendCoin: transfers to the recipient

**Why it matters:** This is the primary spending mechanism. The coin must reach the payload's recipient and the treasury must drop by exactly the payload's amount.

```move
// send_coin_e2e (condensed)
{
    let mut ou = scenario.take_shared<OU>();
    let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
    // Test seam: no vote, no floors. A live OU needs threshold >= 8000 for this bit.
    ou.test_enable_type<SendCoin<SUI>>(
        b"SendCoin".to_ascii_string(),
        config.with_permissions(type_permissions::treasury_spend()),
    );
    test_scenario::return_shared(ou);
};
// fund: vault.deposit(coin::mint_for_testing<SUI>(1_000_000, ctx), ctx)
// submit: board_voting::submit_proposal(&ou, option::some(..), send_coin::new<SUI>(RECIPIENT, 200_000), &clock, ctx)
// vote:   board_voting::vote(&mut proposal, &ou, true, &clock, ctx)
{
    let ticket = board_voting::ticket_from_vote(&mut ou, proposal, &freeze, &clock, scenario.ctx());
    treasury_ops::execute_send_coin<SUI>(&mut vault, ticket, scenario.ctx());
    assert!(vault.balance<SUI>() == 800_000);
};
scenario.next_tx(RECIPIENT);
{
    let coin = scenario.take_from_sender<sui::coin::Coin<SUI>>();
    assert!(coin.value() == 200_000);
    test_scenario::return_to_sender(&scenario, coin);
};
```

---

### SendCoin: insufficient balance aborts

**Why it matters:** An overdraw must fail cleanly and revert the whole PTB, including the deletion of the proposal: the proposal stays Passed and can be retried while its execution window is open.

`send_coin_insufficient_balance_aborts` funds 100, passes `send_coin::new<SUI>(RECIPIENT, 500)`, and expects `execute_send_coin` to abort with `treasury_vault::EInsufficientBalance`.

---

### SendCoin: works with any coin type

**Why it matters:** The treasury is multi-coin. `SendCoin<T>` must work for any `T`, and each instantiation is its own type with its own slot.

`lifecycle_tests::medium_enterprise_lifecycle` enables `SendCoin<USDC>` on the Finance SubOU (step 10) and pays an employee 100,000 USDC; the Finance treasury drops from 500,000 to 400,000. `multiple_coin_types_independent_state` shows the per-instantiation separation for `SendSmallPayment`.

---

### SendCoinToOU: deposits into the target OU treasury

**Why it matters:** This funds SubOUs and pays other OUs. The coin must land in the target's `TreasuryVault`, not as a loose object, and only in the treasury the board approved.

```move
// send_coin_to_ou_e2e (execution step)
let ticket = board_voting::ticket_from_vote(&mut source_ou, proposal, &freeze, &clock, scenario.ctx());
treasury_ops::execute_send_coin_to_ou<SUI>(
    &mut source_vault,
    &mut target_vault, // must be the payload's recipient_treasury
    ticket,
    scenario.ctx(),
);
assert!(source_vault.balance<SUI>() == 700_000);
assert!(target_vault.balance<SUI>() == 300_000);
```

The payload was `send_coin_to_ou::new<SUI>(target_treasury_id, 300_000)`. `send_coin_to_ou_target_mismatch_aborts` passes the vaults swapped and expects `treasury_ops::EVaultOUMismatch`; a wrong target alone would abort `treasury_ops::ETargetVaultMismatch` (planned for this type, tested for the batch type).

---

### SendSmallPayment: rolling epoch cap

**Requirement:** `execute_send_small_payment<T>` keeps a `SmallPaymentState` in the OU's type-state keyed by `SendSmallPayment<T>`. The first execution creates it with a 24 h epoch and a cap of 1% of the current `T` balance (`utils::mul_bps(balance, 100)`). When `now >= epoch_start + epoch_duration` the epoch restarts at `now`, the spend resets to 0 and the cap is recomputed from the current balance. A payment that would take `epoch_spend + amount` above the cap aborts with `treasury_ops::EExceedsDailyCap`.

**Why it matters:** Recurring small payments still need a vote each, but the handler bounds how much a run of them can take within an epoch. The bound lives in the extension's handler, so it is only as strong as that package's code and upgrade key (`docs/package-boundaries.md`, rule 4).

```move
// basic_payment_within_cap_succeeds: after one 5,000 payment on a 1,000,000 treasury
let state: &send_small_payment::SmallPaymentState = ou.borrow_type_state<
    SendSmallPayment<SUI>,
    send_small_payment::SmallPaymentState,
>();
assert!(state.epoch_spend() == 5_000);
assert!(state.max_epoch_spend() == 10_000);
```

`epoch_rollover_resets_spend_tracking` spends 9,000, advances past 24 h, and pays 5,000: the new cap is 1% of 991,000 = 9,910, computed before the second withdrawal.

**Note on `zero_balance_blocks_payments`:** the test submits and votes but never executes, so it asserts nothing about a zero balance. Its comment expects an `EInsufficientBalance` abort; with a zero balance the new state's cap is 0, so the handler aborts earlier with `treasury_ops::EExceedsDailyCap`. `test_small_payment__zero_balance_aborts` (planned) should execute and expect that code.

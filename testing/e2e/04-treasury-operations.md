# 04 — Treasury Operations

> **Tool:** Playwright (Chromium)
> **Network:** Sui localnet
> **Route:** `/dao/$daoId/treasury`, `/dao/$daoId/proposals/new`

## Prerequisites

- DAO created with board members [A, B, C]
- TreasuryWithdraw, SendCoinToDAO, SendSmallPayment proposal types enabled
- Treasury funded with SUI (via deposit or localnet setup)
- A second DAO exists for cross-DAO transfer tests

## Scenarios

### 4.1 — Deposit SUI into treasury

1. Connect as any wallet (need not be a board member)
2. Navigate to `/dao/$daoId/treasury`
3. Click "Deposit" button
4. Deposit dialog opens — select a coin object from wallet
5. Confirm deposit

**Expected:**

- `buildDeposit` transaction succeeds
- Treasury balance increases by the deposited amount
- Dashboard treasury card updates
- Treasury page shows SUI balance row

### 4.2 — Deposit by non-board-member

1. Connect as wallet X (not a board member)
2. Navigate to treasury page
3. Deposit SUI

**Expected:**

- Deposit succeeds — `treasury_vault::deposit` is permissionless
- Anyone can fund the treasury

### 4.3 — SendCoin (TreasuryWithdraw)

1. Treasury has 10 SUI
2. Connect as wallet A
3. Navigate to `/dao/$daoId/proposals/new?type=TreasuryWithdraw`
4. Fill form:
   - Coin type: SUI
   - Amount: 2 SUI (2_000_000_000 MIST)
   - Recipient: wallet D's address
5. Submit proposal
6. Vote Yes with A and B → Passed
7. Execute

**Expected:**

- Treasury balance decreases by 2 SUI (now 8 SUI)
- Wallet D receives 2 SUI
- `CoinSent` event emitted with correct coin_type, amount, recipient
- Treasury page reflects updated balance

### 4.4 — SendCoinToDAO (cross-DAO transfer)

1. DAO Alpha treasury has 8 SUI
2. DAO Beta exists with its own TreasuryVault
3. Submit SendCoinToDAO proposal:
   - Coin type: SUI
   - Amount: 3 SUI
   - Recipient Treasury ID: DAO Beta's treasury vault ID
4. Vote + execute on DAO Alpha

**Expected:**

- DAO Alpha treasury: 5 SUI
- DAO Beta treasury: +3 SUI
- `CoinSentToDAO` event emitted

### 4.5 — SendSmallPayment — first payment (lazy init)

1. Treasury has 10 SUI
2. Submit SendSmallPayment proposal:
   - Coin type: SUI
   - Amount: 0.05 SUI (50_000_000 MIST)
   - Recipient: wallet D
3. Vote + execute

**Expected:**

- Payment sent to wallet D
- SmallPaymentState initialized:
  - max_epoch_spend = 1% of 10 SUI = 0.1 SUI (100_000_000 MIST)
  - epoch_duration_ms = 86_400_000 (24h)
  - epoch_spend = 50_000_000 (this payment)
- `SmallPaymentSent` event emitted with epoch_spend and max_epoch_spend

### 4.6 — SendSmallPayment — cumulative tracking within epoch

1. After scenario 4.5, within the same 24h epoch
2. Submit another SendSmallPayment:
   - Amount: 0.04 SUI (40_000_000 MIST)
3. Vote + execute

**Expected:**

- Payment succeeds
- Cumulative epoch_spend = 90_000_000 MIST (50M + 40M, under 100M cap)

### 4.7 — Negative: SendSmallPayment exceeds epoch cap

1. After scenario 4.6, within the same epoch
2. Submit SendSmallPayment:
   - Amount: 0.02 SUI (20_000_000 MIST) — would push total to 110M, exceeding 100M cap
3. Vote + execute

**Expected:**

- Execution aborts — epoch spend would exceed max_epoch_spend
- Transaction error shown in UI

### 4.8 — SendSmallPayment — epoch reset

1. Wait for epoch_duration_ms (24h) to elapse (or manipulate clock on localnet)
2. Submit SendSmallPayment for 0.05 SUI
3. Vote + execute

**Expected:**

- Epoch resets: epoch_spend starts fresh
- Payment succeeds
- New max_epoch_spend recalculated based on current treasury balance

### 4.9 — Negative: Withdraw more than treasury balance

1. Treasury has 5 SUI
2. Submit TreasuryWithdraw for 10 SUI
3. Vote + execute

**Expected:**

- Execution fails — insufficient balance
- Treasury balance unchanged

### 4.10 — ClaimCoin (recover directly-transferred coins)

1. Send SUI directly to the TreasuryVault object address via `public_transfer` (not through deposit)
2. Navigate to treasury page
3. Trigger claim action (if UI supports it, otherwise via transaction)

**Expected:**

- `treasury_vault::claim_coin` recovers the coins into the vault
- `CoinClaimed` event emitted
- Treasury balance reflects the claimed amount

### 4.11 — Treasury shows multiple coin types

1. Deposit SUI and another coin type (if available on localnet)
2. Navigate to treasury page

**Expected:**

- Multiple rows shown, one per coin type
- Each row shows correct balance
- Dashboard treasury card shows total or multi-coin summary

### 4.12 — Treasury transaction history

1. Perform several treasury operations (deposit, withdraw, small payment)
2. Navigate to treasury page

**Expected:**

- Transaction history / events section shows recent operations
- Each entry shows type, amount, recipient/sender, timestamp

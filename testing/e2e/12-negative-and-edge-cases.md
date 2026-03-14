# 12 — Negative Tests & Edge Cases

> **Tool:** Playwright (Chromium)
> **Network:** Sui localnet
> **Route:** Various

## Prerequisites

- DAO with board members [A, B, C]
- Non-board wallet X funded
- Various proposal types enabled

## Scenarios

---

## Permission Violations

### 12.1 — Non-board-member cannot submit proposals

1. Connect as wallet X (not a board member)
2. Navigate to `/dao/$daoId/proposals/new?type=SetBoard`
3. Fill form and submit

**Expected:**

- Transaction fails — `board_voting::submit_proposal` aborts (not a board member)
- UI shows error toast or message

### 12.2 — Non-board-member cannot vote

1. Connect as wallet X
2. Navigate to an Active proposal's detail page
3. Attempt to vote

**Expected:**

- Vote buttons disabled or hidden (wallet not in vote snapshot)
- If bypassed, transaction aborts — voter not in snapshot

### 12.3 — Non-board-member cannot execute

1. Connect as wallet X
2. Navigate to a Passed proposal
3. Attempt to execute

**Expected:**

- Execute button disabled or hidden
- If bypassed, transaction aborts — caller not a board member

### 12.4 — Non-board-member CAN deposit to treasury

1. Connect as wallet X
2. Navigate to treasury page
3. Deposit SUI

**Expected:**

- Deposit succeeds — permissionless operation

### 12.5 — Non-board-member CAN mark proposals expired

1. Connect as wallet X
2. Navigate to an expired (by time) Active proposal
3. Click "Mark Expired"

**Expected:**

- Transaction succeeds — `try_expire` is permissionless
- Proposal transitions to Expired

---

## Double Actions

### 12.6 — Cannot vote twice on same proposal

1. Wallet A votes Yes on a proposal
2. Wallet A attempts to vote again (Yes or No)

**Expected:**

- UI disables vote buttons after first vote
- If bypassed, transaction aborts — already voted
- Vote tally unchanged

### 12.7 — Cannot execute an already-executed proposal

1. Execute a proposal successfully
2. Attempt to execute again

**Expected:**

- Execute button hidden/disabled for Executed proposals
- If bypassed, transaction aborts — wrong status

---

## Frozen Type Interactions

### 12.8 — Submit proposal of frozen type succeeds

1. Freeze SetBoard
2. Submit a SetBoard proposal

**Expected:**

- Proposal creation succeeds — freeze only blocks execution, not submission
- Proposal appears in proposals list as Active

### 12.9 — Vote on frozen type proposal succeeds

1. Vote on the SetBoard proposal from 12.8

**Expected:**

- Voting succeeds — freeze only blocks execution
- Proposal can reach Passed status

### 12.10 — Execute frozen type proposal fails

1. SetBoard proposal has Passed status, type is still frozen
2. Attempt to execute

**Expected:**

- Execution blocked — `assert_not_frozen` check fails
- Error message indicates type is frozen
- Proposal stays in Passed (can execute after unfreeze)

---

## Paused DAO Interactions

### 12.11 — Controller-paused SubDAO blocks all execution

1. Parent DAO pauses SubDAO execution
2. On SubDAO, submit and pass a proposal
3. Attempt to execute

**Expected:**

- Execution fails — `is_controller_paused` returns true
- Error indicates DAO is paused by controller

### 12.12 — Execution-paused DAO (via SetExecutionPaused)

> **Note:** This is a contract-level mechanism. Verify if UI exposes it.

1. If `set_execution_paused` is available, pause the DAO
2. Attempt to execute any proposal

**Expected:**

- Execution blocked
- Error indicates execution is paused

---

## Empty State Edge Cases

### 12.13 — Treasury withdraw with zero balance

1. Treasury has 0 SUI
2. Submit TreasuryWithdraw for any amount
3. Vote + execute

**Expected:**

- Execution fails — insufficient balance
- Treasury unchanged

### 12.14 — SendCoinToDAO to self

1. Submit SendCoinToDAO with recipient_treasury = own treasury
2. Vote + execute

**Expected:**

- Verify behavior: does the contract allow self-transfer?
- If allowed, net effect is zero (withdraw + deposit to same vault)

### 12.15 — Proposal with zero-amount treasury operations

1. Submit TreasuryWithdraw with amount = 0

**Expected:**

- Form validation catches zero amount
- If bypassed, verify contract behavior (may succeed as no-op or abort)

---

## Concurrent Proposals

### 12.16 — Multiple active proposals of same type

1. Submit two SetBoard proposals simultaneously
2. Both are Active

**Expected:**

- Both proposals exist and can be voted on independently
- Executing one doesn't affect the other's Active/Passed status
- Executing both in sequence applies changes in order

### 12.17 — Conflicting SetBoard proposals

1. Proposal X: SetBoard [A, B, D]
2. Proposal Y: SetBoard [A, C, E]
3. Both pass
4. Execute X first, then execute Y

**Expected:**

- After X: board = [A, B, D]
- After Y: board = [A, C, E] (last execution wins)
- Wallet B loses board membership after Y executes

---

## Snapshot Isolation

### 12.18 — Board change doesn't affect active proposal snapshots

1. Board is [A, B, C]
2. Submit proposal P1 (snapshot captures [A, B, C])
3. Execute a SetBoard to change board to [A, D, E]
4. Wallet B votes on P1

**Expected:**

- Wallet B CAN vote on P1 — they're in P1's snapshot (captured at creation)
- Wallet D CANNOT vote on P1 — not in snapshot
- New proposals would use the new board [A, D, E]

---

## URL/Input Edge Cases

### 12.19 — Invalid address format in forms

1. Enter a malformed address (wrong length, missing 0x prefix) in a board member field

**Expected:**

- Form validation catches invalid address format
- Submit button disabled or error shown

### 12.20 — Very long proposal metadata

1. Submit a proposal with extremely long metadata/description IPFS CID

**Expected:**

- Transaction either succeeds (if within Sui limits) or fails gracefully
- No UI crash

### 12.21 — Special characters in DAO name/description

1. Create a DAO with special characters: `"Test <DAO> & 'Alpha'"`
2. Navigate to charter page

**Expected:**

- Name/description rendered correctly
- No XSS or rendering issues
- HTML entities properly escaped

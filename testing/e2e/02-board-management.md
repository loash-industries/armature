# 02 — Board Management

> **Tool:** Playwright (Chromium)
> **Network:** Sui localnet
> **Route:** `/dao/$daoId/proposals/new?type=SetBoard`, `/dao/$daoId/board`

## Prerequisites

- DAO created with 3 board members: A (creator), B, C
- All wallets funded
- SetBoard proposal type enabled (default)

## Scenarios

### 2.1 — Add a new board member

1. Connect as wallet A
2. Navigate to `/dao/$daoId/proposals/new?type=SetBoard`
3. Form pre-fills current members [A, B, C]
4. Add member D's address
5. Fill metadata description
6. Submit proposal

**Expected:**

- Proposal created, redirected to proposal detail page
- Proposal status: Active
- Payload shows new_members = [A, B, C, D]

7. Vote Yes with wallet A
8. Vote Yes with wallet B (quorum + threshold met with 2/3 yes)

**Expected:**

- Proposal transitions to Passed

9. Execute with wallet A

**Expected:**

- Proposal status: Executed
- Navigate to `/dao/$daoId/board` — shows 4 members [A, B, C, D]
- `BoardUpdated` event emitted

### 2.2 — Remove a board member

1. Connect as wallet A
2. Submit SetBoard proposal with members [A, B] (removing C)
3. Vote Yes with A and B → Passed
4. Execute

**Expected:**

- Board page shows 2 members [A, B]
- Wallet C can no longer submit, vote, or execute proposals

### 2.3 — Replace entire board

1. Current board: [A, B]
2. Submit SetBoard with members [D, E, F] (replacing everyone including proposer)
3. Vote Yes with A and B → Passed
4. Execute with A

**Expected:**

- Board replaced to [D, E, F]
- Wallets A and B lose all governance privileges
- Wallets D, E, F can now submit proposals

### 2.4 — SetBoard diff preview

1. Navigate to SetBoard form
2. Verify form shows current members pre-filled
3. Remove one member, add two new ones
4. Verify diff preview highlights additions (green) and removals (red)

### 2.5 — Negative: Non-board-member submits SetBoard

1. Connect as wallet X (not a board member)
2. Navigate to `/dao/$daoId/proposals/new?type=SetBoard`
3. Fill form and attempt to submit

**Expected:**

- Transaction fails — `board_voting::submit_proposal` aborts (caller not in governance snapshot)
- UI shows transaction error

### 2.6 — Negative: Empty board replacement

1. Submit SetBoard proposal with empty members list

**Expected:**

- Form validation prevents submission
- If bypassed, transaction aborts (governance validates non-empty)

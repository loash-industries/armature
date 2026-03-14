# 03 — Proposal Lifecycle

> **Tool:** Playwright (Chromium)
> **Network:** Sui localnet
> **Route:** `/dao/$daoId/proposals/*`

## Prerequisites

- DAO created with 3 board members: A, B, C
- At least one proposal type enabled (SetBoard used as the test vehicle)
- Default config: quorum=50%, threshold=50%, expiry=7 days, no execution delay, no cooldown

## Scenarios

### 3.1 — Submit a proposal

1. Connect as wallet A
2. Navigate to `/dao/$daoId/proposals/new`
3. Proposal type selector dialog appears — select "Set Board"
4. Fill form, submit

**Expected:**

- Transaction succeeds
- Redirected to `/dao/$daoId/proposals/$proposalId`
- Proposal detail shows:
  - Status: Active
  - Proposer: wallet A (truncated)
  - Type: SetBoard
  - Vote tally: 0 Yes / 0 No
  - Vote snapshot: 3 members (A, B, C) with weight 1 each
- `ProposalCreated` event emitted
- Proposals list (`/dao/$daoId/proposals`) shows the new proposal

### 3.2 — Vote Yes

1. Connect as wallet B
2. Navigate to proposal detail
3. Click "Vote Yes"

**Expected:**

- Transaction succeeds
- Vote tally updates: 1 Yes (weight 1) / 0 No
- Wallet B's vote recorded — vote button disabled / shows "Voted"
- `VoteCast` event emitted (approve=true, weight=1)
- Proposal remains Active (1/3 = 33%, below 50% quorum)

### 3.3 — Vote No

1. Connect as wallet C
2. Click "Vote No"

**Expected:**

- Vote tally: 1 Yes / 1 No
- `VoteCast` event emitted (approve=false, weight=1)
- Proposal remains Active (2/3 = 66% quorum met, but 1/2 = 50% approval — threshold exactly met)
- Actually: quorum = 2/3 >= 50% (met), approval = 1/2 >= 50% (met) → Passed

> **Note:** With default 50% threshold, 1 yes + 1 no = exactly 50% approval. Verify whether this passes or stays active (depends on `gte_bps` — `>=` comparison).

### 3.4 — Proposal passes on quorum + threshold

1. Start fresh: 3-member board [A, B, C]
2. Submit proposal, vote Yes with A and B

**Expected:**

- After B's vote: quorum = 2/3 = 66% (>= 50%), approval = 2/2 = 100% (>= 50%)
- Proposal transitions to Passed immediately after B's vote
- `ProposalPassed` event emitted
- Proposal detail shows status: Passed
- "Execute" button appears for board members

### 3.5 — Execute a passed proposal

1. Proposal is in Passed state (from 3.4)
2. Connect as wallet A
3. Click "Execute Proposal"

**Expected:**

- Transaction succeeds
- Proposal status: Executed
- `ProposalExecuted` event emitted
- Payload side effects applied (e.g., board updated)

### 3.6 — Mark expired

Setup: Create a proposal type with short expiry for testing (or manipulate clock if possible on localnet).

1. Submit a proposal
2. Wait for expiry period to elapse
3. Any connected user clicks "Mark Expired"

**Expected:**

- `buildTryExpire` transaction succeeds
- Proposal status: Expired
- `ProposalExpired` event emitted
- Cannot vote or execute on expired proposal

### 3.7 — Execution delay

Setup: Create a proposal type with `execution_delay_ms > 0` (e.g., via UpdateProposalConfig or EnableProposalType with custom config).

1. Submit proposal of that type
2. Vote until passed
3. Immediately attempt to execute

**Expected:**

- Execution fails — delay not elapsed
- Wait for delay period
- Execute again — succeeds

### 3.8 — Cooldown between executions

Setup: Create a proposal type with `cooldown_ms > 0`.

1. Submit and execute proposal of that type
2. Submit a second proposal of the same type
3. Vote until passed
4. Immediately attempt to execute

**Expected:**

- Execution fails — cooldown not elapsed since last execution of this type
- Wait for cooldown period
- Execute again — succeeds

### 3.9 — Negative: Cannot vote twice

1. Wallet A votes Yes on a proposal
2. Wallet A attempts to vote again (Yes or No)

**Expected:**

- Transaction fails — already voted
- UI should disable vote buttons after voting

### 3.10 — Negative: Cannot execute Active proposal

1. Proposal is Active (not enough votes)
2. Attempt to execute

**Expected:**

- Execute button not shown (or disabled) for Active proposals
- If bypassed, transaction aborts

### 3.11 — Negative: Cannot execute Expired proposal

1. Proposal has been expired (status: Expired)
2. Attempt to execute

**Expected:**

- Execute button not shown for Expired proposals
- If bypassed, transaction aborts

### 3.12 — Negative: Cannot vote after expiry

1. Proposal expiry has elapsed but status not yet updated (still shows Active)
2. Attempt to vote

**Expected:**

- Vote transaction may fail if contract checks expiry on vote
- Or vote succeeds but proposal cannot pass (depends on implementation)

### 3.13 — Proposals list filtering

1. Create multiple proposals in different states (Active, Passed, Executed, Expired)
2. Navigate to `/dao/$daoId/proposals`
3. Click each status tab: All, Active, Passed, Executed, Expired

**Expected:**

- Each tab filters to only proposals of that status
- "All" tab shows everything
- Counts match actual proposals

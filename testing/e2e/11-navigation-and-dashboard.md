# 11 — Navigation & Dashboard

> **Tool:** Playwright (Chromium)
> **Network:** Sui localnet
> **Route:** All routes under `/ou/$ouId/*` and `/create`

## Prerequisites

- At least one OU created with funded treasury, some proposals, and SubOUs
- Board members [A, B, C]

## Scenarios

---

## Root Navigation

### 11.1 — Create page accessible

1. Navigate to `/create`

**Expected:**

- OU creation form loads
- Form fields: name, description, image URL, board members
- Submit button present

### 11.2 — Navigate to OU after creation

1. Create an OU via `/create`
2. After successful creation

**Expected:**

- Redirected to `/ou/$ouId` (dashboard)
- URL contains the new OU's object ID

---

## Sidebar Navigation

### 11.3 — All sidebar links work

1. Navigate to `/ou/$ouId`
2. Click each sidebar link in order:
   - Dashboard (`/ou/$ouId/`)
   - Treasury (`/ou/$ouId/treasury`)
   - Capability Vault (`/ou/$ouId/vault`)
   - Proposals (`/ou/$ouId/proposals`)
   - Board (`/ou/$ouId/board`)
   - Charter (`/ou/$ouId/charter`)
   - Governance (`/ou/$ouId/governance`)
   - Emergency (`/ou/$ouId/emergency`)
   - SubOUs (`/ou/$ouId/subous`)

**Expected:**

- Each page loads without errors
- Active sidebar item highlighted (`isActive` prop)
- No blank pages or unhandled errors

### 11.4 — "New Proposal" sidebar button

1. Click "New Proposal" button in sidebar

**Expected:**

- Navigates to `/ou/$ouId/proposals/new`
- Proposal type selector dialog appears

---

## Dashboard

### 11.5 — Summary cards accuracy

1. Navigate to dashboard
2. Compare summary cards to on-chain data:
   - Treasury total matches `treasury_vault::balance<SUI>`
   - Board member count matches governance config
   - Charter name matches `charter::name()`
   - Enabled proposal types count matches OU's enabled set

**Expected:**

- All values accurate and match on-chain state

### 11.6 — Treasury balances table

1. Dashboard shows treasury balances section

**Expected:**

- Each coin type row with balance
- "View All" link navigates to `/ou/$ouId/treasury`

### 11.7 — Activity feed

1. Perform several actions (create proposal, vote, execute, deposit)
2. Navigate to dashboard

**Expected:**

- Recent Activity section shows last 10 events
- Events include: OUCreated, ProposalCreated, VoteCast, ProposalPassed, ProposalExecuted, ProposalExpired, TypeFrozen, TypeUnfrozen, CoinClaimed
- Events in reverse chronological order
- Each event shows type, summary, timestamp

### 11.8 — Emergency freeze alert banner

1. Freeze at least one proposal type
2. Navigate to dashboard

**Expected:**

- Alert banner visible: "Emergency Freeze Active" (or similar)
- Banner links to emergency page or shows details

### 11.9 — Migrating OU alert banner

1. OU is in Migrating status
2. Navigate to dashboard

**Expected:**

- Alert banner visible: "OU Migrating" (or similar)
- Banner indicates successor OU

---

## Proposal Type Selector

### 11.10 — Type selector shows correct states

1. Navigate to `/ou/$ouId/proposals/new`
2. Type selector dialog appears

**Expected:**

- Types grouped by category (Board, Admin, Security, Treasury, SubOU, Upgrade)
- Enabled types are selectable
- Disabled types shown but grayed out / not selectable
- Frozen types shown with frozen badge
- Protected types (undisableable) shown with appropriate indicator

### 11.11 — Selecting a type routes to correct form

1. Select "Set Board" from type selector

**Expected:**

- URL updates to `?type=SetBoard`
- Correct form renders (SetBoardForm with member list)

2. Go back, select "Treasury Withdraw"

**Expected:**

- URL updates to `?type=TreasuryWithdraw`
- Custom TreasuryWithdrawForm renders

---

## Error States

### 11.12 — Invalid OU ID in URL

1. Navigate to `/ou/0xinvalid`

**Expected:**

- Error state or "OU not found" message
- No unhandled crash

### 11.13 — Invalid proposal ID in URL

1. Navigate to `/ou/$ouId/proposals/0xinvalid`

**Expected:**

- Error state or "Proposal not found" message
- No unhandled crash

### 11.14 — Wallet disconnects during navigation

1. Connected wallet viewing OU dashboard
2. Disconnect wallet
3. Navigate between pages

**Expected:**

- Read-only pages still load (dashboard, board, charter, governance, treasury, vault)
- Action buttons (vote, execute, deposit) disabled or hidden
- No crash on navigation

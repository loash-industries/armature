# 01 — DAO Creation

> **Tool:** Playwright (Chromium)
> **Network:** Sui localnet
> **Route:** `/create`

## Prerequisites

- Localnet running with packages published
- At least 2 funded wallet addresses in keystore
- UI served at `localhost:5173`

## Scenarios

### 1.1 — Happy Path: Create a new DAO

1. Navigate to `/create`
2. Fill in DAO name (e.g., "Test DAO Alpha")
3. Fill in description (e.g., "A test governance organization")
4. Fill in image URL (optional, e.g., an IPFS CID or blank)
5. Add initial board members:
   - Add wallet address A (creator)
   - Add wallet address B (second member)
6. Click "Create DAO" — wallet prompt appears
7. Sign transaction (`buildCreateDao`)

**Expected:**

- Transaction succeeds
- Redirected to `/dao/$newDaoId` (dashboard)
- Dashboard summary cards show:
  - Treasury: 0 SUI
  - Board Members: 2
  - Charter name matches "Test DAO Alpha"
  - Enabled proposal types: 7 (default set)
- On-chain verification:
  - DAO object exists, status = Active
  - TreasuryVault created and linked (`dao.treasury_id`)
  - CapabilityVault created and linked (`dao.capability_vault_id`)
  - Charter created with correct name/description/image_url
  - EmergencyFreeze created with default 7-day max duration
  - FreezeAdminCap transferred to creator wallet
- Default enabled proposal types:
  - SetBoard
  - CharterUpdate (UpdateMetadata)
  - EnableProposalType
  - DisableProposalType
  - UpdateProposalConfig
  - TransferFreezeAdmin
  - UnfreezeProposalType
- Default config per type: quorum=5000 bps (50%), threshold=5000 bps (50%), expiry=7 days, no execution delay, no cooldown
- `DAOCreated` event emitted with correct fields

### 1.2 — Single board member

1. Navigate to `/create`
2. Fill name and description
3. Add only one board member (the creator)
4. Submit

**Expected:**

- Transaction succeeds — single-member DAOs are valid
- Board page shows 1 member

### 1.3 — Negative: Empty board

1. Navigate to `/create`
2. Fill name and description
3. Leave board members list empty
4. Attempt to submit

**Expected:**

- Form validation prevents submission (submit button disabled or error shown)
- If form allows submission, transaction aborts with contract error (governance validates non-empty)

### 1.4 — Negative: Duplicate board members

1. Navigate to `/create`
2. Add the same address twice in the board members list
3. Attempt to submit

**Expected:**

- Form validation catches duplicate and shows error
- If form allows submission, transaction aborts (governance validates no duplicates)

### 1.5 — Negative: Wallet not connected

1. Navigate to `/create` without connecting a wallet
2. Fill form fields

**Expected:**

- Submit button disabled or prompts wallet connection
- Cannot sign transaction without connected wallet

### 1.6 — Verify companion object linkage

After successful DAO creation (scenario 1.1):

1. Navigate to `/dao/$daoId/treasury` — page loads, shows empty balances
2. Navigate to `/dao/$daoId/vault` — page loads, shows empty vault
3. Navigate to `/dao/$daoId/charter` — shows correct name, description, image
4. Navigate to `/dao/$daoId/emergency` — shows no frozen types, max duration = 7 days
5. Navigate to `/dao/$daoId/board` — shows both board members
6. Navigate to `/dao/$daoId/governance` — shows 7 enabled types with default configs

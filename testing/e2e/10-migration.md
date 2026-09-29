# 10 — Migration (SpawnOU + TransferAssets)

> **Tool:** Playwright (Chromium)
> **Network:** Sui localnet
> **Route:** `/ou/$ouId/proposals/new`

## Prerequisites

- OU with board members [A, B, C]
- SpawnOU and TransferAssets proposal types enabled
- Treasury funded with SUI
- Capability vault may contain some capabilities

## Scenarios

---

## SpawnOU (Initiate Migration)

### 10.1 — Spawn a successor OU

1. Connect as wallet A
2. Submit SpawnOU proposal:
   - Name: "OU v2"
   - Description: "Successor governance organization"
3. Vote + execute

**Expected:**

- New successor OU created with Active status
- Origin OU transitions to Migrating status (irreversible)
- `SuccessorOUSpawned` event emitted with origin_ou_id and successor_ou_id
- Dashboard shows "OU Migrating" alert banner
- Origin OU status field = `Migrating { successor_ou_id }`

### 10.2 — Migrating OU restricts proposal types

1. Origin OU is in Migrating status (from 10.1)
2. Attempt to submit various proposals:
   - SetBoard → should fail
   - CharterUpdate → should fail
   - EnableProposalType → should fail
   - TreasuryWithdraw → should fail
   - TransferAssets → should succeed

**Expected:**

- Only TransferAssets proposals can be submitted on a Migrating OU
- All other types rejected by `board_voting::submit_proposal`
- UI should reflect this (type selector only shows TransferAssets)

---

## TransferAssets

### 10.3 — Transfer coins to successor OU

1. Origin OU (Migrating) has 10 SUI in treasury
2. Submit TransferAssets proposal:
   - target_ou_id: successor OU ID
   - target_treasury_id: successor's treasury vault ID
   - target_vault_id: successor's capability vault ID
   - coin_types: [SUI type name]
   - cap_ids: []
3. Vote + execute

**Expected:**

- SUI balance moves from origin treasury to successor treasury
- `AssetsTransferInitiated` event emitted
- Origin treasury shows 0 SUI
- Successor treasury shows 10 SUI

### 10.4 — Transfer capabilities to successor OU

1. Origin OU vault contains capabilities
2. Submit TransferAssets proposal including cap_ids
3. Vote + execute

**Expected:**

- Capabilities extracted from origin vault and received by successor vault
- Origin vault empty after transfer

### 10.5 — Mixed transfer (coins + capabilities)

1. Origin OU has both coins and capabilities
2. Submit TransferAssets with both coin_types and cap_ids
3. Vote + execute

**Expected:**

- All specified assets transferred in a single PTB
- Max 50 combined assets per transfer

### 10.6 — Negative: TransferAssets exceeds 50-asset limit

1. Attempt TransferAssets with > 50 combined coin types + cap IDs

**Expected:**

- Form validation or transaction aborts at `validate_transfer_assets`

---

## OU Destroy (Post-Migration)

### 10.7 — Destroy drained Migrating OU

> **Note:** This may be contract-level only (no UI). Include as a verification step.

1. Origin OU is Migrating, treasury empty, vault empty
2. Call `ou::destroy` (permissionless)

**Expected:**

- OU object and all companion objects destroyed
- `OUDestroyed` event emitted

### 10.8 — Negative: Cannot destroy OU with remaining assets

1. Origin OU is Migrating but treasury still has coins
2. Attempt `ou::destroy`

**Expected:**

- Aborts — treasury/vault not empty

### 10.9 — Negative: Cannot destroy Active OU

1. OU is Active (not Migrating)
2. Attempt `ou::destroy`

**Expected:**

- Aborts — OU must be in Migrating status

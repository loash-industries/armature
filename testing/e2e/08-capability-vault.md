# 08 — Capability Vault

> **Tool:** Playwright (Chromium)
> **Network:** Sui localnet
> **Route:** `/dao/$daoId/vault`, `/dao/$daoId/proposals/new`

## Prerequisites

- Parent DAO with board members [A, B, C]
- TransferCapToSubDAO and ReclaimCapFromSubDAO proposal types enabled
- At least one SubDAO created (SubDAOControl + child's FreezeAdminCap stored in parent vault)

## Scenarios

### 8.1 — View capability vault

1. Navigate to `/dao/$daoId/vault`

**Expected:**

- Page shows all stored capabilities as cards
- Each card displays: object ID (truncated), type name
- SubDAOControl entries show "Controller" badge and linked SubDAO ID
- FreezeAdminCap entries (if stored) show type name

### 8.2 — Type filter pills

1. Vault contains multiple capability types (e.g., SubDAOControl + FreezeAdminCap)
2. Navigate to vault page

**Expected:**

- Filter pills appear for each distinct type
- Clicking a pill filters to only capabilities of that type
- "All" pill shows everything

### 8.3 — Transfer capability to SubDAO

1. Parent vault contains a capability (e.g., a stored FreezeAdminCap from a child SubDAO)
2. Submit TransferCapToSubDAO proposal:
   - cap_id: the capability's object ID
   - target_subdao: SubDAO's vault ID
3. Vote + execute

**Expected:**

- Capability removed from parent vault
- Capability appears in SubDAO's vault
- `CapTransferredToSubDAO` event emitted
- Parent vault page no longer shows the capability
- SubDAO vault page shows the received capability

### 8.4 — Reclaim capability from SubDAO

1. SubDAO vault contains a capability (transferred in 8.3)
2. On the parent DAO, submit ReclaimCapFromSubDAO proposal:
   - subdao_id: SubDAO's ID
   - cap_id: the capability's object ID in SubDAO vault
   - control_id: SubDAOControl object ID in parent vault
3. Vote + execute on parent DAO

**Expected:**

- Capability removed from SubDAO vault (via `privileged_extract`)
- Capability appears in parent vault
- `CapReclaimedFromSubDAO` event emitted
- No governance action needed on SubDAO side (parent uses SubDAOControl authority)

### 8.5 — Vault actions dropdown — Transfer Freeze Admin

1. Vault contains a FreezeAdminCap
2. Click actions dropdown on the FreezeAdminCap card
3. Click "Transfer Freeze Admin"

**Expected:**

- Navigates to `/dao/$daoId/proposals/new?type=TransferFreezeAdmin`
- Form pre-populated if applicable

### 8.6 — Vault is empty after all capabilities extracted

1. Extract all capabilities from vault
2. Navigate to vault page

**Expected:**

- Empty state shown (e.g., "No capabilities stored")
- No filter pills

### 8.7 — Negative: Transfer non-existent capability

1. Submit TransferCapToSubDAO with a cap_id that doesn't exist in vault
2. Vote + execute

**Expected:**

- Execution fails — capability not found in vault

### 8.8 — Negative: Reclaim from uncontrolled DAO

1. Attempt ReclaimCapFromSubDAO targeting a DAO that is NOT controlled by this parent
2. Vote + execute

**Expected:**

- Execution fails — SubDAOControl doesn't match target DAO

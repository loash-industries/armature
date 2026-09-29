# 09 — SubOU Operations

> **Tool:** Playwright (Chromium)
> **Network:** Sui localnet
> **Route:** `/ou/$ouId/subous`, `/ou/$ouId/proposals/new`

## Prerequisites

- Parent OU with board members [A, B, C]
- CreateSubOU, PauseSubOUExecution, UnpauseSubOUExecution, SpinOutSubOU proposal types enabled
- Additional funded wallet addresses for SubOU board members

## Scenarios

---

## CreateSubOU

### 9.1 — Full wizard flow

1. Connect as wallet A
2. Navigate to `/ou/$ouId/proposals/new?type=CreateSubOU`
3. Wizard opens with 6 steps:

**Step 1 — Identity:**
- Fill SubOU name: "Engineering SubOU"
- Fill description: "Handles engineering decisions"
- Click Next

**Step 2 — Board:**
- Add board members: wallet D, wallet E
- Click Next

**Step 3 — Charter:**
- Fill charter name, description, optional image URL
- Click Next

**Step 4 — Proposal Types:**
- Checkbox grid of available types
- Verify SpawnOU, SpinOutSubOU, CreateSubOU are blocked (grayed out / disabled)
- Enable: SetBoard, CharterUpdate, EnableProposalType, DisableProposalType, UpdateProposalConfig, TransferFreezeAdmin, UnfreezeProposalType
- Click Next

**Step 5 — Funding:**
- Enter initial SUI funding: 5 SUI (5_000_000_000 MIST)
- Click Next

**Step 6 — Review:**
- Summary shows all configured values
- Click "Submit Proposal"

4. Sign transaction

**Expected:**

- CreateSubOU proposal created
- Redirected to proposal detail

5. Vote Yes with A and B → Passed
6. Execute

**Expected:**

- SubOU created as a shared object
- Parent vault now contains:
  - SubOUControl token (binding parent → SubOU)
  - SubOU's FreezeAdminCap
- `SubOUCreated` event emitted with controller_ou_id, subou_id, control_cap_id
- SubOU has:
  - Board governance with members [D, E]
  - Charter with specified name/description
  - Empty treasury (or funded if funding step wired)
  - Enabled proposal types as selected (minus hierarchy-altering types)
  - controller_cap_id set to parent's SubOUControl ID

### 9.2 — SubOU appears on SubOUs page

1. After creating a SubOU (9.1)
2. Navigate to `/ou/$ouId/subous`

**Expected:**

- SubOU card appears in the list view
- Card shows SubOU name, board member count
- No paused badges (fresh SubOU)
- Toggle to graph view shows parent-child hierarchy

### 9.3 — Navigate into SubOU context

1. Click on SubOU card
2. Navigates to `/ou/$subouId`

**Expected:**

- Full OU dashboard loads for the SubOU
- All pages functional (treasury, vault, board, charter, emergency, governance)
- Board page shows members [D, E]
- Governance page shows enabled types (without SpawnOU/SpinOutSubOU/CreateSubOU)

---

## Pause/Unpause SubOU Execution

### 9.4 — Pause SubOU execution

1. On the parent OU, connect as wallet A
2. Submit PauseSubOUExecution proposal:
   - control_id: SubOUControl object ID from parent vault
3. Vote + execute on parent OU

**Expected:**

- SubOU's `controller_paused` flag set to true
- `SubOUExecutionPaused` event emitted
- SubOUs page shows paused badge on the SubOU card
- A privileged proposal created on the SubOU for audit trail

### 9.5 — Paused SubOU cannot execute proposals

1. SubOU is controller-paused (from 9.4)
2. Connect as SubOU board member (wallet D)
3. Submit a proposal on the SubOU
4. Vote until Passed
5. Attempt to execute

**Expected:**

- Execution fails — `board_voting::authorize_execution` checks `is_controller_paused`
- Proposal stays in Passed state

### 9.6 — Unpause SubOU execution

1. SubOU is controller-paused
2. On parent OU, submit UnpauseSubOUExecution proposal:
   - control_id: same SubOUControl ID
3. Vote + execute on parent OU

**Expected:**

- SubOU's `controller_paused` flag cleared
- `SubOUExecutionUnpaused` event emitted
- SubOUs page no longer shows paused badge
- Previously-passed proposals on SubOU can now be executed

---

## SpinOutSubOU

### 9.7 — Grant SubOU full independence

1. SubOU exists with controller relationship
2. On parent OU, submit SpinOutSubOU proposal:
   - subou_id: SubOU's object ID
   - (plus config params for SpawnOU, SpinOutSubOU, CreateSubOU to enable on SubOU)
3. Vote + execute on parent OU

**Expected:**

- SubOU's `controller_cap_id` cleared
- SubOU's `controller_paused` cleared
- SpawnOU, SpinOutSubOU, CreateSubOU re-enabled on SubOU with specified configs
- SubOU's FreezeAdminCap transferred from parent vault to SubOU's vault
- SubOUControl token permanently destroyed
- `SubOUSpunOut` event emitted
- Parent's SubOUs page no longer lists this SubOU
- SubOU's governance page shows all 3 hierarchy types now enabled

### 9.8 — Spun-out SubOU operates independently

1. After spin-out (9.7)
2. Navigate to SubOU context
3. Submit a CreateSubOU proposal on the now-independent SubOU

**Expected:**

- Proposal creation succeeds — CreateSubOU is now available
- SubOU can create its own children

---

## SubOU Page Views

### 9.9 — List view vs graph view toggle

1. Create 2+ SubOUs
2. Navigate to SubOUs page
3. Toggle between list and graph views

**Expected:**

- List view: grid of SubOU cards with details
- Graph view: visual hierarchy tree showing parent-child relationships
- Both views consistent in data shown

### 9.10 — Controller actions menu

1. Navigate to SubOUs page
2. Click controller actions dropdown on a SubOU card

**Expected:**

- Menu shows: Pause Execution, Unpause Execution, Transfer Capability, Reclaim Capability, Spin Out SubOU
- Each option navigates to the correct proposal creation page

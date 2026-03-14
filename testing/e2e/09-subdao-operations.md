# 09 — SubDAO Operations

> **Tool:** Playwright (Chromium)
> **Network:** Sui localnet
> **Route:** `/dao/$daoId/subdaos`, `/dao/$daoId/proposals/new`

## Prerequisites

- Parent DAO with board members [A, B, C]
- CreateSubDAO, PauseSubDAOExecution, UnpauseSubDAOExecution, SpinOutSubDAO proposal types enabled
- Additional funded wallet addresses for SubDAO board members

## Scenarios

---

## CreateSubDAO

### 9.1 — Full wizard flow

1. Connect as wallet A
2. Navigate to `/dao/$daoId/proposals/new?type=CreateSubDAO`
3. Wizard opens with 6 steps:

**Step 1 — Identity:**
- Fill SubDAO name: "Engineering SubDAO"
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
- Verify SpawnDAO, SpinOutSubDAO, CreateSubDAO are blocked (grayed out / disabled)
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

- CreateSubDAO proposal created
- Redirected to proposal detail

5. Vote Yes with A and B → Passed
6. Execute

**Expected:**

- SubDAO created as a shared object
- Parent vault now contains:
  - SubDAOControl token (binding parent → SubDAO)
  - SubDAO's FreezeAdminCap
- `SubDAOCreated` event emitted with controller_dao_id, subdao_id, control_cap_id
- SubDAO has:
  - Board governance with members [D, E]
  - Charter with specified name/description
  - Empty treasury (or funded if funding step wired)
  - Enabled proposal types as selected (minus hierarchy-altering types)
  - controller_cap_id set to parent's SubDAOControl ID

### 9.2 — SubDAO appears on SubDAOs page

1. After creating a SubDAO (9.1)
2. Navigate to `/dao/$daoId/subdaos`

**Expected:**

- SubDAO card appears in the list view
- Card shows SubDAO name, board member count
- No paused badges (fresh SubDAO)
- Toggle to graph view shows parent-child hierarchy

### 9.3 — Navigate into SubDAO context

1. Click on SubDAO card
2. Navigates to `/dao/$subdaoId`

**Expected:**

- Full DAO dashboard loads for the SubDAO
- All pages functional (treasury, vault, board, charter, emergency, governance)
- Board page shows members [D, E]
- Governance page shows enabled types (without SpawnDAO/SpinOutSubDAO/CreateSubDAO)

---

## Pause/Unpause SubDAO Execution

### 9.4 — Pause SubDAO execution

1. On the parent DAO, connect as wallet A
2. Submit PauseSubDAOExecution proposal:
   - control_id: SubDAOControl object ID from parent vault
3. Vote + execute on parent DAO

**Expected:**

- SubDAO's `controller_paused` flag set to true
- `SubDAOExecutionPaused` event emitted
- SubDAOs page shows paused badge on the SubDAO card
- A privileged proposal created on the SubDAO for audit trail

### 9.5 — Paused SubDAO cannot execute proposals

1. SubDAO is controller-paused (from 9.4)
2. Connect as SubDAO board member (wallet D)
3. Submit a proposal on the SubDAO
4. Vote until Passed
5. Attempt to execute

**Expected:**

- Execution fails — `board_voting::authorize_execution` checks `is_controller_paused`
- Proposal stays in Passed state

### 9.6 — Unpause SubDAO execution

1. SubDAO is controller-paused
2. On parent DAO, submit UnpauseSubDAOExecution proposal:
   - control_id: same SubDAOControl ID
3. Vote + execute on parent DAO

**Expected:**

- SubDAO's `controller_paused` flag cleared
- `SubDAOExecutionUnpaused` event emitted
- SubDAOs page no longer shows paused badge
- Previously-passed proposals on SubDAO can now be executed

---

## SpinOutSubDAO

### 9.7 — Grant SubDAO full independence

1. SubDAO exists with controller relationship
2. On parent DAO, submit SpinOutSubDAO proposal:
   - subdao_id: SubDAO's object ID
   - (plus config params for SpawnDAO, SpinOutSubDAO, CreateSubDAO to enable on SubDAO)
3. Vote + execute on parent DAO

**Expected:**

- SubDAO's `controller_cap_id` cleared
- SubDAO's `controller_paused` cleared
- SpawnDAO, SpinOutSubDAO, CreateSubDAO re-enabled on SubDAO with specified configs
- SubDAO's FreezeAdminCap transferred from parent vault to SubDAO's vault
- SubDAOControl token permanently destroyed
- `SubDAOSpunOut` event emitted
- Parent's SubDAOs page no longer lists this SubDAO
- SubDAO's governance page shows all 3 hierarchy types now enabled

### 9.8 — Spun-out SubDAO operates independently

1. After spin-out (9.7)
2. Navigate to SubDAO context
3. Submit a CreateSubDAO proposal on the now-independent SubDAO

**Expected:**

- Proposal creation succeeds — CreateSubDAO is now available
- SubDAO can create its own children

---

## SubDAO Page Views

### 9.9 — List view vs graph view toggle

1. Create 2+ SubDAOs
2. Navigate to SubDAOs page
3. Toggle between list and graph views

**Expected:**

- List view: grid of SubDAO cards with details
- Graph view: visual hierarchy tree showing parent-child relationships
- Both views consistent in data shown

### 9.10 — Controller actions menu

1. Navigate to SubDAOs page
2. Click controller actions dropdown on a SubDAO card

**Expected:**

- Menu shows: Pause Execution, Unpause Execution, Transfer Capability, Reclaim Capability, Spin Out SubDAO
- Each option navigates to the correct proposal creation page

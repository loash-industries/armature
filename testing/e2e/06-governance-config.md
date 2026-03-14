# 06 — Governance Configuration

> **Tool:** Playwright (Chromium)
> **Network:** Sui localnet
> **Route:** `/dao/$daoId/governance`, `/dao/$daoId/proposals/new`

## Prerequisites

- DAO with board members [A, B, C]
- Default 7 proposal types enabled
- Governance config page accessible

## Scenarios

---

## EnableProposalType

### 6.1 — Enable a new proposal type

1. Connect as wallet A
2. Navigate to `/dao/$daoId/governance`
3. Verify TreasuryWithdraw shows as "Disabled"
4. Click "Propose Enable" on TreasuryWithdraw (or navigate to `/proposals/new?type=EnableProposalType`)
5. Fill form:
   - Type key: TreasuryWithdraw
   - Quorum: 6000 bps (60%)
   - Approval threshold: 7000 bps (70%)
   - Expiry: 3 days
   - Execution delay: 1 hour
   - Cooldown: 0
6. Submit proposal

**Expected:**

- Proposal created with EnableProposalType payload

7. Vote Yes with A, B, and C (all 3 — need 66%+ approval floor for EnableProposalType)
8. Execute

**Expected:**

- TreasuryWithdraw now appears as Enabled in governance config page
- Config shows quorum=60%, threshold=70%, expiry=3 days, delay=1 hour
- `ProposalTypeEnabled` event emitted

### 6.2 — Negative: EnableProposalType requires 66% approval floor

1. 3-member board [A, B, C]
2. Submit EnableProposalType proposal
3. Vote: A=Yes, B=No → passes with 50% threshold normally
4. Attempt to execute

**Expected:**

- Execution fails — EnableProposalType enforces 66% approval floor at execution time
- Approval is 1/2 = 50% < 66% → aborts
- Need at least 2 yes out of 2 voters, or 2 yes out of 3 total

### 6.3 — Negative: SubDAO cannot enable hierarchy-altering types

1. On a SubDAO (with controller)
2. Attempt to enable SpawnDAO, SpinOutSubDAO, or CreateSubDAO

**Expected:**

- Transaction fails — SubDAOs cannot enable these types while controller exists

---

## DisableProposalType

### 6.4 — Disable an enabled proposal type

1. TreasuryWithdraw is enabled (from 6.1)
2. Navigate to governance page
3. Click "Propose Disable" on TreasuryWithdraw
4. Submit DisableProposalType proposal with type_key = TreasuryWithdraw
5. Vote + execute

**Expected:**

- TreasuryWithdraw removed from enabled set
- Governance page shows it as Disabled
- `ProposalTypeDisabled` event emitted
- Can no longer submit TreasuryWithdraw proposals

### 6.5 — Negative: Cannot disable undisableable types

1. Attempt to submit DisableProposalType for:
   - EnableProposalType
   - DisableProposalType
   - TransferFreezeAdmin
   - UnfreezeProposalType

**Expected:**

- UI should not show "Propose Disable" button for these types
- If bypassed, execution aborts — type is undisableable
- Governance page shows these types with "Protected" badge

### 6.6 — Disabling a type with active proposals

1. Submit a TreasuryWithdraw proposal (Active)
2. Submit and execute DisableProposalType for TreasuryWithdraw
3. Return to the active TreasuryWithdraw proposal, vote until passed
4. Attempt to execute

**Expected:**

- Execution fails — type is no longer enabled
- The active proposal becomes stranded (can still be expired)

---

## UpdateProposalConfig

### 6.7 — Update quorum and threshold for a proposal type

1. Navigate to governance page
2. Click "Propose Config Change" on SetBoard
3. Fill UpdateProposalConfig form:
   - Target type: SetBoard
   - New quorum: 7000 bps (70%)
   - New approval threshold: 8000 bps (80%)
   - Leave other fields unchanged (None → preserved)
4. Submit, vote + execute

**Expected:**

- Governance config page shows SetBoard with quorum=70%, threshold=80%
- `ProposalConfigUpdated` event emitted
- New proposals of type SetBoard use the updated config

### 6.8 — Update expiry and execution delay

1. Submit UpdateProposalConfig for SetBoard:
   - New expiry: 14 days
   - New execution delay: 24 hours
2. Vote + execute

**Expected:**

- Config updated; future SetBoard proposals have 14-day expiry and 24h delay

### 6.9 — Partial config update (only some fields)

1. Submit UpdateProposalConfig changing only quorum (leave all else as None)
2. Vote + execute

**Expected:**

- Only quorum updated; all other config fields preserved at previous values

### 6.10 — Special: UpdateProposalConfig targeting itself requires 80% approval

1. Submit UpdateProposalConfig with target_type_key = "UpdateProposalConfig"
2. 3-member board: A=Yes, B=Yes, C=No → 2/3 = 66%
3. Attempt to execute

**Expected:**

- Execution fails — 66% < 80% approval floor for self-targeting config changes
- Need all 3 voting Yes, or different board composition

### 6.11 — Negative: Invalid config values

1. Submit UpdateProposalConfig with:
   - quorum = 0 (below minimum 1 bps)
   - Or threshold = 4000 (below minimum 5000 bps)
   - Or expiry < 1 hour

**Expected:**

- Form validation catches invalid values
- If bypassed, transaction aborts at `proposal::new_config` validation

### 6.12 — Governance page displays warnings

1. Navigate to governance page with various config states

**Expected:**

- Critical warnings (red) for security-sensitive types below 50% quorum or 66% approval
- Yellow warnings for types below 30% quorum
- Governance types below 66% approval show yellow warning

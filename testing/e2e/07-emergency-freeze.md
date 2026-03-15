# 07 — Emergency Freeze

> **Tool:** Playwright (Chromium)
> **Network:** Sui localnet
> **Route:** `/dao/$daoId/emergency`

## Prerequisites

- DAO with board members [A, B, C]
- Wallet A holds the FreezeAdminCap for this DAO
- Multiple proposal types enabled (for freeze testing)
- TransferFreezeAdmin, UnfreezeProposalType enabled (defaults)

## Scenarios

---

## Admin Freeze/Unfreeze (Direct Actions)

### 7.1 — Freeze a proposal type

1. Connect as wallet A (FreezeAdminCap holder)
2. Navigate to `/dao/$daoId/emergency`
3. Verify admin controls visible (freeze/unfreeze dropdowns)
4. Select "SetBoard" from freeze dropdown
5. Click "Freeze"

**Expected:**

- `buildFreezeType` transaction succeeds
- Emergency page shows SetBoard as frozen with countdown timer
- Timer = max_freeze_duration (7 days from now)
- `TypeFrozen` event emitted with expiry timestamp
- Governance page shows SetBoard with "Frozen" badge

### 7.2 — Frozen type blocks execution

1. SetBoard is frozen (from 7.1)
2. Submit a SetBoard proposal
3. Vote until Passed
4. Attempt to execute

**Expected:**

- `board_voting::authorize_execution` calls `assert_not_frozen` → aborts
- Execution blocked with freeze error
- Proposal stays in Passed state (can be executed after unfreeze)

### 7.3 — Unfreeze a type (admin action)

1. SetBoard is frozen
2. Connect as wallet A
3. Select "SetBoard" from unfreeze dropdown
4. Click "Unfreeze"

**Expected:**

- `buildUnfreezeType` transaction succeeds
- SetBoard removed from frozen list
- Countdown timer disappears
- `TypeUnfrozen` event emitted
- Previously-passed SetBoard proposals can now be executed

### 7.4 — Re-freeze extends expiry

1. Freeze SetBoard (expiry = now + 7 days)
2. Wait some time
3. Freeze SetBoard again

**Expected:**

- Expiry resets to now + 7 days (extended)
- Only one frozen entry (not duplicated)

### 7.5 — Freeze auto-expires

1. Freeze a type
2. Wait for max_freeze_duration to elapse (or manipulate clock)
3. Check `is_frozen` — should return false

**Expected:**

- Type is no longer frozen after expiry
- Emergency page no longer shows it in active freezes
- Proposals of that type can be executed again

### 7.6 — Negative: Cannot freeze exempt types

1. Attempt to freeze TransferFreezeAdmin
2. Attempt to freeze UnfreezeProposalType

**Expected:**

- UI dropdown should not list these types
- If bypassed, transaction aborts — types are freeze-exempt

### 7.7 — Negative: Non-admin cannot freeze/unfreeze

1. Connect as wallet B (does NOT hold FreezeAdminCap)
2. Navigate to emergency page

**Expected:**

- Admin freeze/unfreeze controls not visible
- Only the informational freeze status table shown

---

## Governance Unfreeze (Proposal-Based)

### 7.8 — Unfreeze via UnfreezeProposalType proposal

1. Freeze SetBoard (admin action)
2. Submit UnfreezeProposalType proposal:
   - type_key: SetBoard
3. Vote + execute

**Expected:**

- SetBoard unfrozen via governance (no FreezeAdminCap needed in this PTB)
- `TypeUnfrozen` event emitted
- UnfreezeProposalType itself is freeze-exempt (can always be proposed and executed)

---

## Transfer FreezeAdminCap

### 7.9 — Transfer freeze admin to new address

1. Some types are currently frozen
2. Submit TransferFreezeAdmin proposal:
   - New admin: wallet B's address
3. Vote + execute (current cap holder wallet A must include FreezeAdminCap in the PTB)

**Expected:**

- ALL currently frozen types are unfrozen (side effect of transfer)
- FreezeAdminCap transferred to wallet B
- `FreezeAdminTransferred` event emitted
- Wallet A no longer sees admin controls
- Wallet B now sees admin controls on emergency page

---

## Freeze Config

### 7.10 — Update max freeze duration

1. Submit UpdateFreezeConfig proposal:
   - new_max_freeze_duration_ms: 14 days (1_209_600_000 ms)
2. Vote + execute

**Expected:**

- Emergency page shows updated max duration
- Future freezes use 14-day window
- `FreezeConfigUpdated` event emitted

---

## Freeze Exempt Types

### 7.11 — Add a type to freeze-exempt set

1. Submit UpdateFreezeExemptTypes proposal:
   - types_to_add: ["SetBoard"]
   - types_to_remove: []
2. Vote + execute

**Expected:**

- SetBoard cannot be frozen anymore
- `FreezeExemptTypeAdded` event emitted

### 7.12 — Remove a type from freeze-exempt set

1. Submit UpdateFreezeExemptTypes proposal:
   - types_to_add: []
   - types_to_remove: ["SetBoard"]
2. Vote + execute

**Expected:**

- SetBoard can be frozen again
- `FreezeExemptTypeRemoved` event emitted

### 7.13 — Negative: Cannot remove mandatory exempt types

1. Submit UpdateFreezeExemptTypes:
   - types_to_remove: ["TransferFreezeAdmin"]
2. Vote + execute

**Expected:**

- Execution aborts — TransferFreezeAdmin and UnfreezeProposalType cannot be removed from exempt set

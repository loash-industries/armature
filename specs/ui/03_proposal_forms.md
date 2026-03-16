# 03 — Proposal Type Forms

18 proposal types organized into 3 tiers by form complexity. All forms share a common wrapper that handles proposal submission (see `01_proposal_lifecycle.md` §Submit Tx).

**Common wrapper behaviour:** Every form includes a "Summary" text input (`FormField` → `Input`) for the proposal description, a pre-submission review panel (`Collapsible` → `Card variant="secondary"`), and a "Submit Proposal" `Button` that triggers the wallet transaction.

**Common awar.dev/ui components (all forms):** `Card` (page container), `CardHeader`, `CardContent`, `Form` (react-hook-form + zod), `FormField`, `FormItem`, `FormLabel`, `FormControl`, `FormDescription`, `FormMessage`, `Input` (summary), `Separator` (between sections), `Collapsible` / `CollapsibleTrigger` / `CollapsibleContent` (review panel), `Button` ("Submit Proposal").

**Common layout (ASCII):**

```
Card
┌─────────────────────────────────────────────────────────────────┐
│ CardHeader  "Proposal Type Name"                                │
│ CardContent                                                     │
│  Form                                                           │
│   FormField "Summary" → Input                                   │
│   Separator                                                     │
│   … type-specific fields …                                      │
│   Separator                                                     │
│   Collapsible "Review"                                          │
│    CollapsibleContent → Card (payload preview)                  │
│   Button "Submit Proposal"                                      │
└─────────────────────────────────────────────────────────────────┘
```

---

## Tier 1: Generic Simple Form (`<GenericProposalForm>`)

9 types that share a single form component with 0–2 fields plus the common summary input. The component renders the appropriate field(s) based on the selected type.

**Type-specific field components:** `Input` (text fields), `Select` (`SelectTrigger`, `SelectContent`, `SelectItem`) for dropdowns, `NumberInput` for durations. Confirmation dialogs use `AlertDialog`.

### 1. UpdateMetadata

| Field | Type | Validation | Source |
|-------|------|------------|--------|
| New Metadata CID | Text input | Non-empty string | User input |

Displays current metadata CID for reference.

### 2. DisableProposalType

| Field | Type | Validation | Source |
|-------|------|------------|--------|
| Proposal Type | Dropdown | Must be in enabled types, must not be protected | `dao.enabled_proposals` minus protected set |

Protected types (EnableProposalType, DisableProposalType, TransferFreezeAdmin, UnfreezeProposalType) excluded from dropdown with `Tooltip` explaining why.

### 3. TransferFreezeAdmin

| Field | Type | Validation | Source |
|-------|------|------------|--------|
| Recipient Address | Address input | Valid Sui address | User input |

Shows current FreezeAdminCap holder for reference.

### 4. UnfreezeProposalType

| Field | Type | Validation | Source |
|-------|------|------------|--------|
| Frozen Type | Dropdown | Must be currently frozen | `emergency_freeze.frozen_types` keys |

Shows expiry `<CountdownTimer>` next to each `SelectItem`. Empty state if nothing is frozen: "No types are currently frozen."

### 5. UpdateFreezeConfig

| Field | Type | Validation | Source |
|-------|------|------------|--------|
| Default Duration | Duration input (hours/days) | Positive integer, converted to ms | User input |

Shows current freeze config for reference.

### 6. SpinOutSubDAO

| Field | Type | Validation | Source |
|-------|------|------------|--------|
| SubDAO | Dropdown | Must be a controlled SubDAO | SubDAOControl objects in parent's vault |

**Confirmation dialog** (`AlertDialog` → `AlertDialogContent`, `AlertDialogTitle`, `AlertDialogDescription`, `AlertDialogAction`, `AlertDialogCancel`): "Spinning out [SubDAO Name] is irreversible. The SubDAO will become fully independent and this DAO will lose all controller privileges. Continue?"

Shows what changes: SubDAOControl destroyed, `controller_cap_id` cleared, hierarchy-altering types re-enabled on the child.

### 7. PauseSubDAOExecution

| Field | Type | Validation | Source |
|-------|------|------------|--------|
| SubDAO | Dropdown | Must be a controlled, non-paused SubDAO | SubDAOControl objects filtered by `controller_paused = false` |

### 8. UnpauseSubDAOExecution

| Field | Type | Validation | Source |
|-------|------|------------|--------|
| SubDAO | Dropdown | Must be a controlled, paused SubDAO | SubDAOControl objects filtered by `controller_paused = true` |

Empty state if no SubDAOs are paused.

### 9. RenewCharterStorage

| Field | Type | Validation | Source |
|-------|------|------------|--------|
| New Blob ID | Text input | Non-empty, valid Walrus blob ID format | User input |

Info text: "This updates the storage blob ID without changing the charter version or content hash. Use this when re-uploading the same content to Walrus for storage renewal."

---

## Tier 2: Custom Forms (8 types)

Each type gets its own form component with specific layouts and validation. All use the common `Form` wrapper above plus the type-specific components noted below.

### 10. SendCoin\<T\> (`<SendCoinForm>`)

| Field | awar.dev/ui Component | Validation | Source |
|-------|----------------------|------------|--------|
| Coin Type | `Select` (`SelectTrigger`, `SelectContent`, `SelectItem`) | Must be in treasury `coin_types` | `treasury.coin_types` |
| Amount | `NumberInput unit="SUI"` | > 0, ≤ treasury balance for selected type | User input; max from `treasury::balance<T>` |
| Recipient Address | `Input` | Valid Sui address | User input |

- `Button variant="ghost" size="xs"` "Max" auto-fills full balance
- Shows current balance for selected coin type
- Amount formatted with appropriate decimals (9 for SUI)

### 11. SendCoinToDAO\<T\> (`<SendCoinForm>` variant)

| Field | awar.dev/ui Component | Validation | Source |
|-------|----------------------|------------|--------|
| Coin Type | `Select` | Must be in treasury `coin_types` | `treasury.coin_types` |
| Amount | `NumberInput` | > 0, ≤ treasury balance for selected type | User input |
| Target DAO ID | `Popover` → `Command` (searchable DAO picker) | Valid DAO object ID | User input or search |

- Same balance display as SendCoin
- DAO picker (`Popover` with `CommandInput` + `CommandList`): search by name/ID, shows target DAO name + treasury address for confirmation

### 12. SetBoard (`<SetBoardForm>`)

| Field | awar.dev/ui Component | Validation | Source |
|-------|----------------------|------------|--------|
| Member Addresses | `Table` with `Input` per row + `Button variant="ghost" size="icon-xs"` (✕ remove) | ≥ 1 address, all valid Sui addresses, no duplicates | Pre-populated from `dao.governance.members` |
| Seat Count | `NumberInput` | ≥ number of members | Pre-populated from `dao.governance.seat_count` |

```
FormField "Board Members"
┌─────────────────────────────────────────────────────────────────┐
│ Table                                                           │
│  # │ Input [address]                    │ Badge   │ Button ✕    │
│  1 │ 0xA1b2…                            │ Badge ✓ │             │
│  2 │ 0xF5e6…                            │ Badge ★ │ Button ✕    │
│                                                                 │
│  Button variant="outline" "+ Add Member"                        │
└─────────────────────────────────────────────────────────────────┘

Card "Diff Preview"
┌─────────────────────────────────────────────────────────────────┐
│  + 0xF5e6…   Badge "added"                                     │
│  - 0xC7d8…   Badge "removed"                                   │
│    0xA1b2…   Badge "unchanged"                                  │
└─────────────────────────────────────────────────────────────────┘
```

- Pre-populated with current board for easy editing
- `Button variant="outline"` "Add Member" appends an empty `Input` row
- `Button variant="ghost" size="icon-xs"` (✕) on each row to remove
- Visual diff: `Badge` with green/red/neutral styling (compared to current board)
- `Alert` warning if removing self from board: "You are removing yourself from the board"

### 13. EnableProposalType (`<EnableTypeForm>`)

| Field | awar.dev/ui Component | Validation | Source |
|-------|----------------------|------------|--------|
| Proposal Type | `Select` | Must not already be enabled | All 18 types minus `dao.enabled_proposals` |
| Quorum (bps) | `NumberInput unit="%"` | 1–10000 | User input |
| Threshold (bps) | `NumberInput unit="%"` | 5000–10000 | User input |
| Execution Delay | `NumberInput` + `Select` (hours/days) | ≥ 0 ms | User input |
| Cooldown | `NumberInput` + `Select` (hours/days) | ≥ 0 ms | User input |
| Expiry | `NumberInput` + `Select` (hours/days) | ≥ 1 hour (3600000 ms) | User input |

- ProposalConfig subform validates all bounds inline with `FormMessage` error messages
- Quorum and threshold display both bps value and percentage (e.g., "6600 bps = 66%") via `FormDescription`
- Duration inputs accept hours/days with ms conversion
- **SubDAO blocklist warning:** If SubDAO, `CreateSubDAO`, `SpinOutSubDAO`, `SpawnDAO` shown as disabled `SelectItem` with `Tooltip`: "Blocked for SubDAOs"
- **Threshold floor warning:** `Alert` inline when below floor (66% for Enable, 80% for self-referential Update)

### 14. UpdateProposalConfig (`<UpdateConfigForm>`)

| Field | awar.dev/ui Component | Validation | Source |
|-------|----------------------|------------|--------|
| Target Type | `Select` | Must be enabled | `dao.enabled_proposals` |
| Quorum (bps) | `NumberInput unit="%"` | 1–10000 | Pre-populated from current config |
| Threshold (bps) | `NumberInput unit="%"` | 5000–10000 | Pre-populated from current config |
| Execution Delay | `NumberInput` + `Select` (hours/days) | ≥ 0 ms | Pre-populated from current config |
| Cooldown | `NumberInput` + `Select` (hours/days) | ≥ 0 ms | Pre-populated from current config |
| Expiry | `NumberInput` + `Select` (hours/days) | ≥ 1 hour | Pre-populated from current config |

- Shows "Current → New" for each changed field (rendered in `Table` with `Badge` highlighting changes)
- **Self-referential warning:** `Alert variant="destructive"` if `Target Type = UpdateProposalConfig`: "Requires ≥ 80% approval threshold." Enforce threshold ≥ 8000 bps.
- Only changed fields are highlighted in the `Collapsible` review panel

### 15. AmendCharter (`<AmendCharterForm>`)

| Field | awar.dev/ui Component | Validation | Source |
|-------|----------------------|------------|--------|
| Charter Content | `Textarea` (markdown editor) inside `Tabs` (Edit / Preview / Diff) | Non-empty | Pre-populated from current charter fetched via Walrus |
| Summary | `Input` | Non-empty (describes what changed) | User input |

```
Tabs variant="underline"
 TabsTrigger "Edit"    TabsTrigger "Preview"    TabsTrigger "Diff"

TabsContent "Edit"     → Textarea (full-width markdown editor)
TabsContent "Preview"  → ScrollArea (rendered markdown)
TabsContent "Diff"     → ScrollArea (additions green, deletions red)
```

**Workflow:**
1. Current charter loaded from Walrus and displayed in `Textarea`
2. User edits content
3. `TabsContent "Diff"` shows changes (current vs proposed)
4. On submit:
   a. Content uploaded to Walrus → returns blob ID (`Progress` bar during upload)
   b. SHA-256 computed client-side from content
   c. Proposal created with `(blob_id, content_hash, summary)`

- `Alert` info: "Charter amendments are recommended to require 80% approval threshold and 48-hour execution delay"

### 16. TransferCapToSubDAO (`<TransferCapForm>`)

| Field | awar.dev/ui Component | Validation | Source |
|-------|----------------------|------------|--------|
| Capability | `Select` (cap picker — type name + truncated ID) | Must be in this DAO's vault, not on loan | `capability_vault.cap_types` → `ids_for_type` |
| Target SubDAO | `Select` (SubDAO picker — name + ID) | Must be a SubDAO controlled by this DAO | SubDAOControl objects in vault |

- Cap picker `SelectItem`s show: Type name, Object ID (`Tooltip` for full ID), and any display metadata
- SubDAO picker `SelectItem`s show: SubDAO name, ID
- `Alert`: "This capability will be moved to [SubDAO Name]'s vault. It can be reclaimed via ReclaimCapFromSubDAO."

### 17. ReclaimCapFromSubDAO (`<ReclaimCapForm>`)

| Field | awar.dev/ui Component | Validation | Source |
|-------|----------------------|------------|--------|
| SubDAO | `Select` (SubDAO picker) | Must be controlled by this DAO | SubDAOControl objects in vault |
| Capability | `Select` (cap picker — loads after SubDAO selection) | Must be in the selected SubDAO's vault | Selected SubDAO's `capability_vault` |

- Two-step selection: pick SubDAO first (`Select`), then pick cap from that SubDAO's vault (second `Select`, items load dynamically — shows `Skeleton` while loading)
- `Alert`: if SubDAO is not paused: "Consider pausing the SubDAO before reclaiming capabilities to prevent in-flight usage"

---

## Tier 3: Wizard (1 type)

### 18. CreateSubDAO (`<CreateSubDAOWizard>`)

Multi-step wizard using `Tabs variant="solid"` as step indicator. Each step validates before allowing "Next". Navigation via `Button` ("← Back" / "Next →") — `Tabs` value is controlled programmatically, not by user click.

```
Card
┌─────────────────────────────────────────────────────────────────┐
│ CardHeader "Create SubDAO"                                      │
│                                                                 │
│ Tabs variant="solid" (step indicator)                           │
│ ┌──────┬──────┬───────┬───────┬───────┬────────┐               │
│ │1 ID  │2 Brd │3 Chrt │4 Types│5 Fund │6 Revw  │               │
│ └──────┴──────┴───────┴───────┴───────┴────────┘               │
│                                                                 │
│ TabsContent (current step content)                              │
│                                                                 │
│ Button "← Back"                            Button "Next →"      │
└─────────────────────────────────────────────────────────────────┘
```

#### Step 1 — Identity

| Field | awar.dev/ui Component | Validation |
|-------|----------------------|------------|
| Name | `Input` | Non-empty |
| Metadata CID | `Input` | Non-empty (IPFS/Arweave CID) |

#### Step 2 — Board

| Field | awar.dev/ui Component | Validation |
|-------|----------------------|------------|
| Member Addresses | `Table` with `Input` per row + `Button` (add/remove) | ≥ 1 valid Sui address, no duplicates |
| Seat Count | `NumberInput` | ≥ member count |

#### Step 3 — Charter

| Field | awar.dev/ui Component | Validation |
|-------|----------------------|------------|
| Charter Content | `Textarea` (markdown editor) | Non-empty |

On wizard completion, content is uploaded to Walrus and SHA-256 computed (same flow as AmendCharter). Upload uses `Progress` indicator.

#### Step 4 — Proposal Types

| Field | awar.dev/ui Component | Validation |
|-------|----------------------|------------|
| Enabled Types | `ScrollArea` → `Table` with `Checkbox` per type + inline `NumberInput` fields for ProposalConfig | ≥ 1 type enabled; each enabled type must have valid config |

- Each type has a `Checkbox` + expandable config inputs (quorum, threshold, delay, cooldown, expiry as `NumberInput`)
- **Blocked types:** `Checkbox disabled` + `Tooltip`: "SubDAOs cannot create or spin out further SubDAOs"
- Protected types: `Checkbox checked disabled` — pre-checked and cannot be unchecked
- Default configs pre-filled with recommended values
- `Alert` info note about blocked types

#### Step 5 — Funding

| Field | awar.dev/ui Component | Validation |
|-------|----------------------|------------|
| Coin Type | `Select` | Must be in parent treasury `coin_types` |
| Amount | `NumberInput` | > 0, ≤ parent treasury balance |

Optional step — `Button variant="ghost"` "Skip — no initial funding".

#### Step 6 — Review & Submit

Summary of all wizard inputs rendered as read-only `Card` sections:
- Identity: Name, metadata CID (`Badge` for CID)
- Board: Member list (`Table`), seat count
- Charter: Content preview (truncated in `ScrollArea`), blob ID (after Walrus upload)
- Proposal Types: `Table` of enabled types with configs
- Funding: Coin type + amount (or `Badge "None"`)

`Button` "Create SubDAO" triggers:
1. Walrus upload (if not already done in Step 3) — `Progress` indicator
2. Wallet transaction for `CreateSubDAO` proposal

`Button variant="outline"` "← Back" on each step to revise. Data preserved across steps via react-hook-form state.

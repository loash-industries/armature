# 01 — Universal Proposal Lifecycle

This is the **canonical reference** for all proposal UI. Every page that shows or interacts with proposals references this document rather than duplicating the flow.

---

## Flow Stages

```
Type Selection → Form Fill → Submit Tx → Active (Voting) → Passed → Delay → Execute Tx → Executed
                                              │
                                              └─── (expiry_ms elapsed) ──→ Expired
```

### Stage Details

| Stage | UI State | awar.dev/ui Components | Entry Condition | Exit Condition |
|-------|----------|----------------------|-----------------|----------------|
| **Type Selection** | Searchable modal listing enabled types grouped by category | `Dialog` → `Command` (`CommandInput`, `CommandList`, `CommandGroup`, `CommandItem`, `CommandEmpty`) | User clicks "New Proposal" | User selects a type |
| **Form Fill** | Type-specific form (see `03_proposal_forms.md`) | `Card`, `Form`, `FormField` + type-specific inputs | Type selected | User clicks "Submit" |
| **Submit Tx** | Wallet approval → loading spinner → success/error toast | `Button` (disabled state), toast via `sonner` | Form validated | Transaction confirmed on-chain |
| **Active (Voting)** | Proposal detail with voting panel | `Card`, `Progress`, `Table`, `Button`, `Badge variant="default"` | `ProposalCreated` event | Quorum + threshold met **or** `expiry_ms` elapsed |
| **Passed** | Voting locked, execution delay countdown shown | `Badge variant="secondary"`, `<CountdownTimer>` | Vote threshold crossed | `execution_delay_ms` elapsed |
| **Delay** | Visual sub-state of Passed — countdown timer, execute button disabled | `Button disabled`, `<CountdownTimer>` | Proposal passes | Timer reaches zero |
| **Execute Tx** | Execute button enabled, wallet approval → loading → success/error | `Button`, toast via `sonner` | Delay elapsed, type not frozen, DAO not paused | Transaction confirmed |
| **Executed** | Read-only detail, "Executed" badge, execution timestamp | `Badge variant="outline"` | Execution tx succeeds | Terminal |
| **Expired** | Read-only detail, "Expired" badge | `Badge variant="destructive"` | `expiry_ms` elapsed without passing **or** `try_expire` called | Terminal |

### Privileged Submit (Controller)

When a controller uses `privileged_submit`, the proposal is created directly in **Passed** status (no voting phase). The UI shows:
- A banner: "This proposal was submitted by the controller DAO — no vote required"
- The execution delay countdown starts immediately
- Vote tally section is replaced with "Controller-injected — bypassed voting"

---

## Proposal Detail View (`<ProposalDetail>`)

The single, reusable detail view for any proposal regardless of type.

### Layout (ASCII)

```
Breadcrumb  Proposals / #3 SetBoard
                                                          ┌──────────────────────────┐
Card (header)                                             │ Card "Voting"            │
┌──────────────────────────────────────────────────┐      │ CardContent              │
│ CardHeader                          CardAction   │      │  Quorum    Progress ██░  │
│  h2 "Set Board Members"            Badge status  │      │  Threshold Progress ███░ │
│  p  "by 0xA… · 2h ago"                          │      │  Separator               │
└──────────────────────────────────────────────────┘      │  Table (voter list)      │
                                                          │   addr  Badge "Yes"      │
Alert (freeze / pause / privileged — contextual)          │   addr  Badge "No"       │
                                                          └──────────────────────────┘
Card "Payload"
┌──────────────────────────────────────────────────┐
│ <PayloadSummary> (dispatched by type)             │
│   Table / Badge / diff content per type           │
└──────────────────────────────────────────────────┘

Card "Actions"
┌──────────────────────────────────────────────────┐
│ <CountdownTimer>   Badge "Voting ends in 2h 15m" │
│ Button "Vote Yes"  Button variant="outline" "No"  │
│ (or) Button "Execute"  (or) Button "Expire"       │
└──────────────────────────────────────────────────┘
```

### Layout Sections

| # | Section | awar.dev/ui Components |
|---|---------|----------------------|
| 1 | **Header** — proposal ID, type badge, status badge (colour-coded), creator address, creation timestamp | `Card`, `CardHeader`, `CardAction`, `Badge` (status variant) |
| 2 | **Payload Summary** — type-dispatched panel (see `04_payload_summaries.md`) | `Card`, `CardContent` → `<PayloadSummary>` (app-level, uses `Table`, `Badge` internally) |
| 3 | **Voting Panel** — quorum progress, threshold progress, voter list, vote buttons | `Card`, `CardContent`, `Progress` (×2), `Separator`, `Table` (`TableHeader`, `TableBody`, `TableRow`, `TableCell`), `Badge` (vote indicator), `Button` (×2 for Yes/No) |
| 4 | **Timers** — context-dependent countdowns | `<CountdownTimer>` (app-level component, renders as `Badge`) |
| 5 | **Action Buttons** | `Button` (default for Vote Yes / Execute), `Button variant="outline"` (Vote No), `Button variant="destructive"` (Expire) |
| 6 | **Privileged Submit Banner** — controller-injected | `Alert` (`AlertTitle`, `AlertDescription`) |
| 7 | **Freeze Banner** — type frozen with countdown | `Alert variant="destructive"` with `<CountdownTimer>` |
| 8 | **Pause Banner** — controller-paused | `Alert variant="destructive"` |

### Voting Panel Detail

- Yes/No vote bars: `Progress` (proportional width)
- Quorum progress bar: `Progress` — `(yes + no) / member_count` vs required quorum (basis points displayed as %)
- Threshold indicator: `Progress` — `yes / (yes + no)` vs required threshold (basis points displayed as %)
- Voter list: `Table` (`TableHeader`, `TableBody`, `TableRow`, `TableCell`) with `Badge` per vote — sortable via `TableSortHead`
- "Vote Yes" / "Vote No": `Button` / `Button variant="outline"` (Board Member only, not yet voted)
- "You voted [Yes/No]": `Badge` indicator if already voted

---

## Common Data Reads

| Data | Source | Used For |
|------|--------|----------|
| Proposal object | `sui_getObject(proposal_id)` | All fields — status, payload, votes, timestamps |
| ProposalConfig for this type | `dao.proposal_configs[TypeName]` | Quorum, threshold, delay, cooldown, expiry values |
| Vote snapshot | `proposal.vote_snapshot` | Voter list, tally computation |
| Board members | `dao.governance.members` | Voter eligibility, member count for quorum calc |
| Freeze status | `emergency_freeze.frozen_types[TypeName]` | Whether execute is blocked + expiry timer |
| Pause status | `dao.controller_paused` | Whether execute is blocked by controller |
| Cooldown | `dao.last_execution[TypeName]` + `config.cooldown_ms` | Whether a new proposal of this type can be created |
| DAO status | `dao.status` | Migrating status blocks non-transfer proposals |

---

## Common Transactions

| Action | Move Function | Signer | Preconditions |
|--------|--------------|--------|---------------|
| Create proposal | `proposal::create<P>(dao, payload, clock)` | Board Member | Type enabled, not on cooldown, DAO not migrating (unless TransferAssets) |
| Vote | `board::vote(proposal, dao, vote_bool, clock)` | Board Member | Status = Active, not already voted |
| Execute | `proposal::execute<P>(proposal, dao, clock) → ExecutionRequest<P>` then type-specific consume | Board Member | Status = Passed, delay elapsed, type not frozen, DAO not paused |
| Try expire | `proposal::try_expire(proposal, clock)` | Board Member | Status = Active, `expiry_ms` elapsed |

---

## Timer Components (`<CountdownTimer>`)

App-level component (not in `@awar.dev/ui`). Renders as a `Badge` with live-updating text. Takes a target timestamp and label. Displays `Xd Xh Xm Xs` or "Elapsed" when past.

| Timer | Shown When | Target Timestamp | Label |
|-------|-----------|-----------------|-------|
| Voting expiry | Status = Active | `proposal.created_at_ms + config.expiry_ms` | "Voting ends in" |
| Execution delay | Status = Passed, delay not elapsed | `proposal.passed_at_ms + config.execution_delay_ms` | "Executable in" |
| Cooldown | After execution, same type | `last_execution_ms + config.cooldown_ms` | "Cooldown ends in" |
| Freeze expiry | Type is frozen | `frozen_types[type].expiry_ms` | "Freeze expires in" |

---

## Error & Retry

| Scenario | UI Behaviour | awar.dev/ui Components |
|----------|-------------|----------------------|
| Execution tx fails | Proposal stays in Passed status. Show error toast with message. Show "Retry Execute" button. | toast (`sonner`), `Button` |
| Type frozen during Passed | Disable Execute button. Show freeze banner with expiry timer. Re-enable when freeze expires. | `Button disabled`, `Alert variant="destructive"`, `<CountdownTimer>` |
| Controller paused | Disable Execute button. Show pause banner. Re-enable when unpaused. | `Button disabled`, `Alert variant="destructive"` |
| Wallet not Board Member | Hide Vote/Execute/Create buttons. Show "You are not a board member" in action area. | `Alert` (info) |
| DAO Migrating | Only `TransferAssets` proposals creatable. Show warning banner on all other proposal forms. | `Alert` |
| Already voted | Replace vote buttons with "You voted [Yes/No]" badge. | `Badge` |
| Cooldown active | Disable "New Proposal" for that type. Show cooldown timer in type selector. | `CommandItem` (disabled), `<CountdownTimer>` |

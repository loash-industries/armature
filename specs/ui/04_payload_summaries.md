# 04 — Payload Summaries

Read-only renderers for the Proposal Detail view (`<ProposalDetail>` → `<PayloadSummary>`). Each proposal type dispatches to its summary panel showing the proposal's payload fields in a human-readable format.

The `<PayloadSummary>` component is **app-level** (not in `@awar.dev/ui`). It accepts a `Proposal<P>` and dispatches to the correct renderer based on `P`'s type tag. Each renderer is composed from `@awar.dev/ui` primitives — primarily `Table`, `Badge`, `Tooltip`, and `HoverCard`.

---

## Summary Table

| # | Proposal Type | Displayed Fields |
|---|--------------|-----------------|
| 1 | **UpdateMetadata** | Current metadata CID → Proposed CID |
| 2 | **DisableProposalType** | Type to disable, current config for that type, protected status (should never appear — blocked at form level) |
| 3 | **TransferFreezeAdmin** | Recipient address, current holder address |
| 4 | **UnfreezeProposalType** | Type to unfreeze, current freeze expiry countdown |
| 5 | **UpdateFreezeConfig** | Current default duration → Proposed duration |
| 6 | **SpinOutSubDAO** | SubDAO name/ID, current controller status, warning: "Irreversible — SubDAO becomes independent" |
| 7 | **PauseSubDAOExecution** | SubDAO name/ID, current pause status |
| 8 | **UnpauseSubDAOExecution** | SubDAO name/ID, current pause status |
| 9 | **RenewCharterStorage** | Current blob ID → New blob ID, note: "No version or content change" |
| 10 | **SendCoin\<T\>** | Coin type, amount (formatted), recipient address, current treasury balance for that type |
| 11 | **SendCoinToDAO\<T\>** | Coin type, amount (formatted), target DAO name/ID, current treasury balance for that type |
| 12 | **SetBoard** | Side-by-side: Current board vs Proposed board. Added members highlighted green, removed highlighted red. Current seat count → Proposed seat count. |
| 13 | **EnableProposalType** | Type to enable, ProposalConfig values (quorum %, threshold %, delay, cooldown, expiry). SubDAO blocklist note if applicable. |
| 14 | **UpdateProposalConfig** | Target type, per-field diff: Current → Proposed for quorum, threshold, delay, cooldown, expiry. Changed fields highlighted. Self-referential warning if target = UpdateProposalConfig. |
| 15 | **AmendCharter** | Summary text (from proposal), current charter version, link to proposed content on Walrus (blob ID), link to view diff (fetches current + proposed from Walrus, shows inline diff). Content hash. |
| 16 | **TransferCapToSubDAO** | Capability type, object ID, target SubDAO name/ID |
| 17 | **ReclaimCapFromSubDAO** | Source SubDAO name/ID, capability type, object ID |
| 18 | **CreateSubDAO** | Name, board members (list), seat count, charter summary (truncated), enabled proposal types (with configs), initial funding (coin type + amount or "None") |

---

## Rendering Notes — awar.dev/ui Component Usage

| Element | awar.dev/ui Component(s) | Notes |
|---------|------------------------|-------|
| **Address fields** | `HoverCard` (full address on hover) + `Button variant="ghost" size="icon-xs"` (copy) | Truncated display, link to explorer |
| **Object IDs** | `Tooltip` (full ID on hover) + `Button variant="ghost" size="icon-xs"` (copy) | Truncated display, link to explorer |
| **Amounts** | `Tooltip` (full value on hover) | Formatted with appropriate decimal places (9 for SUI/MIST conversion) |
| **Duration fields** | `Tooltip` (raw ms on hover) | Displayed as human-readable (e.g., "48 hours", "7 days") |
| **Basis points** | Inline text | Displayed as percentage with bps in parentheses (e.g., "66% (6600 bps)") |
| **Diffs** (SetBoard, UpdateProposalConfig, AmendCharter) | `Table` with `Badge` (green/red/neutral) | Additions highlighted, removals highlighted, unchanged shown in neutral style |
| **DAO references** | `HoverCard` (name + ID + metadata preview) | Resolved to name + ID where possible |
| **Walrus links** | `Button variant="link"` | Clickable links that open content in a new tab or inline viewer |
| **"Current" values** | `Alert` (info, when diverged) | Fetched live from on-chain state — they reflect the state at viewing time, not proposal creation time. Alert shown if current state has diverged. |
| **Loading states** | `Skeleton` | Used while fetching on-chain state or Walrus content |

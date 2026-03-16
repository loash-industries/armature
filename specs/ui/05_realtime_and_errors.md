# 05 — Events, Real-Time Updates & Error States

> **Notifications:** Toast notifications use `sonner` (exported via `@awar.dev/ui`). Persistent banners use `Alert` with variant-appropriate styling. Loading placeholders use `Skeleton`.

---

## Event Subscriptions

On-chain events that drive UI updates. Subscribe via `sui_subscribeEvent` filtered by DAO ID where applicable.

| Event | Emitted By | UI Consumer | Update Action |
|-------|-----------|-------------|---------------|
| `DAOCreated` | `dao::create` | `<SubDAOListPage>` | Add new SubDAO card |
| `ProposalCreated` | `proposal::create` | `<ProposalsList>`, `<DaoDashboard>` | Add proposal to list, increment active count |
| `VoteCast` | `board::vote` | `<ProposalDetail>` `<VotingPanel>` | Update vote tally bars, add voter to list |
| `ProposalPassed` | `proposal` (internal status transition) | `<ProposalDetail>`, `<ProposalsList>` | Update status badge to "Passed", start execution delay timer, lock voting panel |
| `ProposalExecuted` | `proposal::execute` consume | `<ProposalDetail>`, `<ProposalsList>`, `<DaoDashboard>` | Update status to "Executed", decrement active count, refresh affected page data |
| `ProposalExpired` | `proposal::try_expire` | `<ProposalDetail>`, `<ProposalsList>` | Update status to "Expired", decrement active count |
| `SubDAOCreated` | `subdao_ops` | `<SubDAOListPage>`, `<DaoDashboard>` | Add SubDAO card, increment SubDAO count |
| `SubDAOSpunOut` | `subdao_ops` | `<SubDAOListPage>` | Remove SubDAO from controller's list, update child DAO's controller banner |
| `CharterAmended` | `charter_ops` | `<CharterPage>` | Reload charter content from Walrus, update version, add amendment to history |
| `CoinClaimed` | `treasury::claim_coin` | `<TreasuryPage>` | Update balance, remove from unclaimed list |
| `TypeFrozen` | `emergency::freeze` | `<EmergencyPage>`, `<ProposalDetail>` | Add to frozen types table, disable execute buttons for frozen type, show freeze banner |
| `TypeUnfrozen` | `emergency::unfreeze` | `<EmergencyPage>`, `<ProposalDetail>` | Remove from frozen types, re-enable execute buttons, remove freeze banner |
| `CapabilityTransferred` | `subdao_ops` | `<CapVaultPage>` (both DAOs) | Remove cap from source vault view, add to target vault view |
| `CapabilityReclaimed` | `subdao_ops` | `<CapVaultPage>` (both DAOs) | Move cap back to controller's vault view |

### Subscription Strategy

- **Per-DAO subscription**: When viewing a DAO, subscribe to all events where `dao_id` matches
- **Polling fallback**: If WebSocket subscription is unavailable, poll every 5 seconds for new events
- **Stale data indicator**: `Badge variant="outline"` "Data may be stale" shown if last successful fetch was > 30 seconds ago

---

## Optimistic Updates

For low-latency UX, update the UI before on-chain confirmation for these actions:

| Action | Optimistic Update | Rollback On Failure |
|--------|------------------|-------------------|
| Vote cast | Immediately add vote to tally, update bars, show "You voted [Yes/No]" | Remove vote, re-enable vote buttons, show error toast |
| Deposit | Immediately increment balance display | Revert balance, show error toast |

All other actions (execute, create proposal, freeze) wait for on-chain confirmation before updating — they have complex side effects that are hard to predict optimistically.

---

## Error States

Each error state maps to specific `@awar.dev/ui` components for consistent presentation.

### Execution Failure

| Condition | UI Behaviour | awar.dev/ui Components |
|-----------|-------------|----------------------|
| `execute` transaction reverts | Proposal stays in **Passed** status on-chain | |
| | Show error toast: "Execution failed: [error message]" | toast (`sonner`) |
| | Show "Retry Execute" button (same preconditions as Execute) | `Button` |
| | Add failed attempt to visible "Execution Attempts" section | `Card`, `Table`, `Badge variant="destructive"` |

### Controller Paused

| Condition | UI Behaviour | awar.dev/ui Components |
|-----------|-------------|----------------------|
| `dao.controller_paused = true` | **Warning banner** on all pages: "Execution paused by [Controller DAO Name]" | `Alert` (`AlertTitle`, `AlertDescription`) |
| | All Execute buttons **disabled** with tooltip: "Paused by controller" | `Button disabled`, `Tooltip` |
| | Proposal creation still allowed (voting can proceed) | |
| | Banner links to controller DAO | `Button variant="link"` inside `Alert` |

### Frozen Type

| Condition | UI Behaviour | awar.dev/ui Components |
|-----------|-------------|----------------------|
| Proposal type is in `emergency_freeze.frozen_types` | Execute button **disabled** for proposals of that type | `Button disabled` |
| | Freeze banner on `<ProposalDetail>`: "Type frozen — execution blocked until [expiry countdown]" | `Alert variant="destructive"`, `<CountdownTimer>` |
| | `<EmergencyPage>` shows frozen type with countdown | `Table`, `<CountdownTimer>` |
| | When freeze expires (timer reaches zero), auto-refresh and re-enable | |

### Cooldown Active

| Condition | UI Behaviour | awar.dev/ui Components |
|-----------|-------------|----------------------|
| `now < last_execution[type] + config.cooldown_ms` | In proposal type selector: type shown but **disabled** with cooldown timer | `CommandItem` (disabled) |
| | Tooltip: "Cooldown active — new proposals of this type available in [countdown]" | `Tooltip`, `<CountdownTimer>` |
| | When cooldown expires, auto-enable in type selector | |

### DAO Migrating

| Condition | UI Behaviour | awar.dev/ui Components |
|-----------|-------------|----------------------|
| `dao.status = Migrating` | **Warning banner** on all pages: "This DAO is migrating. Only TransferAssets proposals can be created." | `Alert` |
| | "New Proposal" type selector: all types disabled except TransferAssets | `CommandItem` (disabled), `Tooltip` |
| | Existing Active proposals can still be voted on and executed | |

### Wallet Not Board Member

| Condition | UI Behaviour | awar.dev/ui Components |
|-----------|-------------|----------------------|
| Connected wallet not in `governance.members` | "New Proposal" button **hidden** | (conditionally rendered) |
| | Vote/Execute buttons **hidden** on `<ProposalDetail>` | (conditionally rendered) |
| | Action menus on `<SubDAOListPage>` **hidden** | (conditionally rendered) |
| | Read-only info message in action areas | `Alert` (info): "Connect a board member wallet to take actions" |
| | Deposit form on `<TreasuryPage>` **still visible** (permissionless) | |

### Charter Integrity Mismatch

| Condition | UI Behaviour | awar.dev/ui Components |
|-----------|-------------|----------------------|
| `SHA-256(walrus_content) ≠ charter.content_hash` | Red "Integrity Mismatch" badge instead of green "Verified" | `Badge variant="destructive"` |
| | Warning: "The content on Walrus does not match the on-chain hash…" | `Alert variant="destructive"` |
| | Show both hashes for manual comparison | `Table` |
| | "Propose Amendment" still available to fix | `Button` |

### Walrus Fetch Failure

| Condition | UI Behaviour | awar.dev/ui Components |
|-----------|-------------|----------------------|
| Cannot fetch charter content from Walrus | Show placeholder: "Charter content unavailable — Walrus fetch failed" | `Skeleton` (content area), `Alert` |
| | Retry button | `Button variant="outline"` |
| | On-chain metadata (version, hash, blob ID) still displayed | `Table`, `Badge` |
| | "Propose Storage Renewal" suggested if blob may have expired | `Alert` with `Button variant="link"` |

### Network / Transaction Errors

| Condition | UI Behaviour | awar.dev/ui Components |
|-----------|-------------|----------------------|
| Wallet transaction rejected by user | Dismiss loading state, no toast (user intentionally cancelled) | — |
| Transaction fails on-chain | Error toast with parsed error message (use `explain_error` for Move abort codes) | toast (`sonner`) |
| Network timeout | Error toast: "Network timeout — please try again" with retry action | toast (`sonner`) with action button |
| Object not found (stale data) | Refresh data, show toast: "Data refreshed — the state has changed" | toast (`sonner`) |

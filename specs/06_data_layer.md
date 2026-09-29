# 06 — Data Layer & Indexing Strategy

## Purpose

This document defines how the frontend reads on-chain state and reacts to changes. It covers each screen of the dashboard UI: what the Sui RPC can read directly, what must be reconstructed from events, and which part of that work the indexer does.

---

## Decision: Event-Sourced History, Direct Reads for Live State

The hackathon plan was to run the UI on JSON-RPC alone, with no indexer. That decision is **superseded**. The production pipeline is:

```
Move contracts (Sui)  →  armature-indexer (Rust, separate repo)  →  PostgreSQL  →  UI
```

Changes to the framework since the hackathon made events the only complete record:

1. **Proposals are deleted when they leave the chain.** Execution deletes the `Proposal` (`ProposalExecuted`), and anyone can delete an expired one (`ProposalExpired`). An executed or expired proposal cannot be read as an object; its payload survives only in `ProposalPayloadCreated.payload_bcs`.
2. **Single-PTB executions never create an object.** `submit_vote_execute`, bypass executions (`ticket_from_cap`) and controller overrides (`privileged_submit`) exist only as event sequences under a freshly minted proposal ID.
3. **The board roster is a `Table`.** It cannot be read as a vector from the OU object; entries are dynamic fields of the table, and former members' entries remain (with closed tenures).
4. **The type registry is dynamic fields.** Enabled types and their configs are `TypeSlot` fields on the OU's `UID`, mixed with display-key index fields and type-state.

The split is therefore:

| Concern | Source |
|---|---|
| History: proposals (open, executed, expired, single-PTB), votes, board membership over time, registry changes, freezes, treasury movements | Indexer, from events |
| Live state: OU flags, open proposals' tallies, treasury balances, vault contents, freeze state, owned caps | Direct RPC reads (and the indexer, where it mirrors them) |
| Derived: vote eligibility, execute eligibility, countdowns | Client-side computation from the above |

Direct RPC alone still works for a single-OU demo against localnet, with the limitations listed at the end.

---

## Sui RPC Methods Used

| Method | Purpose | Pagination |
|--------|---------|------------|
| `sui_getObject(id, options)` | Read any single object (OU, open Proposal, Charter, vaults, freeze) | N/A |
| `sui_multiGetObjects(ids, options)` | Batch-read up to ~50 objects | N/A |
| `suix_getOwnedObjects(address, filter, options)` | Find objects owned by an address: a wallet's `FreezeAdminCap`, or coins sent directly to a treasury vault's address (claimable with `claim_coin`) | Cursor, ~50/page |
| `suix_queryEvents(filter, cursor, limit, descending)` | Discover proposals, executions, votes, SubOUs, registry and membership changes | Cursor, max 1000/page |
| `suix_getDynamicFields(parent_id, cursor, limit)` | Enumerate dynamic fields: type slots on the OU, roster entries on the members table, treasury balances, vault caps | Cursor, ~50/page |
| `suix_getDynamicFieldObject(parent_id, name)` | Read one dynamic field (a type slot, a member's tenures, a coin balance) | N/A |

---

## Data Access Patterns by Page

### Legend

- **Direct** — single `sui_getObject` or field extraction
- **Batch** — `sui_multiGetObjects` or parallel calls
- **Discovery** — `suix_queryEvents` to find object IDs, then batch-fetch
- **Dynamic** — `suix_getDynamicFields` enumeration + value reads
- **Indexed** — served by the indexer from events
- **Computed** — client-side math/logic on fetched data
- **External** — off-chain fetch (the metadata document at `metadata_uri`)

### OU Dashboard

| Data | Pattern | Query |
|------|---------|-------|
| OU object (status, `execution_paused`, `controller_paused`, `controller_cap_id`, companion IDs) | Direct | `sui_getObject(ou_id)` |
| Board member count | Direct | `ou.governance.member_count` |
| Name and metadata URI | Direct | `sui_getObject(charter_id)` → `name`, `metadata_uri` |
| Treasury total balance | Dynamic | `coin_types` from the TreasuryVault, then each coin type's `Balance<T>` field |
| Open proposals (Active / Passed) | Indexed, or Discovery + Batch | `ProposalCreated` events for the OU → `multiGetObjects`; IDs that no longer exist were executed or expired (or never had an object) |
| SubOU list (compact) | Direct + Batch | Parent vault's `ids_by_type` for `SubOUControl` → read each control's `subou_id` → `multiGetObjects` |
| Recent activity | Indexed | Event feed for the OU |

### Treasury

| Data | Pattern | Query |
|------|---------|-------|
| Coin types | Direct | `sui_getObject(treasury_id)` → `coin_types` (type-name strings) |
| Balance per type | Dynamic | `suix_getDynamicFieldObject(treasury_id, { type: "0x1::ascii::String", value: <coin type name> })` |
| Claimable coins | Direct | `suix_getOwnedObjects(treasury_id, …)`: coin objects transferred to the vault's address and not yet claimed |
| Transaction history | Indexed | `CoinDeposited`, `CoinWithdrawn`, `CoinClaimed`, and the treasury handlers' events (`CoinSent`, `CoinSentToOU`, `SmallPaymentSent`, …) |

### Capability Vault

| Data | Pattern | Query |
|------|---------|-------|
| Cap types and IDs per type | Direct | `sui_getObject(cap_vault_id)` → `cap_types`, `ids_by_type` |
| Cap object details | Batch | `sui_multiGetObjects(cap_ids)` |
| SubOUControl objects | Direct + Batch | `ids_by_type` entry for `SubOUControl` → read each → `subou_id` |
| Bypass opt-ins | Direct | `ids_by_type` entries for `ExternalExecutionCap<P>`; history from `BypassEnabled` / `BypassDisabled` |

### Proposals List

| Data | Pattern | Query |
|------|---------|-------|
| All proposals, any path, any status | Indexed | `ProposalCreated` joined with `ProposalPassed`, `ProposalExecuted`, `ProposalExpired`, `ExternalExecutionCreated`, `CompositeSubmitted` |
| Live tallies of open proposals | Batch | `sui_multiGetObjects(open_proposal_ids)` → `yes_weight`, `no_weight`, `status` |
| Filter/sort | Computed | Client-side filter by status/type/path, sort by created/votes/expiry |

Status for display: `Active` / `Passed` from the object; **Executed** if a `ProposalExecuted` exists for the ID; **Expired** if a `ProposalExpired` exists, or if the object is still live but past its deadline (anyone may delete it). An Active proposal whose voting deadline has passed can no longer be voted on.

### Proposal Detail

| Data | Pattern | Query |
|------|---------|-------|
| Open proposal | Direct | `sui_getObject(proposal_id)` — payload, `snapshot_version`, `total_snapshot_weight`, `votes_cast`, `config`, timestamps, `status` |
| Closed or single-PTB proposal | Indexed | Its events: `ProposalCreated`, `ProposalPayloadCreated` (BCS payload, decoded by type), `VoteCast`, `ProposalPassed`, `ProposalExecuted` / `ProposalExpired` |
| Config | Direct | The proposal's own `config` (snapshot at creation). The slot's current config comes from the OU's `TypeSlot` field; its bits apply at execution |
| Freeze status | Direct | `sui_getObject(freeze_id)` → `frozen_types` entry for the payload's full type name, compared with the clock |
| Pause status | Direct | OU object → `execution_paused`, `controller_paused` |
| Vote eligibility | Dynamic + Computed | Wallet's roster entry (`suix_getDynamicFieldObject(members_table_id, wallet)`) → member at `snapshot_version`? not already in `votes_cast`? before `created_at_ms + expiry_ms`? |
| Execute eligibility | Computed | `status == Passed`, delay elapsed, window open (`passed_at_ms + execution_delay_ms + expiry_ms`), not frozen, not paused, cooldown elapsed, wallet a current member |
| Timers | Computed | Voting deadline, execution-delay end, execution-window end, freeze expiry — all client-side countdowns |

### Board Members

| Data | Pattern | Query |
|------|---------|-------|
| Current members | Indexed, or Dynamic | Indexer applies the membership events (see [`docs/indexing_board_events.md`](../docs/indexing_board_events.md)); or enumerate the members table's fields and keep entries whose last tenure is open |
| Member count, roster version | Direct | `ou.governance.member_count`, `roster_version` |

### Charter

| Data | Pattern | Query |
|------|---------|-------|
| Name and metadata URI | Direct | `sui_getObject(charter_id)` → `name`, `metadata_uri` |
| Metadata document | External | Fetch the document at `metadata_uri` (IPFS gateway); the CID is content-addressed |
| History | Indexed | `MetadataUpdated { ou_id, new_ipfs_cid }` events |

### Governance Config

| Data | Pattern | Query |
|------|---------|-------|
| Enabled types + configs (incl. `permissions` and `borrow_scope`) | Indexed, or Dynamic | `TypeSlotAdded` / `TypeSlotConfigUpdated` / `TypeSlotRemoved` carry the full config; or enumerate the OU's `TypeSlot` fields → `ProposalType { display_key, config, last_executed_ms }` |
| Protected types | Computed | Undisableable: EnableProposalType, DisableProposalType, EnableBypassType, DisableBypassType, TransferFreezeAdmin, UnfreezeProposalType. SubOU-blocked: SpawnOU, SpinOutSubOU, CreateSubOU, EnableBypassType, DisableBypassType. Framework types have fixed bits |

### Emergency Freeze

| Data | Pattern | Query |
|------|---------|-------|
| Frozen types + expiries, exempt set, max duration | Direct | `sui_getObject(freeze_id)` → `frozen_types` (type name → expiry), `freeze_exempt_types`, `max_freeze_duration_ms` |
| FreezeAdminCap holder | Indexed + Direct | For an org, the creator (`OUCreated.creator`), then each `FreezeAdminTransferred.new_admin`; confirm with `suix_getOwnedObjects(address, FreezeAdminCap filter)` matched on `ou_id`. Tribe and wired SubOUs send it to an address named at creation (not in any event; find it in the creating transaction's effects). SubOUs created by `CreateSubOU` hold it in the parent's vault |
| Expiry countdowns | Computed | Client-side timer from each entry's expiry |

### SubOU List

| Data | Pattern | Query |
|------|---------|-------|
| SubOUControl objects | Direct | Parent vault's `ids_by_type` for `SubOUControl` |
| Child OU objects | Batch | `sui_multiGetObjects(subou_ids)` |
| Child treasury balances | Dynamic (per child) | Same pattern as Treasury page, for each child |
| Child board + pause | Direct (per child) | `member_count`, `controller_paused` from the child OU objects |

---

## Event Polling

WebSocket subscriptions (`suix_subscribeEvent`) are deprecated. Without the indexer's push channel, the UI polls.

### Implementation

```
Poll loop (React Query `refetchInterval`):
  1. suix_queryEvents({MoveModule: {package, module}}, cursor=lastSeen, limit=50, descending=false)
     for each framework and extension package
  2. For each new event:
     - Match event type → invalidate relevant React Query cache keys
     - Update lastSeen cursor
  3. Repeat every 3–5 seconds
```

### Event → Cache Invalidation Map

| Event | Invalidate |
|-------|-----------|
| `ProposalCreated` / `ProposalPayloadCreated` | proposals list, dashboard counts |
| `VoteCast` | proposal detail (specific ID), proposals list (vote bars) |
| `ProposalPassed` | proposal detail, proposals list |
| `ProposalExecuted` | proposal detail (drop the object; it no longer exists), proposals list, dashboard, and the resources the payload type touches (treasury, vault, board, registry, freeze) |
| `ProposalExpired` | proposal detail (object deleted), proposals list |
| `ExternalExecutionCreated` | proposals list (bypass execution) |
| `CompositeSubmitted` | proposals list (joins the frame to its proposal) |
| `TypeSlotAdded` / `TypeSlotConfigUpdated` / `TypeSlotRemoved` | governance config, proposal forms |
| `BypassEnabled` / `BypassDisabled` | governance config, cap vault |
| `OUBoardInitialized`, `BoardUpdated`, `MemberAdded`, `MemberRemoved`, `MembersBatchAdded`, `MembersBatchRemoved`, `MemberAutojoined`, `ControllerMembersBatchAdded/Removed` (keyed by `subou_id`) | board, dashboard |
| `SubOUCreated` / `SubOUSpunOut` | SubOU list, dashboard, cap vault |
| `SuccessorOUSpawned` / `AssetsTransferInitiated` / `OUDestroyed` | dashboard (status), treasury, cap vault |
| `MetadataUpdated` | charter page, dashboard |
| `CoinDeposited` / `CoinWithdrawn` / `CoinClaimed` | treasury balances |
| `TypeFrozen` / `TypeUnfrozen` / `FreezeExemptTypeAdded` / `FreezeExemptTypeRemoved` / `FreezeAdminTransferred` / `FreezeConfigUpdated` | emergency page, proposal detail (execution eligibility) |
| `CapTransferredToSubOU` / `CapReclaimedFromSubOU` | cap vault (both parent and child) |
| `SubOUExecutionPaused` / `SubOUExecutionUnpaused` | SubOU list, child dashboard |

### Polling Intervals

| Context | Interval | Rationale |
|---------|----------|-----------|
| Active proposal being viewed | 3s | Votes can arrive frequently |
| Dashboard / list pages | 5s | General awareness |
| Static pages (charter, board, gov config) | 15s | Rarely changes |
| Background (tab not focused) | 30s or paused | Save rate limit budget |

---

## Client-Side Cache Strategy (React Query)

### Cache Keys

```
["ou", ou_id]                        — OU object
["registry", ou_id]                   — enabled types and configs
["roster", ou_id]                     — current board members
["treasury", treasury_id]             — TreasuryVault object
["treasury-balance", treasury_id, T]  — Balance for coin type T
["cap-vault", cap_vault_id]           — CapabilityVault object
["charter", charter_id]               — Charter object (name, metadata_uri)
["charter-content", metadata_uri]     — Metadata document (content-addressed)
["freeze", freeze_id]                 — EmergencyFreeze object
["proposals", ou_id]                 — Proposal list (from events / indexer)
["proposal", proposal_id]             — Single open proposal object, or its event record
["subous", ou_id]                   — SubOU list for a parent
["events", ou_id, cursor]            — Event polling state
```

### Stale Times

| Data | `staleTime` | `cacheTime` | Rationale |
|------|-------------|-------------|-----------|
| OU object | 10s | 5min | Flags and status can change |
| Registry | 30s | 5min | Type changes need an 80% vote |
| Proposal object | 3s | 5min | Votes update frequently during active voting |
| Treasury balance | 10s | 5min | Changes on deposit/withdraw |
| Metadata document | 1hr | 24hr | Content-addressed; changes only via `UpdateMetadata` (new URI) |
| Charter object | 30s | 5min | `metadata_uri` changes on `UpdateMetadata` |
| EmergencyFreeze | 5s | 5min | Freeze/unfreeze can happen any time |
| SubOU list | 30s | 5min | Creation/spinout are infrequent |

### Optimistic Updates

| Action | Optimistic Mutation |
|--------|-------------------|
| Cast vote | Add the wallet to `votes_cast`, increment `yes_weight` or `no_weight` |
| Deposit to treasury | Increment displayed balance |

Rollback on transaction failure. All other actions wait for confirmation before updating cache. An executed proposal is removed from the open list only on confirmation, since a handler abort reverts the deletion.

---

## Request Budget Analysis

Worst-case page load request counts in direct-RPC mode (assuming cold cache):

| Page | RPC Calls | Breakdown |
|------|-----------|-----------|
| Dashboard | 5–10 | 1 OU + 1 charter + 1 treasury + N coin balances + 1 event query + M SubOU reads |
| Treasury | 3–8 | 1 treasury + N balance reads + 1 owned-objects query + 1 event query |
| Cap Vault | 2–10 | 1 vault + M cap reads |
| Proposals List | 2–4 | 1–2 event queries + 1 multiGetObjects batch |
| Proposal Detail | 4 | 1 proposal (or events) + 1 OU + 1 freeze + 1 roster entry |
| Board | 1–3 | members-table field pages, or 1 indexer query |
| Charter | 1 + External | 1 charter + 1 document fetch |
| Gov Config | 1–3 | OU dynamic-field pages, or 1 indexer query |
| Emergency | 2 | 1 freeze + 1 owned-objects query |
| SubOU List | 2–6 | 1 vault + M control reads + M child OU reads |

With the indexer, history, lists, rosters and registries are one query each.

---

## Scope

### Implemented Architecture

| Component | Approach |
|-----------|----------|
| **Indexer** | `armature-indexer` (Rust, separate repo) ingests framework and extension events into PostgreSQL. Executed/expired status, single-PTB executions, rosters and registry history come from events |
| **Object reads** | `SuiClient` from `@mysten/sui` — `getObject`, `multiGetObjects` for live state |
| **Dynamic fields** | Type slots, roster entries, treasury balances, vault caps |
| **Real-time updates** | Event polling with cursor tracking where the indexer does not push |
| **Caching** | React Query with per-key stale times, event-driven invalidation |
| **Computation** | Eligibility checks, countdowns — client-side |
| **Metadata document** | Fetched from `metadata_uri` |
| **Wallet integration** | `@mysten/dapp-kit` for connected wallet, owned object queries |

### Options Not Taken Yet

| Component | What It Adds |
|-----------|-------------|
| **Sui GraphQL API** | Replace multi-call sequences with single queries; checkpoint-consistent reads |
| **Multi-level SubOU tree** | Recursive hierarchy traversal and full DAG visualization |
| **Cross-OU proposal aggregation** | "All proposals across all my OUs" view |
| **Treasury aggregate across hierarchy** | Sum parent + all SubOU treasury balances |
| **Third-party RPC provider** | Higher rate limits than the public fullnode |

---

## Data Flow Architecture

```
┌─────────────────────────────────────────────────────────┐
│                     React Frontend                       │
│                                                          │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐ │
│  │  Page         │   │  React Query │   │  Event       │ │
│  │  Components   │◄──│  Cache       │◄──│  Poller      │ │
│  │              │   │              │   │  (3-5s)      │ │
│  └──────────────┘   └──┬────────┬──┘   └──────┬───────┘ │
│                        │        │              │         │
└────────────────────────┼────────┼──────────────┼─────────┘
                         │        │              │
        ┌────────────────▼──┐  ┌──▼──────────────▼───────────┐
        │  armature-indexer  │  │   SuiClient (JSON-RPC)      │
        │  API / PostgreSQL  │  │   getObject / multiGet      │
        │  (history, lists,  │  │   getDynamicField(s)        │
        │   rosters, registry)│  │   queryEvents / getOwned    │
        └────────▲───────────┘  └──────────────┬──────────────┘
                 │ events                       │
        ┌────────┴──────────────────────────────▼──────────────┐
        │              Sui Fullnode / checkpoints               │
        └───────────────────────────────────────────────────────┘

        ┌──────────────────────────────────────┐
        │  Metadata documents (IPFS gateway)    │
        └──────────────────────────────────────┘
```

### Request Flow for Key Operations

**Load Proposal Detail:**
```
1. getObject(proposal_id)          → open proposal (payload, votes, status, snapshot_version)
   └─ not found → load its events (indexer): executed, expired, or single-PTB
2. getObject(ou_id)               → pause flags, members table ID
3. getObject(freeze_id)            → is the payload's type frozen?
4. getDynamicFieldObject(members_table_id, wallet) → tenures (vote eligibility)
   ── all in parallel ──
5. Client computes: vote bars, eligibility, timers
```

**Load Dashboard:**
```
1. getObject(ou_id)               → status, flags, member_count, companion IDs
   ── then in parallel ──
2a. getObject(treasury_id)         → coin_types
2b. getObject(charter_id)          → name, metadata_uri
2c. open proposals (indexer, or ProposalCreated events + multiGet)
2d. getObject(cap_vault_id)        → SubOUControl IDs
   ── then ──
3a. multiGetObjects(subou_ids)    → SubOU summaries
3b. getDynamicFieldObject × N      → treasury balances per coin type
```

---

## Known Limitations (Direct-RPC Mode)

| Limitation | Impact | Mitigation |
|-----------|--------|-----------|
| Executed and expired proposals are deleted | Their details exist only in events | Decode `ProposalPayloadCreated.payload_bcs`; use the indexer |
| Single-PTB executions have no object | Invisible to object reads | Query `ProposalCreated` / `ProposalExecuted` / `ExternalExecutionCreated` events |
| Roster table enumeration includes former members | Must filter on open tenures; O(all members ever) | Use the indexer's roster |
| Type slots share the OU's dynamic fields with display-key index and type-state fields | Must filter on the `TypeSlot` key type | Use `TypeSlot*` events or the indexer |
| No real-time push (WebSocket deprecated) | 3–5s delay before UI reflects on-chain changes | Optimistic updates for votes/deposits |
| Public RPC rate limit | Could hit limit when navigating across many OUs | React Query deduplication + stale times; indexer queries |
| No historical state queries | Can't show "treasury balance at time of proposal creation" | Show current balance with note: "Balance may have changed since proposal was created" |

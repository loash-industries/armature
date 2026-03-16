# 06 — Data Layer & Indexing Strategy

## Purpose

This document defines how the frontend reads on-chain state and reacts to changes. It specifies the querying approach for every screen in the UI spec (`docs/ui/`), identifies what the Sui RPC can handle natively vs what needs client-side work, and draws a clear line between hackathon scope and stretch goals.

---

## Decision: No Custom Indexer

For hackathon scope, **we do not build or deploy a custom indexer**. The entire data layer runs on:

1. **`SuiClient` (JSON-RPC)** — direct object reads, dynamic field queries, event queries, owned-object queries
2. **Client-side cache** — React Query (TanStack Query) for deduplication, staleness, and background refresh
3. **Event polling** — periodic `suix_queryEvents` calls to detect state changes (WebSocket subscriptions are deprecated)
4. **Client-side computation** — vote tallies, eligibility checks, countdowns computed from fetched objects

This covers 100% of the demo flows. No derived tables, no background workers, no database.

---

## Sui RPC Methods Used

| Method | Purpose | Pagination |
|--------|---------|------------|
| `sui_getObject(id, options)` | Read any single object (DAO, Proposal, Charter, etc.) | N/A |
| `sui_multiGetObjects(ids, options)` | Batch-read up to ~50 objects | N/A |
| `suix_getOwnedObjects(address, filter, options)` | Find objects owned by wallet (FreezeAdminCap, user's DAOs) | Cursor, ~50/page |
| `suix_queryEvents(filter, cursor, limit, descending)` | Discover proposals, SubDAOs, vote history, tx history | Cursor, max 1000/page |
| `suix_getDynamicFields(parent_id, cursor, limit)` | Enumerate dynamic fields (treasury coin types, cap types) | Cursor, ~50/page |
| `suix_getDynamicFieldObject(parent_id, name)` | Read a specific dynamic field value (balance for a coin type) | N/A |

All methods available on devnet, testnet, and mainnet. Public rate limit: 100 req/30s — sufficient for single-user demo.

---

## Data Access Patterns by Page

### Legend

- **Direct** — single `sui_getObject` or field extraction, < 50ms
- **Batch** — `sui_multiGetObjects` or parallel calls, < 200ms
- **Discovery** — `suix_queryEvents` to find object IDs, then batch-fetch, < 500ms
- **Dynamic** — `suix_getDynamicFields` enumeration + value reads, < 300ms
- **Computed** — client-side math/logic on fetched data, ~0ms after fetch
- **External** — off-chain fetch (Walrus), 1–3s

### DAO Dashboard

| Data | Pattern | Query |
|------|---------|-------|
| DAO object (status, metadata, governance, controller) | Direct | `sui_getObject(dao_id)` |
| Treasury total balance | Dynamic | Enumerate `coin_types` from TreasuryVault, read each `Balance<T>` dynamic field |
| Board member count | Direct | Extract from `dao.governance.members.length` |
| Charter version | Direct | `sui_getObject(charter_id)` → `version` |
| Active proposal count | Discovery + Computed | Query `ProposalCreated` events → batch-fetch proposal objects → count where status = Active/Passed |
| Active proposals list | Discovery + Batch | Same as above, return first N |
| SubDAO list (compact) | Dynamic + Batch | Query parent's CapabilityVault for `SubDAOControl` dynamic object fields → `sui_multiGetObjects` on child DAO IDs |
| Recent activity | Discovery | `suix_queryEvents(MoveModule: {package, module: "dao"}, descending: true, limit: 10)` |

### Treasury

| Data | Pattern | Query |
|------|---------|-------|
| Coin types | Direct | `sui_getObject(treasury_id)` → `coin_types` VecSet |
| Balance per type | Dynamic | For each type: `suix_getDynamicFieldObject(treasury_id, {type: "TypeName", value: T})` |
| Unclaimed coins | Dynamic | `suix_getDynamicFields(treasury_id)` — coins not yet consolidated |
| Wallet balances | Direct | `suix_getOwnedObjects(wallet, {StructType: "0x2::coin::Coin<T>"})` per type |
| Transaction history | Discovery | `suix_queryEvents` filtered by `CoinClaimed` + treasury-related `ProposalExecuted` events |

### Capability Vault

| Data | Pattern | Query |
|------|---------|-------|
| Cap types | Direct | `sui_getObject(cap_vault_id)` → `cap_types` VecSet |
| Cap IDs per type | Dynamic | `suix_getDynamicFields(cap_vault_id)` to list stored caps |
| Cap object details | Batch | `sui_multiGetObjects(cap_ids)` |
| SubDAOControl objects | Dynamic + Batch | Filter caps by type = `SubDAOControl`, read each → `child_dao_id` |

### Proposals List

| Data | Pattern | Query |
|------|---------|-------|
| All proposal IDs | Discovery | `suix_queryEvents({MoveEventType: "ProposalCreated"}, ...)` filtered by `dao_id` field |
| Proposal objects | Batch | `sui_multiGetObjects(proposal_ids)` — extract status, votes, type, creator |
| Filter/sort | Computed | Client-side filter by status/type, sort by created/votes/expiry |

### Proposal Detail

| Data | Pattern | Query |
|------|---------|-------|
| Proposal object | Direct | `sui_getObject(proposal_id)` — payload, vote_snapshot, status, timestamps |
| ProposalConfig | Direct | Already in DAO object → `proposal_configs` table |
| Freeze status | Direct | `sui_getObject(freeze_id)` → check `frozen_types` for this proposal's type |
| Pause status | Direct | Already in DAO object → `controller_paused` |
| Board members (for quorum calc) | Direct | Already in DAO object → `governance.members` |
| Vote eligibility | Computed | Check wallet in members, not in vote_snapshot |
| Execute eligibility | Computed | Check: status=Passed, delay elapsed, not frozen, not paused, wallet in members |
| Timers | Computed | `passed_at_ms + delay`, `created_at_ms + expiry_ms`, freeze expiry — all client-side countdown |

### Board Members

| Data | Pattern | Query |
|------|---------|-------|
| Members + seat count | Direct | `sui_getObject(dao_id)` → `governance.members`, `governance.seat_count` |

### Charter

| Data | Pattern | Query |
|------|---------|-------|
| Charter metadata | Direct | `sui_getObject(charter_id)` → blob_id, content_hash, version, amendment_history |
| Charter content | External | Walrus HTTP fetch by `current_blob_id` |
| Integrity check | Computed | `SHA-256(fetched_content) === charter.content_hash` — computed in browser (Web Crypto API) |
| Historical versions | External | Walrus fetch for `previous_blob_id` / `new_blob_id` from amendment records |

### Governance Config

| Data | Pattern | Query |
|------|---------|-------|
| Enabled types + configs | Direct | `sui_getObject(dao_id)` → `enabled_proposals`, `proposal_configs` |
| Protected types | Computed | Hardcoded set: EnableProposalType, DisableProposalType, TransferFreezeAdmin, UnfreezeProposalType |

### Emergency Freeze

| Data | Pattern | Query |
|------|---------|-------|
| Frozen types + expiries | Direct | `sui_getObject(freeze_id)` → `frozen_types` map |
| FreezeAdminCap holder | Discovery | `suix_getOwnedObjects` across known addresses, or derive from events |
| Expiry countdowns | Computed | Client-side timer from `freeze_expiry_ms` |

### SubDAO List

| Data | Pattern | Query |
|------|---------|-------|
| SubDAOControl objects | Dynamic | Query parent's CapabilityVault for `SubDAOControl` type caps |
| Child DAO objects | Batch | `sui_multiGetObjects(child_dao_ids)` |
| Child treasury balances | Dynamic (per child) | Same pattern as Treasury page, for each child |
| Child board + pause | Direct (per child) | Extracted from child DAO objects already fetched |

---

## Event Polling

WebSocket subscriptions (`suix_subscribeEvent`) are deprecated. We use **polling** instead.

### Implementation

```
Poll loop (React Query `refetchInterval`):
  1. suix_queryEvents({MoveModule: {package, module}}, cursor=lastSeen, limit=50, descending=false)
  2. For each new event:
     - Match event type → invalidate relevant React Query cache keys
     - Update lastSeen cursor
  3. Repeat every 3–5 seconds
```

### Event → Cache Invalidation Map

| Event | Invalidate |
|-------|-----------|
| `ProposalCreated` | proposals list, dashboard active count |
| `VoteCast` | proposal detail (specific ID), proposals list (vote bars) |
| `ProposalPassed` | proposal detail, proposals list |
| `ProposalExecuted` | proposal detail, proposals list, dashboard, treasury (if SendCoin), cap vault (if TransferCap), board (if SetBoard) |
| `ProposalExpired` | proposal detail, proposals list |
| `SubDAOCreated` | SubDAO list, dashboard |
| `SubDAOSpunOut` | SubDAO list |
| `CharterAmended` | charter page |
| `CoinClaimed` | treasury balances |
| `TypeFrozen` / `TypeUnfrozen` | emergency page, proposal detail (execution eligibility) |
| `CapabilityTransferred` / `CapabilityReclaimed` | cap vault (both parent and child) |

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
["dao", dao_id]                        — DAO object
["treasury", treasury_id]             — TreasuryVault object
["treasury-balance", treasury_id, T]  — Balance for coin type T
["cap-vault", cap_vault_id]           — CapabilityVault object
["charter", charter_id]               — Charter object (on-chain metadata)
["charter-content", blob_id]          — Charter content (from Walrus)
["freeze", freeze_id]                 — EmergencyFreeze object
["proposals", dao_id]                 — Proposal ID list (from events)
["proposal", proposal_id]             — Single proposal object
["subdaos", dao_id]                   — SubDAO list for a parent
["events", dao_id, cursor]            — Event polling state
```

### Stale Times

| Data | `staleTime` | `cacheTime` | Rationale |
|------|-------------|-------------|-----------|
| DAO object | 10s | 5min | Governance config changes rarely, but pause/status can change |
| Proposal object | 3s | 5min | Votes update frequently during active voting |
| Treasury balance | 10s | 5min | Changes on deposit/withdraw |
| Charter content (Walrus) | 1hr | 24hr | Content doesn't change until amendment |
| Charter metadata | 30s | 5min | Version/blob_id change on amendment |
| EmergencyFreeze | 5s | 5min | Freeze/unfreeze can happen any time |
| SubDAO list | 30s | 5min | Creation/spinout are infrequent |

### Optimistic Updates

| Action | Optimistic Mutation |
|--------|-------------------|
| Cast vote | Add vote to `vote_snapshot`, increment `yes_weight` or `no_weight` |
| Deposit to treasury | Increment displayed balance |

Rollback on transaction failure. All other actions wait for confirmation before updating cache.

---

## Request Budget Analysis

Worst-case page load request counts (assuming cold cache):

| Page | RPC Calls | Breakdown |
|------|-----------|-----------|
| Dashboard | 5–10 | 1 DAO + 1 treasury + N coin balances + 1 event query + M SubDAO reads |
| Treasury | 3–8 | 1 treasury + N balance reads + 1 event query |
| Cap Vault | 3–10 | 1 vault + 1 dynamic fields + M cap reads |
| Proposals List | 2–4 | 1 event query + 1 multiGetObjects batch |
| Proposal Detail | 3 | 1 proposal + 1 DAO (configs) + 1 freeze |
| Board | 1 | 1 DAO |
| Charter | 2 + Walrus | 1 charter + 1 Walrus fetch |
| Gov Config | 1 | 1 DAO |
| Emergency | 2 | 1 freeze + 1 owned-objects query |
| SubDAO List | 2–6 | 1 vault dynamic fields + M child DAO reads |

**Total for full navigation**: ~25–50 RPC calls. Well within the 100 req/30s public rate limit for a single-user demo. With React Query caching, repeat visits hit cache — real load is ~5–10 calls/page after warmup.

---

## Hackathon Scope vs Stretch

### Hackathon Scope (Ship This)

| Component | Approach |
|-----------|----------|
| **Object reads** | `SuiClient` from `@mysten/sui` — `getObject`, `multiGetObjects` |
| **Dynamic fields** | `getDynamicFields`, `getDynamicFieldObject` for treasury balances, cap vault contents |
| **Event discovery** | `queryEvents` with `MoveEventType` filter for proposals, SubDAOs, history |
| **Real-time updates** | Polling `queryEvents` every 3–5s with cursor tracking |
| **Caching** | React Query with per-key stale times, event-driven invalidation |
| **Computation** | Vote tallies, eligibility checks, countdowns — all client-side from fetched objects |
| **Charter content** | Direct Walrus HTTP fetch + browser-side SHA-256 verification |
| **SubDAO hierarchy** | One level deep — query parent's vault for SubDAOControls, batch-fetch children |
| **Wallet integration** | `@mysten/dapp-kit` for connected wallet, owned object queries |

### Stretch Goals (If Time Permits)

| Component | What It Adds | Why Stretch |
|-----------|-------------|-------------|
| **Sui GraphQL API** | Replace multi-call sequences with single GraphQL queries (e.g., fetch DAO + treasury + proposals in one request). Consistent checkpoint-based reads. | Beta API; JSON-RPC works fine for demo; adds SDK dependency (`SuiGraphQLClient`) |
| **Multi-level SubDAO tree** | Recursive hierarchy traversal beyond one level. Full DAG visualization. | Unbounded recursion, many RPC calls for deep trees. Hackathon DAOs will be 1–2 levels deep. |
| **Cross-DAO proposal aggregation** | "All proposals across all my DAOs" unified view. | Requires querying events across all DAOs the user belongs to, then deduplicating. Not needed for single-DAO demo flow. |
| **Treasury aggregate across hierarchy** | Sum parent + all SubDAO treasury balances. | N+1 queries per level of depth. Nice dashboard metric but not in demo script. |
| **Persistent event cache** | IndexedDB or localStorage cache of seen events to avoid re-querying on page reload. | Saves RPC calls but adds complexity. React Query's in-memory cache is sufficient for a demo session. |
| **Third-party RPC provider** | Higher rate limits (QuickNode, Shinami, BlockEden). | Only needed if public rate limit becomes a bottleneck during demo; unlikely for single user. |
| **Custom indexer** | Derived tables for proposal history, voting analytics, participation metrics. | Full backend service (Rust `sui-indexer-alt-framework` or TypeScript Subsquid). Only justified for multi-user production. |

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
│  └──────────────┘   └──────┬───────┘   └──────┬───────┘ │
│                            │                   │         │
└────────────────────────────┼───────────────────┼─────────┘
                             │                   │
                    ┌────────▼───────────────────▼────────┐
                    │         SuiClient (JSON-RPC)        │
                    │                                      │
                    │  getObject / multiGetObjects         │
                    │  getDynamicFields / getDynamicField   │
                    │  queryEvents (cursor-based)           │
                    │  getOwnedObjects                     │
                    └────────────────┬─────────────────────┘
                                     │
                    ┌────────────────▼─────────────────────┐
                    │      Sui Fullnode (Public RPC)        │
                    │      testnet / devnet / localnet      │
                    └──────────────────────────────────────┘

                    ┌──────────────────────────────────────┐
                    │      Walrus (Charter Content)         │
                    │      HTTP fetch by blob ID            │
                    └──────────────────────────────────────┘
```

### Request Flow for Key Operations

**Load Proposal Detail:**
```
1. getObject(proposal_id)          → proposal object (payload, votes, status)
2. getObject(dao_id)               → governance.members (quorum calc), proposal_configs
3. getObject(freeze_id)            → check if proposal type is frozen
   ── all 3 in parallel ──
4. Client computes: vote bars, eligibility, timers
```

**Load Dashboard:**
```
1. getObject(dao_id)               → status, metadata, governance, companion IDs
   ── then in parallel ──
2a. getObject(treasury_id)         → coin_types
2b. getObject(charter_id)          → version
2c. queryEvents(ProposalCreated)   → proposal IDs
2d. getDynamicFields(cap_vault_id) → SubDAOControl objects
   ── then ──
3a. multiGetObjects(proposal_ids)  → active proposals with status
3b. multiGetObjects(subdao_ids)    → SubDAO summaries
3c. getDynamicFieldObject × N      → treasury balances per coin type
```

**Poll for Updates:**
```
Every 3-5s:
  queryEvents(package, cursor=last, limit=50, descending=false)
  → new events? → invalidate affected React Query keys → components re-render
```

---

## Known Limitations (Hackathon Accepted)

| Limitation | Impact | Mitigation |
|-----------|--------|-----------|
| No real-time push (WebSocket deprecated) | 3–5s delay before UI reflects on-chain changes | Optimistic updates for votes/deposits; polling is fast enough for demo |
| Public RPC rate limit (100 req/30s) | Could hit limit if navigating rapidly across many DAOs | React Query deduplication + stale times prevent redundant calls; single-user demo won't hit this |
| No cross-DAO aggregation | Can't show "all my DAOs" dashboard efficiently | User selects a DAO first; per-DAO views are efficient |
| Event cursor not persisted | On page reload, must re-query recent events | In-flight polling quickly catches up; React Query cache survives soft navigation |
| Dynamic field enumeration is O(N) | Large treasuries (many coin types) or vaults (many caps) require many reads | Hackathon DAOs will have < 10 coin types and < 20 caps; batch reads handle this fine |
| No historical state queries | Can't show "treasury balance at time of proposal creation" | Show current balance with note: "Balance may have changed since proposal was created" |
| FreezeAdminCap discovery is imprecise | Must search owned objects to find who holds it | For demo, the cap holder is known; query their owned objects with StructType filter |

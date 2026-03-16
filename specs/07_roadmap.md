# 07 — Roadmap

**Implementation repo:** [`loash-industries/armature`](https://github.com/loash-industries/armature)

This roadmap aligns to the open issues on `armature`. Each phase maps to concrete deliverables, armature issue numbers, and demo flow coverage. See `09_issue_breakdown.md` for the full sub-issue decomposition.

---

## Phase Overview

| Phase | Focus | Armature Issues | Gate |
|-------|-------|-----------------|------|
| **P0 — Core Contracts** | DAO creation, Board governance, proposal lifecycle, treasury, cap vault | #3, #2 | All unit tests pass; can create DAO and execute a proposal on localnet |
| **P1 — Composition** | SubDAO hierarchy, charter with Walrus, mocked assemblies, integration tests | #2 (continued) | SubDAO flows work end-to-end on localnet |
| **P2 — Demo + Indexer** | Testnet deployment, demo flows, indexer scaffold, gas profiling | #4 | Full demo rehearsal on Testnet; indexer serving events |
| **P3 — Frontend** | UI scaffold, pages, forms, hierarchy graph, security dashboard | #5, #6, #7, #8, #10 | Demo flows executable through UI on Testnet |
| **P4 — Polish** | Error UX, demo script, documentation, submission | — | Submission-ready |

---

## P0 — Core Contracts

**Goal:** The minimum on-chain objects and logic to create a DAO, propose, vote, and execute.

**Package:** `armature_framework` (armature #3)

| Deliverable | Modules | Demo Flow Coverage |
|---|---|---|
| DAO Object & Creation | `dao.move`, `governance.move` | Flow A Step 1 |
| Proposal Lifecycle | `proposal.move` | All flows — every step that involves proposals |
| Board Voting | `voting/board.move` | All flows — vote counting for Board governance |
| Treasury Vault | `treasury.move` | Flow A Step 3 (deposit), Flow A Step 6 (SendCoin) |
| Capability Vault | `capability_vault.move` | Flow B Step 3 (deposit caps), Flow C Steps 1-3 (loan/return) |
| Emergency Freeze | `emergency.move` | Safety infrastructure — not demoed directly |

**Package:** `armature_proposals` (armature #2)

| Deliverable | Modules | Demo Flow Coverage |
|---|---|---|
| Admin Proposals | `proposals/admin.move` | `EnableProposalType` used throughout to unlock new proposal types |
| Treasury Proposals | `proposals/treasury_ops.move` | Flow A Step 6, Flow B Step 6 |
| Board Proposals | `proposals/board_ops.move` | Flow A Step 2 (SetBoard), Flow A Step 7 (parent override) |

**Exit criteria:** Can create a DAO on localnet, add board members, deposit to treasury, create/vote/execute a SendCoin proposal.

---

## P1 — Composition

**Goal:** SubDAO hierarchy and charter integration — the features that make the DAO composable.

**Package:** `armature_framework` (armature #3 — extend with SubDAOControl)

| Deliverable | Modules | Demo Flow Coverage |
|---|---|---|
| SubDAOControl struct | `dao.move` extension | Controller machinery for SubDAO hierarchy |

**Package:** `armature_proposals` (armature #2 — remaining handlers)

| Deliverable | Modules | Demo Flow Coverage |
|---|---|---|
| SubDAO Proposals | `proposals/subdao_ops.move` | Flow A Steps 4-5 (CreateSubDAO), Flow B Steps 1-2 |
| Charter Object & Walrus | `charter.move`, `proposals/charter_ops.move` | Flow A Step 1 (create), Flow B Step 7 (AmendCharter) |
| `privileged_submit` | `proposal.move` extension | Flow A Step 7 (parent override) |
| Capability Delegation | `TransferCapToSubDAO`, `ReclaimCapFromSubDAO` | Flow C Step 6 (delegate gate to SubDAO) |

**Package:** `mock_assemblies` (new — no armature issue yet)

| Deliverable | Modules | Demo Flow Coverage |
|---|---|---|
| Mocked Smart Assemblies | `mock_gate.move`, `mock_ssu.move` | Flow B Steps 3-4, Flow C Steps 1-3, 7 |

**Exit criteria:** Full SubDAO lifecycle on localnet: create SubDAO → fund → delegate cap → sub-DAO operates → parent overrides board → parent reclaims cap.

---

## P2 — Demo Hardening + Indexer

**Goal:** All three demo flows execute cleanly on Testnet. Indexer serves event data to frontend.

| Deliverable | Armature Issue | Description |
|---|---|---|
| Testnet deployment | — | Publish `armature_framework`, `armature_proposals`, `mock_assemblies` to testnet |
| Flow A rehearsal | — | Create DAO → SetBoard → deposit → CreateSubDAO → SubDAO SendCoin → parent override |
| Flow B rehearsal | — | CreateSubDAO (Gate Builders) → deploy mocked gates → configure tolls → revenue share → charter amendment |
| Flow C rehearsal | — | Deposit gate caps → ConfigureGateAccess → toll revenue → delegate to SubDAO → SSU integration |
| Indexer scaffold | #4 | Two crates: indexer (custom indexing framework) + schema migration (DB init/updates). Depends on event types from #2 and #3. |
| Gas profiling | — | Validate complex PTBs fit within gas limits; document costs per operation |

**Exit criteria:** Each demo flow rehearsed on Testnet without failures. Indexer consuming events. PTB gas costs documented.

---

## P3 — Frontend

**Goal:** UI that allows demo flows to be executed through a browser.

| Deliverable | Armature Issue | Description |
|---|---|---|
| UI scaffold | #5 | `@mysten/dapp-kit` + `@tanstack/react-query` + `@tanstack/react-router` + Tailwind v4 + `@awar.dev/ui`. Vite SPA, Caddy-fronted static deployment. |
| ProposalConfig defaults | #10 | Table of initial config settings per proposal type, integrated into security dashboard. |
| Proposal security dashboard | #7 | Governance config page — enabled/disabled types, thresholds, delays, warning indicators. |
| Dynamic proposal form | #8 | All 18 proposal type forms with validation, config display, warnings. |
| DAO hierarchy graph | #6 | React Flow (`GraphCanvas` from `@awar.dev/ui`) visualization of SubDAO tree. Blocked on #5. |
| Dashboard + pages | — | DAO dashboard, treasury, capability vault, board, charter, emergency pages. |
| Proposal detail + voting | — | Proposal lifecycle UI with voting panel, timers, action buttons. |
| Payload summaries | — | Type-dispatched read-only renderers for all 18 proposal types. |

**Exit criteria:** All three demo flows executable through the UI on Testnet.

---

## P4 — Polish

**Goal:** Submission-ready quality.

| Deliverable | Description |
|---|---|
| Demo script | Step-by-step narration for each demo flow with timing |
| Documentation | This docs folder serves as whitepaper and technical reference |
| Error UX | Move abort codes → human-readable messages, loading states, confirmation dialogs |
| Submission package | Final testnet deployment, demo video/script, hackathon submission |

**Exit criteria:** Demo can be presented to judges with confidence.

---

## Contract Features → Demo Flow Mapping

| Feature | Flow A | Flow B | Flow C | Phase |
|---------|--------|--------|--------|-------|
| `dao::create_dao` | ✓ | | | P0 |
| `treasury::deposit` | ✓ | | | P0 |
| `proposal::create/vote/execute` | ✓ | ✓ | ✓ | P0 |
| `board_ops::SetBoard` | ✓ | | | P0 |
| `treasury_ops::SendCoin` | ✓ | ✓ | | P0 |
| `subdao_ops::CreateSubDAO` | ✓ | ✓ | | P1 |
| `charter_ops::AmendCharter` | | ✓ | | P1 |
| `capability_vault::deposit` | | ✓ | ✓ | P0 |
| `capability_vault::loan_cap/return_cap` | | ✓ | ✓ | P0 |
| `privileged_submit` (parent override) | ✓ | ✓ | | P1 |
| `subdao_ops::TransferCapToSubDAO` | | | ✓ | P1 |
| `RevenuePolicy` (split-on-deposit) | | ✓ | | P2 |
| Mocked Smart Gate hooks | | ✓ | ✓ | P1 |
| Mocked Smart SSU hooks | | | ✓ | P1 |
| Walrus charter upload/read | ✓ | ✓ | | P1 |
| Third-party DApp read queries | | | ✓ | P2 |

---

## Technical Risk Register

| Risk | Impact | Mitigation | Phase |
|---|---|---|---|
| PTB gas limits for complex SubDAO operations (atomic reclaim = 4 operations) | Operations may exceed gas limit | Gas profiling on testnet; may need to split operations | P1 |
| Walrus blob availability for charter content | Charter content inaccessible if blob expires | `RenewCharterStorage` proposal type; off-chain archival | P1 |
| Mocked gate/SSU contracts diverge from real EVE world contracts | Demo integration not representative | Document all assumptions; use interface patterns that adapt to real contracts | P1 |
| Indexer event schema drift | Indexer breaks if event types change | Stabilize event types in #3 before starting #4 | P2 |

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────┐
│                armature_framework (#3)                    │
│                                                          │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌─────────┐ │
│  │ dao.move │  │governance│  │ proposal │  │emergency│ │
│  │          │  │  .move   │  │  .move   │  │  .move  │ │
│  └──────────┘  └──────────┘  └──────────┘  └─────────┘ │
│                                                          │
│  ┌──────────┐  ┌──────────────┐  ┌──────────┐           │
│  │treasury  │  │capability    │  │ charter  │           │
│  │  .move   │  │ _vault.move  │  │  .move   │           │
│  └──────────┘  └──────────────┘  └──────────┘           │
│                                                          │
│  ┌────────────────────────────────────────────────────┐  │
│  │ voting/                                             │  │
│  │  board.move                                         │  │
│  └────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│                armature_proposals (#2)                    │
│                                                          │
│  ┌────────────────────────────────────────────────────┐  │
│  │ proposals/                                          │  │
│  │  admin.move | treasury_ops.move | board_ops.move   │  │
│  │  subdao_ops.move | charter_ops.move                │  │
│  └────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│                 mock_assemblies                          │
│  mock_gate.move | mock_ssu.move                         │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│                 External Dependencies                    │
│  Walrus (blob storage) | SUI framework | Clock          │
└─────────────────────────────────────────────────────────┘
```

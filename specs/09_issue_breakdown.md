# 09 — Issue Breakdown

> **Implementation repo:** [`loash-industries/armature`](https://github.com/loash-industries/armature)
>
> This document decomposes the hackathon project into trackable issues. Existing armature issues (#2–#10) serve as **parent epics**. Sub-issues are filed underneath with `Part of #N` references. New issues (marked **NEW**) need to be created on the armature repo.
>
> Each sub-issue is:
> - **Self-contained** — one PR, mergeable independently (within dependency ordering)
> - **Testable** — explicit acceptance criteria
> - **Small enough** — completable in 1–3 focused sessions

---

## Issue Map

### Existing Armature Issues

| # | Title | Phase | Status | Sub-issues |
|---|-------|-------|--------|------------|
| #3 | Create the `armature_framework` package | P0 | Open | #13 → #18 |
| #2 | Create the `armature_proposals` package | P0/P1 | Open | C-07 → C-13 |
| #4 | Scaffold the indexer | P2 | Assigned (blurpesec) | I-01 → I-02 |
| #5 | Scaffold the UI | P3 | Assigned (blurpesec) | F-01 |
| #6 | React Flow DAO hierarchy | P3 | Open (blocked on #5) | F-08 |
| #7 | Proposal security dashboard | P3 | Open | F-05.b |
| #8 | Dynamic proposal form UI component | P3 | Open | F-06, F-07 |
| #10 | ProposalConfig defaults table | P3 | Open | (data task → feeds #7, #8) |

### New Issues Needed

| ID | Title | Phase | Parent / Dep |
|----|-------|-------|-------------|
| **NEW** | Mocked smart assemblies package | P1 | Depends on #3 |
| **NEW** | Integration test suite (3 demo flows) | P1 | Depends on #2, #3, mocks |
| **NEW** | Testnet deployment + demo rehearsals | P2 | Depends on integration tests |
| **NEW** | Gas profiling report | P2 | Depends on testnet deployment |
| **NEW** | DAO Dashboard + navigation shell | P3 | Depends on #5 |
| **NEW** | Proposal list + detail + voting UI | P3 | Depends on dashboard |
| **NEW** | Treasury + capability vault pages | P3 | Depends on dashboard |
| **NEW** | Board + charter pages | P3 | Depends on dashboard |
| **NEW** | Payload summary renderers | P3 | Depends on proposal detail |
| **NEW** | CreateSubDAO wizard | P3 | Depends on #8 |
| **NEW** | SubDAO controller actions | P3 | Depends on proposal detail |
| **NEW** | Demo script + rehearsal | P4 | Depends on all P3 |
| **NEW** | Error UX polish | P4 | Depends on all P3 |
| **NEW** | Documentation + submission | P4 | Depends on all |

---

## P0 — Core Contracts

### Armature #3 — `armature_framework` package

> Create the framework package containing core DAO types, governance, proposal lifecycle, treasury, capability vault, emergency freeze, and board voting.

#### #13: DAO object, GovernanceConfig, and `dao::create` — Part of #3

**Module:** `dao.move`, `governance.move`

**Scope:**
- `DAO` struct with all fields from spec §1.1
- `GovernanceConfig` enum (Board variant only)
- `DAOStatus` enum (Active, Migrating)
- `dao::create` — creates DAO + TreasuryVault + CapabilityVault + Charter + EmergencyFreeze as shared objects
- `DAOCreated` event emission
- Default enabled proposal types + default `ProposalConfig` entries

**Acceptance:**
- `test_create_dao` — creates DAO, asserts all companion objects exist, governance = Board with creator as sole member
- `test_dao_created_event` — event emitted with correct fields
- `test_default_proposal_types` — enabled types match spec

**Blocks:** Everything else in #3 and #2

---

#### #14: TreasuryVault — deposit, withdraw, balance, claim — Part of #3

**Module:** `treasury.move`

**Scope:**
- `TreasuryVault` struct with dynamic field storage
- `deposit<T>` (permissionless), `withdraw<T, P>` (`public(friend)`, requires `ExecutionRequest<P>`), `claim_coin<T>`, `balance<T>`
- Zero-balance cleanup, registry sync, `CoinClaimed` event

**Acceptance:** Withdraw auth, registry sync, zero-balance cleanup, deposit, insufficient balance, claim, balance queries (16 tests)

**Depends on:** #13

---

#### #15: CapabilityVault — store, borrow, loan, extract — Part of #3

**Module:** `capability_vault.move`

**Scope:**
- `CapabilityVault` struct with dynamic object fields
- `store_cap_init` / `store_cap`, `borrow_cap` / `borrow_cap_mut`, `loan_cap` / `return_cap` (hot potato `CapLoan`), `extract_cap`, `privileged_extract` (controller reclaim)
- `contains` / `ids_for_type` queries, registry tracking

**Acceptance:** Access control, registry sync, loan semantics, privileged extract, contains, ID queries (20 tests)

**Depends on:** #13

---

#### #16: Proposal lifecycle — create, vote, expire, execute — Part of #3

**Module:** `proposal.move`

**Scope:**
- `Proposal<P>` struct, `ProposalConfig` with validation
- `create<P>`, `vote`, `try_expire`, `execute<P>` → `ExecutionRequest<P>` hot potato
- Status transitions, snapshot immutability, retry semantics
- Events: `ProposalCreated`, `VoteCast`, `ProposalPassed`, `ProposalExecuted`, `ProposalExpired`

**Acceptance:** Hot potato enforcement, status monotonicity, snapshot immutability, executor eligibility, retry semantics, double vote, NO votes, delays, cooldown (25 tests)

**Depends on:** #13, #14, #15

---

#### #17: Board voting module — Part of #3

**Module:** `voting/board.move`

**Scope:**
- Wire `proposal::vote` to board-specific logic
- Vote counting: `(yes + no) * 10000 >= quorum * member_count` AND `yes * 10000 / (yes + no) >= threshold`
- Proposer/executor eligibility: wallet in `governance.members`

**Acceptance:** Single member, 2/3 majority, NO majority, exact threshold, abstention, large board, quorum calculations (10 tests)

**Depends on:** #16

---

#### #18: EmergencyFreeze — freeze, unfreeze, auto-expiry — Part of #3

**Module:** `emergency.move`

**Scope:**
- `EmergencyFreeze` struct, `FreezeAdminCap`, `freeze_type`, `unfreeze_type`
- Cannot freeze `TransferFreezeAdmin` or `UnfreezeProposalType`
- Auto-expiry: `is_frozen` check compares expiry against clock
- Events: `TypeFrozen`, `TypeUnfrozen`

**Acceptance:** Freeze blocks execution, protected types, auto-expiry, cap unfreeze, governance unfreeze, events (10 tests)

**Depends on:** #16

---

### Armature #2 — `armature_proposals` package

> Create the proposals package with all admin, treasury, board, SubDAO, and charter operations.

#### C-07: Admin proposals (6 types) — Part of #2

**Module:** `proposals/admin.move`

**Scope:**
- `UpdateProposalConfig` (80% floor when self-referential)
- `EnableProposalType` (66% floor; SubDAO blocklist)
- `DisableProposalType` (cannot disable protected types)
- `UpdateMetadata`, `TransferFreezeAdmin` (unfrozen), `UnfreezeProposalType` (unfrozen)

**Acceptance:** All 6 types with happy path + negative tests (16 tests). All governance invariants (18 tests).

**Depends on:** #16, #17, #18

---

#### C-08: Treasury proposals — SendCoin, SendCoinToDAO — Part of #2

**Module:** `proposals/treasury_ops.move`

**Scope:**
- `SendCoin<T>` — withdraw + transfer to address
- `SendCoinToDAO<T>` — withdraw + deposit into target DAO treasury
- Both consume `ExecutionRequest`

**Acceptance:** Transfer, balance reduction, insufficient balance abort, generic coin types, cross-DAO deposit (7 tests)

**Depends on:** #14, #16, #17

---

#### C-09: Board proposals — SetBoard — Part of #2

**Module:** `proposals/board_ops.move`

**Scope:**
- `SetBoard` — atomic full-slate board replacement
- Old members lose eligibility immediately, new members gain immediately
- Empty board aborts, governance type preserved

**Acceptance:** Replace all, old member blocked, new member can propose, seat count update, empty board abort (6 tests)

**Depends on:** #16, #17

---

#### C-10: SubDAOControl struct and controller machinery — Part of #2

**Module:** `dao.move` (extend), `capability_vault.move` (extend)

**Scope:**
- `SubDAOControl` struct, `controller_cap_id` / `controller_paused` fields on DAO
- `privileged_extract` on CapabilityVault
- Blocklist enforcement, acyclic graph, single controller

**Acceptance:** All SubDAO invariants (subset covering struct/machinery)

**Depends on:** #13, #15

---

#### C-11: SubDAO proposals — 6 types — Part of #2

**Module:** `proposals/subdao_ops.move`

**Scope:**
- `CreateSubDAO` → child DAO + `SubDAOControl` in parent vault + fund + set board + blocklist. `SubDAOCreated` event.
- `SpinOutSubDAO` → destroy control, clear controller, re-enable hierarchy types. Irreversible. `SubDAOSpunOut` event.
- `TransferCapToSubDAO`, `ReclaimCapFromSubDAO` → `CapabilityTransferred`, `CapabilityReclaimed` events.
- `PauseSubDAOExecution`, `UnpauseSubDAOExecution`

**Acceptance:** CreateSubDAO (4), SpinOut (2), TransferCap (1), ReclaimCap (1), Pause (2), atomic reclaim (1) — 22 tests

**Depends on:** C-10, #16, #17, #14, #15

---

#### C-12: `privileged_submit` — controller bypass — Part of #2

**Module:** `proposal.move` (extend)

**Scope:**
- `privileged_submit<P>` — creates proposal on SubDAO in Passed status directly
- Two simultaneous hot potatoes (controller's + SubDAO's ExecutionRequest)
- CapLoan for SubDAOControl must be returned in same PTB

**Acceptance:** 7 tests — happy path, unauthorized abort, wrong SubDAO, interaction with pause

**Depends on:** C-10, C-11, #16

---

#### C-13: Charter object and charter proposals — Part of #2

**Module:** `charter.move`, `proposals/charter_ops.move`

**Scope:**
- `Charter` struct, `AmendmentRecord`, `AmendCharter` proposal, `RenewCharterStorage` proposal
- Version monotonicity, amendment history, renewal distinction
- `CharterAmended` event

**Acceptance:** Charter tests (10) + charter ops tests (10)

**Depends on:** #13, #16, #17

---

### Armature #10 — ProposalConfig defaults table

> Compile the initial ProposalConfig settings for all 18 proposal types, considering the security spec. Integrate into #7.

**Scope:**
- Table of default quorum, threshold, execution delay, cooldown, and expiry per proposal type
- Respect invariants: UpdateProposalConfig ≥ 80%, EnableProposalType ≥ 66%, protected type floors
- Warning thresholds for the security dashboard (#7)
- Recommended vs minimum values with security rationale

**Acceptance:**
- Markdown table in docs with all 18 types
- JSON/TypeScript constant exported for frontend consumption
- Values validated against invariant constraints

**Depends on:** C-07 (admin proposal validation rules defined)

---

## P1 — Composition (continued)

### NEW — Mocked smart assemblies package

**Module:** `mock_gate.move`, `mock_ssu.move` (separate package: `mock_assemblies`)

**Scope:**
- `MockGate` — `GateAdminCap`, `configure_access`, `collect_toll`
- `MockSSU` — `SSUAdminCap`, `store_item`, `retrieve_item`
- Both caps are `key + store` for CapabilityVault storage
- Minimal logic — demonstrate cap loan/return pattern in demo flows

**Acceptance:**
- Can store `GateAdminCap` in vault, loan, call `configure_access`, return
- Can store `SSUAdminCap` in vault, loan, call `store_item`, return

**Depends on:** #15

---

### NEW — Integration test suite (3 demo flows)

**Module:** `tests/integration_flows.move`

**Scope:**
- Flow A: create DAO → SetBoard → deposit → CreateSubDAO → SubDAO SendCoin → parent override (8 tests)
- Flow B: CreateSubDAO (Gate Builders) → deploy mocked gates → configure tolls → revenue share → charter amendment (8 tests)
- Flow C: deposit gate caps → configure gate access → toll revenue → delegate to SubDAO → SSU integration (8 tests)

**Acceptance:** All 24 tests pass with `sui move test`

**Depends on:** #13 through C-13, mocked assemblies

---

## P2 — Demo Hardening + Indexer

### NEW — Testnet deployment + Flow A rehearsal

**Scope:**
- Publish `armature_framework`, `armature_proposals`, `mock_assemblies` to testnet
- Execute Flow A step-by-step using CLI (`sui client call`)
- Document exact object IDs, tx digests, gas costs per step

**Acceptance:** Flow A completes end-to-end on testnet. Gas costs documented.

**Depends on:** Integration tests

---

### NEW — Testnet Flow B + Flow C rehearsal

**Scope:**
- Execute Flow B and Flow C on testnet using CLI
- Validate mocked gate/SSU interactions, atomic reclaim gas limits
- Document object IDs, tx digests, gas costs

**Acceptance:** Flow B and C complete on testnet. Atomic reclaim fits within gas limit.

**Depends on:** Testnet deployment

---

### NEW — Error handling + edge cases on testnet

**Scope:**
- Test expired proposals, insufficient balance, unauthorized actions, freeze/unfreeze cycles on testnet
- Verify event emission queryable via `suix_queryEvents`
- Document abort codes for frontend error messages

**Acceptance:** All error paths produce correct abort codes. Events queryable via RPC.

**Depends on:** Testnet deployment

---

### NEW — Gas profiling report

**Scope:**
- Table: operation → gas budget → actual gas used → margin
- Identify PTBs approaching gas limit, recommend `gas_budget` per transaction type

**Acceptance:** No operations exceed 80% of gas limit. Markdown table committed.

**Depends on:** All testnet rehearsals

---

### Armature #4 — Scaffold the indexer

> Two crates: indexer (custom indexing framework from SUI) + schema migration (DB init/updates). Depends on event types from #2 and #3.

#### I-01: Indexer schema + migration crate — Part of #4

**Scope:**
- PostgreSQL schema for: DAOs, proposals, votes, treasury transactions, SubDAO relationships, charter amendments, freeze events
- Migration framework (e.g., `sqlx` migrations or `diesel`)
- Tables mirror on-chain event structure

**Acceptance:** `cargo test` passes. Schema can be initialized from scratch.

**Depends on:** #2, #3 (event types finalized)

---

#### I-02: Indexer crate — event consumer — Part of #4

**Scope:**
- SUI custom indexing framework integration
- Event handlers for all 15 event types: `DAOCreated`, `ProposalCreated`, `VoteCast`, `ProposalPassed`, `ProposalExecuted`, `ProposalExpired`, `SubDAOCreated`, `SubDAOSpunOut`, `CharterAmended`, `CoinClaimed`, `TypeFrozen`, `TypeUnfrozen`, `CapabilityTransferred`, `CapabilityReclaimed`, `BoardReplaced`
- Cursor tracking for restart resilience

**Acceptance:** Indexer consumes events from testnet and populates DB. Can restart without data loss.

**Depends on:** I-01, testnet deployment

---

## P3 — Frontend

### Armature #5 — Scaffold the UI (assigned: blurpesec)

> `@mysten/dapp-kit` + `@tanstack/react-query` + `@tanstack/react-router` + Tailwind v4 + `@awar.dev/ui`. Vite SPA, Caddy-fronted static deployment.

#### F-01: Project scaffold + data layer + wallet — Part of #5

**Scope:**
- Vite + React project with TypeScript, `@awar.dev/ui` component library, `@mysten/dapp-kit` wallet integration, `@tanstack/react-router` routing
- `SuiClient` wrapper with React Query provider, cache key structure from `06_data_layer.md`
- Event polling hook (`useEventPoller`) — polls `suix_queryEvents` every 3–5s, invalidates cache keys per event→cache map
- DAO context provider — selected DAO ID, companion object IDs resolved on selection
- `AWARProvider` + `SidebarProvider` shell wired up

**Acceptance:**
- Can connect wallet on testnet, fetch and display a DAO object by ID
- Event poller runs, React Query devtools show cache entries

**Depends on:** Testnet deployment (for DAO IDs)

---

### NEW — DAO Dashboard + navigation shell

> `AppShell`, `DaoSidebar`, `SubDAOBreadcrumb`, `DaoDashboard` per `ui/00_overview.md` and `ui/02_core_pages.md`.

**Scope:**
- `Sidebar` with all 9 nav items (`SidebarMenu`, `SidebarMenuButton`, `SidebarMenuBadge`), `LogoLockup`, DAO switcher (`Select`), "New Proposal" `Button` (Member only)
- `SubDAOBreadcrumb` via `Breadcrumb` components, wallet `Badge` in header
- `DaoDashboard` — summary `Card` ×4, active proposals `Table` with `Progress` bars, SubDAO list, recent activity, controller `Alert` banner

**Acceptance:**
- Navigate between all sidebar pages (pages can be empty shells)
- Dashboard shows live data from a testnet DAO
- Controller banner appears for SubDAOs, "New Proposal" hidden for non-members

**Depends on:** F-01

---

### NEW — Proposal list + detail + voting UI

> `ProposalsList`, `ProposalDetail`, `VotingPanel`, `CountdownTimer`, execution panel per `ui/01_proposal_lifecycle.md` and `ui/02_core_pages.md`.

**Scope:**
- `ProposalsList` — `Tabs` (status filter), `Table` with `TableSortHead`, `Badge`, `Progress`
- `ProposalDetail` — `Card` header with `Badge`, payload summary (placeholder), voting `Progress` bars, voter `Table`, `<CountdownTimer>`, action `Button`s
- Vote transaction + optimistic update, execute transaction, expire transaction
- `Alert` banners for freeze/pause/privileged

**Acceptance:**
- List proposals, filter by status, view detail with live vote tally
- Board member can vote, tally updates optimistically
- Board member can execute after delay, freeze/pause banners shown
- Timers count down accurately

**Depends on:** Dashboard

---

### NEW — Treasury + capability vault pages

> `TreasuryPage`, `CapVaultPage` per `ui/02_core_pages.md`.

**Scope:**
- `TreasuryPage` — `Table` with `TableSortHead` (coin balances), deposit `Collapsible` form (`Form`, `Select`, `NumberInput`), transaction history
- `CapVaultPage` — `Accordion` grouped by type, `Table` with `Badge` (loan status), `DropdownMenu` for cap actions, SubDAOControl section

**Acceptance:**
- Treasury shows coin types with formatted balances, can deposit from wallet
- Cap vault lists stored capabilities, SubDAOControl entries link to child DAOs

**Depends on:** Dashboard

---

### NEW — Board + charter pages

> `BoardPage`, `CharterPage` per `ui/02_core_pages.md`.

**Scope:**
- `BoardPage` — `Card` with `Table`, `Badge` ("You"), `Button` ("Propose Board Change")
- `CharterPage` — `Tabs` (Document / Integrity), `ScrollArea` for rendered markdown, SHA-256 integrity `Badge`, `Accordion` for amendment history

**Acceptance:**
- Board page shows members, highlights connected wallet
- Charter renders markdown from Walrus, shows "Verified" badge, amendment history expandable

**Depends on:** Dashboard

---

### Armature #7 — Proposal security dashboard

> Governance config page — enabled/disabled types, thresholds, delays, warning indicators.

#### F-05.b: Governance config + emergency freeze pages — Part of #7

**Scope:**
- `GovConfigPage` — `Table` with `TableSortHead` per enabled type (quorum, threshold, delay, cooldown, expiry), `Badge` ("Protected"), `DropdownMenu` (Edit / Disable), `Collapsible` for disabled types, `Alert` for validation rules
- `EmergencyPage` — `Alert variant="destructive"`, frozen types `Table` with `<CountdownTimer>`, freeze controls `Form` with `Select` + `Button variant="destructive"`, `Skeleton` loading
- Warning indicators per armature #10 defaults: highlight when config is below recommended security thresholds

**Acceptance:**
- Gov config shows all enabled types with config values, can trigger edit/enable/disable proposals
- Emergency page shows frozen types with countdowns
- Warning indicators surface when thresholds are dangerously low

**Depends on:** Dashboard, #10 (for default/warning values)

---

### Armature #8 — Dynamic proposal form UI component

> For each DAO, display enabled/disabled proposals with their settings, and provide forms for creating proposals of each type.

#### F-06: Proposal forms — Tier 1 (generic) + Tier 2 (custom) — Part of #8

**Scope:**
- Type selector: `Dialog` → `Command` (`CommandInput`, `CommandGroup`, `CommandItem`) grouped by category
- `GenericProposalForm` — shared `Form` for 9 simple types using `Input`, `Select`, `AlertDialog` (SpinOut confirmation)
- Custom forms: `SendCoinForm` (`Select`, `NumberInput`), `SetBoardForm` (`Table` + `Input` rows, diff `Badge`), `EnableTypeForm` / `UpdateConfigForm` (`NumberInput unit="%"`), `AmendCharterForm` (`Tabs` + `Textarea`), `TransferCapForm` / `ReclaimCapForm` (`Select` pickers)
- Transaction construction per type

**Acceptance:**
- Can create a proposal for each of the 17 types (excluding wizard)
- Form validation matches spec constraints
- Walrus upload works for AmendCharter

**Depends on:** Proposal detail, treasury/vault data, charter data, #10

---

#### F-07: CreateSubDAO wizard — Part of #8

**Scope:**
- `CreateSubDAOWizard` — 6-step wizard using `Tabs variant="solid"`:
  1. Identity (`Input` ×2)
  2. Board (`Table` + `Input` rows, `NumberInput`)
  3. Charter (`Textarea` + Walrus upload)
  4. Proposal Types (`ScrollArea` → `Table` + `Checkbox` + `NumberInput`, blocklist `Tooltip`)
  5. Funding (`Select` + `NumberInput`, optional)
  6. Review (`Card` sections, `Table`, `Button`)
- Step validation, back button preserves state via react-hook-form

**Acceptance:**
- Wizard completes end-to-end, blocked types greyed out, protected types locked
- Walrus upload before submit, review step shows complete summary

**Depends on:** F-06

---

### Armature #6 — React Flow DAO hierarchy (blocked on #5)

> React Flow (`GraphCanvas` from `@awar.dev/ui`) visualization of SubDAO tree.

#### F-08: SubDAO list page + hierarchy graph + controller actions — Part of #6

**Scope:**
- `SubDAOListPage` — `Tabs` (List / Graph views)
- List view: `Card` per SubDAO with `Badge` (status), `DropdownMenu` (controller actions), `AlertDialog` (SpinOut confirmation)
- Graph view: `GraphCanvas` with custom node components, `GraphEdge` (control links), `GraphLegend`
- Controller actions → proposal creation (Replace Board, Pause, Unpause, Reclaim Cap, Spin Out)

**Acceptance:**
- SubDAO list populated from parent's CapabilityVault, graph view renders hierarchy
- Controller actions trigger correct proposal creation, SpinOut shows confirmation

**Depends on:** Proposal detail, #5

---

### NEW — Payload summary renderers

> `PayloadSummary` — type-dispatched read-only renderers for all 18 proposal types per `ui/04_payload_summaries.md`.

**Scope:**
- Dispatch component rendering correct summary based on proposal type
- 18 renderers using `Table`, `Badge`, `Tooltip`, `HoverCard` for addresses/IDs
- Diff highlighting (SetBoard, UpdateProposalConfig, AmendCharter), amount formatting, duration formatting, bps → percentage

**Acceptance:**
- Every proposal type renders payload summary in `ProposalDetail`
- Diffs show green/red highlighting, amounts formatted, Walrus links work

**Depends on:** Proposal detail

---

## P4 — Polish

### NEW — Demo script + rehearsal

**Scope:**
- Step-by-step narration for each demo flow (target: each under 5 minutes)
- Pre-created testnet state (DAOs, funded treasuries)
- Rehearsal run-through, fallback plan

**Acceptance:** Each flow completes under 5 minutes in the UI. Script covers narration + timing.

**Depends on:** All P3 issues

---

### NEW — Error UX polish

**Scope:**
- Move abort code → human-readable messages (toast via `sonner`)
- Loading states (`Skeleton`, `Button disabled`), confirmation `AlertDialog`s
- Stale data `Badge variant="outline"`, all transaction paths have loading → success/error feedback

**Acceptance:** No raw error codes visible, every transaction path has feedback.

**Depends on:** All P3 issues

---

### NEW — Documentation + README

**Scope:**
- Project README: architecture overview, local setup, deployment instructions
- Contract deployment instructions (localnet + testnet)
- Frontend setup instructions, link to docs/ spec

**Acceptance:** A new developer can clone, build, and run locally.

**Depends on:** All prior issues

---

### NEW — Submission package

**Scope:**
- Final testnet deployment with stable object IDs
- Demo video recording or live demo prep
- Hackathon submission form

**Acceptance:** Submission complete, demo ready, testnet stable.

**Depends on:** All prior issues

---

## Dependency Graph

```
                        #3 armature_framework
                        ┌─────────────────────┐
                        │ #13 ──┬── #14     │
                        │        ├── #15     │
                        │        ├── #16 ── #17
                        │        └── #18     │
                        └─────────────────────┘
                                 │
                        #2 armature_proposals
                        ┌─────────────────────┐
                        │ C-07 (after #17,06)│
                        │ C-08 (after #14,05)│
                        │ C-09 (after #17)   │
                        │ C-10 (after #13,03)│
                        │ C-11 (after C-10)   │
                        │ C-12 (after C-11)   │
                        │ C-13 (after #13,05)│
                        └─────────────────────┘
                                 │
              ┌──────────────────┼──────────────────┐
              │                  │                  │
         Mock Assemblies   Integration Tests   #10 Config
         (after #15)      (after all C-xx)    (after C-07)
                                 │
                    ┌────────────┼────────────┐
                    │            │            │
              Testnet Deploy   #4 Indexer   Gas Profile
              + Flow A         ┌──────┐
              │                │I-01  │
              ├── Flow B+C     │I-02  │
              └── Error tests  └──────┘
                    │
              ┌─────┴──────────────────────────────────┐
              │                                        │
         #5 UI Scaffold                                │
              │                                        │
         Dashboard + Nav Shell                         │
              │                                        │
    ┌─────────┼──────────┬──────────────┐              │
    │         │          │              │              │
Proposal   Treasury   Board+Charter  #7 GovConfig     │
List+Detail  +Vault    Pages          +Emergency       │
    │                                   │              │
    ├──────── Payload Summaries         │              │
    │                                   │              │
    ├──────── #8 Proposal Forms ◄── #10 ┘              │
    │              │                                   │
    │         #8 CreateSubDAO Wizard                   │
    │                                                  │
    ├──────── #6 SubDAO Hierarchy (Graph) ◄────────────┘
    │
    └──────── SubDAO Controller Actions
                    │
         ┌──────────┼──────────┐
         │          │          │
    Demo Script  Error UX   Docs+README
                    │
              Submission Package
```

---

## Parallel Work Opportunities

| Track | Issues | Owner Profile |
|-------|--------|---------------|
| **Framework core** | #13 → #14, #15 (parallel after #13) | Move developer |
| **Proposal system** | #16 → #17 → #18 → C-07 (sequential) | Move developer |
| **Proposal handlers** | C-08, C-09 (parallel after #17) | Move developer |
| **Composition** | C-10 → C-11 → C-12 (sequential after #15 + #17) | Move developer |
| **Charter** | C-13 (parallel after #13 + #17) | Move developer |
| **Mocks** | Mock assemblies (parallel after #15) | Move developer |
| **Indexer** | #4: I-01 → I-02 (after event types stabilized) | Backend developer (blurpesec) |
| **UI scaffold** | #5: F-01 (after testnet deploy) | Frontend developer (blurpesec) |
| **UI pages** | Dashboard → Proposal/Treasury/Board/Charter (parallel after dashboard) | Frontend developer |
| **UI forms** | #8: F-06 → F-07, #7: F-05.b (after pages) | Frontend developer |
| **UI graph** | #6: F-08 (after #5, can parallel with forms) | Frontend developer |
| **Config data** | #10 (after C-07, feeds into #7 and #8) | Either |
| **Polish** | Demo script, error UX, docs, submission (after all P3) | Either |

### Critical Path (2 developers)

```
#13 → #16 → #17 → C-07 → C-11 → C-12 → Integration → Testnet → F-01 → Dashboard → Proposal UI → F-06 → Demo Script
```

#14, #15, #18, C-08, C-09, C-13, mocks can all be parallelized around this spine. Indexer (#4) runs on the backend track independently.

---

## Summary Counts

| Phase | Existing Issues | New Issues | Total |
|-------|----------------|------------|-------|
| P0/P1 Contracts | #2, #3 | Mocks, Integration | 4 epics, 15 sub-issues |
| P2 Demo + Indexer | #4 | Testnet deploy, flows, gas | 1 epic, 6 sub-issues |
| P3 Frontend | #5, #6, #7, #8, #10 | Dashboard, pages ×3, detail, summaries, wizard, controller | 5 epics, 11 sub-issues |
| P4 Polish | — | Demo, error UX, docs, submission | 4 issues |
| **Total** | **8 existing** | **~19 new** | **~27 issues** |

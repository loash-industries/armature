# 07 — Roadmap

**Implementation repo:** [`loash-industries/armature`](https://github.com/loash-industries/armature)

This roadmap was written for the March 2026 hackathon and aligned phases P0–P4 to the open issues on `armature`. It is now the status record for those phases: each deliverable says whether it shipped as planned, shipped in a different form, or was dropped. [Beyond the original phases](#beyond-the-original-phases) lists what shipped outside them, and [What's next](#whats-next) lists only the follow-ups the repo itself records. See `09_issue_breakdown.md` for the sub-issue decomposition with outcomes and `.cortex/changelog.md` for the post-hackathon history. The long-range vision (governance models, federation, ticker registry, charter invariants) lives in the repo-root `ROADMAP.md` and in `stretch/`; none of it is implemented.

> **Status basis.** The source at commit `6ed2b77` (branch `fix/road-39-arg-binding`), 2026-09-26. At the time of writing, the September 2026 framework work (ARMATURE-9 … ARMATURE-15, PRs #162–#167, on the `cycle-7` branch; ROAD-39 with ARMATURE-21 … ARMATURE-35, on its feature branch) was not yet on `main`, whose last merge is #161 (2026-08-12). Every testnet publish (`testnet` 2026-03-27, `testnet_wip` June, `testnet_stillness` 2026-06-25) predates that work.

**Status key:** **Done**: shipped as planned. **Changed**: shipped, but the design differs from the plan. **Dropped**: not built, or removed. **Open**: still to do.

---

## Phase Overview

| Phase | Focus | Armature Issues | Gate | Status |
|-------|-------|-----------------|------|--------|
| **P0 — Core Contracts** | OU creation, Board governance, proposal lifecycle, treasury, cap vault | #3, #2 | All unit tests pass; can create OU and execute a proposal on localnet | **Done** (2026-03-11 – 13); every module since reworked (see below) |
| **P1 — Composition** | SubOU hierarchy, charter with Walrus, mocked assemblies, integration tests | #2 (continued) | SubOU flows work end-to-end on localnet | **Changed**: SubOU hierarchy done; Walrus charter and mocked assemblies dropped |
| **P2 — Demo + Indexer** | Testnet deployment, demo flows, indexer scaffold, gas profiling | #4 | Full demo rehearsal on Testnet; indexer serving events | **Changed**: testnet publish, demo and indexer done; Flows B/C and the gas report dropped |
| **P3 — Frontend** | UI scaffold, pages, forms, hierarchy graph, security dashboard | #5, #6, #7, #8, #10 | Demo flows executable through UI on Testnet | **Done** in March; the UI was removed from this repo in #148 (2026-05-26) |
| **P4 — Polish** | Error UX, demo script, documentation, submission | — | Submission-ready | **Done**, except the abort-code error UX |

---

## P0 — Core Contracts — Done

**Goal:** The minimum on-chain objects and logic to create an OU, propose, vote, and execute.

**Package:** `armature_framework` (armature #3), merged 2026-03-11/12 as PRs #22, #25, #26, #29, #31, #33 (sub-issues #13–#18).

| Deliverable | Modules (planned → current) | Demo Flow Coverage | Status |
|---|---|---|---|
| OU Object & Creation | `ou.move`, `governance.move` | Flow A Step 1 | **Changed**: the type registry is one dynamic-field slot per enabled type (ARMATURE-9); the roster is a versioned `Table` and Board is the only governance model (ARMATURE-13) |
| Proposal Lifecycle | `proposal.move` | All flows | **Changed**: handlers receive an `ExecutionTicket<P>` (#149); stored statuses are `Active` / `Passed` only; execution and expiry delete the proposal (ARMATURE-12) |
| Board Voting | `voting/board.move` → `board_voting.move` | All flows | **Changed**: holds the submit, vote and execute entry points; voters are the members at the proposal's roster version (ARMATURE-13/14) |
| Treasury Vault | `treasury.move` → `treasury_vault.move` | Flow A Step 3 (deposit), Flow A Step 6 (SendCoin) | **Done**; multicoin balances added (#150), later removed with the `multicoin` dependency |
| Capability Vault | `capability_vault.move` | Flow B Step 3 (deposit caps), Flow C Steps 1–3 (loan/return) | **Done**; borrows limited to the request's borrow scope (ROAD-39) |
| Emergency Freeze | `emergency.move` | Safety infrastructure, not demoed directly | **Changed**: keyed by the payload's `TypeName` (ARMATURE-15); the `FreezeAdminCap` goes to the creator, who freezes directly |

**Package:** `armature_proposals` (armature #2), PRs #12, #20, #24, #30, #66.

| Deliverable | Modules (planned → current) | Demo Flow Coverage | Status |
|---|---|---|---|
| Admin Proposals | `proposals/admin.move` → framework `sources/types/` with handlers `armature::admin_ops` and `armature::freeze_ops` | `EnableProposalType` used throughout to unlock new proposal types | **Changed**: moved into the framework (ARMATURE-9, ROAD-39); EnableProposalType's floor rose from 66% to 80% |
| Treasury Proposals | `proposals/treasury_ops.move` → `armature_proposals::treasury_ops` | Flow A Step 6, Flow B Step 6 | **Done**; `SendSmallPayment` (#84) and batch multicoin sends (#150) added; the batch sends were later removed with the `multicoin` dependency |
| Board Proposals | `proposals/board_ops.move` → framework `board_ops`, `member_ops` | Flow A Step 2 (SetBoard), Flow A Step 7 (parent override) | **Changed**: `SetBoard` is an add/remove diff (ARMATURE-13); AddMember / RemoveMember (#134), BatchAddMembers (#142) and BatchRemoveMembers (#158) added |

**Exit criteria:** Can create an OU on localnet, add board members, deposit to treasury, create/vote/execute a SendCoin proposal. **Met**: unit tests, localnet setup scripts (#100) and UI wiring on localnet (#110).

---

## P1 — Composition — Changed

**Goal:** SubOU hierarchy and charter integration — the features that make the OU composable.

| Deliverable | Planned module | Where it landed | Status |
|---|---|---|---|
| SubOUControl struct | `ou.move` extension | `capability_vault::SubOUControl { id, subou_id }`; `OU.controller_cap_id` (#72) and `controller_paused` | **Done** |
| SubOU Proposals | `proposals/subou_ops.move` | `CreateSubOU`, `SpinOutSubOU` (and `SpawnOU`, `TransferAssets`) are framework types handled by `armature::lifecycle_ops`; pause/unpause, cap transfer/reclaim and controller batch member types stay in `armature_proposals::subou_ops`; SubOU-blocked types (#82) | **Changed** |
| Charter Object & Walrus | `charter.move`, `proposals/charter_ops.move` | `Charter { name, metadata_uri }` (#159); `UpdateMetadata` (display key "CharterUpdate") is its only mutation | **Dropped**: Walrus storage, `AmendCharter`, `RenewCharterStorage`, versions and amendment history (planned in `05_charter.md`) |
| `privileged_submit` | `proposal.move` extension | `controller::privileged_submit` (#73); creates no `Proposal` object and returns a privileged request (ARMATURE-11, ARMATURE-22) | **Changed** |
| Capability Delegation | `TransferCapToSubOU`, `ReclaimCapFromSubOU` | `armature_proposals::subou_ops` | **Done** |
| Mocked Smart Assemblies | `mock_assemblies` (`mock_gate.move`, `mock_ssu.move`) | Never built. EVE world integration went through `armature_world_bridge` instead (autojoin, #144), built against the real `world` package | **Dropped** |

**Exit criteria:** Full SubOU lifecycle on localnet: create SubOU → fund → delegate cap → sub-OU operates → parent overrides board → parent reclaims cap. **Met in Move scenario tests**, not as one localnet run: `armature_proposals/tests/subou_ops_tests.move` (create, cap transfer and reclaim, pause/unpause, controller batch members), `migration_tests.move` (spin-out, board change through `privileged_submit`) and `lifecycle_tests.move` (a multi-SubOU scenario). The gate/SSU steps went with the mocks.

---

## P2 — Demo Hardening + Indexer — Changed

**Goal:** All three demo flows execute cleanly on Testnet. Indexer serves event data to frontend.

| Deliverable | Armature Issue | Description | Status |
|---|---|---|---|
| Testnet deployment | — | Publish `armature_framework`, `armature_proposals`, `mock_assemblies` to testnet | **Done** without `mock_assemblies`: published for the demo on 2026-03-27 (`packages/*/deploy.txt`); republished to `testnet_wip` (June) and `testnet_stillness` (2026-06-25) together with `armature_world_bridge` |
| Flow A rehearsal | — | Create OU → SetBoard → deposit → CreateSubOU → SubOU SendCoin → parent override | **Changed**: demo recorded (video linked from `README.md`, 2026-03-31); the Walrus charter step cannot run as written. No rehearsal log is kept in the repo |
| Flow B rehearsal | — | CreateSubOU (Gate Builders) → deploy mocked gates → configure tolls → revenue share → charter amendment | **Dropped**: needs mocked gates, a revenue policy and charter amendments, none of which exist |
| Flow C rehearsal | — | Deposit gate caps → ConfigureGateAccess → toll revenue → delegate to SubOU → SSU integration | **Dropped**: needs the mocked gate/SSU caps |
| Indexer scaffold | #4 | Two crates: indexer (custom indexing framework) + schema migration (DB init/updates). Depends on event types from #2 and #3. | **Done** in this repo (#122, #124), then moved to the separate `armature-indexer` repo (removed here in #148) |
| Gas profiling | — | Validate complex PTBs fit within gas limits; document costs per operation | **Dropped** as a report. Gas data from a live testnet OU later drove ARMATURE-9 … ARMATURE-12 (see [Beyond the original phases](#beyond-the-original-phases)) |

Manual end-to-end QA scenarios, including negative and edge cases, are in `testing/e2e/` (#109).

**Exit criteria:** Each demo flow rehearsed on Testnet without failures. Indexer consuming events. PTB gas costs documented. **Partly met**: Flow A-style operations and the indexer; Flows B/C and the gas table were not done.

---

## P3 — Frontend — Done (UI since moved out of this repo)

**Goal:** UI that allows demo flows to be executed through a browser.

| Deliverable | Armature Issue | Description | Status |
|---|---|---|---|
| UI scaffold | #5 | `@mysten/dapp-kit` + `@tanstack/react-query` + `@tanstack/react-router` + Tailwind v4 + `@awar.dev/ui`. Vite SPA, Caddy-fronted static deployment. | **Done** (#65); `@awar.dev/ui` replaced by shadcn/ui (#128) |
| ProposalConfig defaults | #10 | Table of initial config settings per proposal type, integrated into security dashboard. | **Changed**: warning thresholds shipped in the governance config page (#83). Defaults and floors are now fixed on-chain (`ou::config_for_type`, `ou::assert_config_floors`); `docs/proposal-types.md` lists each type's bits and floor |
| Proposal security dashboard | #7 | Governance config page — enabled/disabled types, thresholds, delays, warning indicators. | **Done** (#83) |
| Dynamic proposal form | #8 | All 18 proposal type forms with validation, config display, warnings. | **Done** (#85, wired to transactions in #107); no AmendCharter form, since the contracts have none |
| OU hierarchy graph | #6 | React Flow (`GraphCanvas` from `@awar.dev/ui`) visualization of SubOU tree. Blocked on #5. | **Done** (#87) |
| Dashboard + pages | — | OU dashboard, treasury, capability vault, board, charter, emergency pages. | **Done** (#67, #89) |
| Proposal detail + voting | — | Proposal lifecycle UI with voting panel, timers, action buttons. | **Done** (#98, #110) |
| Payload summaries | — | Type-dispatched read-only renderers for all 18 proposal types. | **Done** (#85) for the types that existed then |

The UI, the Rust indexer and the API server were removed from this repo in #148 (2026-05-26). This repo now holds the Move packages only. The removed UI targeted the March contract shapes; clients must follow the September changes (see [What's next](#whats-next)).

**Exit criteria:** All three demo flows executable through the UI on Testnet. **Partly met**: the UI was wired end to end on localnet (#110) and to testnet wallets (#111); Flows B and C depended on dropped pieces.

---

## P4 — Polish — Done except error UX

**Goal:** Submission-ready quality.

| Deliverable | Description | Status |
|---|---|---|
| Demo script | Step-by-step narration for each demo flow with timing | **Done**: demo video linked from `README.md` (2026-03-31) |
| Documentation | This docs folder serves as whitepaper and technical reference | **Done**: specs added 2026-03-16; Typst whitepaper (#113, restructured in #126), revised to v0.2 to match the implementation (#160) with tagged PDF releases (#161) |
| Error UX | Move abort codes → human-readable messages, loading states, confirmation dialogs | **Open** when the UI left this repo: no abort-code-to-message mapping was built |
| Submission package | Final testnet deployment, demo video/script, hackathon submission | **Done**: testnet publish (2026-03-27), demo video, README rewrite and `ROADMAP.md` (2026-03-29) |

**Exit criteria:** Demo can be presented to judges with confidence. **Met.**

---

## Beyond the original phases

### Shipped during the hackathon, outside P0–P4

These were stretch items in the plan (`stretch/03_migration.md`, `stretch/05_advanced_proposals.md`) but landed in March:

| Change | Refs |
|---|---|
| Migration: `SpawnOU` successor + `Active → Migrating`, `TransferAssets`, permissionless `ou::destroy` | #78 |
| `SendSmallPayment<T>`: rate-limited treasury spend held in type-state | #84 |
| `ProposeUpgrade`: package upgrades through a vault-held `UpgradeCap` | `armature_proposals/sources/upgrade/` (March) |
| SubOU-blocked proposal types | #82 |

### After the hackathon

| When | Change | Refs |
|---|---|---|
| 2026-05-10/11 | Tribe constructors: `tribe::create_tribe` builds Tribe → Officers → Members OUs in one transaction | #132; `create_tribe_configured`, `create_wired_subou` in #157 (2026-06-19) |
| 2026-05-11 | Seal-encrypted entries (`encrypted_entry`, `seal_approve`, `encrypt_epoch`) | #133 |
| 2026-05-12 – 18 | AddMember, RemoveMember; BatchAddMembers | #134; #142 |
| 2026-05-13 | Proposer-weight threshold; `spend_guard` rolling-epoch spend limit | #135, #136 |
| 2026-05-19 | Bypass execution: `ExternalExecutionCap<P>`, `EnableBypassType` / `DisableBypassType`, `ticket_from_cap` | #143 |
| 2026-05-19 | New package `armature_world_bridge`: `AutojoinOU` self-join for allowlisted EVE tribes | #144 |
| 2026-05-21 | Currency types over OU-held `TreasuryCap`s: AdoptCurrency, MintCoin, MintAllowance, BurnCoin, ReturnCurrencyCap | #146 |
| 2026-05-21 | Composite proposals: up to 16 steps, no nesting, component-wise maximum config | #137 |
| 2026-05-26 | One `ExecutionTicket<P>` handler model for the vote, composite and bypass paths; UI, indexer and API removed from this repo | #149, #148 |
| 2026-05-28 | Multicoin treasury storage for many assets; batch multicoin send types (later removed, with the `multicoin` dependency) | #150 |
| 2026-06-07 | Atomic single-vote path `board_voting::submit_vote_execute` | #152 (`proposals/ADR_SUBMIT_VOTE_EXECUTE.md`) |
| 2026-06-11 | OU initialization events (`OUBoardInitialized`) | #155 |
| 2026-06-19 | BatchRemoveMembers; controller batch member ops on SubOUs (`ControllerBatchAddMembers` / `ControllerBatchRemoveMembers`) | #158 |
| 2026-06-19 | Charter reduced to `{ name, metadata_uri }` | #159 |
| 2026-08-10/12 | Whitepaper v0.2 accuracy revision; tagged PDF releases | #160, #161 |
| 2026-09-24 | Type-keyed registry: one dynamic-field slot per canonical `TypeName`; the payload type selects the slot, with no caller-supplied `type_key` | ARMATURE-9 (#162) |
| 2026-09-24/25 | Read-only (`&OU`) variants of the atomic, two-PTB and bypass paths; single-PTB executions leave only events, no `Proposal` object | ARMATURE-10, ARMATURE-11 (#163, #164) |
| 2026-09-25 | Execution deletes the proposal; anyone deletes an expired one; saturating deadlines; no votes after expiry | ARMATURE-12 (#165) |
| 2026-09-26 | Table-backed roster with `roster_version`; snapshot by version; `SetBoard` as a diff; Direct/Weighted variants removed | ARMATURE-13, ARMATURE-14 (#166) |
| 2026-09-26 | Emergency freeze keyed by `TypeName`; third-party fixture package `armature_external_type_tests` | ARMATURE-15 (#167) |
| 2026-09-26 | Permission model: per-type bits, fixed framework bits, floors enforced in `ou` (EnableProposalType now 80%), grant rules, every mutator gated, CI gate check, denial tests | ARMATURE-22 … ARMATURE-29, ARMATURE-32, ARMATURE-35 (ROAD-39) |
| 2026-09-26 | Package boundaries (`docs/package-boundaries.md`): `Permit`-bound tickets, borrow scope, bypass-safe bits, freeze-governance types moved into the framework, authenticated `MintAllowance` bypass | ROAD-39, ARMATURE-31 |

The September redesign was driven by gas data from a live testnet OU (a tribe's officers SubOU): every transaction rewrote an 18.5 KB OU root, which was 88% of the non-refundable storage burn, and 743 undeleted single-PTB audit objects held about 5.35 SUI of deposits (`.cortex/changelog.md`).

**Stretch items now shipped:** migration (`stretch/03`), rate-limited payments and upgrade authorization (`stretch/05`), proposal composition (`stretch/09`), and third-party proposal types (`stretch/11`), delivered as permission bits plus `Permit`-bound tickets, with `armature_external_type_tests` as the template. **Dropped from the code:** the Direct and Weighted governance variants (ARMATURE-13). They remain a stretch design (`stretch/02`), but a weighted model would need each member's weight at every past roster version, which the roster does not keep.

The repo-root `ROADMAP.md` still lists proposal composition as future work (Phase 1), and its Phase 0 cites the old 66% enable floor.

---

## What's next

Only follow-ups the repo records:

| Item | Source | Status |
|---|---|---|
| Fresh publish of the ROAD-39 framework. A type's package is a one-way door, so placement is settled before it; `ProposalConfig` and `ExecutionRequest` gain a trailing `borrow_scope` (BCS change), and every `VAULT_BORROW` config must now carry a scope | `.cortex/changelog.md` (ROAD-39), `docs/package-boundaries.md` | Open |
| Consumer updates (ARMATURE-16, plus the ROAD-39 config changes). PTB builders drop `type_key`, call `board_voting::vote(proposal, &ou, …)`, stop passing `clock` to `privileged_submit` and the five `subou_ops` handlers that forwarded it, use the typed composite grant steps, and pass bits and borrow scopes in configs. The indexer adds `ProposalCreated.metadata_ipfs`, derives executed/expired from events, and follows the `TypeSlot*`, freeze (`type_name`) and `BoardUpdated { added, removed }` shapes. Named consumers: indexer, SDK, UI, triex-app-api, signer-api allowlist | `.cortex/changelog.md` | Open |
| Specs and docs brought in line with ARMATURE-9 … ROAD-39 (ARMATURE-17) | `.cortex/changelog.md` | `specs/` done in this revision (`specs/stretch/` kept as the original designs; `specs/ui/` removed). Still stale: `docs/single-vote-execute.md`, `docs/tribe_configuration_proposals_config.md` (66% `EnableProposalType` configs, which now abort), `docs/indexing_board_events.md`, `docs/tribe-creation.md`, `README.md`, `ROADMAP.md` |
| Default non-zero `execution_delay_ms` for governance-sensitive types (SetBoard, AddMember, RemoveMember, UpdateProposalConfig, EnableProposalType, …) so they cannot take the atomic path | `proposals/ADR_GOVERNANCE_TYPE_DELAY_DEFAULTS.md` | Proposed; defaults still have delay 0 |
| ADR status fields: `ADR_COMPOSABLE_PROPOSALS`, `ADR_SUBMIT_VOTE_EXECUTE` and `ADR_SUBMISSION_TIME_FLOOR_ENFORCEMENT` still say "Proposed" although the code implements them (the last is superseded by the floors in `ou`, ARMATURE-24) | `proposals/` | Open |
| Formal verification with sui-prover | `10_formal_verification.md` | Plan only; no prover specs or CI job |

---

## Contract Features → Demo Flow Mapping

| Feature (planned name) | Flow A | Flow B | Flow C | Phase | Status / current API |
|---------|--------|--------|--------|-------|--------|
| `ou::create_ou` | ✓ | | | P0 | **Done**: `ou::create(&GovernanceTypeInit, name, metadata_uri, ctx)`; tribe constructors in `tribe` |
| `treasury::deposit` | ✓ | | | P0 | **Done**: `treasury_vault::deposit<T>`, permissionless |
| `proposal::create/vote/execute` | ✓ | ✓ | ✓ | P0 | **Changed**: `board_voting::submit_proposal<P>` / `vote` / `ticket_from_vote`; atomic `submit_vote_execute` |
| `board_ops::SetBoard` | ✓ | | | P0 | **Changed**: framework `board_ops::execute_set_board`, add/remove diff |
| `treasury_ops::SendCoin` | ✓ | ✓ | | P0 | **Done**: `armature_proposals::treasury_ops::execute_send_coin<T>` (TREASURY_WITHDRAW, 80%) |
| `subou_ops::CreateSubOU` | ✓ | ✓ | | P1 | **Changed**: framework `lifecycle_ops::execute_create_subou` |
| `charter_ops::AmendCharter` | | ✓ | | P1 | **Dropped**: `UpdateMetadata` replaces the charter's metadata URI |
| `capability_vault::deposit` | | ✓ | ✓ | P0 | **Done**: `capability_vault::store_cap` (VAULT_STORE) |
| `capability_vault::loan_cap/return_cap` | | ✓ | ✓ | P0 | **Done**: VAULT_BORROW, and the cap type must be in the request's `borrow_scope` |
| `privileged_submit` (parent override) | ✓ | ✓ | | P1 | **Changed**: `controller::privileged_submit`, event-only, returns a privileged request |
| `subou_ops::TransferCapToSubOU` | | | ✓ | P1 | **Done**: `armature_proposals::subou_ops::execute_transfer_cap<T>` |
| `RevenuePolicy` (split-on-deposit) | | ✓ | | P2 | **Dropped**: not implemented |
| Mocked Smart Gate hooks | | ✓ | ✓ | P1 | **Dropped** |
| Mocked Smart SSU hooks | | | ✓ | P1 | **Dropped** |
| Walrus charter upload/read | ✓ | ✓ | | P1 | **Dropped**: the Charter holds a metadata URI (by convention IPFS) |
| Third-party DApp read queries | | | ✓ | P2 | Available through public reads (`ou::is_governance_member`, `governance::was_member_at`, registry reads); no demo DApp in the repo |

---

## Technical Risk Register

| Risk | Impact | Mitigation | Phase | Outcome |
|---|---|---|---|---|
| PTB gas limits for complex SubOU operations (atomic reclaim = 4 operations) | Operations may exceed gas limit | Gas profiling on testnet; may need to split operations | P1 | No gas report was produced. The cost that materialised was storage: an OU root rewritten by every transaction and undeleted audit objects, fixed by ARMATURE-9 … ARMATURE-13. Per-call bounds cap work: `TransferAssets` ≤ 50 assets, batch member ops ≤ 100, composites ≤ 16 steps |
| Walrus blob availability for charter content | Charter content inaccessible if blob expires | `RenewCharterStorage` proposal type; off-chain archival | P1 | Moot: there is no Walrus charter |
| Mocked gate/SSU contracts diverge from real EVE world contracts | Demo integration not representative | Document all assumptions; use interface patterns that adapt to real contracts | P1 | Moot: mocks dropped; `armature_world_bridge` builds against the real EVE `world` package at a pinned revision |
| Indexer event schema drift | Indexer breaks if event types change | Stabilize event types in #3 before starting #4 | P2 | Occurred: ARMATURE-9 … ROAD-39 changed event and config shapes; consumer updates are ARMATURE-16 |
| Extension package upgrade keys | Whoever holds a package's `UpgradeCap` can use every bit and scope OUs granted that package's types | Keep the cap in an OU vault behind `ProposeUpgrade`, or publish immutable per release | Post-hackathon | Recommendation in `docs/package-boundaries.md` |
| Type placement is a one-way door | Moving a type to another package creates a new type that every OU must re-enable and the indexer must re-key | Settle placement before the ROAD-39 fresh publish | Post-hackathon | Placement rule in `docs/package-boundaries.md` |
| Atomic path skips the observation and freeze window | A delay-0 type can be submitted, passed and executed in one PTB when the quorum lets one YES pass | Configure governance-sensitive types with `execution_delay_ms > 0` | Post-hackathon | Recommendation only; ADR still Proposed |
| Freeze outlasting an execution window | With the default 7-day freeze and 7-day expiry, freezing a type right after a proposal passes can run out that proposal's window | — | Post-hackathon | Accepted behaviour |

---

## Architecture Diagram

Current layout (the March plan had `armature_framework` with `treasury.move` and `voting/board.move`, `armature_proposals` with `admin`, `board`, `subou` and `charter_ops` modules, and a `mock_assemblies` package):

```
┌───────────────────────────────────────────────────────────────────┐
│  armature_framework  (armature::)  — the kernel                    │
│  "never touched after a release"                                   │
│                                                                    │
│  ou · governance · proposal · board_voting · controller           │
│  external_execution · composite · permissions · treasury_vault     │
│  capability_vault · charter · emergency · tribe · encrypted_entry  │
│  spend_guard · utils                                               │
│                                                                    │
│  types/     framework payload types (board, type admin, bypass,    │
│             freeze governance, lifecycle, CompositePayload)        │
│  handlers/  admin_ops · board_ops · member_ops · lifecycle_ops ·   │
│             freeze_ops                                             │
└───────────────────────────────────────────────────────────────────┘
          ▲ depends on                           ▲ depends on
┌─────────┴──────────────────────────┐ ┌────────┴──────────────────────┐
│ armature_proposals                  │ │ armature_world_bridge          │
│ (armature_proposals::)              │ │ (armature_world_bridge::)      │
│ first-party extension: asset ops    │ │ first-party extension: EVE     │
│ treasury/ · currency/ · subou/ ·   │ │ autojoin/ (autojoin_ops,       │
│ upgrade/ · type_permissions         │ │ configure_autojoin,            │
│                                     │ │ tribe_allowlist)               │
└─────────────────────────────────────┘ └────────────────────────────────┘

┌───────────────────────────────────────────────────────────────────┐
│  armature_external_type_tests — never published; plays a           │
│  third-party integrator (Rebalance<T>); the template for new types │
└───────────────────────────────────────────────────────────────────┘

┌───────────────────────────────────────────────────────────────────┐
│  External dependencies                                             │
│  Sui framework + Move stdlib (Clock, dynamic fields,               │
│  std::internal::Permit) · EVE Frontier `world`                     │
│  (world bridge only) · Seal key servers (off-chain, seal_approve)  │
└───────────────────────────────────────────────────────────────────┘
```

Which package a type belongs in is decided by the placement rule in `docs/package-boundaries.md`: the framework holds every type that changes who may do what; extension packages hold types that move or use assets inside an authority graph already set.

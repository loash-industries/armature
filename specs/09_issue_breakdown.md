# 09 — Issue Breakdown

> **Implementation repo:** [`loash-industries/armature`](https://github.com/loash-industries/armature)
>
> **Annotated history (updated 2026-09-26).** This is the original March 2026 hackathon breakdown, kept for history. Every issue now carries an **Outcome** line: **Done**, **Done differently**, **Dropped** or **Open**, with a note on how it landed. Design statements that contradicted the current code (APIs, object shapes, floors, statuses, package placement) are corrected in place. PR numbers come from the git history; the tracker numbers of the NEW issues are not recorded here. The UI, Rust indexer and API from P2–P3 were built in this repo and removed from it in #148 (2026-05-26); the indexer now lives in the separate `armature-indexer` repo. For the current design see `03_core_spec.md`, `docs/package-boundaries.md`, `docs/proposal-types.md` and `packages/armature_framework/internal_workings.md`. For what came after the hackathon see `07_roadmap.md`.
>
> The plan decomposed the hackathon project into trackable issues. Existing armature issues (#2–#10) served as **parent epics**, with sub-issues filed underneath using `Part of #N` references. New issues (marked **NEW**) were to be created on the armature repo.
>
> Each sub-issue was meant to be:
> - **Self-contained** — one PR, mergeable independently (within dependency ordering)
> - **Testable** — explicit acceptance criteria
> - **Small enough** — completable in 1–3 focused sessions

---

## Issue Map

### Existing Armature Issues

| # | Title | Phase | Outcome | Sub-issues |
|---|-------|-------|---------|------------|
| #3 | Create the `armature_framework` package | P0 | **Done differently**: merged 2026-03-11/12 (PRs #22, #25, #26, #29, #31, #33); the package has since become the kernel that also holds every type that changes who may do what, with its handlers | #13 → #18 |
| #2 | Create the `armature_proposals` package | P0/P1 | **Done differently**: built in March (PRs #12, #20, #24, #30, #66, #72, #73, #78, #82, #84); admin, board, freeze-governance and lifecycle types later moved into the framework; charter ops never built | C-07 → C-13 |
| #4 | Scaffold the indexer | P2 | **Done** (PRs #122, #124), then moved to the `armature-indexer` repo (#148) | I-01 → I-02 |
| #5 | Scaffold the UI | P3 | **Done** (PR #65; shadcn/ui refactor #128); removed from this repo in #148 | F-01 |
| #6 | React Flow DAO hierarchy | P3 | **Done** (PR #87) | F-08 |
| #7 | Proposal security dashboard | P3 | **Done** (PR #83) | F-05.b |
| #8 | Dynamic proposal form UI component | P3 | **Done differently** (PR #85, wired in #107): no AmendCharter or Walrus parts, since the contracts never had them | F-06, F-07 |
| #10 | ProposalConfig defaults table | P3 | **Done differently**: warning thresholds in the governance config page (PR #83); defaults and floors are now enforced on-chain | (data task → feeds #7, #8) |

### New Issues (planned)

| ID | Title | Phase | Parent / Dep | Outcome |
|----|-------|-------|-------------|---------|
| **NEW** | Mocked smart assemblies package | P1 | Depends on #3 | **Dropped** |
| **NEW** | Integration test suite (3 demo flows) | P1 | Depends on #2, #3, mocks | **Done differently**: Move scenario tests, not the three demo flows |
| **NEW** | Testnet deployment + demo rehearsals | P2 | Depends on integration tests | **Done differently**: published 2026-03-27 without mocks; Flows B/C dropped |
| **NEW** | Gas profiling report | P2 | Depends on testnet deployment | **Dropped** |
| **NEW** | DAO Dashboard + navigation shell | P3 | Depends on #5 | **Done** (PRs #65, #67) |
| **NEW** | Proposal list + detail + voting UI | P3 | Depends on dashboard | **Done** (PRs #98, #110) |
| **NEW** | Treasury + capability vault pages | P3 | Depends on dashboard | **Done** (PRs #67, #89) |
| **NEW** | Board + charter pages | P3 | Depends on dashboard | **Done differently** (PR #67): no Walrus content to render |
| **NEW** | Payload summary renderers | P3 | Depends on proposal detail | **Done differently** (PR #85): no AmendCharter diff or Walrus links |
| **NEW** | CreateSubDAO wizard | P3 | Depends on #8 | **Done differently** (PR #85): charter step without Walrus |
| **NEW** | SubDAO controller actions | P3 | Depends on proposal detail | **Done** (PR #87) |
| **NEW** | Demo script + rehearsal | P4 | Depends on all P3 | **Done**: demo video |
| **NEW** | Error UX polish | P4 | Depends on all P3 | **Open** when the UI left this repo |
| **NEW** | Documentation + submission | P4 | Depends on all | **Done** |

---

## P0 — Core Contracts

### Armature #3 — `armature_framework` package

> Create the framework package containing core DAO types, governance, proposal lifecycle, treasury, capability vault, emergency freeze, and board voting.

**Outcome: Done differently.** All six sub-issues merged on 2026-03-11/12. The package has since also taken the framework payload types (`sources/types/`) and their handlers (`sources/handlers/`), the permission model, composites, bypass execution, tribes and encrypted entries (see `docs/package-boundaries.md`).

#### #13: DAO object, GovernanceConfig, and `dao::create` — Part of #3

**Outcome: Done differently** (PR #22). Governance became a table-backed roster (ARMATURE-13) and the proposal-type maps became per-type slots (ARMATURE-9).

**Module:** `dao.move`, `governance.move`

**Scope** (corrected to the current code):
- `DAO` struct: `status`, `governance`, the four companion IDs, `execution_paused`, `controller_cap_id`, `controller_paused`, `encrypt_epoch`, `entries` (see `03_core_spec.md` §1.1)
- `GovernanceConfig` is a struct, not an enum: `members: Table<address, Member>`, `member_count`, `roster_version`. Board is the only model; the plan's enum and its unused Direct/Weighted variants were removed in ARMATURE-13. It is initialised from `GovernanceTypeInit::InitBoard { initial_members }`
- `DAOStatus` enum (`Active`, `Migrating { successor_dao_id }`)
- `dao::create(&GovernanceTypeInit, name, metadata_uri, ctx): ID` creates DAO + TreasuryVault + CapabilityVault + Charter + EmergencyFreeze as shared objects and transfers the `FreezeAdminCap` to the creator
- `DAOCreated` and `DAOBoardInitialized` events
- Default enabled proposal types are seeded as dynamic-field slots (`TypeSlot { name: TypeName }` → `ProposalType { display_key, config, last_executed_ms }`): 14 on a DAO, 12 on a SubDAO (no bypass meta-types). `TypeSlotAdded` fires for each

**Acceptance:**
- `test_create_dao` — creates DAO, asserts all companion objects exist, governance = Board with the initial members, `FreezeAdminCap` held by the creator
- `test_dao_created_event` — event emitted with correct fields
- `test_default_proposal_types` — enabled types match spec

**Blocks:** Everything else in #3 and #2

---

#### #14: TreasuryVault — deposit, withdraw, balance, claim — Part of #3

**Outcome: Done** (PR #25). The module is `treasury_vault.move`. Deposit/withdraw events (#121) and multicoin balances (#150) were added, and since ROAD-39 `withdraw` checks the `TREASURY_WITHDRAW` bit.

**Module:** `treasury.move` → `treasury_vault.move`

**Scope:**
- `TreasuryVault` struct with dynamic field storage (coin type name → `Balance<T>`; multicoin collections as dynamic object fields)
- `deposit<T>(vault, coin, ctx)` (permissionless; a zero-value coin is a no-op), `withdraw<T, P>(vault, amount, &ExecutionRequest<P>, ctx)`, `claim_coin<T>(vault, Receiving<Coin<T>>, ctx)`, `balance<T>`. `withdraw` is `public`, not `public(friend)`: it needs a request of this DAO carrying `TREASURY_WITHDRAW`
- Zero-balance cleanup, registry sync; events `CoinDeposited`, `CoinWithdrawn`, `CoinClaimed` (plus `MultiCoinDeposited`, `MultiCoinWithdrawn`)

**Acceptance:** Withdraw auth, registry sync, zero-balance cleanup, deposit, insufficient balance, claim, balance queries (16 tests)

**Depends on:** #13

---

#### #15: CapabilityVault — store, borrow, loan, extract — Part of #3

**Outcome: Done** (PR #26). Since ROAD-39 every operation needs a permission bit, and borrows also need the cap type in the request's borrow scope.

**Module:** `capability_vault.move`

**Scope:**
- `CapabilityVault` struct with dynamic object fields
- `store_cap_init` (`public(package)`, creation only) / `store_cap` (VAULT_STORE); `borrow_cap` / `borrow_cap_mut` (VAULT_BORROW, cap type in `borrow_scope`); `loan_cap` / `return_cap` (same gate; hot potato `CapLoan { cap_id, vault_id }`, and `return_cap` checks both IDs); `extract_cap` (VAULT_EXTRACT); `privileged_extract` (controller reclaim: needs a `&SubDAOControl` whose `subdao_id` is the vault's DAO, and nothing else is compared)
- `SubDAOControl { id, subdao_id }` lives here, with `create_subdao_control` / `destroy_subdao_control` (VAULT_EXTRACT); `receive_cap` / `receive_cap_authorized` for cross-DAO moves; `borrow_external_cap` (ungated) for bypass caps
- `contains` / `ids_for_type` queries, registry tracking

**Acceptance:** Access control, registry sync, loan semantics, privileged extract, contains, ID queries (20 tests)

**Depends on:** #13

---

#### #16: Proposal lifecycle — create, vote, expire, execute — Part of #3

**Outcome: Done differently** (PR #29). Reworked since: handlers receive an `ExecutionTicket<P>` (#149), proposals are deleted on execution and expiry (ARMATURE-12), voters are fixed by roster version (ARMATURE-13/14), and single-PTB paths create no `Proposal` at all (ARMATURE-11).

**Module:** `proposal.move` (package-internal core), with the public entry points in `board_voting.move`

**Scope** (corrected):
- `Proposal<P>` struct (`snapshot_version`, `total_snapshot_weight`, snapshotted `config`, `status`) and `ProposalConfig` with validation (`quorum ∈ [1, 10000]`, `approval_threshold ∈ [5000, 10000]`, `expiry_ms ≥ 1 h`), plus `composable_allowed`, `permissions` and `borrow_scope`
- `proposal::create` and `record_vote` are `public(package)`. The public path is `board_voting::submit_proposal<P>` (no `type_key` argument; `P` selects the slot) → `board_voting::vote(proposal, &dao, approve, clock, ctx)` → `board_voting::ticket_from_vote(dao, proposal /* by value */, freeze, clock, ctx)`. The last deletes the proposal and returns an `ExecutionTicket<P>` wrapping the `ExecutionRequest<P>` hot potato, which the type's handler closes with `discharge(permit)`
- `try_expire` is replaced by `proposal::delete_expired_proposal`: anyone deletes an Active proposal after `created_at + expiry_ms`, or a Passed one after `passed_at + execution_delay_ms + expiry_ms`. Deadlines saturate at `u64::MAX`
- Status transitions: `Active → Passed` is the only stored one. There is no `Executed` or `Expired` status: the `ProposalExecuted` / `ProposalExpired` events and the object's deletion record them. Votes after `created_at + expiry_ms` abort (`EVotingClosed`), and execution after the window closes aborts (`EExecutionWindowClosed`)
- Snapshot immutability: `snapshot_version`, `total_snapshot_weight` and `config` are write-once. Retry semantics: a handler abort reverts the whole PTB, deletion included, so the proposal stays Passed while its window is open
- Events: `ProposalCreated` (now with `metadata_ipfs`), `ProposalPayloadCreated`, `VoteCast`, `ProposalPassed`, `ProposalExecuted`, `ProposalExpired`

**Acceptance:** Hot potato enforcement, status monotonicity, snapshot immutability, executor eligibility, retry semantics, double vote, NO votes, delays, cooldown (25 tests)

**Depends on:** #13, #14, #15

---

#### #17: Board voting module — Part of #3

**Outcome: Done differently** (PR #31). The module is `board_voting.move`, not `voting/board.move`, and holds the submit, vote and execute entry points; the pass rule lives in `ProposalConfig::passes`.

**Module:** `voting/board.move` → `board_voting.move`

**Scope** (corrected):
- Public `board_voting::vote` wraps the package-internal `proposal::record_vote`
- Vote counting: `yes + no > 0` AND `(yes + no) * 10000 >= quorum * total_snapshot_weight` AND `yes * 10000 >= approval_threshold * (yes + no)`, cross-multiplied in u128 (`utils::gte_bps`) with no division. `total_snapshot_weight` is the member count when the proposal was created. One member, one vote
- Eligibility: the proposer and the vote-path executor must be current members. A voter must have been a member at the proposal's `snapshot_version` (`governance::was_member_at`), so members added later cannot vote and members removed later still can

**Acceptance:** Single member, 2/3 majority, NO majority, exact threshold, abstention, large board, quorum calculations (10 tests)

**Depends on:** #16

---

#### #18: EmergencyFreeze — freeze, unfreeze, auto-expiry — Part of #3

**Outcome: Done differently** (PR #33). Freezes are keyed by the payload's canonical `TypeName` (ARMATURE-15), and the governance side is gated by the `FREEZE` bit (ROAD-39).

**Module:** `emergency.move`

**Scope** (corrected):
- `EmergencyFreeze { frozen_types: VecMap<TypeName, u64>, max_freeze_duration_ms, freeze_exempt_types }` and `FreezeAdminCap`. `dao::create` transfers the cap to the creator (wallet-owned); a SubDAO made by `CreateSubDAO` has its cap stored in the parent's vault
- `freeze_type<P>(freeze, &cap, clock)`: the cap holder freezes `P` directly for `max_freeze_duration_ms` (default 7 days); `unfreeze_type<P>(freeze, &cap)`
- `TransferFreezeAdmin` and `UnfreezeProposalType` are mandatory exemptions, matched by the framework's own types: they can never be frozen (`EProtectedType`) or removed from the exempt set (`EMandatoryExemptType`)
- Auto-expiry: `is_frozen` check compares expiry against clock
- Governance side (`FREEZE` bit): `governance_unfreeze_type`, `update_freeze_duration`, `unfreeze_all`, `add_freeze_exempt_type` / `remove_freeze_exempt_type`
- Events: `TypeFrozen`, `TypeUnfrozen`, `FreezeExemptTypeAdded`, `FreezeExemptTypeRemoved`, all carrying `type_name`

**Acceptance:** Freeze blocks execution, protected types, auto-expiry, cap unfreeze, governance unfreeze, events (10 tests)

**Depends on:** #16

---

### Armature #2 — `armature_proposals` package

> Create the proposals package with all admin, treasury, board, SubDAO, and charter operations.

**Outcome: Done differently.** Built in March. The package is now a first-party *extension* holding asset operations only (treasury, currency, SubDAO control, upgrades, plus `type_permissions`), with no special treatment from the framework. Admin, board, member, freeze-governance and lifecycle types moved into the framework (types in ARMATURE-9, handlers in ROAD-39) because the framework names them: fixed bits, the undisableable and SubDAO-blocked sets, default slots. See `docs/package-boundaries.md`. Charter operations were never built.

#### C-07: Admin proposals (6 types) — Part of #2

**Outcome: Done differently.** All six exist as framework types (`armature_framework/sources/types/`), handled by `armature::admin_ops` (UpdateMetadata, EnableProposalType, DisableProposalType, UpdateProposalConfig) and `armature::freeze_ops` (TransferFreezeAdmin, UnfreezeProposalType). Floors are higher than planned and are enforced in `dao`.

**Module:** `proposals/admin.move` → framework `types/` + `handlers/admin_ops.move`, `handlers/freeze_ops.move`

**Scope** (corrected):
- `UpdateProposalConfig`: its own config is always held to 80% (`dao::assert_config_floors`), not only when self-referential. The submission wrapper `admin_ops::propose_update_proposal_config` keeps the old self-targeting check (`EFloorNotMet`). Every config it stores must meet the target type's floor and permission floor, and it cannot change a framework type's fixed bits (`EFixedPermissions`)
- `EnableProposalType`: 80% floor (the plan's 66% was raised in ROAD-39), checked at submission (`board_voting::EFloorNotMet`) and on every stored config; the payload pins the Move type (`type_name`, `ETypeMismatch`); SubDAO blocklist
- `DisableProposalType`: cannot disable the undisableable types EnableProposalType, DisableProposalType, EnableBypassType, DisableBypassType, TransferFreezeAdmin, UnfreezeProposalType (`admin_ops::EUndisableableType`)
- `UpdateMetadata` (display key "CharterUpdate"); `TransferFreezeAdmin` (unfreezes all, then transfers the cap) and `UnfreezeProposalType`, both permanently freeze-exempt
- Permission bits (ROAD-39): all six hold fixed bits (TYPE_ADMIN, METADATA or FREEZE)

**Acceptance:** All 6 types with happy path + negative tests (16 tests). All governance invariants (18 tests).

**Depends on:** #16, #17, #18

---

#### C-08: Treasury proposals — SendCoin, SendCoinToDAO — Part of #2

**Outcome: Done.** In `armature_proposals::treasury_ops`; `SendSmallPayment` (#84) and the batch multicoin sends (#150) joined them.

**Module:** `proposals/treasury_ops.move` → `armature_proposals/sources/treasury/treasury_ops.move`

**Scope:**
- `SendCoin<T>` — `execute_send_coin<T>(vault, ticket, ctx)`: withdraw + transfer to the payload's address
- `SendCoinToDAO<T>` — `execute_send_coin_to_dao<T>(src, target, ticket, ctx)`: withdraw + deposit into the target DAO's treasury
- Both consume an `ExecutionTicket<P>` (not a bare `ExecutionRequest`) and close it with `discharge(permit)`. The types must be enabled with `TREASURY_WITHDRAW` (`type_permissions::treasury_spend()`), which requires an 80% config

**Acceptance:** Transfer, balance reduction, insufficient balance abort, generic coin types, cross-DAO deposit (7 tests)

**Depends on:** #14, #16, #17

---

#### C-09: Board proposals — SetBoard — Part of #2

**Outcome: Done differently.** `SetBoard` is a framework type, and since ARMATURE-13 it is a diff, because the roster table cannot be enumerated on-chain. Single and batch add/remove types were added.

**Module:** `proposals/board_ops.move` → framework `handlers/board_ops.move` (plus `handlers/member_ops.move`)

**Scope** (corrected):
- `SetBoard { to_add, to_remove }` applies the diff as one roster change (`roster_version` + 1), not a full-slate replacement. It emits `BoardUpdated { dao_id, added, removed }` and aborts `ENoBoardChange` if both lists are empty
- Removed members lose proposing and vote-path execution immediately, and added members gain them immediately. Voting follows each proposal's `snapshot_version`: removed members can still vote on proposals created before their removal, and added members cannot
- Empty board aborts (`EEmptyBoard`). "Governance type preserved" no longer applies, since Board is the only model
- Added later: `AddMember`, `RemoveMember` (#134), `BatchAddMembers` (#142; ≤ 100, skips existing members), `BatchRemoveMembers` (#158; atomic). Any member removal rotates `encrypt_epoch`

**Acceptance:** Replace all, old member blocked, new member can propose, seat count update, empty board abort (6 tests)

**Depends on:** #16, #17

---

#### C-10: SubDAOControl struct and controller machinery — Part of #2

**Outcome: Done differently** (PRs #72, #82). The machinery is in the framework. Blocklist enforcement exists; "acyclic graph" and "single controller" were never implemented as checks.

**Module:** `dao.move` (extend), `capability_vault.move` (extend)

**Scope** (corrected):
- `SubDAOControl { id, subdao_id }` in `capability_vault.move`; on the DAO, `controller_cap_id: Option<ID>` (set by `dao::share_subdao`, cleared by `clear_controller` at spin-out) and `controller_paused`
- `privileged_extract(vault, cap_id, &SubDAOControl)` checks only that `control.subdao_id` is the vault's DAO
- Blocklist: a DAO with `controller_cap_id` set cannot enable SpawnDAO, SpinOutSubDAO, CreateSubDAO, EnableBypassType or DisableBypassType. This is checked in the `admin_ops` and `external_execution` handlers and on creation-time overrides
- Acyclicity and single controller: not enforced. The framework's creation paths mint one control per new SubDAO, but `create_subdao_control` (VAULT_EXTRACT) accepts any `subdao_id`, and `privileged_submit` / `privileged_extract` compare only `control.subdao_id` with the target. Neither checks the target's `controller_cap_id`

**Acceptance:** All SubDAO invariants (subset covering struct/machinery)

**Depends on:** #13, #15

---

#### C-11: SubDAO proposals — 6 types — Part of #2

**Outcome: Done differently.** `CreateSubDAO` and `SpinOutSubDAO` (with `SpawnDAO` and `TransferAssets`) are framework types handled by `armature::lifecycle_ops`. The cap-delegation and pause types stay in `armature_proposals::subdao_ops` and are proposed on the controller DAO. Event names differ from the plan.

**Module:** `proposals/subdao_ops.move` → framework `handlers/lifecycle_ops.move` + `armature_proposals/sources/subdao/subdao_ops.move`

**Scope** (corrected):
- `CreateSubDAO { name, initial_board, metadata_uri }` creates the child DAO with the default SubDAO slots (no bypass meta-types; the enable handlers refuse blocked types) and stores the `SubDAOControl` and the child's `FreezeAdminCap` in the parent vault. The payload carries no funding (fund with `SendCoinToDAO`). Event `SubDAOCreated { controller_dao_id, subdao_id, control_cap_id }`. Fixed bits VAULT_STORE + VAULT_EXTRACT, 80% floor
- `SpinOutSubDAO` loans the control, runs `clear_controller` on the SubDAO through `privileged_submit`, re-enables SpawnDAO / SpinOutSubDAO / CreateSubDAO with the payload's configs, moves the `FreezeAdminCap` into the SubDAO's vault and destroys the control. Irreversible. Event `SubDAOSpunOut`
- `TransferCapToSubDAO`, `ReclaimCapFromSubDAO` → events `CapTransferredToSubDAO`, `CapReclaimedFromSubDAO` (not `CapabilityTransferred` / `CapabilityReclaimed`). Reclaim is loan control → `privileged_extract` → `store_cap` in one PTB
- `PauseSubDAOExecution`, `UnpauseSubDAOExecution` are voted on the controller DAO (VAULT_BORROW scoped to `SubDAOControl`); the SubDAO side runs `set_controller_paused` on a privileged request. Events `SubDAOExecutionPaused` / `SubDAOExecutionUnpaused`
- Added later: `ControllerBatchAddMembers` / `ControllerBatchRemoveMembers` (#158)

**Acceptance:** CreateSubDAO (4), SpinOut (2), TransferCap (1), ReclaimCap (1), Pause (2), atomic reclaim (1) — 22 tests

**Depends on:** C-10, #16, #17, #14, #15

---

#### C-12: `privileged_submit` — controller bypass — Part of #2

**Outcome: Done differently** (PR #73). It lives in `controller.move` and creates no proposal object.

**Module:** `proposal.move` (extend) → `controller.move`

**Scope** (corrected):
- `controller::privileged_submit<P: store + drop>(control, subdao, type_key, metadata_ipfs, payload, ctx): ExecutionRequest<P>` does not create a Passed proposal. No `Proposal` object exists (ARMATURE-11); `ProposalCreated`, `ProposalPayloadCreated` and `ProposalExecuted` are the record. It takes no clock, and checks only `control.subdao_id == subdao.id` (`EControlMismatch`) and that the SubDAO is Active
- The returned request is privileged (0 bits, empty scope) and passes every permission check on that SubDAO; `set_controller_paused` and `clear_controller` accept only privileged requests. It is closed with `controller::privileged_consume(req, &control)`
- Two simultaneous hot potatoes: the controller DAO's own ticket (which needs VAULT_BORROW scoped to `SubDAOControl` to loan the control) and the SubDAO's privileged request
- CapLoan for SubDAOControl must be returned in same PTB
- Pause interaction: `privileged_submit` ignores `controller_paused`, so the controller can always unpause

**Acceptance:** 7 tests — happy path, unauthorized abort, wrong SubDAO, interaction with pause

**Depends on:** C-10, C-11, #16

---

#### C-13: Charter object and charter proposals — Part of #2

**Outcome: Dropped.** No Walrus integration, amendment records or charter proposals were built. The Charter is `{ id, dao_id, name, metadata_uri }` (since #159; during the hackathon it held a name, description and image URL), and its only mutation is `charter::update_metadata` (METADATA bit), reached through `UpdateMetadata`. The Walrus design remains planned in `05_charter.md`.

**Module (planned):** `charter.move`, `proposals/charter_ops.move`

**Scope (planned):**
- `Charter` struct, `AmendmentRecord`, `AmendCharter` proposal, `RenewCharterStorage` proposal
- Version monotonicity, amendment history, renewal distinction
- `CharterAmended` event

**Acceptance (planned):** Charter tests (10) + charter ops tests (10)

**Depends on:** #13, #16, #17

---

### Armature #10 — ProposalConfig defaults table

> Compile the initial ProposalConfig settings for all 18 proposal types, considering the security spec. Integrate into #7.

**Outcome: Done differently.** The UI's governance config page shipped warning thresholds (PR #83). The defaults and floors are now code, enforced on every stored config. Seeded types start at quorum 50%, approval 50% raised to the type's floors, 7-day expiry, no delay and no cooldown (`dao::config_for_type`), and `docs/proposal-types.md` lists every type's bits and floor.

**Scope** (corrected):
- Table of default quorum, threshold, execution delay, cooldown, and expiry per proposal type
- Invariants (current): EnableProposalType, UpdateProposalConfig and EnableBypassType ≥ 80%; any config holding TYPE_ADMIN, MIGRATE, TREASURY_WITHDRAW, VAULT_BORROW or VAULT_EXTRACT ≥ 80% (`dao::permission_floor`). The plan's 66% EnableProposalType floor no longer applies
- Warning thresholds for the security dashboard (#7)
- Recommended vs minimum values with security rationale. `proposals/ADR_GOVERNANCE_TYPE_DELAY_DEFAULTS.md` (status Proposed) recommends non-zero delays for governance-sensitive types; today's defaults have none

**Acceptance:**
- Markdown table in docs with all 18 types (there are now about 40 types across three packages)
- JSON/TypeScript constant exported for frontend consumption
- Values validated against invariant constraints

**Depends on:** C-07 (admin proposal validation rules defined)

---

## P1 — Composition (continued)

### NEW — Mocked smart assemblies package

**Outcome: Dropped.** Never built. EVE world integration went through `armature_world_bridge` instead (autojoin through the bypass path, #144), which builds against the real EVE `world` package.

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

**Outcome: Done differently.** There is no `integration_flows.move`, and the gate/SSU and charter-amendment flows were never built. Scenario coverage lives in `armature_proposals/tests/`: `lifecycle_tests.move` (a small startup; an enterprise with two SubDAOs, a freeze, a controller board change and cross-DAO payments), `migration_tests.move` (successor spawn and origin destroy, SubDAO spin-out, controller board change through `privileged_submit`, `TransferAssets`) and `subdao_ops_tests.move`. `armature_external_type_tests` runs a third-party type through every execution path.

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

**Outcome: Done differently.** `armature_framework` (10 modules at the time) and `armature_proposals` were published to testnet on 2026-03-27 (`packages/*/deploy.txt`); there was no `mock_assemblies` to publish. The demo was recorded (video linked from `README.md`), but per-step object IDs, digests and gas costs were not committed. The later `testnet_wip` (June) and `testnet_stillness` (2026-06-25) publishes added `armature_world_bridge`.

**Scope:**
- Publish `armature_framework`, `armature_proposals`, `mock_assemblies` to testnet
- Execute Flow A step-by-step using CLI (`sui client call`)
- Document exact object IDs, tx digests, gas costs per step

**Acceptance:** Flow A completes end-to-end on testnet. Gas costs documented.

**Depends on:** Integration tests

---

### NEW — Testnet Flow B + Flow C rehearsal

**Outcome: Dropped.** Both flows needed the mocked gate/SSU package, and Flow B also needed revenue sharing and charter amendments; none were built.

**Scope:**
- Execute Flow B and Flow C on testnet using CLI
- Validate mocked gate/SSU interactions, atomic reclaim gas limits
- Document object IDs, tx digests, gas costs

**Acceptance:** Flow B and C complete on testnet. Atomic reclaim fits within gas limit.

**Depends on:** Testnet deployment

---

### NEW — Error handling + edge cases on testnet

**Outcome: Done differently.** Manual QA scenarios live in `testing/e2e/` (#109), including `12-negative-and-edge-cases.md`. Abort codes are defined per module in the source; no frontend message table was committed. Since ARMATURE-11/12, executed and expired proposals exist only as events, and expiry is `proposal::delete_expired_proposal`, which anyone may call.

**Scope:**
- Test expired proposals, insufficient balance, unauthorized actions, freeze/unfreeze cycles on testnet
- Verify event emission queryable via `suix_queryEvents`
- Document abort codes for frontend error messages

**Acceptance:** All error paths produce correct abort codes. Events queryable via RPC.

**Depends on:** Testnet deployment

---

### NEW — Gas profiling report

**Outcome: Dropped.** No report was committed. Later gas analysis of a live testnet DAO found the real cost in storage rather than PTB limits, and drove ARMATURE-9 … ARMATURE-12 (see `07_roadmap.md`).

**Scope:**
- Table: operation → gas budget → actual gas used → margin
- Identify PTBs approaching gas limit, recommend `gas_budget` per transaction type

**Acceptance:** No operations exceed 80% of gas limit. Markdown table committed.

**Depends on:** All testnet rehearsals

---

### Armature #4 — Scaffold the indexer

> Two crates: indexer (custom indexing framework from SUI) + schema migration (DB init/updates). Depends on event types from #2 and #3.

**Outcome: Done**, then moved. Built in this repo (PR #122: event pipelines and REST API; PR #124: full event coverage, vote ledger, freeze state, pagination) and removed from it in #148 (2026-05-26). It now lives in the separate `armature-indexer` repo, which must follow the September 2026 event changes (ARMATURE-16).

#### I-01: Indexer schema + migration crate — Part of #4

**Outcome: Done** (PRs #122, #124; Diesel migrations). There are no charter-amendment events to store (charter changes emit `admin_ops::MetadataUpdated`), and since ARMATURE-12 a proposal's executed or expired state comes only from events.

**Scope:**
- PostgreSQL schema for: DAOs, proposals, votes, treasury transactions, SubDAO relationships, charter amendments, freeze events
- Migration framework (e.g., `sqlx` migrations or `diesel`)
- Tables mirror on-chain event structure

**Acceptance:** `cargo test` passes. Schema can be initialized from scratch.

**Depends on:** #2, #3 (event types finalized)

---

#### I-02: Indexer crate — event consumer — Part of #4

**Outcome: Done** (PRs #122, #124). Four of the planned event names never existed: `CharterAmended` (charter changes emit `MetadataUpdated`), `CapabilityTransferred` / `CapabilityReclaimed` (actual: `CapTransferredToSubDAO` / `CapReclaimedFromSubDAO`) and `BoardReplaced` (actual: `BoardUpdated { dao_id, added, removed }`). Events added since include `ProposalPayloadCreated`, `DAOBoardInitialized`, `TypeSlotAdded` / `TypeSlotRemoved` / `TypeSlotConfigUpdated`, `CoinDeposited` / `CoinWithdrawn`, `FreezeExemptTypeAdded` / `Removed`, and the member, bypass, composite and currency events; `ProposalCreated` carries `metadata_ipfs`, and freeze events carry `type_name`. Single-PTB executions (atomic, bypass, controller) exist only as events.

**Scope:**
- SUI custom indexing framework integration
- Event handlers for the lifecycle events: `DAOCreated`, `ProposalCreated`, `VoteCast`, `ProposalPassed`, `ProposalExecuted`, `ProposalExpired`, `SubDAOCreated`, `SubDAOSpunOut`, `MetadataUpdated` (planned: `CharterAmended`), `CoinClaimed`, `TypeFrozen`, `TypeUnfrozen`, `CapTransferredToSubDAO` (planned: `CapabilityTransferred`), `CapReclaimedFromSubDAO` (planned: `CapabilityReclaimed`), `BoardUpdated` (planned: `BoardReplaced`)
- Cursor tracking for restart resilience

**Acceptance:** Indexer consumes events from testnet and populates DB. Can restart without data loss.

**Depends on:** I-01, testnet deployment

---

## P3 — Frontend

All P3 work was built in this repo's top-level `ui/` app during the hackathon and removed from this repo in #148 (2026-05-26); the hackathon UI specs it followed have since been removed from `specs/` too. The outcomes below describe the hackathon deliverable. Contract-facing statements are corrected to the current framework.

### Armature #5 — Scaffold the UI (assigned: blurpesec)

> `@mysten/dapp-kit` + `@tanstack/react-query` + `@tanstack/react-router` + Tailwind v4 + `@awar.dev/ui`. Vite SPA, Caddy-fronted static deployment.

#### F-01: Project scaffold + data layer + wallet — Part of #5

**Outcome: Done** (PR #65: React 19, Tailwind v4, Vite 6, `@awar.dev/ui` v2, dapp-kit, React Query, TanStack Router). `@awar.dev/ui` was later replaced by shadcn/ui (#128).

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

> `AppShell`, `DaoSidebar`, `SubDAOBreadcrumb`, `DaoDashboard` per the hackathon UI specs (overview and core pages; since removed).

**Outcome: Done** (PRs #65, #67).

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

> `ProposalsList`, `ProposalDetail`, `VotingPanel`, `CountdownTimer`, execution panel per the hackathon UI specs (proposal lifecycle and core pages; since removed).

**Outcome: Done** (PRs #98, #110). Against today's contracts: the only stored statuses are Active and Passed (executed and expired come from events, as the object is deleted); "execute" is `board_voting::ticket_from_vote` followed by the type's handler in one PTB; "expire" is `proposal::delete_expired_proposal`, which anyone may call; atomic and bypass executions never appear as objects.

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

> `TreasuryPage`, `CapVaultPage` per the hackathon UI specs (core pages; since removed).

**Outcome: Done** (PRs #67, #89).

**Scope:**
- `TreasuryPage` — `Table` with `TableSortHead` (coin balances), deposit `Collapsible` form (`Form`, `Select`, `NumberInput`), transaction history
- `CapVaultPage` — `Accordion` grouped by type, `Table` with `Badge` (loan status), `DropdownMenu` for cap actions, SubDAOControl section

**Acceptance:**
- Treasury shows coin types with formatted balances, can deposit from wallet
- Cap vault lists stored capabilities, SubDAOControl entries link to child DAOs

**Depends on:** Dashboard

---

### NEW — Board + charter pages

> `BoardPage`, `CharterPage` per the hackathon UI specs (core pages; since removed).

**Outcome: Done differently** (PR #67). The Charter holds a name and a metadata URI, so there is no Walrus markdown, integrity hash or amendment history to show; charter changes are `UpdateMetadata` proposals.

**Scope:**
- `BoardPage` — `Card` with `Table`, `Badge` ("You"), `Button` ("Propose Board Change")
- `CharterPage` — `Tabs` (Document / Integrity), `ScrollArea` for rendered markdown, SHA-256 integrity `Badge`, `Accordion` for amendment history (planned; depends on C-13, dropped)

**Acceptance:**
- Board page shows members, highlights connected wallet
- Charter renders markdown from Walrus, shows "Verified" badge, amendment history expandable (not possible without C-13)

**Depends on:** Dashboard

---

### Armature #7 — Proposal security dashboard

> Governance config page — enabled/disabled types, thresholds, delays, warning indicators.

#### F-05.b: Governance config + emergency freeze pages — Part of #7

**Outcome: Done** (PR #83; emergency page in #67). Against today's contracts: "Protected" means the six undisableable types and the two mandatory freeze exemptions. The `FreezeAdminCap` holder freezes directly with `emergency::freeze_type<P>`, not through a proposal. Unfreezing is by the cap or by FREEZE-bit proposals such as `UnfreezeProposalType`. Freezes apply per canonical `TypeName`, and configs now also carry permission bits and a borrow scope.

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

**Outcome: Done differently** (PR #85, wired to transactions in #107). There is no AmendCharter form, since the contracts have no such type: `CharterUpdateForm` builds `UpdateMetadata`, and nothing uploads to Walrus. Against today's contracts: `SetBoard` is an add/remove diff, configs carry permission bits and a borrow scope, and submission takes no `type_key`.

**Scope:**
- Type selector: `Dialog` → `Command` (`CommandInput`, `CommandGroup`, `CommandItem`) grouped by category
- `GenericProposalForm` — shared `Form` for 9 simple types using `Input`, `Select`, `AlertDialog` (SpinOut confirmation)
- Custom forms: `SendCoinForm` (`Select`, `NumberInput`), `SetBoardForm` (`Table` + `Input` rows, diff `Badge`), `EnableTypeForm` / `UpdateConfigForm` (`NumberInput unit="%"`), `AmendCharterForm` (`Tabs` + `Textarea`; not built), `TransferCapForm` / `ReclaimCapForm` (`Select` pickers)
- Transaction construction per type

**Acceptance:**
- Can create a proposal for each of the 17 types (excluding wizard)
- Form validation matches spec constraints
- Walrus upload works for AmendCharter (not possible without C-13)

**Depends on:** Proposal detail, treasury/vault data, charter data, #10

---

#### F-07: CreateSubDAO wizard — Part of #8

**Outcome: Done differently** (PR #85). The wizard's charter step collected name, description and image fields rather than a Walrus upload. Against today's contracts, the `CreateSubDAO` payload is `{ name, initial_board, metadata_uri }`. The SubDAO gets the default SubDAO slots; per-type configs and funding are not part of the proposal. Funding is a separate `SendCoinToDAO`, and per-type overrides exist only on the direct constructors (`dao::create_subdao_configured`, `tribe::create_tribe_configured`, `tribe::create_wired_subdao`).

**Scope:**
- `CreateSubDAOWizard` — 6-step wizard using `Tabs variant="solid"`:
  1. Identity (`Input` ×2)
  2. Board (`Table` + `Input` rows, `NumberInput`)
  3. Charter (`Textarea` + Walrus upload; built without Walrus)
  4. Proposal Types (`ScrollArea` → `Table` + `Checkbox` + `NumberInput`, blocklist `Tooltip`)
  5. Funding (`Select` + `NumberInput`, optional)
  6. Review (`Card` sections, `Table`, `Button`)
- Step validation, back button preserves state via react-hook-form

**Acceptance:**
- Wizard completes end-to-end, blocked types greyed out, protected types locked
- Walrus upload before submit (not possible without C-13), review step shows complete summary

**Depends on:** F-06

---

### Armature #6 — React Flow DAO hierarchy (blocked on #5)

> React Flow (`GraphCanvas` from `@awar.dev/ui`) visualization of SubDAO tree.

#### F-08: SubDAO list page + hierarchy graph + controller actions — Part of #6

**Outcome: Done** (PR #87: `SubDAOListPage`, `SubDAOGraph`, `ControllerActionsMenu`). The removed UI offered pause, unpause, cap transfer, cap reclaim and spin-out. There is no controller "Replace Board" type: controller board changes use `ControllerBatchAddMembers` / `ControllerBatchRemoveMembers` (#158).

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

> `PayloadSummary` — type-dispatched read-only renderers for all 18 proposal types per the hackathon UI specs (payload summaries; since removed).

**Outcome: Done differently** (PR #85). It rendered the hackathon-era types; there is no AmendCharter diff and there are no Walrus links, since neither exists on-chain. There are now about 40 types, and a payload is also available from the `ProposalPayloadCreated` event after the object is deleted.

**Scope:**
- Dispatch component rendering correct summary based on proposal type
- 18 renderers using `Table`, `Badge`, `Tooltip`, `HoverCard` for addresses/IDs
- Diff highlighting (SetBoard, UpdateProposalConfig, AmendCharter), amount formatting, duration formatting, bps → percentage

**Acceptance:**
- Every proposal type renders payload summary in `ProposalDetail`
- Diffs show green/red highlighting, amounts formatted, Walrus links work (not possible without C-13)

**Depends on:** Proposal detail

---

## P4 — Polish

### NEW — Demo script + rehearsal

**Outcome: Done.** The demo video is linked from `README.md` (2026-03-31).

**Scope:**
- Step-by-step narration for each demo flow (target: each under 5 minutes)
- Pre-created testnet state (DAOs, funded treasuries)
- Rehearsal run-through, fallback plan

**Acceptance:** Each flow completes under 5 minutes in the UI. Script covers narration + timing.

**Depends on:** All P3 issues

---

### NEW — Error UX polish

**Outcome: Open.** It was not finished before the UI left this repo: the removed UI's `sonner` toasts showed the raw error message, with no abort-code-to-message mapping.

**Scope:**
- Move abort code → human-readable messages (toast via `sonner`)
- Loading states (`Skeleton`, `Button disabled`), confirmation `AlertDialog`s
- Stale data `Badge variant="outline"`, all transaction paths have loading → success/error feedback

**Acceptance:** No raw error codes visible, every transaction path has feedback.

**Depends on:** All P3 issues

---

### NEW — Documentation + README

**Outcome: Done.** The README was rewritten with architecture and quick start on 2026-03-29, alongside `docs/local-dev.md` and the Makefile targets. The Typst whitepaper came in #113 and #126, with a v0.2 accuracy revision in #160. Since then `docs/package-boundaries.md` and `docs/proposal-types.md` document the extension model.

**Scope:**
- Project README: architecture overview, local setup, deployment instructions
- Contract deployment instructions (localnet + testnet)
- Frontend setup instructions, link to docs/ spec

**Acceptance:** A new developer can clone, build, and run locally.

**Depends on:** All prior issues

---

### NEW — Submission package

**Outcome: Done.** The testnet publish (2026-03-27) and demo video are in the repo. The hackathon submission itself is not recorded here.

**Scope:**
- Final testnet deployment with stable object IDs
- Demo video recording or live demo prep
- Hackathon submission form

**Acceptance:** Submission complete, demo ready, testnet stable.

**Depends on:** All prior issues

---

## Dependency Graph

> Historical plan. C-13 and the mock assemblies were never built; the Flow B/C rehearsals and the gas report were dropped; the UI and indexer left this repo in #148.

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

The plan's staffing view, kept as written:

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

As planned:

| Phase | Existing Issues | New Issues | Total |
|-------|----------------|------------|-------|
| P0/P1 Contracts | #2, #3 | Mocks, Integration | 4 epics, 15 sub-issues |
| P2 Demo + Indexer | #4 | Testnet deploy, flows, gas | 1 epic, 6 sub-issues |
| P3 Frontend | #5, #6, #7, #8, #10 | Dashboard, pages ×3, detail, summaries, wizard, controller | 5 epics, 11 sub-issues |
| P4 Polish | — | Demo, error UX, docs, submission | 4 issues |
| **Total** | **8 existing** | **~19 new** | **~27 issues** |

Outcomes across the 36 issue sections above (excluding the parent epics):

| Outcome | Count | Issues |
|---|---|---|
| **Done** | 14 | #14, #15, C-08, I-01, I-02, F-01, dashboard shell, proposal list/detail/voting, treasury + vault pages, F-05.b, F-08, demo script, documentation, submission |
| **Done differently** | 17 | #13, #16, #17, #18, C-07, C-09, C-10, C-11, C-12, #10, integration tests, testnet + Flow A, error handling on testnet, board + charter pages, F-06, F-07, payload summaries |
| **Dropped** | 4 | C-13 (charter/Walrus), mocked assemblies, Flow B + C rehearsal, gas profiling report |
| **Open** | 1 | Error UX polish |

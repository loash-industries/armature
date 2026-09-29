# 10 — Formal Verification Strategy

> **Tool**: [Asymptotic sui-prover](https://github.com/asymptotic-code/sui-prover) — standalone formal verification for Sui Move, backed by the Z3 SMT solver.

> **Status: plan, not implemented** (checked 2026-09-26 at commit `6ed2b77`). The repo has no prover specs (`#[spec(...)]` functions), no spec modules and no prover CI job. Today the properties listed here are enforced by the Move type system, the unit and scenario tests, and a CI gate check (§5). This document is the plan for adding proofs on top of those.

## 1. Why Formal Verification for OU Protocol

This protocol governs treasury funds, capability delegation, organizational hierarchy and, since ROAD-39, a per-type permission model that decides what each executed proposal may touch. A single arithmetic bug in quorum calculation, a missed permission check or a mis-scoped borrow could drain a treasury, hand a capability to the wrong type, or deadlock governance permanently.

**Testing proves the presence of correct behavior. Formal verification proves the absence of incorrect behavior.**

The invariants in `03_core_spec.md` §6 are covered by about 569 Move tests (framework 410, proposals 121, world bridge 20, external-type fixture 18) and by a CI check that every mutator is gated. Tests only cover enumerated scenarios. The prover checks specs against *all* possible inputs, catching edge cases no human would think to write tests for: integer boundary overflows, obscure abort paths, and subtle state-machine violations.

### High-Value Targets

| Module | Risk if Broken | Verification Priority |
|--------|---------------|----------------------|
| Permission model (`permissions`; floors and grant rules in `ou`; `proposal::assert_permitted` / `assert_may_borrow`; bypass-safe bits in `external_execution`) | A request reaches a mutator its type was never granted; a no-vote path changes the authority graph | **Critical** |
| TreasuryVault | Fund loss / phantom balances | **Critical** |
| Governance arithmetic (pass rule, config bounds, floors) | Broken quorum → unauthorized execution | **Critical** |
| CapabilityVault + CapLoan | Capability theft / stuck loans / borrow outside scope | **High** |
| Proposal state machine and deadlines | Double execution, skipped execution, proposals deletable too early or never | **High** |
| Type registry (slots, display keys) | A payload executing under another type's config or bits | **High** |
| EmergencyFreeze | Permanent lockout / freeze bypass | **High** |
| SubOU hierarchy and controller | Authority laundering / stuck pause / control over the wrong OU | **High** |
| Composite pipeline | Bits pooling across steps; grants carried inside a composite | **Medium** |
| OU lifecycle | Orphaned state / premature destroy | **Medium** |
| `spend_guard` | Rate-limit bypass | **Medium** |

The Charter targets of the original plan (tampered history, version skip) are gone: the Charter holds only a name and a metadata URI (`05_charter.md`), and its one mutator is covered by the permission checks.

## 2. Tooling

### Asymptotic sui-prover (Recommended)

```bash
# Install
brew install asymptotic-code/sui-prover/sui-prover

# Run from a package root (where Move.toml lives)
cd packages/armature_framework && sui-prover
```

- **Spec syntax**: `#[spec(prove)]` attribute on Move functions
- **Key constructs**: `requires()`, `ensures()`, `asserts()`, `old!()`, `clone!()`
- **Backend**: Boogie → Z3 SMT solver
- **Platform**: macOS/Linux native, Windows via WSL

Start with `armature_framework`: every check in §4 lives there. `armature_proposals` and `armature_world_bridge` are extension packages whose reach is bounded by those framework checks; proofs there would cover handler-level bounds such as the `SendSmallPayment` spend window and the authorization in the `MintAllowance` and autojoin bypass entries.

### Legacy `sui move prove` (Not Recommended)

Uses older MSL `spec { }` blocks from the Diem era. Known issues with module filtering, less actively maintained. We use the Asymptotic prover exclusively.

## 3. Specification Approach

### Spec File Organization (proposed)

None of these files exist yet. Specs would live beside the code they prove, in a `specs/` directory inside the package (not this design-doc folder), organized by module category:

```
packages/armature_framework/specs/        (proposed)
├── permissions_spec.move          — bit gating, fixed framework bits, floors, grants, borrow scope, bypass-safe bits
├── governance_arith_spec.move     — pass rule, config bounds, roster invariants
├── registry_spec.move             — slot and display-key uniqueness, type selects slot, classification sets
├── proposal_lifecycle_spec.move   — status machine, deletion, saturating deadlines, snapshot eligibility
├── treasury_vault_spec.move       — conservation, registry sync, zero-balance cleanup
├── capability_vault_spec.move     — gating, loan lifecycle, registry sync, privileged extract
├── emergency_spec.move            — TypeName keying, mandatory exemptions, auto-expiry
├── controller_spec.move           — controller pause, privileged requests, controller-only mutators
├── composite_spec.move            — step bounds, no nesting, config maximum
├── ou_lifecycle_spec.move        — Active → Migrating, migration gate, destroy preconditions
└── spend_guard_spec.move          — rolling-epoch cap
```

### Spec Writing Pattern

Each spec function mirrors a production function and proves properties about it. For `treasury_vault::withdraw`:

```move
#[spec(prove)]
public fun withdraw_spec<T, P>(
    vault: &mut TreasuryVault,
    amount: u64,
    req: &ExecutionRequest<P>,
    ctx: &mut TxContext,
): Coin<T> {
    // Preconditions: a request of this OU carrying TREASURY_WITHDRAW
    // (or privileged), and enough balance
    requires(vault.ou_id() == req.req_ou_id());
    requires(req.req_has_permission(permissions::treasury_withdraw()));
    requires(balance<T>(vault) >= amount);

    // Snapshot pre-state
    let old_bal = old!(balance<T>(vault));

    // Call real function
    let result = withdraw<T, P>(vault, amount, req, ctx);

    // Postconditions — the actual proof obligations
    ensures(balance<T>(vault) == old_bal - amount);      // conservation
    ensures(coin::value(&result) == amount);               // output correctness

    result
}
```

The abort side is specified with `asserts()`: `withdraw` aborts with `EOUIdMismatch` for another OU's request, `EPermissionDenied` without the bit, and `EInsufficientBalance` past the balance. Every gated mutator in `packages/armature_framework/internal_workings.md` §2 gets the same pair of specs. That turns each `gate_tests.move` denial test, which checks one input, into a statement about all inputs.

### What the Prover Does

1. **Translates** Move bytecode + specs into Boogie intermediate verification language
2. **Generates** verification conditions (VCs) — logical formulas that must be valid
3. **Dispatches** VCs to Z3 SMT solver
4. **Reports** either ✅ proved or ❌ counterexample (concrete inputs violating the spec)

A proved spec means: *for ALL possible inputs satisfying `requires`, the `ensures` conditions hold after execution, and every `asserts` condition holds at its program point.*

## 4. Coverage Tracker

Each invariant below restates one from `03_core_spec.md` §6 (Consolidated Invariants) or `packages/armature_framework/internal_workings.md` and maps to one proposed spec file. **No row has a spec yet.** "Enforced today by" names what holds the property until a proof exists; "type system" means the Move compiler rejects any violation.

**Changes from the March tracker (41 rows).** Dropped: `Charter::VersionMonotonic`, `Charter::AmendmentRecords` and `Charter::RenewStorage` (no Walrus charter, versions or amendments), and every property of the removed `Executed` / `Expired` statuses. Changed: `Admin::EnableTypeFloor` (66%) and `Admin::UpdateConfigFloor` (self-referential 80%) became `Permissions::Floors` (80% on every stored config); `Proposal::TypeGate` ("in `enabled_proposals`") became `Registry::TypeSelectsSlot`; `SubOU::HierarchyBlocklist` moved into `Registry::ClassificationSets`. Removed as unenforced: "only one `SubOUControl` per SubOU" (now covered by `SubOU::PrivilegedScope`: only the registered control has authority). Added: the Permissions, Registry, Composite and SpendGuard groups and the deletion and deadline rows.

### Permissions (`permissions_spec.move`)

| ID | Invariant | Enforced today by |
|----|-----------|-------------------|
| `Permissions::MutatorGated` | Every framework `public fun` taking an `ExecutionRequest` checks the request's OU, then its bits or `privileged`. The exceptions are on a reviewed allowlist: accessors, the checks themselves, `P`-scoped type-state, `privileged_consume` and test helpers | `scripts/check_request_gates.py` (CI); `gate_tests.move`, one denial test per gated mutator (30) |
| `Permissions::BitsFromSlot` | A request's `permissions` and `borrow_scope` equal `P`'s slot values at mint time on the vote, atomic, bypass and composite-step paths. Only `controller::privileged_submit` mints `privileged = true`, with 0 bits and an empty scope | `permissions_tests`, `borrow_scope_tests`, `composite_tests` |
| `Permissions::FixedFrameworkBits` | A framework type's slot always holds exactly `ou::framework_permissions` and `ou::framework_borrow_scope` (`EFixedPermissions`) | `permissions_tests`, `borrow_scope_tests` |
| `Permissions::Floors` | Every stored config meets `min_approval_threshold_for_type` (80% for EnableProposalType, UpdateProposalConfig, EnableBypassType) and `permission_floor(bits)` (80% with TYPE_ADMIN, MIGRATE, TREASURY_WITHDRAW, VAULT_BORROW or VAULT_EXTRACT). Checked on enable, update and creation-time overrides (`EThresholdBelowMinimum`) | `permissions_tests`, `admin_ops_tests`, `tribe_tests` |
| `Permissions::GrantRules` | Only an EnableProposalType, EnableBypassType or UpdateProposalConfig request, or a privileged one, changes a type's bits or scope (`EPermissionChangeNotAllowed`). The added bits' floor never exceeds the granter's floor (`EGrantFloorNotMet`), and a scope change counts as a VAULT_BORROW grant | `permissions_tests`, `borrow_scope_tests` |
| `Permissions::NoGrantInComposite` | `add_step` refuses EnableProposalType and UpdateProposalConfig (`EUseTypedStep`). `add_enable_proposal_type_step` refuses a config with bits or a scope, and `add_update_proposal_config_step` refuses any change to them (`EGrantInComposite`) | `permissions_tests` |
| `Permissions::NoPooling` | Each composite step's request carries only its own type's bits and scope; `CompositePayload` holds none | `composite_tests` (`armature_proposals`) |
| `Permissions::BorrowScope` | `borrow_cap`, `borrow_cap_mut` and `loan_cap` need VAULT_BORROW and the cap type in the request's scope (`EBorrowScopeDenied`); a privileged request passes | `borrow_scope_tests`, `gate_tests` |
| `Permissions::BypassSafeBits` | A bypass-enabled type never holds TYPE_ADMIN, MIGRATE, VAULT_EXTRACT or FREEZE. This is refused at `execute_enable_bypass_type` and on every `ticket_from_cap` (`EBypassForbiddenBits`) | `external_execution_tests` |
| `Permissions::PermitBinding` | `ticket_request`, `discharge`, `discharge_returning_payload` and `ticket_from_cap(_readonly)` require `Permit<P>`, so only `P`'s defining module (or its package) can spend, close or bypass-mint a `P` ticket | Type system (`std::internal::Permit`); `check_request_gates.py` (`PERMIT_REQUIRED`); `external_type_lifecycle_tests` |
| `Permissions::ControllerOnly` | `set_controller_paused` and `clear_controller` accept only privileged requests (`ou::ENotPrivileged`) | `gate_tests` |
| `Charter::MetadataGate` | `charter::update_metadata` needs a request of the charter's OU carrying METADATA | `gate_tests`, `charter_tests` |

### Governance arithmetic (`governance_arith_spec.move`)

| ID | Invariant | Enforced today by |
|----|-----------|-------------------|
| `Board::PassRule` | A proposal passes iff `yes + no > 0`, `(yes + no) · 10000 ≥ quorum · total_snapshot_weight` and `yes · 10000 ≥ approval_threshold · (yes + no)`, computed in u128 with no overflow (`utils::gte_bps`) | `utils` unit tests (incl. `u64::MAX` inputs), `board_voting_tests`, `proposal_tests` |
| `ProposalConfig::Validation` | `new_config` aborts unless `quorum ∈ [1, 10000]`, `approval_threshold ∈ [5000, 10000]` and `expiry_ms ≥ 3,600,000`. There is no upper bound on expiry or delay | `ou_tests` |
| `Board::NonEmpty` | No roster change leaves the board empty (`EEmptyBoard`). Adding a current member aborts (`EDuplicateBoardMember`), except in a batch add, which skips it | `board_ops_tests`, `member_ops_tests`, `tribe_tests` |
| `Board::RosterVersion` | `roster_version` rises by exactly one per membership change (a batch counts once, a no-op batch not at all); a former member keeps a closed tenure | `proposal_tests` (`test_roster_version_and_snapshot_version`) |

### Registry (`registry_spec.move`)

| ID | Invariant | Enforced today by |
|----|-----------|-------------------|
| `Registry::SlotUnique` | At most one slot per canonical `TypeName` (`ETypeAlreadyEnabled`). Display keys are non-empty and unique per OU (`EEmptyDisplayKey`, `EDisplayKeyTaken`), and the display-key index stays the inverse of the slots across enable and disable | `ou_tests`, `admin_ops_tests` |
| `Registry::TypeSelectsSlot` | Submission and execution take config, display key and bits from `P`'s own slot, with no caller-supplied key; a type without a slot aborts `ETypeNotEnabled` | `ou_tests`, `external_type_lifecycle_tests` |
| `Registry::PinnedType` | EnableProposalType and EnableBypassType execute only for the Move type the payload names (`ETypeMismatch`) | `admin_ops_tests`, `external_execution_tests` |
| `Registry::ClassificationSets` | Undisableable types are never disabled; SubOU-blocked types are never enabled on an OU with a controller; only `TransferAssets` runs while Migrating. The first two are handler-level (see §4.1) | `admin_ops_tests`, `tribe_tests`, `migration_tests` |

### Proposal lifecycle (`proposal_lifecycle_spec.move`)

| ID | Invariant | Enforced today by |
|----|-----------|-------------------|
| `Proposal::StatusMonotonic` | `Active → Passed` is the only stored transition | `proposal_tests` |
| `Proposal::DeleteOnExecute` | `ticket_from_vote` consumes the `Proposal` by value and deletes it, so it cannot execute twice | Type system (by-value consume); `proposal_tests` |
| `Proposal::ExpiryDeletion` | `delete_expired_proposal` succeeds exactly from `created_at + expiry_ms` (Active) or `passed_at + execution_delay_ms + expiry_ms` (Passed). Voting closes exactly when deletion opens (`EVotingClosed`), and execution closes with the window (`EExecutionWindowClosed`) | `proposal_tests` |
| `Proposal::SaturatingDeadlines` | Deadline, delay and cooldown sums on the vote paths saturate at `u64::MAX` instead of aborting | `proposal_tests` (`test_execute_with_max_expiry_does_not_overflow`), `utils` tests |
| `Proposal::SnapshotEligibility` | Only a member at `snapshot_version` may vote (`ENotInSnapshot`). `snapshot_version`, `total_snapshot_weight` and `config` are write-once | `proposal_tests` (removed and re-added members, non-snapshot voter) |
| `Proposal::ExecutorEligibility` | The vote-path executor is a current member (`ENotEligible`) | `proposal_tests` |
| `Proposal::NoDuplicateVote` | One vote per member (`EAlreadyVoted`) | `proposal_tests` |
| `Proposal::DelayAndCooldown` | On the two-PTB, atomic and bypass paths, execution waits `execution_delay_ms` after passing and `cooldown_ms` after the type's last execution. Composite steps get no per-step cooldown check (see §4.1) | `proposal_tests`, `submit_vote_execute_tests`, `external_execution_tests` |
| `Proposal::RetryableFailure` | A handler abort reverts the PTB, deletion included, so the proposal stays Passed while its window is open | `proposal_tests` (`test_passed_proposal_retryable_after_failure`) |
| `Proposal::AtomicPath` | `submit_vote_execute` requires `execution_delay_ms == 0` and the proposer's single YES to pass against `member_count`; the read-only entry points require `cooldown_ms == 0` | `submit_vote_execute_tests`, `board_voting_tests` |
| `Proposal::EventOnlySinglePTB` | Atomic, bypass and controller executions create no `Proposal` object; their IDs come from `fresh_object_address` | `submit_vote_execute_tests`, `external_execution_tests`, `controller_tests` |
| `ExecutionRequest::HotPotato` | `ExecutionRequest`, `ExecutionTicket`, `CapLoan`, `Pipeline`, `AssetTransfer` and `PendingUpgrade` have no abilities | Type system |

### Treasury (`treasury_vault_spec.move`)

| ID | Invariant | Enforced today by |
|----|-----------|-------------------|
| `Treasury::WithdrawGate` | `withdraw` needs a request of this OU carrying TREASURY_WITHDRAW (or privileged) | `gate_tests`, `treasury_vault_tests` |
| `Treasury::Conservation` | `withdraw` lowers the balance by exactly `amount` and returns a coin of `amount`; `deposit` raises it by the coin's value | `treasury_vault_tests` |
| `Treasury::RegistrySynced` | `coin_types` is exactly the set of coin types with a non-zero balance | `treasury_vault_tests` |
| `Treasury::ZeroBalanceCleanup` | No zero `Balance<T>` field persists; a zero-value deposit is a no-op | `treasury_vault_tests` |
| `Treasury::PermissionlessDeposit` | Anyone can deposit; `claim_coin` moves a coin sent to the vault's address into the vault | `treasury_vault_tests` |

### Capability Vault (`capability_vault_spec.move`)

| ID | Invariant | Enforced today by |
|----|-----------|-------------------|
| `CapabilityVault::Gating` | Store needs VAULT_STORE; borrow and loan need VAULT_BORROW plus scope; extract and `SubOUControl` create/destroy need VAULT_EXTRACT. `borrow_external_cap` is the only ungated read | `gate_tests`, `borrow_scope_tests`, `capability_vault_tests` |
| `CapabilityVault::RegistrySynced` | `cap_types`, `cap_ids` and `ids_by_type` match the stored caps | `capability_vault_tests` |
| `CapabilityVault::LoanPreservesRegistries` | `loan_cap` leaves the registries unchanged (the ID counts as held) | `capability_vault_tests` |
| `CapabilityVault::CapLoanVerification` | `return_cap` accepts only the loaned cap, into the vault it came from (`ECapIdMismatch`, `EVaultIdMismatch`) | Code only; no negative test exists |
| `CapabilityVault::PrivilegedExtract` | `controller::privileged_extract` needs the SubOU's vault (`EControlMismatch`) and its registered `&SubOUControl` (`assert_registered_control`); `capability_vault::privileged_extract` is `public(package)` and checks `control.subou_id == vault.ou_id` | `capability_vault_tests`, `cross_ou_auth_tests` |
| `CapabilityVault::ReceiveFromController` | A cap enters another OU's vault only through `receive_cap_authorized` (both requests), `controller::receive_cap_from_controller` (sender's vault holds the target's registered control; `ENotController`) or the framework's SpinOutSubOU / TransferAssets handlers; `receive_cap` is `public(package)` | `capability_vault_tests`, `cross_ou_auth_tests` |

### Emergency Freeze (`emergency_spec.move`)

| ID | Invariant | Enforced today by |
|----|-----------|-------------------|
| `EmergencyFreeze::BlocksExecution` | A frozen type cannot execute on the two-PTB, atomic, bypass or composite-step path (`assert_not_frozen<P>`); the freeze passed must be the executing OU's (`EOUMismatch`) | `freeze_path_tests`, `external_type_lifecycle_tests`, `cross_ou_auth_tests` |
| `EmergencyFreeze::KeyedByTypeName` | Freezing one instantiation (`Rebalance<CredA>`) leaves others executable | `freeze_path_tests`, `external_type_lifecycle_tests` |
| `EmergencyFreeze::AutoExpiry` | A freeze ends at `now + max_freeze_duration_ms` with no further action | `emergency_tests` |
| `EmergencyFreeze::MandatoryExemptions` | `TransferFreezeAdmin` and `UnfreezeProposalType`, matched by framework type, can never be frozen (`EProtectedType`) or un-exempted (`EMandatoryExemptType`) | `emergency_tests`, `freeze_ops_tests` |
| `EmergencyFreeze::GovernanceOverride` | FREEZE-bit requests (and the cap holder) can unfreeze; only FREEZE-bit requests change the duration or the exempt set | `gate_tests`, `freeze_ops_tests` |

### SubOU and controller (`controller_spec.move`)

| ID | Invariant | Enforced today by |
|----|-----------|-------------------|
| `SubOU::ControllerCapId` | `controller_cap_id` is set when a SubOU is shared (`share_subou`) and cleared only by `clear_controller` (privileged) | `controller_tests`, `migration_tests` |
| `SubOU::PauseCompleteness` | While `controller_paused`, the vote, atomic and bypass paths abort (`EControllerPaused`); only the controller's privileged path still runs | `controller_tests`, `subou_ops_tests` (`paused_subou_blocks_execution`) |
| `SubOU::PauseGranularity` | While paused, submission and voting still work | `subou_ops_tests` |
| `SubOU::SpinOutCleanup` | `clear_controller` resets `controller_paused` to false | `migration_tests` |
| `SubOU::PrivilegedScope` | `privileged_submit` needs `control.subou_id == subou.id` (`EControlMismatch`), `subou.controller_cap_id == some(id(control))` (`ENotController`) and an Active target; its request passes every check on that OU and on no other | `controller_tests`, `cross_ou_auth_tests` |

### Composite (`composite_spec.move`)

| ID | Invariant | Enforced today by |
|----|-----------|-------------------|
| `Composite::Bounds` | At most 16 steps; no nested `CompositePayload` (`ECompositeNesting`); each step type is enabled and `composable_allowed` | `composite_tests` (both packages) |
| `Composite::OUBound` | `begin_pipeline` and `advance_step` take only the ticket's / pipeline's OU (`EOUIdMismatch`); each step aborts if the OU is execution- or controller-paused (`EExecutionPaused`, `EControllerPaused`) or the step type is disabled (`ETypeNotEnabled`) | `cross_ou_auth_tests` |
| `Composite::ConfigMaximum` | The composite's config is the component-wise maximum of the "Composite" slot and every step's config; EnableProposalType and UpdateProposalConfig steps force ≥ 80% (`composite::EFloorNotMet`) | Code (`submit_composite`); `composite_tests` cover the passing case only |

### OU Lifecycle (`ou_lifecycle_spec.move`)

| ID | Invariant | Enforced today by |
|----|-----------|-------------------|
| `OU::StatusTransition` | `Active → Migrating` only (`set_migrating`, MIGRATE); no path back | `migration_tests` |
| `OU::MigrationGate` | While Migrating, only `TransferAssets` may be submitted or executed; the bypass path requires Active | `migration_tests` |
| `OU::DestroyRequirements` | `ou::destroy` needs Migrating, matching companion IDs, no encrypted entries, empty vaults and an empty frozen-type map | `migration_tests` (`spawn_ou_and_destroy_origin_e2e`) |

### SpendGuard (`spend_guard_spec.move`)

| ID | Invariant | Enforced today by |
|----|-----------|-------------------|
| `SpendGuard::EpochCap` | After a successful `charge`, `epoch_spend ≤ max_epoch_spend`; the window rolls forward by whole epochs | `spend_guard_tests` |

### 4.1 Properties that do not hold today

Specs written naively for these would fail. Each needs a decision (change the code, or state the weaker property) before it can be specified.

- **Classification checks are handler-level.** The undisableable, SubOU-blocked and composable-versus-cooldown checks run in the framework handlers (`admin_ops`, `external_execution`), and the SubOU blocklist also on creation-time overrides. They do not run in `ou::enable_proposal_type`, `disable_proposal_type` or `update_proposal_config`. A non-framework type granted TYPE_ADMIN (an 80% vote; never bypass-enabled) reaches those mutators with arguments of its own handler's choosing. The properties therefore hold only if no such type is enabled, or must be proved per handler.
- **Composite steps skip the step type's cooldown.** `composite::advance_step` checks no per-step cooldown: it asserts only `cooldown_ms == 0 || composable_allowed`, and the `last_executed_snapshot` that `begin_pipeline` records is never read. The design relies on cooldown types not being composable, but only the `admin_ops` and `external_execution` handlers refuse a config that is both. Creation-time overrides keep a default slot's `composable_allowed` and do not run that check. A default-composable type such as AddMember, given a cooldown at creation, therefore runs inside composites without its own cooldown; the composite is rate-limited only by the `CompositePayload` slot's last execution. The module's doc comments still say `advance_step` enforces cooldowns.
- **Arithmetic that aborts instead of saturating.** `emergency::freeze_type` computes `now + max_freeze_duration_ms` unchecked, and `update_freeze_duration` accepts any value, so a very large duration makes every freeze abort until governance lowers it. `external_execution` checks the bypass cooldown as `last + cooldown_ms` unchecked, whereas the vote paths use `utils::saturating_add`; the outcome is the same (blocked), but the abort code differs. `spend_guard::charge` divides by `epoch_duration_ms`, so a window created with a zero duration aborts every charge.
- **Destroy liveness.** `ou::destroy` needs the frozen-type map empty, and expired entries stay in it until an unfreeze removes them. On a Migrating OU no governance unfreeze can run (only `TransferAssets` executes), so only the `FreezeAdminCap` holder can clear them.

Accepted behaviours, which specs must state rather than forbid:

- A config with an enormous `expiry_ms` or `execution_delay_ms` never expires: a Passed proposal under it leaves the chain only by execution.
- With the default 7-day freeze and 7-day expiry, freezing a type right after one of its proposals passes can run out that proposal's execution window.
- `disable_proposal_type` drops the type's cooldown state, so a re-enabled type's first execution is not rate-limited.
- `capability_vault::receive_cap` (`public(package)`) does not check the receiving vault's OU; its framework callers (SpinOutSubOU, TransferAssets, `receive_cap_from_controller`) tie the sender to the target.
- Destroying an OU leaves its type slots attached to the deleted UID and drops the roster table without reclaiming entry deposits.

## 5. What Enforces These Today, and CI Integration

### Current enforcement (in place of proofs)

- **Move type system.** Hot potatoes have no abilities. `ExecutionRequest` has no public constructor: its mint functions and `proposal::create`, `record_vote`, `execute` and `consume` are `public(package)`. `std::internal::Permit<P>` can be minted only by `P`'s defining module.
- **Unit and scenario tests** (`sui move test` per package): framework 410, proposals 121, world bridge 20, external-type fixture 18. The security-relevant suites are:
  - `gate_tests.move`: one denial test per gated mutator (28). Each mutator must refuse a request holding every bit except the one it needs; for the controller-only pair, any unprivileged request
  - `permissions_tests`, `borrow_scope_tests`, `freeze_path_tests`, `submit_vote_execute_tests`
  - `cross_ou_auth_tests`: forged or spun-out `SubOUControl`s, another OU's freeze object, deposits into a vault the sender does not control, and composites run against another OU or after a pause or disable
  - `proposal_tests`: deadlines, deletion, snapshot eligibility, the saturating maximum expiry
  - `armature_external_type_tests`: a third-party type on every path, and replays of the confirmed cross-type attacks
  - the world bridge's autojoin tickets, which carry BOARD_ADD only
  - `currency_ops_tests::mint_allowance_bypass_outsider_aborts` (ARMATURE-31)
- **CI gate check** — `scripts/check_request_gates.py`. Every `public fun` in `armature_framework/sources` that takes an `ExecutionRequest` must call `assert_permitted` / `assert_controller` or be on the reviewed allowlist (18 entries). Every gated function (28 today) must have a denial test in `gate_tests.move` whose name starts with the function's name. The five ticket entry points (`ticket_request`, `discharge`, `discharge_returning_payload`, `ticket_from_cap`, `ticket_from_cap_readonly`) must take `Permit<P>`. Removing a gate or adding an ungated mutator fails CI.
- **CI workflow** — `.github/workflows/pr.yml` runs on pull requests to `main` that touch `packages/**` or the workflows. It runs the prettier-move format check (`armature_framework`, `armature_proposals`), then the gate check, then `sui move build` and `sui move test` for every package under `packages/`. A separate job builds the whitepaper when `whitepaper/**` changes. There is no prover step.

### Proposed prover job (not in the repo)

```yaml
# .github/workflows/formal-verification.yml  (proposed)
name: Formal Verification
on:
  pull_request:
    branches: [main]
    paths: ['packages/armature_framework/**']

jobs:
  prove:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install Homebrew          # as in pr.yml
        run: |
          /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
          echo "/home/linuxbrew/.linuxbrew/bin" >> $GITHUB_PATH
      - name: Install sui-prover
        run: brew install asymptotic-code/sui-prover/sui-prover
      - name: Run prover
        run: cd packages/armature_framework && sui-prover
        timeout-minutes: 30
```

## 6. Process

```
Write module → Write tests → Write specs → sui-prover → Code review → Merge
                   ↑                            │
                   └── counterexample found ─────┘
```

Proposed; until specs exist, the gate check and the test suites are the blocking checks. A new gated mutator needs a denial test, and a removed gate fails CI. Once specs exist:

- Specs are reviewed alongside code in PRs
- Counterexamples from the prover become new test cases
- Coverage tracker updated on each merge
- Prover runs as blocking CI check on `packages/armature_framework/**` changes

## 7. Limitations & Scope

**In scope:**
- Functional correctness (pre/post conditions)
- Abort condition completeness
- Arithmetic overflow/underflow
- State machine transition validity
- Registry synchronization invariants
- Permission-bit, borrow-scope and grant checks

**Out of scope:**
- Economic attack modeling (MEV, oracle manipulation)
- Gas optimization correctness
- Off-chain consumers: indexer, SDK, UI, RPC data layer
- Cross-chain interoperability
- Availability of off-chain content (charter metadata URIs, Seal key servers)
- Trust in extension packages' upgrade keys. Whoever holds a package's `UpgradeCap` can change how its types spend their requests (`docs/package-boundaries.md`); proofs cover the framework's bounds on that, not the extension's code

**Known tooling limitations:**
- Dynamic fields may require manual modeling. The type registry (slots and the display-key index), type-state, treasury balances and vault caps all live in dynamic fields, and the roster in a `Table`
- Hot potato patterns (no-ability structs) are partially supported. Structural guarantees come from Move's type system; specs verify behavioral properties
- Properties that cross package boundaries (`Permit<P>` binding, which package may spend a ticket) come from the type system and `std::internal`, not from specs
- The framework uses Move 2024 enums (`ProposalStatus`, `Closeout`, `OUStatus`), macros (`do_ref!`) and `std::internal::Permit`. Check prover support for each before writing specs
- Z3 may timeout on deeply nested nonlinear arithmetic — keep specs focused
- Integer specs use unbounded `num` — constrain with `requires(x <= u64::max_value!())`

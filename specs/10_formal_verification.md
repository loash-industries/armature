# 10 — Formal Verification Strategy

> **Tool**: [Asymptotic sui-prover](https://github.com/asymptotic-code/sui-prover) — standalone formal verification for Sui Move, backed by the Z3 SMT solver.

## 1. Why Formal Verification for DAO Protocol

This protocol governs treasury funds, capability delegation, and organizational hierarchy through typed proposals. A single arithmetic bug in quorum calculation or a missed access-control check could drain a treasury or deadlock governance permanently.

**Testing proves the presence of correct behavior. Formal verification proves the absence of incorrect behavior.**

Our 41 invariants and 214 tests provide strong confidence, but tests only cover enumerated scenarios. The prover exhaustively checks specs against *all* possible inputs, catching edge cases no human would think to write tests for — integer boundary overflows, obscure abort paths, and subtle state-machine violations.

### High-Value Targets

| Module | Risk if Broken | Verification Priority |
|--------|---------------|----------------------|
| TreasuryVault | Fund loss / phantom balances | **Critical** |
| Governance arithmetic | Broken quorum → unauthorized execution | **Critical** |
| CapabilityVault + CapLoan | Capability theft / stuck loans | **High** |
| Proposal state machine | Double-execution / skip-execution | **High** |
| EmergencyFreeze | Permanent lockout / freeze bypass | **High** |
| SubDAO hierarchy | Authority laundering / stuck pause | **Medium** |
| Charter | Tampered history / version skip | **Medium** |
| DAO lifecycle | Orphaned state / premature destroy | **Medium** |

## 2. Tooling

### Asymptotic sui-prover (Recommended)

```bash
# Install
brew install asymptotic-code/sui-prover/sui-prover

# Run from package root (where Move.toml lives)
cd dao-protocol && sui-prover
```

- **Spec syntax**: `#[spec(prove)]` attribute on Move functions
- **Key constructs**: `requires()`, `ensures()`, `asserts()`, `old!()`, `clone!()`
- **Backend**: Boogie → Z3 SMT solver
- **Platform**: macOS/Linux native, Windows via WSL

### Legacy `sui move prove` (Not Recommended)

Uses older MSL `spec { }` blocks from the Diem era. Known issues with module filtering, less actively maintained. We use the Asymptotic prover exclusively.

## 3. Specification Approach

### Spec File Organization

All formal specs live in `dao-protocol/specs/`, organized by module category:

```
specs/
├── 00_overview.md                 — this index; coverage tracker
├── 01_treasury_vault.move         — fund conservation, registry sync, balance checks
├── 02_governance_arithmetic.move  — quorum/threshold math, overflow protection
├── 03_capability_vault.move       — access control, loan lifecycle, registry sync
├── 04_proposal_lifecycle.move     — state machine, vote counting, timing controls
├── 05_emergency_freeze.move       — freeze/unfreeze transitions, auto-expiry, protected types
├── 06_subdao_hierarchy.move       — control lifecycle, pause semantics, blocklist
├── 07_charter.move                — version monotonicity, amendment records, ownership
├── 08_dao_lifecycle.move          — status transitions, destroy preconditions
└── 09_admin_proposals.move        — protected types, threshold floors, atomic enable
```

### Spec Writing Pattern

Each spec function mirrors a production function and proves properties about it:

```move
#[spec(prove)]
public fun withdraw_conservation_spec<T, P>(
    vault: &mut TreasuryVault,
    amount: u64,
    req: &ExecutionRequest<P>,
    ctx: &mut TxContext,
): Coin<T> {
    // Preconditions
    requires(balance<T>(vault) >= amount);

    // Snapshot pre-state
    let old_bal = old!(balance<T>(vault));

    // Call real function
    let result = withdraw<T, P>(vault, amount, req, ctx);

    // Postconditions — the actual proof obligations
    ensures(balance<T>(vault) == old_bal - amount);      // conservation
    ensures(coin::value(&result) == amount);               // output correctness
    ensures(balance<T>(vault) >= 0);                       // no underflow

    result
}
```

### What the Prover Does

1. **Translates** Move bytecode + specs into Boogie intermediate verification language
2. **Generates** verification conditions (VCs) — logical formulas that must be valid
3. **Dispatches** VCs to Z3 SMT solver
4. **Reports** either ✅ proved or ❌ counterexample (concrete inputs violating the spec)

A proved spec means: *for ALL possible inputs satisfying `requires`, the `ensures` conditions hold after execution, and every `asserts` condition holds at its program point.*

## 4. Coverage Tracker

Each invariant from `03_core_spec.md` maps to one or more spec functions:

| ID | Invariant | Spec File | Status |
|----|-----------|-----------|--------|
| `Treasury::WithdrawGate` | Withdraw requires ExecutionRequest | `01_treasury_vault.move` | Pending |
| `Treasury::RegistrySynced` | coin_types reflects non-zero balances | `01_treasury_vault.move` | Pending |
| `Treasury::ZeroBalanceCleanup` | No zero-balance dynamic fields persist | `01_treasury_vault.move` | Pending |
| `Treasury::BalanceCheck` | Cannot withdraw > available | `01_treasury_vault.move` | Pending |
| `Treasury::PermissionlessDeposit` | Anyone can deposit | `01_treasury_vault.move` | Pending |
| `Treasury::CoinRecovery` | claim_coin recovers direct transfers | `01_treasury_vault.move` | Pending |
| `Board::VoteCounting` | Quorum/threshold arithmetic | `02_governance_arithmetic.move` | Pending |
| `ProposalConfig::Validation` | Config bounds enforcement | `02_governance_arithmetic.move` | Pending |
| `Admin::UpdateConfigFloor` | 80% self-referential floor | `09_admin_proposals.move` | Pending |
| `Admin::EnableTypeFloor` | 66% enable floor | `09_admin_proposals.move` | Pending |
| `CapabilityVault::AccessControl` | All access requires ExecutionRequest | `03_capability_vault.move` | Pending |
| `CapabilityVault::RegistrySynced` | cap_types/cap_ids reflect stored caps | `03_capability_vault.move` | Pending |
| `CapabilityVault::LoanPreservesRegistries` | Loan doesn't update registries | `03_capability_vault.move` | Pending |
| `CapabilityVault::CapLoanVerification` | return_cap verifies cap_id match | `03_capability_vault.move` | Pending |
| `CapabilityVault::PrivilegedExtract` | Requires matching SubDAOControl | `03_capability_vault.move` | Pending |
| `Proposal::TypeGate` | Type must be in enabled_proposals | `04_proposal_lifecycle.move` | Pending |
| `Proposal::StatusMonotonic` | No reverse transitions | `04_proposal_lifecycle.move` | Pending |
| `Proposal::VoteSnapshot` | Snapshot immutable after creation | `04_proposal_lifecycle.move` | Pending |
| `Proposal::ExecutorEligibility` | Only board members execute | `04_proposal_lifecycle.move` | Pending |
| `Proposal::ExecutionDelay` | Delay must elapse | `04_proposal_lifecycle.move` | Pending |
| `Proposal::Cooldown` | Cooldown enforced per type | `04_proposal_lifecycle.move` | Pending |
| `Proposal::RetryableFailure` | Failed exec leaves Passed | `04_proposal_lifecycle.move` | Pending |
| `Proposal::NoDuplicateVote` | One vote per member | `04_proposal_lifecycle.move` | Pending |
| `Proposal::VoteEligibility` | Only snapshot members vote | `04_proposal_lifecycle.move` | Pending |
| `ExecutionRequest::HotPotato` | No drop/store/copy | `04_proposal_lifecycle.move` | Pending |
| `EmergencyFreeze::BlocksExecution` | Frozen type blocks execute | `05_emergency_freeze.move` | Pending |
| `EmergencyFreeze::SelectiveFreeze` | Freeze is per-type | `05_emergency_freeze.move` | Pending |
| `EmergencyFreeze::AutoExpiry` | Freeze expires automatically | `05_emergency_freeze.move` | Pending |
| `EmergencyFreeze::ProtectedTypes` | Cannot freeze protected types | `05_emergency_freeze.move` | Pending |
| `EmergencyFreeze::GovernanceOverride` | Governance can unfreeze | `05_emergency_freeze.move` | Pending |
| `SubDAO::HierarchyBlocklist` | Controlled SubDAO blocked types | `06_subdao_hierarchy.move` | Pending |
| `SubDAO::ControllerCapId` | Set at creation, cleared at spinout | `06_subdao_hierarchy.move` | Pending |
| `SubDAO::PauseCompleteness` | Paused blocks ALL execution | `06_subdao_hierarchy.move` | Pending |
| `SubDAO::PauseGranularity` | Paused allows proposal creation | `06_subdao_hierarchy.move` | Pending |
| `SubDAO::SpinOutCleanup` | Spinout clears paused flag | `06_subdao_hierarchy.move` | Pending |
| `Charter::VersionMonotonic` | Version strictly increments | `07_charter.move` | Pending |
| `Charter::AmendmentRecords` | Both blob IDs recorded | `07_charter.move` | Pending |
| `Charter::OwnershipValidation` | Charter belongs to executing DAO | `07_charter.move` | Pending |
| `Charter::RenewStorage` | Renew changes blob_id only | `07_charter.move` | Pending |
| `DAO::StatusTransition` | Active → Migrating only | `08_dao_lifecycle.move` | Pending |
| `DAO::DestroyRequirements` | Destroy requires Migrating + empty | `08_dao_lifecycle.move` | Pending |

## 5. CI Integration

```yaml
# .github/workflows/formal-verification.yml
name: Formal Verification
on:
  pull_request:
    paths: ['dao-protocol/sources/**', 'dao-protocol/specs/**']

jobs:
  prove:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install sui-prover
        run: |
          brew install asymptotic-code/sui-prover/sui-prover
      - name: Run prover
        run: |
          cd dao-protocol && sui-prover
        timeout-minutes: 30
```

## 6. Process

```
Write module → Write tests → Write specs → sui-prover → Code review → Merge
                   ↑                            │
                   └── counterexample found ─────┘
```

- Specs are reviewed alongside code in PRs
- Counterexamples from the prover become new test cases
- Coverage tracker updated on each merge
- Prover runs as blocking CI check on `sources/` and `specs/` changes

## 7. Limitations & Scope

**In scope:**
- Functional correctness (pre/post conditions)
- Abort condition completeness
- Arithmetic overflow/underflow
- State machine transition validity
- Registry synchronization invariants

**Out of scope:**
- Economic attack modeling (MEV, oracle manipulation)
- Gas optimization correctness
- Frontend/RPC data layer
- Cross-chain interoperability
- Walrus blob availability (external dependency)

**Known tooling limitations:**
- Dynamic fields may require manual modeling
- Hot potato patterns (no-ability structs) are partially supported — structural guarantees come from Move's type system, specs verify behavioral properties
- Z3 may timeout on deeply nested nonlinear arithmetic — keep specs focused
- Integer specs use unbounded `num` — constrain with `requires(x <= u64::max_value!())`

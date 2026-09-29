# Test Conventions

How the Move test suites are laid out, named and checked, and how the files in `specs/tests/` cite them.

## Layout

Four packages carry tests. Every test file is a `#[test_only]` module named `<address>::<subject>_tests` (`armature::proposal_tests`, `armature_proposals::charter_tests`) in the package's `tests/` directory. The only in-source tests are the eight `#[test]` functions at the bottom of `armature_framework/sources/utils.move`.

| Package (address) | Test modules | Tests |
|---|---|---|
| `armature_framework` (`armature::`) | 20 files in `packages/armature_framework/tests/` + `sources/utils.move` | 410 |
| `armature_proposals` | 13 files in `packages/armature_proposals/tests/` | 121 |
| `armature_world_bridge` | `autojoin_e2e_tests` (8), `tribe_allowlist_tests` (12) | 20 |
| `armature_external_type_tests` | `external_type_lifecycle_tests` (11), `tribe_e2e_tests` (7) (third-party fixture, never published) | 18 |

Counts are from `sui move test` on the working tree on top of commit `690cda2` (2026-09-29), after the `multicoin` dependency was removed; all 569 pass.

**Framework test modules**

| Module | Tests | Covers |
|---|---|---|
| `board_voting_tests` | 22 | Board pass math, propose threshold, slot-keyed submission, `ticket_from_vote` vs `_readonly` |
| `borrow_scope_tests` | 9 | `borrow_scope` on requests and in the vault; scope changes as grants |
| `capability_vault_tests` | 23 | store / borrow / loan / extract, registries, `privileged_extract`, `receive_cap(_authorized)` (package-level) |
| `composite_tests` | 2 | composite nesting refused, per-step display key |
| `controller_tests` | 5 | `privileged_submit` / `privileged_consume`, controller pause |
| `cross_ou_auth_tests` | 17 | registered `SubOUControl`, the OU's own freeze object, `receive_cap_from_controller`, composites bound to their OU |
| `ou_tests` | 20 | creation, default slots, type registry, root size, `ProposalConfig` bounds, `create_returning_vault` |
| `emergency_tests` | 18 | freeze / unfreeze / expiry / exemptions on a standalone `EmergencyFreeze` |
| `encrypted_entry_tests` | 39 | Seal-encrypted entries, epoch rotation, `destroy` with entries |
| `external_execution_tests` | 26 | `EnableBypassType` / `DisableBypassType`, `ticket_from_cap(_readonly)` |
| `freeze_ops_tests` | 5 | `UpdateFreezeConfig`, `UpdateFreezeExemptTypes` through governance |
| `freeze_path_tests` | 7 | freeze keyed by `TypeName` on the atomic, bypass and two-PTB paths |
| `gate_tests` | 34 | one denial test per gated mutator (see CI gate check) |
| `lifecycle_ops_tests` | 5 | `TransferAssets` hot-potato flow |
| `permissions_tests` | 35 | permission bits, floors, grant rules, fixed framework bits, composite grants |
| `proposal_tests` | 42 | proposal lifecycle, deletion, expiry, snapshot versions, tickets |
| `spend_guard_tests` | 9 | rolling spend window |
| `submit_vote_execute_tests` | 26 | atomic single-vote path and its read-only variant |
| `treasury_vault_tests` | 17 | coin deposit / withdraw / claim, registry, `destroy_empty` |
| `tribe_tests` | 41 | tribe constructors, `create_wired_subou`, creation-time overrides |
| `utils` (in `sources/`) | 8 | bps math, `saturating_add` |

**`armature_proposals` test modules**: `admin_ops_tests` (21), `board_ops_tests` (6), `charter_tests` (2), `composite_tests` (20), `currency_ops_tests` (12), `emergency_freeze_tests` (8), `lifecycle_tests` (2), `member_ops_tests` (15), `migration_tests` (4), `subou_ops_tests` (16), `treasury_ops_tests` (9), `tribe_setup_tests` (4), `upgrade_ops_tests` (2). Several of them drive framework handlers (`admin_ops`, `board_ops`, `member_ops`, `freeze_ops`, `lifecycle_ops`) end to end.

## Citing Tests in These Specs

Test matrices have three columns: the test function, the expected result, and where the test lives.

- **Where** is the test module. Framework modules are written without the `armature::` prefix (`proposal_tests`); other packages' modules carry their package (`armature_proposals::charter_tests`). In prose a test is cited as `module::function`.
- **planned** means no such test exists yet. The name is a proposal; the expected result and abort code are what the current code does.
- **structural** means the property is enforced by the compiler or the object model and has no runtime test.

## Naming

Names are snake_case and describe the behaviour. Patterns in use:

| Pattern | Examples |
|---|---|
| `test_<subject>__<behaviour>` (double underscore) | `test_freeze__sets_expiry`, `test_board__threshold_boundary_50_percent`, `test_sve__nonzero_delay_aborts` |
| `test_<behaviour>` | `test_execute_deletes_proposal`, `test_delete_expired_passed_after_window` |
| `<behaviour>` without a prefix (newer modules) | `borrow_outside_scope_aborts`, `receive_cap_authorized_aborts_on_recv_ou_mismatch` |
| `<path>__<behaviour>` | `two_ptb__frozen_instantiation_aborts`, `ticket_from_vote_readonly__slot_cooldown_aborts` |
| `<mutator>_needs_<bit>` (required in `gate_tests`) | `withdraw_needs_treasury_withdraw`, `set_controller_paused_needs_privileged_request` |
| `_aborts` suffix for expected failures | `test_vote_after_expiry_aborts` |
| `_e2e` suffix for submit → vote → execute flows | `send_coin_e2e`, `update_freeze_config_e2e` |

## Addresses

There are no shared address constants. Each module declares its own; the common ones are:

```move
const CREATOR: address = @0xA;   // OU creator and first board member (29 modules)
const MEMBER_B: address = @0xB;
const MEMBER_C: address = @0xC;
const NON_MEMBER: address = @0xD; // varies by module: @0xC, @0xD or @0xFF
```

## Abort Codes

Each module declares its own error constants, numbered from 0 within the module:

```move
// proposal.move
const ENotActive: u64 = 3;
/// vote called on an Active proposal after its voting period (expiry_ms) ended.
const EVotingClosed: u64 = 20;
/// The request's type does not hold the permission bits a mutator requires
/// (see armature::permissions), and the request is not privileged.
const EPermissionDenied: u64 = 21;
```

- Codes are unique only within a module. `EOUIdMismatch` is 2 in `ou` and `board_voting`, 1 in `treasury_vault`, 3 in `capability_vault` and 6 in `external_execution` and `composite`. Always cite `module::EName`.
- Retired codes are left unused rather than reassigned, so modules have gaps (`ou`: 1, 10, 18, 20, 22; `proposal`: 14, 18; `admin_ops`: 3, 5).
- Tests name the constant: `#[test, expected_failure(abort_code = proposal::EVotingClosed)]`, with the module in a `use`, or fully qualified (`abort_code = armature::board_voting::EInsufficientVotingWeight`). Two older tests use a number and a location (`abort_code = 6, location = armature::board_voting` and `abort_code = 15, location = armature::ou` in `armature_proposals::admin_ops_tests`); new tests use the named form.
- A permission denial aborts with `proposal::EPermissionDenied` whichever module the mutator lives in. `ou` mutators first abort with `ou::EOUIdMismatch` for another OU's request; the vault, charter and emergency modules use their own OU-mismatch codes.
- Checks without a named code use a bare `#[expected_failure]`: `capability_vault::destroy_empty` and `emergency::destroy` assert without a code, and a missing dynamic field aborts inside Sui's `dynamic_field`. The four `ProposalConfig` bound tests in `ou_tests` also use a bare `expected_failure`, though `proposal::EInvalidQuorum`, `EInvalidApprovalThreshold` and `EInvalidExpiryMs` exist.
- When the aborting call leaves hot potatoes or shared objects in scope, the test ends with `abort 0` to satisfy the type checker. The expected abort fires first. `gate_tests` and `permissions_tests` use this pattern.

## Scenario and Clock

- `test_scenario::begin(CREATOR)`, `scenario.next_tx(addr)` (returns the previous transaction's effects), `scenario.take_shared<T>()` / `take_shared_by_id<T>(id)`, `test_scenario::return_shared(obj)`, `scenario.take_from_sender<T>()` / `return_to_sender(obj)`, `scenario.end()`.
- Time comes from `clock::create_for_testing(scenario.ctx())`, set absolutely with `clock.set_for_testing(ms)` and dropped with `clock.destroy_for_testing()`. Unit-level modules (`emergency_tests`, `capability_vault_tests`) use `tx_context::dummy()` and no scenario.
- Hot potatoes must be closed before the transaction block ends: tickets by the type's handler or `ticket.discharge(permit)`, raw requests by `proposal::consume` (framework tests only) or `proposal::consume_execution_request_for_testing`. See `01_test_helpers.md`.
- Leftover objects are dropped with `sui::test_utils::destroy`.

## Running

```bash
sui move test --path packages/armature_framework --build-env testnet
sui move test --path packages/armature_framework --build-env testnet proposal_tests   # name filter
```

Locally, `--build-env testnet` is needed: the packages declare only testnet-style environments. The compiler prints ANSI colour codes even when piped.

## CI

`.github/workflows/pr.yml` runs on pull requests to `main` that touch `packages/**` or the workflows:

1. `prettier-move -c` on `armature_framework` and `armature_proposals` (formatting check).
2. `python3 scripts/check_request_gates.py` (below).
3. `sui move build --path <pkg>` for every package.
4. `sui move test --path <pkg> -i 100000000 --force` for every package. The instruction limit is why `ou_tests::test_root_size_independent_of_board_size` adds 20 members, not 100.

### CI Gate Check

`scripts/check_request_gates.py` scans `packages/armature_framework/sources`. It fails when:

- a `public fun` takes an `ExecutionRequest` but calls neither `assert_permitted(` nor `assert_controller(` and is not on its reviewed allowlist (accessors, the checks themselves, `P`-scoped type-state, `controller::privileged_consume`, two test-only helpers);
- a gated function has no test in `packages/armature_framework/tests/gate_tests.move` whose name starts with `<function>_` (so every new gated mutator needs a denial test there);
- `proposal::ticket_request`, `discharge`, `discharge_returning_payload` or `external_execution::ticket_from_cap(_readonly)` stops taking `Permit<P>`.

On the same tree it reports `28 gated functions, 18 allowed without a gate, 5 Permit-gated ticket entry points`. Each `gate_tests` test builds a request with every bit except the one the mutator needs (`permissions::all() ^ missing`) and expects `proposal::EPermissionDenied` (`ou::ENotPrivileged` for the controller-only `set_controller_paused` and `clear_controller`); three more expect `proposal::EBorrowScopeDenied` from a request holding every bit and an empty borrow scope.

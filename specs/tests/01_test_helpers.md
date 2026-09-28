# Test Helpers

There is no shared `test_helpers` module. Tests get their setup from three places:

1. `#[test_only]` seams in the package sources (mostly `armature_framework`), usable from any package's tests.
2. `public(package)` framework functions, which framework test modules can call because they belong to the `armature` package.
3. Small helpers and macros that each test module defines for itself.

A fourth tool, `std::internal::permit<P>()`, is what lets a test close the tickets of the payload types it defines.

---

## 1. Test-Only Seams in the Sources

### `armature::dao`

| Helper | Does | Still enforced |
|---|---|---|
| `dao.test_enable_type<T>(display_key: ascii::String, config: ProposalConfig)` | Adds a slot for `T` with no request, no floors and no grant rules. Emits `TypeSlotAdded`. | A framework type gets its fixed bits and scope (`dao::EFixedPermissions` for any other non-empty set); `dao::ETypeAlreadyEnabled`, `EDisplayKeyTaken`, `EEmptyDisplayKey`. |
| `dao.test_update_config<T>(config: ProposalConfig)` | Replaces `T`'s config with no floors and no grant rules. No event. | Fixed framework bits; `dao::ETypeNotEnabled` if `T` has no slot. |
| `dao.test_disable_type<T>()` | Removes `T`'s slot and display key. Emits `TypeSlotRemoved`. | `dao::ETypeNotEnabled` if absent. |

`test_enable_type` is the usual way to give a test DAO a type (about 90 call sites in 20 modules). Because it skips the floors, a test can seed a config the production paths would refuse. Some tests rely on that on purpose: `armature_proposals::admin_ops_tests::enable_proposal_type_submission_floor_rejects_below_80_percent` lowers `EnableProposalType` below 80% with `test_update_config` to reach the submission check. Tests of the floors themselves must go through `dao::enable_proposal_type` / `update_proposal_config` with a request (`permissions_tests`) or through the handlers (`armature_proposals::admin_ops_tests`).

### `armature::proposal`

| Helper | Returns |
|---|---|
| `new_execution_request_for_testing<P>(dao_id, proposal_id)` | Unprivileged request carrying every bit (`permissions::all()`) and an empty borrow scope |
| `new_permitted_request_for_testing<P>(dao_id, proposal_id, bits)` | Unprivileged request carrying exactly `bits`, empty scope |
| `new_privileged_request_for_testing<P>(dao_id, proposal_id)` | Privileged request, 0 bits; passes every bit and scope check on `dao_id` |
| `with_borrow_scope_for_testing<P>(req, scope)` | `req` with its borrow scope replaced |
| `consume_execution_request_for_testing<P>(req)` | Destroys any request; tests outside the framework package need it because `proposal::consume` is `public(package)` |
| `new_standalone_ticket_for_testing<P: store>(dao_id, proposal_id, payload, yes_weight, total_snapshot_weight)` | Standalone ticket, every bit, empty scope; for handlers that check vote weights (e.g. `EnableBypassType`'s 80% floor) |
| `new_composite_ticket_for_testing<P: store>(dao_id, proposal_id, payload)` / `new_external_ticket_for_testing` | Composite / External ticket, every bit, empty scope |
| `privileged_create_for_testing<P: store>(dao_id, type_key, proposer, metadata_ipfs, payload, ctx)` | Standalone ticket, every bit, zero weights, under a fresh ID; emits `ProposalCreated` and `ProposalExecuted`, creates no object |
| `new_external_execution_cap_for_testing<P>(dao_id, ctx)` / `destroy_external_execution_cap_for_testing<P>(cap)` | An `ExternalExecutionCap<P>` without an `EnableBypassType` vote, and its disposal |
| `created_event_proposal_id`, `created_event_proposer`, `created_event_metadata_ipfs`, `payload_event_proposal_id`, `payload_event_bcs`, `vote_event_weight`, `passed_event_yes_weight`, `executed_event_proposal_id` | Field readers for events returned by `sui::event::events_by_type<T>()` |

A request from `new_execution_request_for_testing` or one of the synthesized tickets holds every bit, so a test built on it says nothing about permission bits. Use `new_permitted_request_for_testing` to choose them.

### `armature::emergency` and `armature::capability_vault`

| Helper | Does |
|---|---|
| `emergency::new_for_testing(dao_id, ctx)` | A standalone `EmergencyFreeze` (7-day max, the two mandatory exemptions) |
| `emergency::new_admin_cap_for_testing(dao_id, ctx)` | A `FreezeAdminCap` for any DAO ID |
| `freeze.add_exempt_type_for_testing<T>()` | Exempts `T` with no request |
| `freeze.remove_exempt_type_for_testing<T>()` | Un-exempts `T`; still aborts `emergency::EMandatoryExemptType` for the mandatory pair |
| `capability_vault::new_subdao_control_for_testing(subdao_id, ctx)` | A loose `SubDAOControl` for any ID |
| `vault.store_cap_for_testing<T>(cap)` | Stores a cap with no request (same as the package-internal `store_cap_init`) |

### Other packages

| Helper | Does |
|---|---|
| `armature_world_bridge::tribe_allowlist::new_for_testing(enabled, tribe_ids)` | A `TribeIdAllowlist` value, duplicates dropped |
| `armature_external_type_tests::rebalance::request_for_testing<T>(&ticket)` | The ticket's request as `Rebalance`'s own module sees it; lets tests show that permission bits still bound a faulty handler in that module |

---

## 2. Package-Internal Functions Used by Framework Tests

Framework test modules (`armature::*_tests`) are part of the `armature` package, so they can call its `public(package)` functions. Tests in the other packages cannot.

| Function | Used for |
|---|---|
| `proposal::create<P>(dao_id, type_key, proposer, metadata_ipfs, payload, config, &governance, is_dao_active, clock, ctx)` | A shared `Proposal<P>` with any config and label and no slot (`proposal_tests`; the `submit_proposal_with_config` helper in `board_voting_tests`) |
| `prop.execute(&governance, last_executed_ms, execution_paused, permissions, borrow_scope, clock, ctx): (P, ExecutionRequest<P>)` | The checks behind `ticket_from_vote`, driven with explicit inputs (`proposal_tests`) |
| `proposal::consume(req)` | Destroy a raw request |
| `dao.governance_mut()` with `set_board`, `add_board_member(s)`, `remove_board_member(s)` | Change the roster without a proposal (`proposal_tests` roster tests, `dao_tests`) |
| `capability_vault::new`, `vault.store_cap_init(cap)`, `treasury_vault::new`, `treasury_vault::destroy_empty`, `dao::create_returning_vault` | Standalone vaults and the package-internal constructors |
| `<type module>::permit()` | Each framework type module has `public(package) fun permit(): Permit<T>`; a framework test can close a framework type's ticket without its handler (`submit_vote_execute_tests` uses `armature::enable_proposal_type::permit()`). `armature_proposals` tests do the same for that package's types (`armature_proposals::send_coin::permit()` in its `composite_tests`). |

---

## 3. Permits in Tests

`ticket_request`, `discharge` and `discharge_returning_payload` take `std::internal::Permit<P>`, and `internal::permit<P>()` compiles only inside the module that defines `P`. So a test that wants to hold or close a ticket itself defines its own payload type:

```move
#[test_only]
module armature::board_voting_tests;

public struct TestPayload has drop, store { value: u64 }

// ...
let ticket = board_voting::ticket_from_vote(&mut dao, prop, &freeze, &clock, scenario.ctx());
assert!(ticket.ticket_payload().value == 7);   // anyone may read the payload
ticket.discharge(internal::permit());           // only this module can mint Permit<TestPayload>
```

Test-local payload types in use: `TestPayload`, `AltPayload`, `FastPayload`, `Probe`, `Scoped`, `Granted` / `Ungranted` / `Target`, `Order<T>`, `CredA` / `CredB` markers, and `ControllerOp` (an `armature_proposals` test type granted `VAULT_BORROW` to loan a `SubDAOControl`). A ticket for a type defined elsewhere is closed by that type's handler, e.g. `board_ops::execute_set_board(&mut dao, ticket)`.

---

## 4. Per-Module Helpers

Each module repeats a small setup. The typical shape:

```move
fun create_dao(scenario: &mut test_scenario::Scenario) {
    scenario.next_tx(CREATOR);
    let init = governance::init_board(vector[CREATOR, MEMBER_B]);
    dao::create(&init, string::utf8(b"Test DAO"), string::utf8(b"https://example.com/logo.png"), scenario.ctx());
}

/// Submit `payload` as a two-PTB proposal and vote it through (single-member board).
fun submit_and_pass<P: store + drop>(scenario: &mut Scenario, clock: &mut Clock, payload: P) {
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        board_voting::submit_proposal(&dao, option::none(), payload, clock, scenario.ctx());
        ts::return_shared(dao);
    };
    scenario.next_tx(CREATOR);
    {
        let mut prop = scenario.take_shared<Proposal<P>>();
        let dao = scenario.take_shared<DAO>();
        board_voting::vote(&mut prop, &dao, true, clock, scenario.ctx());
        ts::return_shared(dao);
        ts::return_shared(prop);
    };
}
```

(Adapted from `submit_and_pass` in `external_type_lifecycle_tests`, which also advances the clock between transactions. `dao::create` shares the DAO and its four companions and transfers the `FreezeAdminCap` to the sender.)

Execution then happens in its own transaction:

```move
scenario.next_tx(CREATOR);
{
    let mut dao = scenario.take_shared<DAO>();
    let prop = scenario.take_shared<Proposal<SetBoard>>();   // by value: execution deletes it
    let freeze = scenario.take_shared<EmergencyFreeze>();
    let ticket = board_voting::ticket_from_vote(&mut dao, prop, &freeze, &clock, scenario.ctx());
    board_ops::execute_set_board(&mut dao, ticket);           // the handler closes the ticket
    test_scenario::return_shared(freeze);
    test_scenario::return_shared(dao);
};
```

Notable local helpers:

| Module | Helper | Purpose |
|---|---|---|
| `proposal_tests` | `create_test_dao`, `create_test_proposal` | Board `[@0xA, @0xB]`; a `Proposal<TestPayload>` made with `proposal::create` (50% / 50%, 1-hour expiry, labelled "SetBoard") |
| `board_voting_tests` | `create_dao_with_members`, `enable_test_payload`, `submit_proposal_with_config`, `vote_as`, `passed_test_proposal` | Boards of 1–10 members; proposals with a chosen quorum and threshold |
| `submit_vote_execute_tests` | `create_single_member_dao` (and two-, three-member), `enable_fast_type(quorum, threshold, delay, cooldown)`, `call_sve_drop_ticket` | Atomic-path setups |
| `gate_tests` | `all_but(dao, missing)`, macro `run!` | A request with every bit but one; a fresh DAO's five shared objects handed to a closure that must abort |
| `permissions_tests` | macro `with_dao!`, `permitted<P>`, `enable_target<P>`, `update_target<P>` | Call the `dao` registry mutators with a request of type `P` |
| `borrow_scope_tests` | `setup(scope)`, `execute_and_borrow<T>` | A `VAULT_BORROW` type with a chosen scope; borrow through a real atomic ticket |
| `capability_vault_tests` | `setup`, `make_req`, `setup_two_vaults` | Standalone vaults; a request with every bit and scope `[TestCap]` |
| `treasury_vault_tests`, `treasury_vault_multicoin_tests` | `create_test_execution_request`, `make_req` | A request with every bit for the vault's DAO |
| `emergency_tests` | `setup`, `teardown` | Standalone `EmergencyFreeze`, `FreezeAdminCap` and `Clock` |
| `freeze_path_tests` | `setup`, `run_atomic<T>`, `run_bypass<T>`, `run_two_ptb<T>` | One payload through each execution path |
| `freeze_ops_tests` | `enable_type<T>`, `submit_exempt_types` | Freeze-governance proposals end to end |
| `lifecycle_ops_tests` | macro `with_transfer!` | Three DAOs and a begun `AssetTransfer` |
| `external_type_lifecycle_tests` | `submit_and_pass<P>`, `enable_via_vote<T>`, `enable_bypass_via_vote<T>`, `unfreeze_via_vote<T>`, `admin_freeze<T>`, `execute_two_ptb/atomic/bypass<T>`, macro `with_rebalance_request!` | Production handlers only; no registry seams |
| `armature_proposals::*` | `create_dao`, `enable_*_type`, `fund_treasury_sui`, `vote_yes`, `run_enable_type<T>`, `pass_then_freeze` | Per-handler setups |

### Why these exist

| Helper | Rationale |
|---|---|
| `test_enable_type` / `test_update_config` | Enabling a type through an `EnableProposalType` vote takes three transactions (submit, vote, execute); most tests only need the slot. |
| Synthesized requests and tickets | Mutators and handlers can be tested without minting a real request; `new_permitted_request_for_testing` and `new_privileged_request_for_testing` make the permission model testable in isolation. |
| `proposal::create` / `prop.execute` in `proposal_tests` | Lifecycle rules (voting window, execution window, cooldown, eligibility) can be driven with explicit configs and timestamps, independent of any slot. |
| `governance_mut()` | Roster-version and eligibility tests need board changes between a proposal's creation and its vote. |
| Local payload types | Only the defining module can mint a `Permit`, so tests that inspect or close tickets need their own types. |

---

## 5. Suggested, Not in the Suite

The per-module helpers repeat `create_dao`, `submit_and_pass` and the execute-in-its-own-transaction block. A `#[test_only]` module in the framework's sources could host them, since test-only code of a dependency is available to the dependent packages' tests (as `proposal::new_permitted_request_for_testing` is to `armature_proposals`). None exists today; the specs in this directory do not assume one.

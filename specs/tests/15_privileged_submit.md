# Privileged Submit Tests

## Summary

`controller::privileged_submit` is the controller override: it lets the holder of a SubDAO's `SubDAOControl` act on that SubDAO without the SubDAO's vote.

```move
public fun privileged_submit<P: store + drop>(
    control: &SubDAOControl,
    subdao: &DAO,
    type_key: std::ascii::String,   // free-form label recorded in the events
    metadata_ipfs: Option<String>,
    payload: P,
    ctx: &mut TxContext,
): ExecutionRequest<P>

public fun privileged_consume<P>(req: ExecutionRequest<P>, control: &SubDAOControl)
```

- **Checks:** `controller::assert_registered_control` — `control.subdao_id() == subdao.id()` (`controller::EControlMismatch`) and `subdao.controller_cap_id() == some(object::id(control))` (`controller::ENotController`), so a control minted elsewhere or retired by `clear_controller` is refused — and the SubDAO is Active (`controller::EDAONotActive`). Nothing else is checked: not `controller_paused`, not the SubDAO's freezes, and not whether `P` has a slot on the SubDAO.
- **No `Proposal` object.** The proposal ID is minted from `ctx.fresh_object_address()`. The call emits `ProposalCreated`, `ProposalPayloadCreated` (the payload's BCS) and `ProposalExecuted`, with no `VoteCast` or `ProposalPassed`; these events are the audit record. The payload is dropped after serialisation (hence `P: drop`). There is no clock argument.
- **Privileged request.** The returned `ExecutionRequest<P>` carries `permissions = 0`, an empty borrow scope and `privileged = true`. It passes every permission-bit check (`proposal::req_has_permission`) and every borrow-scope check (`proposal::req_may_borrow`), and it may change a type's bits or scope without the grant rules. Mutators that act on a DAO's objects check the request's DAO first, so it works only on that SubDAO's objects; the exception is the sending request of `receive_cap_authorized`, which checks only the bit (`capability_vault::receive_cap` is `public(package)`, and its public wrapper `controller::receive_cap_from_controller` ties the request's DAO to the controller vault). Floors and fixed framework bits still apply. `dao::set_controller_paused` and `dao::clear_controller` accept only privileged requests (`dao::assert_controller`, `dao::ENotPrivileged`).
- **Closing.** A privileged request is a bare hot potato, not a ticket. `privileged_consume(req, &control)` destroys it after checking `req`'s DAO against `control.subdao_id()` (`controller::EControlMismatch`).

The `SubDAOControl` sits in the controller's `CapabilityVault`, so a controller-side handler first spends its own ticket to loan it: `capability_vault::loan_cap<SubDAOControl, P>` needs `VAULT_BORROW` and `SubDAOControl` in the ticket type's borrow scope, and returns the control with a `CapLoan` hot potato that only `return_cap` (cap and vault IDs checked: `capability_vault::ECapIdMismatch`, `EVaultIdMismatch`) can close. The PTB therefore holds three hot potatoes at once, the controller's ticket, the `CapLoan` and the SubDAO's privileged request, and cannot complete until each is closed.

First-party users, all proposed and voted on the controller: `SpinOutSubDAO` (framework `lifecycle_ops`), `PauseSubDAOExecution` / `UnpauseSubDAOExecution` and `ControllerBatchAddMembers` / `ControllerBatchRemoveMembers` (`armature_proposals::subdao_ops`). `ReclaimCapFromSubDAO` uses `controller::privileged_extract` instead, which applies the same `assert_registered_control` (`13_subdao_ops.md`).

Real suites: `packages/armature_framework/tests/controller_tests.move` (5), plus tests cited from `cross_dao_auth_tests.move`, `permissions_tests.move`, `borrow_scope_tests.move`, `gate_tests.move`, `migration_tests.move`, `subdao_ops_tests.move` and `lifecycle_tests.move`.

## Test Matrix

| Test | Expected |
|------|----------|
| `controller_tests::privileged_submit_records_execution_in_events` | Request bound to the SubDAO; no object created; exactly 3 events (`ProposalCreated` with the metadata, `ProposalPayloadCreated` with the payload BCS, `ProposalExecuted`) under the request's proposal ID |
| `controller_tests::privileged_submit_rejects_wrong_control` | Control for another DAO: Abort `controller::EControlMismatch` |
| `cross_dao_auth_tests::forged_control_cannot_privileged_submit` | Another DAO mints a control naming the SubDAO (`create_subdao_control`) and calls `privileged_submit`: Abort `controller::ENotController` |
| `cross_dao_auth_tests::cleared_controller_rejects_old_control` | After `clear_controller`, the old control: Abort `controller::ENotController` |
| `controller_tests::privileged_consume_rejects_wrong_control` | Request closed with a control for another DAO: Abort `controller::EControlMismatch` |
| `controller_tests::privileged_submit_rejects_inactive_subdao` | SubDAO Migrating: Abort `controller::EDAONotActive` |
| `controller_tests::authorize_execution_blocks_when_controller_paused` | The SubDAO's own vote path is blocked while paused: Abort `board_voting::EControllerPaused` |
| `permissions_tests::only_controller_requests_are_privileged` | `privileged_submit` mints a privileged request; the vote and bypass paths do not |
| `permissions_tests::assert_permitted_passes_privileged_request` | A privileged request passes every bit, even for a type with no slot |
| `permissions_tests::assert_permitted_privileged_request_is_dao_scoped` | Used on another DAO: Abort `dao::EDAOIdMismatch` |
| `permissions_tests::privileged_request_may_change_bits` | May change a type's bits without the grant rules |
| `permissions_tests::composite_payload_cannot_hold_bits` | Fixed framework bits hold even for a privileged request: Abort `dao::EFixedPermissions` |
| `borrow_scope_tests::privileged_request_ignores_scope` | Passes the borrow-scope check |
| `gate_tests::set_controller_paused_needs_privileged_request` | Unprivileged request with every bit: Abort `dao::ENotPrivileged` |
| `gate_tests::clear_controller_needs_privileged_request` | Abort `dao::ENotPrivileged` |
| `gate_tests::loan_cap_needs_vault_borrow` | Controller ticket without VAULT_BORROW cannot loan the control: Abort `proposal::EPermissionDenied` |
| `gate_tests::loan_cap_scope_denied_with_all_bits` | Cap type not in scope: Abort `proposal::EBorrowScopeDenied` |
| `migration_tests::controller_set_board_via_privileged_submit` | Dual hot potato: loan control, privileged SetBoard diff on the SubDAO, consume, return, discharge; SubDAO board now includes CREATOR |
| `subdao_ops_tests::pause_and_unpause_subdao_e2e` | Pause, then unpause, each through a privileged request; the unpause runs while the SubDAO is paused |
| `subdao_ops_tests::controller_batch_add_members_e2e` / `controller_batch_remove_members_e2e` | SubDAO board changed through privileged requests |
| `migration_tests::create_subdao_and_spin_out_e2e` | SpinOutSubDAO: privileged `clear_controller` and three `enable_proposal_type` calls on the SubDAO |
| `lifecycle_tests::medium_enterprise_lifecycle` (step 7) | Privileged SetBoard diff removes a member from a SubDAO in the same PTB as a freeze |
| `test_privileged_request__floors_still_apply` (planned) | `subdao.enable_proposal_type<SpawnDAO, P>(key, config_below_8000, &priv_req)`: Abort `dao::EThresholdBelowMinimum` |
| `test_privileged_submit__ignores_subdao_freeze` (planned) | `P` frozen on the SubDAO's `EmergencyFreeze`: `privileged_submit<P>` still returns a request (no freeze check on this path) |

## Tests

---

### Records the execution in events only

**Requirement:** `privileged_submit` creates no object and emits exactly `ProposalCreated`, `ProposalPayloadCreated` and `ProposalExecuted` under a fresh proposal ID, which is also the request's `req_proposal_id()`.

**Why it matters:** The controller's own vote already approved the action; a second vote on the SubDAO would defeat hierarchical control. The events keep the override auditable on the SubDAO without leaving an object whose storage deposit nobody reclaims.

```move
// controller_tests::privileged_submit_records_execution_in_events
let req = controller::privileged_submit(
    &control,
    &subdao,
    b"TestPayload".to_ascii_string(),
    option::some(string::utf8(b"Privileged test")),
    TestPayload { value: 42 },
    scenario.ctx(),
);
assert!(req.req_dao_id() == subdao_id);

let created = event::events_by_type<ProposalCreated>();
assert!(created.length() == 1);
assert!(created[0].created_event_proposal_id() == req.req_proposal_id());
let payloads = event::events_by_type<ProposalPayloadCreated>();
assert!(payloads[0].payload_event_bcs() == std::bcs::to_bytes(&TestPayload { value: 42 }));
let executed = event::events_by_type<ProposalExecuted>();
assert!(executed[0].executed_event_proposal_id() == req.req_proposal_id());

controller::privileged_consume(req, &control);
...
let effects = scenario.next_tx(CREATOR);
assert!(effects.created().is_empty());
assert!(effects.num_user_events() == 3);
```

`TestPayload` has no slot on the SubDAO: the type key is only a label.

---

### Requires the SubDAO's registered control and an Active SubDAO

**Requirement:** `privileged_submit` aborts with `controller::EControlMismatch` unless `control.subdao_id() == subdao.id()`, with `controller::ENotController` unless `control` is the SubDAO's `controller_cap_id`, and with `controller::EDAONotActive` if the SubDAO is Migrating. `privileged_consume` aborts with `controller::EControlMismatch` unless the request is for the control's SubDAO.

**Why it matters:** The `SubDAOControl` is the proof of authority over one SubDAO. Without the checks, any DAO holding any control could act on any other DAO, or mint a control naming a DAO it does not control.

```move
#[test, expected_failure(abort_code = controller::EControlMismatch)]
fun privileged_submit_rejects_wrong_control() {
    // A SubDAO, and a control created for a different ID
    // (capability_vault::new_subdao_control_for_testing).
    let req = controller::privileged_submit(&wrong_control, &subdao, key, option::none(), payload, ctx);
    ...
}
```

---

### The privileged request passes bits and scope, confined to its SubDAO by DAO checks

**Requirement:** A privileged request passes `proposal::assert_permitted` for any bits and `proposal::assert_may_borrow` for any cap type. DAO-ID checks still run: using it on another DAO's objects aborts (`dao::EDAOIdMismatch` in `dao`; the treasury, capability vault, charter and freeze each check their own DAO). `capability_vault::receive_cap` is the exception: it checks no DAO, only that the request carries VAULT_EXTRACT, which a privileged request does. Config writes through it skip the grant rules but not the floors or the fixed framework bits.

**Why it matters:** The controller's authority over a SubDAO is complete but confined to that SubDAO. The permission and borrow-scope model otherwise applies unchanged.

`permissions_tests::assert_permitted_passes_privileged_request`, `assert_permitted_privileged_request_is_dao_scoped`, `privileged_request_may_change_bits`, `composite_payload_cannot_hold_bits`, `only_controller_requests_are_privileged`, and `borrow_scope_tests::privileged_request_ignores_scope`. The floor case is planned (`test_privileged_request__floors_still_apply`); `SpinOutSubDAO` relies on it, since the configs in its payload must meet 8000 for the three types it enables.

---

### Controller-only mutators

**Requirement:** `dao::set_controller_paused` and `dao::clear_controller` require a privileged request (`dao::ENotPrivileged` for any other request, whatever its bits).

**Why it matters:** No permission bit can grant pause or release of a SubDAO: only its controller can, through a vote on the controller.

`gate_tests::set_controller_paused_needs_privileged_request` and `clear_controller_needs_privileged_request` pass a request holding every bit and expect `dao::ENotPrivileged`.

---

### Dual hot potato

**Why it matters:** The controller-side PTB holds its own ticket, the `CapLoan` and the SubDAO's privileged request at once. All three are hot potatoes, so the transaction succeeds only if the handler spends and closes each one; the control cannot be kept and the SubDAO request cannot leak.

```move
// migration_tests::controller_set_board_via_privileged_submit (execution step)
// ControllerOp is a test type enabled on the parent with
// type_permissions::subdao_control() and type_permissions::subdao_control_scope().
let parent_req = board_voting::ticket_from_vote(&mut parent_dao, parent_proposal, &parent_freeze, &clock, scenario.ctx());

// 1. Loan the SubDAOControl (VAULT_BORROW, SubDAOControl in scope)
let (control, loan) = vault.loan_cap<SubDAOControl, ControllerOp>(
    control_cap_id,
    parent_req.ticket_request(internal::permit()), // the test module defines ControllerOp
);

// 2. Privileged request on the SubDAO
let priv_req = controller::privileged_submit(
    &control,
    &subdao,
    b"SetBoard".to_ascii_string(),
    option::some(string::utf8(b"Controller sets SubDAO board")),
    set_board::new(vector[CREATOR], vector[]),
    scenario.ctx(),
);

// 3. Apply the change with the privileged request
dao::set_board_governance(&mut subdao, vector[CREATOR], vector[], &priv_req);

// 4. Close everything
controller::privileged_consume(priv_req, &control);
vault.return_cap(control, loan);
parent_req.discharge(internal::permit());

assert!(subdao.governance().is_board_member(SUBDAO_MEMBER));
assert!(subdao.governance().is_board_member(CREATOR));
```

The test's comment notes that a parent ticket of another type (for example SetBoard) is denied the loan; `gate_tests::loan_cap_needs_vault_borrow` and `loan_cap_scope_denied_with_all_bits` cover both denials.

---

### First-party controller handlers

**Why it matters:** These are the supported ways a controller acts on a SubDAO; each runs the dual-hot-potato sequence inside one handler, so the PTB author never holds the privileged request.

| Handler | SubDAO-side effect on the privileged request | Test |
|---------|---------------------------------------------|------|
| `subdao_ops::execute_pause_subdao_execution` | `set_controller_paused(true)` | `subdao_ops_tests::pause_and_unpause_subdao_e2e` |
| `subdao_ops::execute_unpause_subdao_execution` | `set_controller_paused(false)` | `subdao_ops_tests::pause_and_unpause_subdao_e2e` |
| `subdao_ops::execute_controller_batch_add_members` | `add_board_members_governance` | `subdao_ops_tests::controller_batch_add_members_e2e` |
| `subdao_ops::execute_controller_batch_remove_members` | `remove_board_members_governance` | `subdao_ops_tests::controller_batch_remove_members_e2e` |
| `lifecycle_ops::execute_spin_out_subdao` | `clear_controller`, then `enable_proposal_type` for SpawnDAO, SpinOutSubDAO, CreateSubDAO | `migration_tests::create_subdao_and_spin_out_e2e` |

---

### The control returns to the parent vault

**Requirement:** The control is loaned, never extracted, by every handler above except `SpinOutSubDAO`, which returns it and then destroys it with `destroy_subdao_control`.

**Why it matters:** If the control stayed out of the vault the parent would lose future control of the SubDAO.

This is structural: `CapLoan` has no abilities, and only `capability_vault::return_cap` consumes it, after checking the cap's ID and the vault's ID. `migration_tests::create_subdao_and_spin_out_e2e` shows the one intended exception: after spin-out the parent vault is empty.

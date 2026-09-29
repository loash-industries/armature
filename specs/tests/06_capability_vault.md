# Capability Vault Tests

## Summary

`capability_vault.move` stores arbitrary `key + store` capabilities as dynamic object fields keyed by object ID, with three registries: `cap_ids` (every stored ID), and `cap_types` and `ids_by_type`, keyed by the cap type's name string (`type_name::with_defining_ids<T>()`). Every function that takes an `ExecutionRequest` checks a permission bit, and all but `receive_cap` first check the request's OU against the vault's (`capability_vault::EOUIdMismatch`); borrowing and loaning also need the cap's type in the request's borrow scope. A loan hands out the cap with a `CapLoan` hot potato. `privileged_extract` takes a `SubOUControl` instead of a request. `receive_cap`, `privileged_extract` and `create_subou_control` are `public(package)`; other packages reach the first two through `controller::receive_cap_from_controller` and `controller::privileged_extract`, which check the SubOU's registered controller.

These tests verify the gates, the borrow scope, registry bookkeeping, loan semantics, cross-OU receipt, the controller reclaim path and the bypass-cap lookup.

## Test Matrix

**Gates**

| Test | Expected | Where |
|------|----------|-------|
| `test_store_cap_requires_execution_request` | `store_cap` with a request for the vault's OU stores the cap | `capability_vault_tests` |
| `test_borrow_cap_requires_execution_request` | `borrow_cap` with `VAULT_BORROW` and the type in scope returns the cap | `capability_vault_tests` |
| `test_loan_cap_requires_execution_request` | `loan_cap` then `return_cap` | `capability_vault_tests` |
| `test_extract_cap_requires_execution_request` | `extract_cap` returns the cap | `capability_vault_tests` |
| `store_cap_needs_vault_store` | Every bit except `VAULT_STORE`: `proposal::EPermissionDenied` | `gate_tests` |
| `borrow_cap_needs_vault_borrow`, `borrow_cap_mut_needs_vault_borrow`, `loan_cap_needs_vault_borrow` | Every bit except `VAULT_BORROW`: `proposal::EPermissionDenied` | `gate_tests` |
| `extract_cap_needs_vault_extract`, `create_subou_control_needs_vault_extract`, `destroy_subou_control_needs_vault_extract` | Every bit except `VAULT_EXTRACT`: `proposal::EPermissionDenied` | `gate_tests` |
| `receive_cap_needs_vault_extract_on_sender`, `receive_cap_authorized_needs_vault_extract_on_sender`, `receive_cap_authorized_needs_vault_store_on_receiver` | `proposal::EPermissionDenied` | `gate_tests` |
| `test_vault_other_ou_request_aborts` | A request for another OU: `capability_vault::EOUIdMismatch` | planned |
| `test_store_cap_init_only_during_ou_creation` | `store_cap_init` stores without a request; it is `public(package)` | `capability_vault_tests` (structural) |

**Borrow scope**

| Test | Expected | Where |
|------|----------|-------|
| `borrow_cap_scope_denied_with_all_bits`, `borrow_cap_mut_scope_denied_with_all_bits`, `loan_cap_scope_denied_with_all_bits` | Every bit and an empty scope: `proposal::EBorrowScopeDenied` | `gate_tests` |
| `request_carries_slot_scope_and_borrows_in_scope` | A real ticket carries its slot's scope and borrows a cap in it | `borrow_scope_tests` |
| `borrow_outside_scope_aborts` | `VAULT_BORROW` with scope `[CapA]` borrowing a `CapB`: `proposal::EBorrowScopeDenied` | `borrow_scope_tests` |
| `empty_scope_borrows_nothing` | `proposal::EBorrowScopeDenied` | `borrow_scope_tests` |
| `privileged_request_ignores_scope` | A privileged request borrows any cap | `borrow_scope_tests` |
| `spin_out_subou_scope_is_subou_control` | `SpinOutSubOU`'s fixed scope is `[SubOUControl]` | `borrow_scope_tests` |
| `meta_type_may_change_scope` | After `UpdateProposalConfig` moves the scope, the next request borrows the new type | `borrow_scope_tests` |

**Registries**

| Test | Expected | Where |
|------|----------|-------|
| `test_store_updates_cap_types_and_cap_ids` | Type and ID registered | `capability_vault_tests` |
| `test_extract_removes_from_cap_types_and_cap_ids` | Type and ID deregistered | `capability_vault_tests` |
| `test_store_multiple_same_type_updates_ids` | Two IDs under one type | `capability_vault_tests` |
| `test_extract_last_of_type_removes_type` | Type stays until its last cap is extracted | `capability_vault_tests` |
| `test_ids_for_type__returns_correct_list` | IDs per type, types kept apart | `capability_vault_tests` |
| `test_contains__returns_true_for_stored_cap`, `test_contains__returns_false_for_missing_cap` | `contains` by ID | `capability_vault_tests` |
| `test_borrow_cap__returns_immutable_reference` | `borrow_cap` returns `&T` with the stored data | `capability_vault_tests` |

**Loans**

| Test | Expected | Where |
|------|----------|-------|
| `CapLoan` has no abilities | A loan must be returned in the same PTB | structural |
| `test_loan_does_not_update_registries` | During a loan the cap is still listed | `capability_vault_tests` |
| `test_loan_and_return_restores_capability` | After `return_cap` the cap borrows again | `capability_vault_tests` |
| `test_loan_cap_not_borrowable_during_loan` | The cap's field is gone during the loan: borrowing aborts inside Sui's dynamic-field code (bare `expected_failure`) | `capability_vault_tests` |
| `test_return_wrong_cap_aborts` | Returning a different cap against the loan: `capability_vault::ECapIdMismatch` | planned |
| `test_return_to_wrong_vault_aborts` | Returning the cap to another vault: `capability_vault::EVaultIdMismatch` | planned |

**Cross-OU receipt**

| Test | Expected | Where |
|------|----------|-------|
| `receive_cap_unguarded_accepts_any_req_ou_id` | `receive_cap` (package-only) does not check the receiving vault's OU | `capability_vault_tests` |
| `unrelated_ou_cannot_deposit_into_subou_vault` | `receive_cap_from_controller` from an OU whose vault lacks the SubOU's registered control: `controller::ENotController` | `cross_ou_auth_tests` |
| `cannot_deposit_into_top_level_ou_vault` | Target has no controller: `controller::ENotController` | `cross_ou_auth_tests` |
| `controller_vault_must_match_request` | `controller_vault` is not the request's OU's: `controller::EControlMismatch` | `cross_ou_auth_tests` |
| `transfer_cap_to_subou_e2e` | The controller's `TransferCapToSubOU` deposits through `receive_cap_from_controller` | `armature_proposals::subou_ops_tests` |
| `receive_cap_authorized_succeeds_with_matching_recv_ou` | Sender and receiver requests both present | `capability_vault_tests` |
| `receive_cap_authorized_aborts_on_recv_ou_mismatch` | Receiver request for another OU: `capability_vault::EOUIdMismatch` | `capability_vault_tests` |

**Controller reclaim and SubOUControl**

| Test | Expected | Where |
|------|----------|-------|
| `test_privileged_extract_requires_subou_control`, `test_privileged_extract_verifies_subou_id` | A `SubOUControl` whose `subou_id` is the vault's OU extracts the cap | `capability_vault_tests` |
| `test_privileged_extract_succeeds` | ... and the registries drop it | `capability_vault_tests` |
| `test_privileged_extract_wrong_subou_aborts` | `control.subou_id` is another OU: `capability_vault::ENotController` | `capability_vault_tests` |
| `registered_control_privileged_extract_succeeds` | `controller::privileged_extract` with the SubOU's registered control extracts the cap | `cross_ou_auth_tests` |
| `unregistered_control_cannot_privileged_extract` | A control bound to the SubOU but not its `controller_cap_id`: `controller::ENotController` | `cross_ou_auth_tests` |
| `reclaim_cap_from_subou_e2e` | Parent loans its control, `controller::privileged_extract`s from the SubOU vault, stores the cap | `armature_proposals::subou_ops_tests` |
| `create_subou_and_spin_out_e2e` | `create_subou_control` stores a control in the parent vault; spin-out destroys it and leaves the parent vault empty | `armature_proposals::migration_tests` |

**Bypass caps and emptiness**

| Test | Expected | Where |
|------|----------|-------|
| `execute_enable_bypass_type_e2e` | `borrow_external_cap(vault, ou_id, cap_id)` returns the stored `ExternalExecutionCap` without a request | `external_execution_tests` |
| `test_borrow_external_cap_wrong_ou_aborts` | `ou_id` not the vault's: `capability_vault::EOUIdMismatch` | planned |
| `test_create_returning_vault_vault_starts_empty` | A fresh vault `is_empty` | `ou_tests` |
| `test_destroy_empty_with_cap_aborts` | `destroy_empty` with a cap stored: bare `expected_failure` (the assert has no code) | planned |

## Tests

---

### Every vault mutator checks the request's OU and one bit

**Requirement:** Each request-taking function except the package-only `receive_cap` checks the vault's OU first (`capability_vault::EOUIdMismatch`), then the bit it needs (`proposal::EPermissionDenied` unless the request carries it or is privileged):

| Function | Bit |
|---|---|
| `store_cap<T, P>(vault, cap, &req)` | `VAULT_STORE` |
| `borrow_cap<T, P>`, `borrow_cap_mut<T, P>`, `loan_cap<T, P>` | `VAULT_BORROW`, and `T` in the request's borrow scope |
| `extract_cap<T, P>`, `create_subou_control<P>`, `destroy_subou_control<P>` | `VAULT_EXTRACT` |
| `receive_cap<T, P>(vault, cap, &req)` (`public(package)`) | `VAULT_EXTRACT` on the sending OU's request; the receiving vault is not checked |
| `receive_cap_authorized<T, Send, Recv>(vault, cap, &send, &recv)` | `VAULT_EXTRACT` on `send`, `VAULT_STORE` on `recv`; `recv` must be the vault's OU |

`store_cap_init` is `public(package)` and used only by framework construction paths; `create_subou_control` is `public(package)` and called only by `CreateSubOU`. `borrow_external_cap` and `privileged_extract` take no request (below).

**Why it matters:** The vault holds the OU's most powerful objects (`TreasuryCap`, `UpgradeCap`, `SubOUControl`, a SubOU's `FreezeAdminCap`). A request of an unrelated type, or of another OU, must not reach them.

```move
// From gate_tests: every bit except VAULT_EXTRACT
#[test, expected_failure(abort_code = proposal::EPermissionDenied)]
fun extract_cap_needs_vault_extract() {
    run!(|ou, _, vault, _, _, _| {
        let r = all_but(ou, permissions::vault_extract());
        let cap: TestCap = vault.extract_cap(object::id_from_address(@0x4), &r);
        abort 0
    });
}
```

---

### Borrowing is limited to the request's borrow scope

**Requirement:** `borrow_cap`, `borrow_cap_mut` and `loan_cap` call `proposal::assert_may_borrow(req, &type_name::with_defining_ids<T>())` after the `VAULT_BORROW` check and abort `proposal::EBorrowScopeDenied` unless `T` is in the request's `borrow_scope` or the request is privileged. The scope comes from `P`'s slot when the request is minted; an empty scope borrows nothing. Framework types hold a fixed scope (`SpinOutSubOU`: `[SubOUControl]`; all others empty); extension types publish theirs in `armature_proposals::type_permissions` (e.g. `currency_scope<T>()` = `[TreasuryCap<T>]`, `subou_control_scope()` = `[SubOUControl]`).

**Why it matters:** `VAULT_BORROW` alone would let a type that mints one coin reach the `UpgradeCap` or a `SubOUControl` in the same vault.

```move
// From borrow_scope_tests: Scoped holds VAULT_BORROW with scope [CapA]
#[test, expected_failure(abort_code = proposal::EBorrowScopeDenied)]
fun borrow_outside_scope_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let (_, b_id) = setup(&mut scenario, scope_of<CapA>());
    execute_and_borrow<CapB>(&mut scenario, b_id);   // atomic Scoped ticket, then vault.borrow_cap<CapB>
    scenario.end();
}
```

---

### Registries mirror the stored caps

**Requirement:** Storing a cap (through `store_cap`, `store_cap_init`, `receive_cap`, `receive_cap_authorized` or `create_subou_control`) adds its ID to `cap_ids` and to `ids_by_type[T]`, and adds `T` to `cap_types` on the first cap of that type. Extracting (`extract_cap`, `privileged_extract`, `destroy_subou_control`) removes the ID, and removes the type when its last ID goes. `ids_for_type<T>()` returns a copy of the IDs (empty if none); `contains(id)` checks `cap_ids`.

**Why it matters:** The registries are how clients and `TransferAssets` payloads find caps by type without scanning dynamic fields, and `destroy_empty` relies on them.

```move
// From capability_vault_tests::test_extract_last_of_type_removes_type
vault.store_cap_init(cap_a);
vault.store_cap_init(cap_b);
let req_a = make_req(ou_id);
let req_b = make_req(ou_id);

let ex_a = vault.extract_cap<TestCap, TestProposal>(id_a, &req_a);
let type_name = std::type_name::get<TestCap>().into_string();
assert!(vault.cap_types().contains(&type_name));    // cap_b remains

let ex_b = vault.extract_cap<TestCap, TestProposal>(id_b, &req_b);
assert!(!vault.cap_types().contains(&type_name));
```

---

### Loans keep the registries and must return the same cap

**Requirement:** `loan_cap<T, P>(vault, cap_id, &req): (T, CapLoan)` removes the cap's field but leaves the registries alone: the cap counts as held. `CapLoan { cap_id, vault_id }` has no abilities, so the PTB must call `return_cap<T>(vault, cap, loan)`, which aborts `capability_vault::ECapIdMismatch` if the cap is not the one loaned and `capability_vault::EVaultIdMismatch` if the vault is not the one it came from. While on loan, the cap cannot be borrowed (its field is absent).

**Why it matters:** Loans are how handlers use caps that functions take by value (a `SubOUControl` for `privileged_submit`, an `UpgradeCap` for an upgrade). A handler must not be able to keep the valuable cap and return a worthless one, or park it in another vault.

```move
// From capability_vault_tests::test_loan_does_not_update_registries
let (loaned, loan) = vault.loan_cap<TestCap, TestProposal>(cap_id, &req);
assert!(vault.contains(cap_id));
assert!(vault.cap_ids().contains(&cap_id));
vault.return_cap(loaned, loan);

#[test, expected_failure(abort_code = capability_vault::ECapIdMismatch)]
fun test_return_wrong_cap_aborts() {   // planned
    // ... two TestCaps stored; request with every bit and scope [TestCap]
    let (loaned, loan) = vault.loan_cap<TestCap, TestProposal>(id_a, &req);
    let other = vault.extract_cap<TestCap, TestProposal>(id_b, &req);
    vault.return_cap(other, loan);   // cap_id differs from the loan's
    abort 0
}
```

---

### Cross-OU receipt

**Requirement:** `receive_cap` needs `VAULT_EXTRACT` on the sending OU's request and does not check which OU the receiving vault belongs to, so it is `public(package)` and each caller ties the sender to the target: `SpinOutSubOU` moving its own SubOU's `FreezeAdminCap`, `TransferAssets` to the voted target, and `controller::receive_cap_from_controller`. That public entry checks that `subou_vault` is the SubOU's and `controller_vault` the request's OU's (`controller::EControlMismatch`), and that `controller_vault` holds the SubOU's registered control (`controller::ENotController`); `TransferCapToSubOU` uses it. `receive_cap_authorized` also requires `VAULT_STORE` on a request of the receiving OU and checks that OU owns the vault (`capability_vault::EOUIdMismatch`); other cross-OU handlers use it.

**Why it matters:** An unrelated OU must not push caps into another OU's vault. The controller form relies on the control relationship; the dual form lets a receiving OU refuse caps it did not vote to accept.

```move
// From capability_vault_tests::receive_cap_authorized_aborts_on_recv_ou_mismatch
let send_req = make_req(ou_a);
let wrong_recv_req = make_recv_req(ou_a);   // recv_vault belongs to ou_b
let extracted = src_vault.extract_cap<TestCap, TestProposal>(cap_id, &send_req);
recv_vault.receive_cap_authorized(extracted, &send_req, &wrong_recv_req);   // EOUIdMismatch
```

---

### Controller reclaim with SubOUControl

**Requirement:** `controller::privileged_extract<T>(subou_vault, cap_id, &subou, &SubOUControl)` extracts a cap without a request. It checks that `subou_vault` is `subou`'s (`controller::EControlMismatch`) and calls `controller::assert_registered_control` (`EControlMismatch` unless `control.subou_id` is the SubOU, `ENotController` unless the control is its `controller_cap_id`), then the package-only `capability_vault::privileged_extract`, which checks `control.subou_id == vault.ou_id` (`capability_vault::ENotController`). The parent reaches its `SubOUControl` by loaning it from its own vault with a request whose type holds `VAULT_BORROW` scoped to `SubOUControl` (`ReclaimCapFromSubOU`, `SpinOutSubOU`). `create_subou_control<P>` (package-only) mints a control into the vault and `destroy_subou_control<P>` deletes one, both under `VAULT_EXTRACT`.

**Why it matters:** This is how a controller OU takes back what it delegated. A control for one SubOU must not open another SubOU's vault, and a control minted outside the SubOU's creation (or retired at spin-out) must not open its own.

```move
#[test, expected_failure(abort_code = capability_vault::ENotController)]
fun test_privileged_extract_wrong_subou_aborts() {
    let mut ctx = tx_context::dummy();
    let (mut vault, _ou_id) = setup(&mut ctx);
    let cap = make_cap(&mut ctx, 77);
    let cap_id = object::id(&cap);
    vault.store_cap_init(cap);

    let control = capability_vault::new_subou_control_for_testing(object::id_from_address(@0xBAD), &mut ctx);
    let extracted = vault.privileged_extract<TestCap>(cap_id, &control);
    // unreachable
    sui::test_utils::destroy(extracted);
    sui::test_utils::destroy(control);
    sui::test_utils::destroy(vault);
}
```

---

### Bypass caps are looked up without a request

**Requirement:** `borrow_external_cap<P>(vault, ou_id, cap_id): &ExternalExecutionCap<P>` takes no request and checks only that the vault belongs to `ou_id` (`capability_vault::EOUIdMismatch`). The cap is the OU's opt-in to bypass execution for `P`, not a bearer credential: `external_execution::ticket_from_cap` also needs `Permit<P>`, so only `P`'s own module can mint a bypass ticket with it.

**Why it matters:** Anyone can read the cap, so the vault check is one of two boundaries between a borrowed cap and an OU; `ticket_from_cap` re-checks the cap's own OU (`proposal::ECapOUMismatch`).

```move
// From external_execution_tests::execute_enable_bypass_type_e2e
let cap: &ExternalExecutionCap<DummyBypass> = vault.borrow_external_cap(ou.id(), cap_id);
```

---

### Emptiness

**Requirement:** `is_empty` is true when `cap_ids` is empty. `destroy_empty` (`public(package)`, called by `ou::destroy`) asserts, without a named code, that `cap_ids`, `cap_types` and `ids_by_type` are all empty.

**Why it matters:** Destroying a vault that still holds a `SubOUControl` or `TreasuryCap` would delete the only handle to it.

The planned `test_destroy_empty_with_cap_aborts` stores a cap and calls `destroy_empty` under a bare `#[expected_failure]`; the OU-level form is in `02_ou_lifecycle.md`.

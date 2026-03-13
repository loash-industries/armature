#[test_only]
module armature::capability_vault_tests;

use armature::capability_vault::{Self, CapabilityVault};
use armature::proposal;

// === Test Structs ===

public struct TestCap has key, store {
    id: UID,
    value: u64,
}

public struct AnotherCap has key, store {
    id: UID,
}

public struct TestProposal has drop {}

// === Constants ===

const ADMIN: address = @0xA;

// === Helpers ===

fun setup(ctx: &mut TxContext): (CapabilityVault, ID) {
    let dao_id = object::id_from_address(@0xDA0);
    let vault = capability_vault::new(dao_id, ctx);
    (vault, dao_id)
}

fun make_cap(ctx: &mut TxContext, value: u64): TestCap {
    TestCap { id: object::new(ctx), value }
}

fun make_another_cap(ctx: &mut TxContext): AnotherCap {
    AnotherCap { id: object::new(ctx) }
}

fun make_req(dao_id: ID): proposal::ExecutionRequest<TestProposal> {
    proposal::new_execution_request<TestProposal>(dao_id, object::id_from_address(@0xBEEF))
}

// === Tests ===

#[test]
/// store_cap requires ExecutionRequest — verifies the function works with one.
fun test_store_cap_requires_execution_request() {
    let mut ctx = tx_context::dummy();
    let (mut vault, dao_id) = setup(&mut ctx);
    let cap = make_cap(&mut ctx, 1);
    let req = make_req(dao_id);

    vault.store_cap(cap, &req);

    proposal::consume(req);
    sui::test_utils::destroy(vault);
}

#[test]
/// borrow_cap requires ExecutionRequest — verifies the function works with one.
fun test_borrow_cap_requires_execution_request() {
    let mut ctx = tx_context::dummy();
    let (mut vault, dao_id) = setup(&mut ctx);
    let cap = make_cap(&mut ctx, 10);
    let cap_id = object::id(&cap);
    vault.store_cap_init(cap);
    let req = make_req(dao_id);

    let ref_cap: &TestCap = vault.borrow_cap(cap_id, &req);
    assert!(ref_cap.value == 10);

    proposal::consume(req);
    sui::test_utils::destroy(vault);
}

#[test]
/// loan_cap requires ExecutionRequest — verifies the function works with one.
fun test_loan_cap_requires_execution_request() {
    let mut ctx = tx_context::dummy();
    let (mut vault, dao_id) = setup(&mut ctx);
    let cap = make_cap(&mut ctx, 20);
    let cap_id = object::id(&cap);
    vault.store_cap_init(cap);
    let req = make_req(dao_id);

    let (loaned, loan) = vault.loan_cap<TestCap, TestProposal>(cap_id, &req);
    vault.return_cap(loaned, loan);

    proposal::consume(req);
    sui::test_utils::destroy(vault);
}

#[test]
/// extract_cap requires ExecutionRequest — verifies the function works with one.
fun test_extract_cap_requires_execution_request() {
    let mut ctx = tx_context::dummy();
    let (mut vault, dao_id) = setup(&mut ctx);
    let cap = make_cap(&mut ctx, 30);
    let cap_id = object::id(&cap);
    vault.store_cap_init(cap);
    let req = make_req(dao_id);

    let extracted = vault.extract_cap<TestCap, TestProposal>(cap_id, &req);

    proposal::consume(req);
    sui::test_utils::destroy(extracted);
    sui::test_utils::destroy(vault);
}

#[test]
/// store_cap_init is public(package) — works during DAO init context.
fun test_store_cap_init_only_during_dao_creation() {
    let mut ctx = tx_context::dummy();
    let (mut vault, _dao_id) = setup(&mut ctx);
    let cap = make_cap(&mut ctx, 99);
    let cap_id = object::id(&cap);

    vault.store_cap_init(cap);

    assert!(vault.contains(cap_id));
    sui::test_utils::destroy(vault);
}

#[test]
/// Storing a capability updates both cap_types and cap_ids registries.
fun test_store_updates_cap_types_and_cap_ids() {
    let mut ctx = tx_context::dummy();
    let (mut vault, _dao_id) = setup(&mut ctx);
    let cap = make_cap(&mut ctx, 1);
    let cap_id = object::id(&cap);

    vault.store_cap_init(cap);

    assert!(vault.cap_ids().contains(&cap_id));
    let type_name = std::type_name::get<TestCap>().into_string();
    assert!(vault.cap_types().contains(&type_name));
    sui::test_utils::destroy(vault);
}

#[test]
/// Extracting a capability removes it from both cap_types and cap_ids registries.
fun test_extract_removes_from_cap_types_and_cap_ids() {
    let mut ctx = tx_context::dummy();
    let (mut vault, dao_id) = setup(&mut ctx);
    let cap = make_cap(&mut ctx, 1);
    let cap_id = object::id(&cap);
    vault.store_cap_init(cap);
    let req = make_req(dao_id);

    let extracted = vault.extract_cap<TestCap, TestProposal>(cap_id, &req);

    assert!(!vault.cap_ids().contains(&cap_id));
    let type_name = std::type_name::get<TestCap>().into_string();
    assert!(!vault.cap_types().contains(&type_name));

    proposal::consume(req);
    sui::test_utils::destroy(extracted);
    sui::test_utils::destroy(vault);
}

#[test]
/// Storing multiple capabilities of the same type registers all their IDs.
fun test_store_multiple_same_type_updates_ids() {
    let mut ctx = tx_context::dummy();
    let (mut vault, _dao_id) = setup(&mut ctx);
    let cap_a = make_cap(&mut ctx, 1);
    let cap_b = make_cap(&mut ctx, 2);
    let id_a = object::id(&cap_a);
    let id_b = object::id(&cap_b);

    vault.store_cap_init(cap_a);
    vault.store_cap_init(cap_b);

    assert!(vault.contains(id_a));
    assert!(vault.contains(id_b));
    let ids = vault.ids_for_type<TestCap>();
    assert!(ids.length() == 2);
    assert!(ids.contains(&id_a));
    assert!(ids.contains(&id_b));
    sui::test_utils::destroy(vault);
}

#[test]
/// Extracting the last capability of a type removes the type from cap_types.
fun test_extract_last_of_type_removes_type() {
    let mut ctx = tx_context::dummy();
    let (mut vault, dao_id) = setup(&mut ctx);
    let cap_a = make_cap(&mut ctx, 1);
    let cap_b = make_cap(&mut ctx, 2);
    let id_a = object::id(&cap_a);
    let id_b = object::id(&cap_b);
    vault.store_cap_init(cap_a);
    vault.store_cap_init(cap_b);
    let req_a = make_req(dao_id);
    let req_b = make_req(dao_id);

    let ex_a = vault.extract_cap<TestCap, TestProposal>(id_a, &req_a);
    // Type should still be present (cap_b remains)
    let type_name = std::type_name::get<TestCap>().into_string();
    assert!(vault.cap_types().contains(&type_name));

    let ex_b = vault.extract_cap<TestCap, TestProposal>(id_b, &req_b);
    // Now type should be gone
    assert!(!vault.cap_types().contains(&type_name));

    proposal::consume(req_a);
    proposal::consume(req_b);
    sui::test_utils::destroy(ex_a);
    sui::test_utils::destroy(ex_b);
    sui::test_utils::destroy(vault);
}

#[test]
/// Loaning a capability does NOT update cap_types or cap_ids registries.
fun test_loan_does_not_update_registries() {
    let mut ctx = tx_context::dummy();
    let (mut vault, dao_id) = setup(&mut ctx);
    let cap = make_cap(&mut ctx, 42);
    let cap_id = object::id(&cap);
    vault.store_cap_init(cap);
    let req = make_req(dao_id);

    let (loaned, loan) = vault.loan_cap<TestCap, TestProposal>(cap_id, &req);

    // Registries unchanged during loan
    assert!(vault.contains(cap_id));
    let type_name = std::type_name::get<TestCap>().into_string();
    assert!(vault.cap_types().contains(&type_name));
    assert!(vault.cap_ids().contains(&cap_id));

    vault.return_cap(loaned, loan);
    proposal::consume(req);
    sui::test_utils::destroy(vault);
}

#[test]
/// After loaning and returning, the capability is accessible again.
fun test_loan_and_return_restores_capability() {
    let mut ctx = tx_context::dummy();
    let (mut vault, dao_id) = setup(&mut ctx);
    let cap = make_cap(&mut ctx, 77);
    let cap_id = object::id(&cap);
    vault.store_cap_init(cap);
    let req = make_req(dao_id);

    let (loaned, loan) = vault.loan_cap<TestCap, TestProposal>(cap_id, &req);
    assert!(loaned.value == 77);
    vault.return_cap(loaned, loan);

    // Verify cap is accessible again
    let ref_cap: &TestCap = vault.borrow_cap(cap_id, &req);
    assert!(ref_cap.value == 77);

    proposal::consume(req);
    sui::test_utils::destroy(vault);
}

#[test, expected_failure]
/// A loaned capability cannot be borrowed while on loan.
fun test_loan_cap_not_borrowable_during_loan() {
    let mut ctx = tx_context::dummy();
    let (mut vault, dao_id) = setup(&mut ctx);
    let cap = make_cap(&mut ctx, 42);
    let cap_id = object::id(&cap);
    vault.store_cap_init(cap);
    let req = make_req(dao_id);

    let (loaned, loan) = vault.loan_cap<TestCap, TestProposal>(cap_id, &req);

    // This should abort — dynamic field was removed during loan
    vault.borrow_cap<TestCap, TestProposal>(cap_id, &req);

    // Unreachable — satisfies type checker
    vault.return_cap(loaned, loan);
    proposal::consume(req);
    sui::test_utils::destroy(vault);
}

#[test]
/// privileged_extract works with correct SubDAOControl.
fun test_privileged_extract_requires_subdao_control() {
    let mut ctx = tx_context::dummy();
    let (mut vault, dao_id) = setup(&mut ctx);
    let cap = make_cap(&mut ctx, 55);
    let cap_id = object::id(&cap);
    vault.store_cap_init(cap);

    let control = capability_vault::new_subdao_control_for_testing(dao_id, &mut ctx);
    let extracted = vault.privileged_extract<TestCap>(cap_id, &control);

    assert!(extracted.value == 55);
    sui::test_utils::destroy(extracted);
    sui::test_utils::destroy(control);
    sui::test_utils::destroy(vault);
}

#[test]
/// privileged_extract verifies control.subdao_id matches vault.dao_id.
fun test_privileged_extract_verifies_subdao_id() {
    let mut ctx = tx_context::dummy();
    let (mut vault, dao_id) = setup(&mut ctx);
    let cap = make_cap(&mut ctx, 66);
    let cap_id = object::id(&cap);
    vault.store_cap_init(cap);

    // Matching subdao_id succeeds
    let control = capability_vault::new_subdao_control_for_testing(dao_id, &mut ctx);
    assert!(control.subdao_id() == vault.dao_id());

    let extracted = vault.privileged_extract<TestCap>(cap_id, &control);
    sui::test_utils::destroy(extracted);
    sui::test_utils::destroy(control);
    sui::test_utils::destroy(vault);
}

#[test, expected_failure(abort_code = capability_vault::ENotController)]
/// privileged_extract aborts when control.subdao_id does not match vault.dao_id.
fun test_privileged_extract_wrong_subdao_aborts() {
    let mut ctx = tx_context::dummy();
    let (mut vault, _dao_id) = setup(&mut ctx);
    let cap = make_cap(&mut ctx, 77);
    let cap_id = object::id(&cap);
    vault.store_cap_init(cap);

    // Wrong subdao_id
    let wrong_id = object::id_from_address(@0xBAD);
    let control = capability_vault::new_subdao_control_for_testing(wrong_id, &mut ctx);

    // Should abort with ENotController
    let extracted = vault.privileged_extract<TestCap>(cap_id, &control);

    // Unreachable
    sui::test_utils::destroy(extracted);
    sui::test_utils::destroy(control);
    sui::test_utils::destroy(vault);
}

#[test]
/// privileged_extract succeeds and updates registries.
fun test_privileged_extract_succeeds() {
    let mut ctx = tx_context::dummy();
    let (mut vault, dao_id) = setup(&mut ctx);
    let cap = make_cap(&mut ctx, 88);
    let cap_id = object::id(&cap);
    vault.store_cap_init(cap);

    let control = capability_vault::new_subdao_control_for_testing(dao_id, &mut ctx);
    let extracted = vault.privileged_extract<TestCap>(cap_id, &control);

    // Registries updated
    assert!(!vault.contains(cap_id));
    let type_name = std::type_name::get<TestCap>().into_string();
    assert!(!vault.cap_types().contains(&type_name));

    sui::test_utils::destroy(extracted);
    sui::test_utils::destroy(control);
    sui::test_utils::destroy(vault);
}

#[test]
/// contains returns true for a stored capability.
fun test_contains__returns_true_for_stored_cap() {
    let mut ctx = tx_context::dummy();
    let (mut vault, _dao_id) = setup(&mut ctx);
    let cap = make_cap(&mut ctx, 1);
    let cap_id = object::id(&cap);

    vault.store_cap_init(cap);

    assert!(vault.contains(cap_id));
    sui::test_utils::destroy(vault);
}

#[test]
/// contains returns false for a non-existent capability.
fun test_contains__returns_false_for_missing_cap() {
    let mut ctx = tx_context::dummy();
    let (vault, _dao_id) = setup(&mut ctx);
    let missing_id = object::id_from_address(@0xDEAD);

    assert!(!vault.contains(missing_id));
    sui::test_utils::destroy(vault);
}

#[test]
/// ids_for_type returns the correct list of IDs for a given type.
fun test_ids_for_type__returns_correct_list() {
    let mut ctx = tx_context::dummy();
    let (mut vault, _dao_id) = setup(&mut ctx);

    // Store two TestCaps and one AnotherCap
    let cap_a = make_cap(&mut ctx, 1);
    let cap_b = make_cap(&mut ctx, 2);
    let other = make_another_cap(&mut ctx);
    let id_a = object::id(&cap_a);
    let id_b = object::id(&cap_b);
    let id_other = object::id(&other);

    vault.store_cap_init(cap_a);
    vault.store_cap_init(cap_b);
    vault.store_cap_init(other);

    // ids_for_type<TestCap> should return 2 IDs
    let test_ids = vault.ids_for_type<TestCap>();
    assert!(test_ids.length() == 2);
    assert!(test_ids.contains(&id_a));
    assert!(test_ids.contains(&id_b));

    // ids_for_type<AnotherCap> should return 1 ID
    let other_ids = vault.ids_for_type<AnotherCap>();
    assert!(other_ids.length() == 1);
    assert!(other_ids.contains(&id_other));

    sui::test_utils::destroy(vault);
}

#[test]
/// borrow_cap returns an immutable reference with correct data.
fun test_borrow_cap__returns_immutable_reference() {
    let mut ctx = tx_context::dummy();
    let (mut vault, dao_id) = setup(&mut ctx);
    let cap = make_cap(&mut ctx, 123);
    let cap_id = object::id(&cap);
    vault.store_cap_init(cap);
    let req = make_req(dao_id);

    let ref_cap: &TestCap = vault.borrow_cap(cap_id, &req);
    assert!(ref_cap.value == 123);

    proposal::consume(req);
    sui::test_utils::destroy(vault);
}

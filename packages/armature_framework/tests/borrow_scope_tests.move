/// Borrow scope: VAULT_BORROW says a type may borrow from the vault,
/// `ProposalConfig.borrow_scope` says which capability types. The scope rides
/// on the request like the bits do, the vault checks it on every borrow and
/// loan, framework types hold a fixed scope, and changing a scope is a grant
/// only the type-admin meta-types may make.
#[test_only]
module armature::borrow_scope_tests;

use armature::board_voting;
use armature::capability_vault::{CapabilityVault, SubOUControl};
use armature::ou::{Self, OU};
use armature::emergency::EmergencyFreeze;
use armature::governance;
use armature::permissions;
use armature::proposal;
use armature::spin_out_subou::SpinOutSubOU;
use armature::update_proposal_config::UpdateProposalConfig;
use std::internal;
use std::string;
use std::type_name::{Self, TypeName};
use sui::clock;
use sui::test_scenario;

const CREATOR: address = @0xA;

/// A type granted VAULT_BORROW with a scope chosen per test.
public struct Scoped has drop, store {}

/// Some other type, used as the requester in grant-rule tests.
public struct Other has drop, store {}

public struct CapA has key, store { id: UID }

public struct CapB has key, store { id: UID }

fun scope_of<T>(): vector<TypeName> { vector[type_name::with_defining_ids<T>()] }

fun fake_id(): ID { object::id_from_address(@0x1234) }

fun create_ou(scenario: &mut test_scenario::Scenario) {
    scenario.next_tx(CREATOR);
    let init = governance::init_board(vector[CREATOR]);
    ou::create(&init, string::utf8(b"OU"), string::utf8(b""), scenario.ctx());
}

/// Enable `Scoped` with VAULT_BORROW and `scope`; store one CapA and one CapB
/// in the OU's vault. Returns (cap_a_id, cap_b_id).
fun setup(scenario: &mut test_scenario::Scenario, scope: vector<TypeName>): (ID, ID) {
    create_ou(scenario);
    scenario.next_tx(CREATOR);
    let mut ou = scenario.take_shared<OU>();
    let mut vault = scenario.take_shared_by_id<CapabilityVault>(ou.capability_vault_id());
    let config = proposal::new_config(1, 8_000, 0, 604_800_000, 0, 0)
        .with_permissions(permissions::vault_borrow())
        .with_borrow_scope(scope);
    ou.test_enable_type<Scoped>(b"Scoped".to_ascii_string(), config);
    let a = CapA { id: object::new(scenario.ctx()) };
    let b = CapB { id: object::new(scenario.ctx()) };
    let (a_id, b_id) = (object::id(&a), object::id(&b));
    vault.store_cap_for_testing(a);
    vault.store_cap_for_testing(b);
    test_scenario::return_shared(vault);
    test_scenario::return_shared(ou);
    (a_id, b_id)
}

/// Execute a single-vote `Scoped` ticket and borrow the cap `cap_id` as `T`.
fun execute_and_borrow<T: key + store>(scenario: &mut test_scenario::Scenario, cap_id: ID) {
    scenario.next_tx(CREATOR);
    let mut ou = scenario.take_shared<OU>();
    let vault = scenario.take_shared_by_id<CapabilityVault>(ou.capability_vault_id());
    let freeze = scenario.take_shared_by_id<EmergencyFreeze>(ou.emergency_freeze_id());
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1000);
    let ticket = board_voting::submit_vote_execute<Scoped>(
        &mut ou,
        option::none(),
        Scoped {},
        &freeze,
        &clock,
        scenario.ctx(),
    );
    let req = ticket.ticket_request(internal::permit());
    assert!(
        req.req_borrow_scope() == ou.type_config_by_name(&type_name::with_defining_ids<Scoped>()).borrow_scope(),
    );
    let _cap: &T = vault.borrow_cap(cap_id, req);
    ticket.discharge(internal::permit());
    clock.destroy_for_testing();
    test_scenario::return_shared(freeze);
    test_scenario::return_shared(vault);
    test_scenario::return_shared(ou);
}

// === The scope rides on the request and the vault checks it ===

#[test]
/// A request minted on the atomic vote path carries its slot's scope, and a
/// cap in that scope can be borrowed.
fun request_carries_slot_scope_and_borrows_in_scope() {
    let mut scenario = test_scenario::begin(CREATOR);
    let (a_id, _) = setup(&mut scenario, scope_of<CapA>());
    execute_and_borrow<CapA>(&mut scenario, a_id);
    scenario.end();
}

#[test, expected_failure(abort_code = proposal::EBorrowScopeDenied)]
/// VAULT_BORROW alone does not reach a cap outside the scope.
fun borrow_outside_scope_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let (_, b_id) = setup(&mut scenario, scope_of<CapA>());
    execute_and_borrow<CapB>(&mut scenario, b_id);
    scenario.end();
}

#[test, expected_failure(abort_code = proposal::EBorrowScopeDenied)]
/// An empty scope borrows nothing, whatever bits the type holds.
fun empty_scope_borrows_nothing() {
    let mut scenario = test_scenario::begin(CREATOR);
    let (a_id, _) = setup(&mut scenario, vector[]);
    execute_and_borrow<CapA>(&mut scenario, a_id);
    scenario.end();
}

#[test]
/// A privileged (controller) request passes the scope check like every other.
fun privileged_request_ignores_scope() {
    let mut scenario = test_scenario::begin(CREATOR);
    let (_, b_id) = setup(&mut scenario, scope_of<CapA>());
    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared<OU>();
        let vault = scenario.take_shared_by_id<CapabilityVault>(ou.capability_vault_id());
        let req = proposal::new_privileged_request_for_testing<Other>(ou.id(), fake_id());
        let _cap: &CapB = vault.borrow_cap(b_id, &req);
        proposal::consume_execution_request_for_testing(req);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(ou);
    };
    scenario.end();
}

// === Framework types hold a fixed scope ===

#[test]
fun spin_out_subou_scope_is_subou_control() {
    let spin = type_name::with_defining_ids<SpinOutSubOU>();
    assert!(ou::framework_borrow_scope(&spin) == scope_of<SubOUControl>());
    assert!(ou::framework_borrow_scope(&type_name::with_defining_ids<Scoped>()).is_empty());

    let mut scenario = test_scenario::begin(CREATOR);
    create_ou(&mut scenario);
    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared<OU>();
        // An empty scope in the enabling config is replaced by the fixed one.
        let config = proposal::new_config(1, 8_000, 0, 604_800_000, 0, 0);
        ou.test_enable_type<SpinOutSubOU>(b"SpinOutSubOU".to_ascii_string(), config);
        assert!(ou.type_config_by_name(&spin).borrow_scope() == scope_of<SubOUControl>());
        test_scenario::return_shared(ou);
    };
    scenario.end();
}

#[test, expected_failure(abort_code = ou::EFixedPermissions)]
fun framework_type_scope_cannot_be_changed() {
    let mut scenario = test_scenario::begin(CREATOR);
    create_ou(&mut scenario);
    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared<OU>();
        let config = proposal::new_config(1, 8_000, 0, 604_800_000, 0, 0).with_borrow_scope(
            scope_of<CapA>(),
        );
        ou.test_enable_type<SpinOutSubOU>(b"SpinOutSubOU".to_ascii_string(), config);
        abort 0
    }
}

// === Changing a scope is a grant ===

#[test, expected_failure(abort_code = ou::EPermissionChangeNotAllowed)]
/// A TYPE_ADMIN request of a non-meta type may reconfigure a type but not
/// widen its borrow scope.
fun scope_change_needs_meta_type() {
    let mut scenario = test_scenario::begin(CREATOR);
    setup(&mut scenario, scope_of<CapA>());
    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared<OU>();
        let req = proposal::new_permitted_request_for_testing<Other>(
            ou.id(),
            fake_id(),
            permissions::type_admin(),
        );
        let name = type_name::with_defining_ids<Scoped>();
        let widened = ou.type_config_by_name(&name).with_borrow_scope(scope_of<CapB>());
        ou.update_proposal_config(name, widened, &req);
        abort 0
    }
}

#[test, expected_failure(abort_code = ou::EPermissionChangeNotAllowed)]
/// Enabling a type with a scope is a grant too.
fun enable_with_scope_needs_meta_type() {
    let mut scenario = test_scenario::begin(CREATOR);
    create_ou(&mut scenario);
    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared<OU>();
        let req = proposal::new_permitted_request_for_testing<Other>(
            ou.id(),
            fake_id(),
            permissions::type_admin(),
        );
        let config = proposal::new_config(1, 8_000, 0, 604_800_000, 0, 0).with_borrow_scope(
            scope_of<CapA>(),
        );
        ou.enable_proposal_type<Scoped, Other>(b"Scoped".to_ascii_string(), config, &req);
        abort 0
    }
}

#[test]
/// UpdateProposalConfig (a meta-type at the 80% floor) may change a scope, and
/// a later request carries the new one.
fun meta_type_may_change_scope() {
    let mut scenario = test_scenario::begin(CREATOR);
    let (_, b_id) = setup(&mut scenario, scope_of<CapA>());
    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared<OU>();
        let req = proposal::new_permitted_request_for_testing<UpdateProposalConfig>(
            ou.id(),
            fake_id(),
            permissions::type_admin(),
        );
        let name = type_name::with_defining_ids<Scoped>();
        let moved = ou.type_config_by_name(&name).with_borrow_scope(scope_of<CapB>());
        ou.update_proposal_config(name, moved, &req);
        assert!(ou.type_config_by_name(&name).borrow_scope() == scope_of<CapB>());
        proposal::consume_execution_request_for_testing(req);
        test_scenario::return_shared(ou);
    };
    execute_and_borrow<CapB>(&mut scenario, b_id);
    scenario.end();
}

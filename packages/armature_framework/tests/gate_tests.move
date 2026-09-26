/// Negative authorization suite (ARMATURE-32): every framework mutator that
/// acts on an ExecutionRequest refuses a request missing the one bit it
/// requires, even when the request carries every other bit. So each mutator
/// checks the right bit, not merely some bit. `scripts/check_request_gates.py`
/// keeps the list complete: a new request-taking public function without a
/// gate fails CI.
#[test_only]
module armature::gate_tests;

use armature::capability_vault::CapabilityVault;
use armature::charter::Charter;
use armature::dao::{Self, DAO};
use armature::emergency::EmergencyFreeze;
use armature::governance;
use armature::permissions;
use armature::proposal::{Self, ExecutionRequest};
use armature::treasury_vault::TreasuryVault;
use armature::tribe;
use std::string;
use std::type_name;
use sui::sui::SUI;
use sui::test_scenario;

const CREATOR: address = @0xA;

/// The request's payload type. Its bits come from the request, not a slot.
public struct Probe has drop, store {}

public struct TestCap has key, store { id: UID }

/// A request for `dao` carrying every bit except `missing`.
fun all_but(dao: &DAO, missing: u64): ExecutionRequest<Probe> {
    proposal::new_permitted_request_for_testing<Probe>(
        dao.id(),
        object::id_from_address(@0x1),
        permissions::all() ^ missing,
    )
}

/// Create a DAO and hand its shared objects to `$f`, which must abort.
macro fun run(
    $f: |
        &mut DAO,
        &mut TreasuryVault,
        &mut CapabilityVault,
        &mut Charter,
        &mut EmergencyFreeze,
        &mut TxContext,
    |,
) {
    let mut scenario = test_scenario::begin(CREATOR);
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR]);
        dao::create(&init, string::utf8(b"DAO"), string::utf8(b""), scenario.ctx());
    };
    scenario.next_tx(CREATOR);
    let mut dao = scenario.take_shared<DAO>();
    let mut treasury = scenario.take_shared_by_id<TreasuryVault>(dao.treasury_id());
    let mut vault = scenario.take_shared_by_id<CapabilityVault>(dao.capability_vault_id());
    let mut charter = scenario.take_shared_by_id<Charter>(dao.charter_id());
    let mut freeze = scenario.take_shared_by_id<EmergencyFreeze>(dao.emergency_freeze_id());
    $f(&mut dao, &mut treasury, &mut vault, &mut charter, &mut freeze, scenario.ctx());
    abort 0
}

// === dao: board ===

#[test, expected_failure(abort_code = proposal::EPermissionDenied)]
fun set_board_governance_needs_board_set() {
    run!(|dao, _, _, _, _, _| {
        let r = all_but(dao, permissions::board_set());
        dao.set_board_governance(vector[@0xB], vector[], &r);
        abort 0
    });
}

#[test, expected_failure(abort_code = proposal::EPermissionDenied)]
fun add_board_member_governance_needs_board_add() {
    run!(|dao, _, _, _, _, _| {
        let r = all_but(dao, permissions::board_add());
        dao.add_board_member_governance(@0xB, &r);
        abort 0
    });
}

#[test, expected_failure(abort_code = proposal::EPermissionDenied)]
fun add_board_members_governance_needs_board_add() {
    run!(|dao, _, _, _, _, _| {
        let r = all_but(dao, permissions::board_add());
        dao.add_board_members_governance(vector[@0xB], &r);
        abort 0
    });
}

#[test, expected_failure(abort_code = proposal::EPermissionDenied)]
fun remove_board_member_governance_needs_board_remove() {
    run!(|dao, _, _, _, _, _| {
        let r = all_but(dao, permissions::board_remove());
        dao.remove_board_member_governance(CREATOR, &r);
        abort 0
    });
}

#[test, expected_failure(abort_code = proposal::EPermissionDenied)]
fun remove_board_members_governance_needs_board_remove() {
    run!(|dao, _, _, _, _, _| {
        let r = all_but(dao, permissions::board_remove());
        dao.remove_board_members_governance(vector[CREATOR], &r);
        abort 0
    });
}

// === dao: type registry ===

#[test, expected_failure(abort_code = proposal::EPermissionDenied)]
fun enable_proposal_type_needs_type_admin() {
    run!(|dao, _, _, _, _, _| {
        let r = all_but(dao, permissions::type_admin());
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        dao.enable_proposal_type<Probe, Probe>(b"Probe".to_ascii_string(), config, &r);
        abort 0
    });
}

#[test, expected_failure(abort_code = proposal::EPermissionDenied)]
fun disable_proposal_type_needs_type_admin() {
    run!(|dao, _, _, _, _, _| {
        let r = all_but(dao, permissions::type_admin());
        dao.disable_proposal_type(
            type_name::with_defining_ids<armature::add_member::AddMember>(),
            &r,
        );
        abort 0
    });
}

#[test, expected_failure(abort_code = proposal::EPermissionDenied)]
fun update_proposal_config_needs_type_admin() {
    run!(|dao, _, _, _, _, _| {
        let r = all_but(dao, permissions::type_admin());
        let name = type_name::with_defining_ids<armature::add_member::AddMember>();
        let config = dao.type_config_by_name(&name);
        dao.update_proposal_config(name, config, &r);
        abort 0
    });
}

// === dao: lifecycle ===

#[test, expected_failure(abort_code = proposal::EPermissionDenied)]
fun set_execution_paused_needs_pause() {
    run!(|dao, _, _, _, _, _| {
        let r = all_but(dao, permissions::pause());
        dao.set_execution_paused(true, &r);
        abort 0
    });
}

#[test, expected_failure(abort_code = proposal::EPermissionDenied)]
fun set_migrating_needs_migrate() {
    run!(|dao, _, _, _, _, _| {
        let r = all_but(dao, permissions::migrate());
        dao.set_migrating(object::id_from_address(@0x2), &r);
        abort 0
    });
}

#[test, expected_failure(abort_code = dao::ENotPrivileged)]
/// No bit grants the controller-only mutators.
fun set_controller_paused_needs_privileged_request() {
    run!(|dao, _, _, _, _, _| {
        let r = all_but(dao, 0);
        dao.set_controller_paused(true, &r);
        abort 0
    });
}

#[test, expected_failure(abort_code = dao::ENotPrivileged)]
fun clear_controller_needs_privileged_request() {
    run!(|dao, _, _, _, _, _| {
        let r = all_but(dao, 0);
        dao.clear_controller(&r);
        abort 0
    });
}

// === charter ===

#[test, expected_failure(abort_code = proposal::EPermissionDenied)]
fun update_metadata_needs_metadata() {
    run!(|dao, _, _, charter, _, _| {
        let r = all_but(dao, permissions::metadata());
        charter.update_metadata(string::utf8(b"ipfs://x"), &r);
        abort 0
    });
}

// === emergency ===

#[test, expected_failure(abort_code = proposal::EPermissionDenied)]
fun governance_unfreeze_type_needs_freeze() {
    run!(|dao, _, _, _, freeze, _| {
        let r = all_but(dao, permissions::emergency_freeze());
        freeze.governance_unfreeze_type(type_name::with_defining_ids<Probe>(), &r);
        abort 0
    });
}

#[test, expected_failure(abort_code = proposal::EPermissionDenied)]
fun update_freeze_duration_needs_freeze() {
    run!(|dao, _, _, _, freeze, _| {
        let r = all_but(dao, permissions::emergency_freeze());
        freeze.update_freeze_duration(1, &r);
        abort 0
    });
}

#[test, expected_failure(abort_code = proposal::EPermissionDenied)]
fun unfreeze_all_needs_freeze() {
    run!(|dao, _, _, _, freeze, _| {
        let r = all_but(dao, permissions::emergency_freeze());
        freeze.unfreeze_all(&r);
        abort 0
    });
}

#[test, expected_failure(abort_code = proposal::EPermissionDenied)]
fun add_freeze_exempt_type_needs_freeze() {
    run!(|dao, _, _, _, freeze, _| {
        let r = all_but(dao, permissions::emergency_freeze());
        freeze.add_freeze_exempt_type(type_name::with_defining_ids<Probe>(), &r);
        abort 0
    });
}

#[test, expected_failure(abort_code = proposal::EPermissionDenied)]
fun remove_freeze_exempt_type_needs_freeze() {
    run!(|dao, _, _, _, freeze, _| {
        let r = all_but(dao, permissions::emergency_freeze());
        freeze.remove_freeze_exempt_type(type_name::with_defining_ids<Probe>(), &r);
        abort 0
    });
}

// === treasury_vault ===

#[test, expected_failure(abort_code = proposal::EPermissionDenied)]
fun withdraw_needs_treasury_withdraw() {
    run!(|dao, treasury, _, _, _, ctx| {
        let r = all_but(dao, permissions::treasury_withdraw());
        let coin = treasury.withdraw<SUI, Probe>(1, &r, ctx);
        abort 0
    });
}

#[test, expected_failure(abort_code = proposal::EPermissionDenied)]
fun withdraw_multicoin_needs_treasury_withdraw() {
    run!(|dao, treasury, _, _, _, ctx| {
        let r = all_but(dao, permissions::treasury_withdraw());
        let balance = treasury.withdraw_multicoin(object::id_from_address(@0x3), 0, 1, &r, ctx);
        abort 0
    });
}

// === capability_vault ===

#[test, expected_failure(abort_code = proposal::EPermissionDenied)]
fun store_cap_needs_vault_store() {
    run!(|dao, _, vault, _, _, ctx| {
        let r = all_but(dao, permissions::vault_store());
        vault.store_cap(TestCap { id: object::new(ctx) }, &r);
        abort 0
    });
}

#[test, expected_failure(abort_code = proposal::EPermissionDenied)]
fun receive_cap_needs_vault_extract_on_sender() {
    run!(|dao, _, vault, _, _, ctx| {
        let r = all_but(dao, permissions::vault_extract());
        vault.receive_cap(TestCap { id: object::new(ctx) }, &r);
        abort 0
    });
}

#[test, expected_failure(abort_code = proposal::EPermissionDenied)]
fun receive_cap_authorized_needs_vault_extract_on_sender() {
    run!(|dao, _, vault, _, _, ctx| {
        let send = all_but(dao, permissions::vault_extract());
        let recv = all_but(dao, 0);
        vault.receive_cap_authorized(TestCap { id: object::new(ctx) }, &send, &recv);
        abort 0
    });
}

#[test, expected_failure(abort_code = proposal::EPermissionDenied)]
fun receive_cap_authorized_needs_vault_store_on_receiver() {
    run!(|dao, _, vault, _, _, ctx| {
        let send = all_but(dao, 0);
        let recv = all_but(dao, permissions::vault_store());
        vault.receive_cap_authorized(TestCap { id: object::new(ctx) }, &send, &recv);
        abort 0
    });
}

#[test, expected_failure(abort_code = proposal::EPermissionDenied)]
fun borrow_cap_needs_vault_borrow() {
    run!(|dao, _, vault, _, _, _| {
        let r = all_but(dao, permissions::vault_borrow());
        let _cap: &TestCap = vault.borrow_cap(object::id_from_address(@0x4), &r);
        abort 0
    });
}

#[test, expected_failure(abort_code = proposal::EPermissionDenied)]
fun borrow_cap_mut_needs_vault_borrow() {
    run!(|dao, _, vault, _, _, _| {
        let r = all_but(dao, permissions::vault_borrow());
        let _cap: &mut TestCap = vault.borrow_cap_mut(object::id_from_address(@0x4), &r);
        abort 0
    });
}

#[test, expected_failure(abort_code = proposal::EPermissionDenied)]
fun loan_cap_needs_vault_borrow() {
    run!(|dao, _, vault, _, _, _| {
        let r = all_but(dao, permissions::vault_borrow());
        let (cap, loan) = vault.loan_cap<TestCap, Probe>(object::id_from_address(@0x4), &r);
        abort 0
    });
}

#[test, expected_failure(abort_code = proposal::EPermissionDenied)]
fun extract_cap_needs_vault_extract() {
    run!(|dao, _, vault, _, _, _| {
        let r = all_but(dao, permissions::vault_extract());
        let cap: TestCap = vault.extract_cap(object::id_from_address(@0x4), &r);
        abort 0
    });
}

#[test, expected_failure(abort_code = proposal::EPermissionDenied)]
fun create_subdao_control_needs_vault_extract() {
    run!(|dao, _, vault, _, _, ctx| {
        let r = all_but(dao, permissions::vault_extract());
        vault.create_subdao_control(object::id_from_address(@0x5), &r, ctx);
        abort 0
    });
}

#[test, expected_failure(abort_code = proposal::EPermissionDenied)]
fun destroy_subdao_control_needs_vault_extract() {
    run!(|dao, _, vault, _, _, _| {
        let r = all_but(dao, permissions::vault_extract());
        vault.destroy_subdao_control(object::id_from_address(@0x5), &r);
        abort 0
    });
}

// === tribe ===

#[test, expected_failure(abort_code = proposal::EPermissionDenied)]
fun create_wired_subdao_needs_vault_extract() {
    run!(|dao, _, vault, _, _, ctx| {
        let r = all_but(dao, permissions::vault_extract());
        tribe::create_wired_subdao(
            vector[CREATOR],
            string::utf8(b"Sub"),
            string::utf8(b""),
            CREATOR,
            vault,
            &r,
            vector[],
            ctx,
        );
        abort 0
    });
}

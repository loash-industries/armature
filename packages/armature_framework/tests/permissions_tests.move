#[test_only]
module armature::permissions_tests;

use armature::capability_vault;
use armature::controller;
use armature::dao::{Self, DAO};
use armature::emergency::EmergencyFreeze;
use armature::external_execution;
use armature::governance;
use armature::permissions;
use armature::proposal;
use std::string;
use sui::clock;
use sui::test_scenario;

const CREATOR: address = @0xA;

/// A type granted BOARD_ADD and PAUSE.
public struct Granted has drop, store {}

/// A type granted nothing.
public struct Ungranted has drop, store {}

/// A type with no slot on the DAO.
public struct Unknown has drop, store {}

fun base_config(): proposal::ProposalConfig {
    proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0)
}

fun create_dao(scenario: &mut test_scenario::Scenario) {
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR]);
        dao::create(
            &init,
            string::utf8(b"Test DAO"),
            string::utf8(b"https://example.com/logo.png"),
            scenario.ctx(),
        );
    };
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        dao.test_enable_type<Granted>(
            b"Granted".to_ascii_string(),
            base_config().with_permissions(permissions::board_add() | permissions::pause()),
        );
        dao.test_enable_type<Ungranted>(b"Ungranted".to_ascii_string(), base_config());
        test_scenario::return_shared(dao);
    };
}

fun fake_id(): ID { object::id_from_address(@0x1234) }

// === ProposalConfig ===

#[test]
/// new_config grants nothing; with_permissions replaces the mask and leaves
/// the other fields alone; has_permission requires every bit asked for.
fun config_permissions_builder_and_accessors() {
    let config = base_config();
    assert!(config.permissions() == 0);
    assert!(!config.has_permission(permissions::board_add()));
    // The empty mask is held by every config.
    assert!(config.has_permission(0));

    let both = permissions::board_add() | permissions::treasury_withdraw();
    let granted = config.with_permissions(both).with_composable_allowed(true);
    assert!(granted.permissions() == both);
    assert!(granted.has_permission(permissions::board_add()));
    assert!(granted.has_permission(both));
    assert!(!granted.has_permission(permissions::board_add() | permissions::migrate()));
    assert!(granted.approval_threshold() == config.approval_threshold());
    assert!(granted.composable_allowed());

    // Replacing, not merging.
    assert!(granted.with_permissions(0).permissions() == 0);
    assert!(
        config.with_permissions(permissions::all()).has_permission(permissions::vault_extract()),
    );
}

#[test]
/// The bits are distinct single bits and `all` is exactly their union.
fun permission_bits_are_distinct() {
    let bits = vector[
        permissions::board_add(),
        permissions::board_remove(),
        permissions::board_set(),
        permissions::type_admin(),
        permissions::pause(),
        permissions::migrate(),
        permissions::metadata(),
        permissions::treasury_withdraw(),
        permissions::vault_store(),
        permissions::vault_borrow(),
        permissions::vault_extract(),
    ];
    let mut union = 0;
    bits.do!(|b| {
        assert!(b != 0 && b & (b - 1) == 0);
        assert!(union & b == 0);
        union = union | b;
    });
    assert!(union == permissions::all());
}

#[test, expected_failure(abort_code = permissions::EUnknownPermission)]
fun with_permissions_rejects_unknown_bit() {
    base_config().with_permissions(permissions::all() + 1);
}

// === dao::assert_permitted ===

#[test]
/// A type passes for any subset of its bits, including all of them at once.
fun assert_permitted_passes_for_granted_bits() {
    let mut scenario = test_scenario::begin(CREATOR);
    create_dao(&mut scenario);
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let req = proposal::new_execution_request_for_testing<Granted>(dao.id(), fake_id());
        dao.assert_permitted(permissions::board_add(), &req);
        dao.assert_permitted(permissions::pause(), &req);
        dao.assert_permitted(permissions::board_add() | permissions::pause(), &req);
        assert!(!dao.is_permitted(permissions::board_remove(), &req));
        proposal::consume_execution_request_for_testing(req);
        test_scenario::return_shared(dao);
    };
    scenario.end();
}

#[test, expected_failure(abort_code = dao::EPermissionDenied)]
/// A type with a slot but without the bit is denied.
fun assert_permitted_denies_ungranted_type() {
    let mut scenario = test_scenario::begin(CREATOR);
    create_dao(&mut scenario);
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let req = proposal::new_execution_request_for_testing<Ungranted>(dao.id(), fake_id());
        dao.assert_permitted(permissions::board_add(), &req);
        abort 0
    }
}

#[test, expected_failure(abort_code = dao::EPermissionDenied)]
/// Holding some of the requested bits is not enough.
fun assert_permitted_denies_partial_grant() {
    let mut scenario = test_scenario::begin(CREATOR);
    create_dao(&mut scenario);
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let req = proposal::new_execution_request_for_testing<Granted>(dao.id(), fake_id());
        dao.assert_permitted(permissions::board_add() | permissions::board_remove(), &req);
        abort 0
    }
}

#[test, expected_failure(abort_code = dao::ETypeNotEnabled)]
/// A type with no slot on the DAO is rejected before any bit is read.
fun assert_permitted_rejects_missing_slot() {
    let mut scenario = test_scenario::begin(CREATOR);
    create_dao(&mut scenario);
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let req = proposal::new_execution_request_for_testing<Unknown>(dao.id(), fake_id());
        assert!(!dao.is_permitted(0, &req));
        dao.assert_permitted(0, &req);
        abort 0
    }
}

#[test, expected_failure(abort_code = dao::EDAOIdMismatch)]
/// A request for another DAO is rejected even if the type holds the bit here.
fun assert_permitted_rejects_cross_dao_request() {
    let mut scenario = test_scenario::begin(CREATOR);
    create_dao(&mut scenario);
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let req = proposal::new_execution_request_for_testing<Granted>(fake_id(), fake_id());
        dao.assert_permitted(permissions::board_add(), &req);
        abort 0
    }
}

#[test]
/// A privileged request passes every bit, even for a type with no slot.
fun assert_permitted_passes_privileged_request() {
    let mut scenario = test_scenario::begin(CREATOR);
    create_dao(&mut scenario);
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let req = proposal::new_privileged_request_for_testing<Unknown>(dao.id(), fake_id());
        dao.assert_permitted(permissions::all(), &req);
        proposal::consume_execution_request_for_testing(req);
        test_scenario::return_shared(dao);
    };
    scenario.end();
}

#[test, expected_failure(abort_code = dao::EDAOIdMismatch)]
/// Privilege is scoped to the controlled SubDAO: it does not carry to another DAO.
fun assert_permitted_privileged_request_is_dao_scoped() {
    let mut scenario = test_scenario::begin(CREATOR);
    create_dao(&mut scenario);
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let req = proposal::new_privileged_request_for_testing<Unknown>(fake_id(), fake_id());
        dao.assert_permitted(0, &req);
        abort 0
    }
}

// === Who mints privileged requests ===

#[test]
/// controller::privileged_submit mints a privileged request; the bypass path
/// (ticket_from_cap) and the vote path do not.
fun only_controller_requests_are_privileged() {
    let mut scenario = test_scenario::begin(CREATOR);
    let clock = clock::create_for_testing(scenario.ctx());
    create_dao(&mut scenario);
    scenario.next_tx(CREATOR);
    let (dao_id, freeze_id) = {
        let dao = scenario.take_shared<DAO>();
        let dao_id = dao.id();
        let freeze_id = dao.emergency_freeze_id();
        test_scenario::return_shared(dao);
        (dao_id, freeze_id)
    };

    // Controller override on a SubDAO.
    {
        let init = governance::init_board(vector[CREATOR]);
        let (subdao, freeze_cap) = dao::create_subdao(
            &init,
            string::utf8(b"SubDAO"),
            string::utf8(b"https://example.com/sub.png"),
            scenario.ctx(),
        );
        let control = capability_vault::new_subdao_control_for_testing(
            object::id(&subdao),
            scenario.ctx(),
        );
        let req = controller::privileged_submit(
            &control,
            &subdao,
            b"Unknown".to_ascii_string(),
            option::none(),
            Unknown {},
            scenario.ctx(),
        );
        assert!(req.req_is_privileged());
        subdao.assert_permitted(permissions::all(), &req);
        controller::privileged_consume(req, &control);

        sui::test_utils::destroy(control);
        sui::test_utils::destroy(freeze_cap);
        transfer::public_share_object(subdao);
    };

    // Bypass ticket for a granted type: unprivileged, held to its own bits.
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared_by_id<DAO>(dao_id);
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(freeze_id);
        let cap = proposal::new_external_execution_cap_for_testing<Granted>(
            dao.id(),
            scenario.ctx(),
        );
        let ticket = external_execution::ticket_from_cap(
            &cap,
            &mut dao,
            &freeze,
            option::none(),
            Granted {},
            &clock,
            scenario.ctx(),
        );
        assert!(!ticket.ticket_request().req_is_privileged());
        assert!(dao.is_permitted(permissions::board_add(), ticket.ticket_request()));
        assert!(!dao.is_permitted(permissions::treasury_withdraw(), ticket.ticket_request()));
        ticket.discharge();
        proposal::destroy_external_execution_cap_for_testing(cap);
        test_scenario::return_shared(freeze);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

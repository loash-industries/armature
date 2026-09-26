#[test_only]
module armature::permissions_tests;

use armature::capability_vault;
use armature::composite;
use armature::composite_payload::CompositePayload;
use armature::controller;
use armature::dao::{Self, DAO};
use armature::emergency::EmergencyFreeze;
use armature::enable_bypass_type::EnableBypassType;
use armature::enable_proposal_type::{Self, EnableProposalType};
use armature::external_execution;
use armature::governance;
use armature::permissions;
use armature::proposal::{Self, ExecutionRequest};
use armature::update_proposal_config::{Self, UpdateProposalConfig};
use std::string;
use std::type_name;
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
        permissions::emergency_freeze(),
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

// === Floors and grant rules (ARMATURE-24) ===

/// A fresh type to enable in grant tests.
public struct Target has drop, store {}

fun config_at(threshold: u16, bits: u64): proposal::ProposalConfig {
    proposal::new_config(5_000, threshold, 0, 604_800_000, 0, 0).with_permissions(bits)
}

fun req<P>(dao: &DAO): ExecutionRequest<P> {
    proposal::new_execution_request_for_testing<P>(dao.id(), fake_id())
}

/// Run `f` against the test DAO in its own transaction.
macro fun with_dao($f: |&mut DAO|) {
    let mut scenario = test_scenario::begin(CREATOR);
    create_dao(&mut scenario);
    scenario.next_tx(CREATOR);
    let mut dao = scenario.take_shared<DAO>();
    $f(&mut dao);
    test_scenario::return_shared(dao);
    scenario.end();
}

fun enable_target<P>(dao: &mut DAO, config: proposal::ProposalConfig) {
    let r = req<P>(dao);
    dao.enable_proposal_type<Target, P>(b"Target".to_ascii_string(), config, &r);
    proposal::consume_execution_request_for_testing(r);
}

fun update_target<P>(dao: &mut DAO, config: proposal::ProposalConfig) {
    let r = req<P>(dao);
    dao.update_proposal_config(type_name::with_defining_ids<Target>(), config, &r);
    proposal::consume_execution_request_for_testing(r);
}

#[test]
/// The floor of a mask is 80% iff it holds a high-impact bit.
fun permission_floor_values() {
    assert!(dao::permission_floor(0) == 0);
    assert!(
        dao::permission_floor(
            permissions::board_add() | permissions::board_remove() | permissions::board_set()
            | permissions::pause() | permissions::metadata() | permissions::vault_store()
            | permissions::emergency_freeze(),
        ) == 0,
    );
    assert!(dao::permission_floor(permissions::vault_borrow()) == 8_000);
    assert!(dao::permission_floor(permissions::type_admin()) == 8_000);
    assert!(dao::permission_floor(permissions::migrate()) == 8_000);
    assert!(dao::permission_floor(permissions::treasury_withdraw()) == 8_000);
    assert!(dao::permission_floor(permissions::vault_extract() | permissions::pause()) == 8_000);
}

#[test]
/// EnableProposalType may grant low bits; the slot stores them.
fun enable_proposal_type_grants_low_bits() {
    with_dao!(|dao| {
        enable_target<EnableProposalType>(dao, config_at(5_000, permissions::board_add()));
        assert!(dao.type_config<Target>().permissions() == permissions::board_add());
    });
}

#[test]
/// EnableProposalType sits at the 80% floor, so it may grant an 80% bit.
fun enable_proposal_type_grants_high_bits() {
    with_dao!(|dao| {
        enable_target<EnableProposalType>(dao, config_at(8_000, permissions::treasury_withdraw()));
        assert!(dao.type_config<Target>().has_permission(permissions::treasury_withdraw()));
    });
}

#[test]
/// EnableBypassType (80%) may grant an 80% bit to a config at 80%.
fun enable_bypass_type_grants_high_bits() {
    with_dao!(|dao| {
        enable_target<EnableBypassType>(dao, config_at(8_000, permissions::treasury_withdraw()));
        assert!(dao.type_config<Target>().has_permission(permissions::treasury_withdraw()));
    });
}

#[test, expected_failure(abort_code = dao::EThresholdBelowMinimum)]
/// A config holding an 80% bit must itself require 80% approval.
fun enable_with_high_bits_under_floor_aborts() {
    with_dao!(|dao| {
        enable_target<EnableBypassType>(dao, config_at(7_999, permissions::vault_extract()));
    });
}

#[test, expected_failure(abort_code = dao::EPermissionChangeNotAllowed)]
/// Only the three meta-types may grant bits: an ordinary type cannot enable a
/// type with bits, whatever bits it holds itself.
fun enable_by_non_meta_type_with_bits_aborts() {
    with_dao!(|dao| {
        enable_target<Granted>(dao, config_at(5_000, permissions::board_add()));
    });
}

#[test]
/// Without bits, the grant rules do not apply to the requester.
fun enable_by_non_meta_type_without_bits_passes() {
    with_dao!(|dao| {
        enable_target<Granted>(dao, config_at(5_000, 0));
        assert!(dao.is_type_enabled<Target>());
    });
}

#[test]
/// UpdateProposalConfig (80%) grants an 80% bit, and can later take it away.
fun update_proposal_config_grants_and_revokes_high_bits() {
    with_dao!(|dao| {
        enable_target<EnableProposalType>(dao, config_at(5_000, 0));
        update_target<UpdateProposalConfig>(dao, config_at(8_000, permissions::migrate()));
        assert!(dao.type_config<Target>().permissions() == permissions::migrate());
        update_target<UpdateProposalConfig>(dao, config_at(8_000, 0));
        assert!(dao.type_config<Target>().permissions() == 0);
    });
}

#[test, expected_failure(abort_code = dao::EThresholdBelowMinimum)]
/// Lowering the threshold of a type that holds an 80% bit below 80% aborts.
fun update_lowering_threshold_under_permission_floor_aborts() {
    with_dao!(|dao| {
        enable_target<EnableBypassType>(dao, config_at(8_000, permissions::type_admin()));
        update_target<UpdateProposalConfig>(dao, config_at(5_000, permissions::type_admin()));
    });
}

#[test, expected_failure(abort_code = dao::EPermissionChangeNotAllowed)]
/// A non-meta type cannot change bits through update_proposal_config.
fun update_bits_by_non_meta_type_aborts() {
    with_dao!(|dao| {
        enable_target<EnableProposalType>(dao, config_at(5_000, 0));
        update_target<Granted>(dao, config_at(5_000, permissions::board_add()));
    });
}

#[test]
/// A non-meta type can rewrite other fields while leaving the bits alone
/// (the TYPE_ADMIN gate on this mutator comes with ARMATURE-27).
fun update_without_bit_change_by_non_meta_type_passes() {
    with_dao!(|dao| {
        enable_target<EnableProposalType>(dao, config_at(5_000, permissions::board_add()));
        update_target<Granted>(dao, config_at(6_000, permissions::board_add()));
        assert!(dao.type_config<Target>().approval_threshold() == 6_000);
    });
}

#[test, expected_failure(abort_code = dao::EFixedPermissions)]
/// UpdateProposalConfig cannot change its own bits: framework bits are fixed.
fun update_proposal_config_self_grant_aborts() {
    with_dao!(|dao| {
        let r = req<UpdateProposalConfig>(dao);
        let name = type_name::with_defining_ids<UpdateProposalConfig>();
        let config = dao.type_config<UpdateProposalConfig>().with_permissions(permissions::pause());
        dao.update_proposal_config(name, config, &r);
        abort 0
    });
}

#[test, expected_failure(abort_code = dao::EThresholdBelowMinimum)]
/// A type's own floor holds when dao is called directly, not only via admin_ops.
fun type_floor_holds_on_direct_update() {
    with_dao!(|dao| {
        let r = req<UpdateProposalConfig>(dao);
        let name = type_name::with_defining_ids<EnableProposalType>();
        dao.update_proposal_config(name, config_at(7_999, permissions::type_admin()), &r);
        abort 0
    });
}

#[test]
/// A privileged (controller) request may change bits without the grant rules.
fun privileged_request_may_change_bits() {
    with_dao!(|dao| {
        enable_target<EnableProposalType>(dao, config_at(8_000, 0));
        let r = proposal::new_privileged_request_for_testing<Unknown>(dao.id(), fake_id());
        let name = type_name::with_defining_ids<Target>();
        dao.update_proposal_config(name, config_at(8_000, permissions::vault_extract()), &r);
        proposal::consume_execution_request_for_testing(r);
        assert!(dao.type_config<Target>().has_permission(permissions::vault_extract()));
    });
}

#[test, expected_failure(abort_code = dao::EFixedPermissions)]
/// CompositePayload can never hold bits, even via a privileged request.
fun composite_payload_cannot_hold_bits() {
    with_dao!(|dao| {
        let r = proposal::new_privileged_request_for_testing<Unknown>(dao.id(), fake_id());
        let name = type_name::with_defining_ids<CompositePayload>();
        let config = dao.type_config<CompositePayload>().with_permissions(permissions::board_add());
        dao.update_proposal_config(name, config, &r);
        abort 0
    });
}

// === Composite: grants are standalone-only ===

#[test, expected_failure(abort_code = composite::EUseTypedStep)]
fun add_step_rejects_enable_proposal_type() {
    with_dao!(|dao| {
        let mut frame = composite::new_frame(dao.id(), &mut tx_context::dummy());
        let payload = enable_proposal_type::new(
            b"Target".to_ascii_string(),
            type_name::with_defining_ids<Target>(),
            config_at(5_000, 0),
        );
        composite::add_step(&mut frame, dao, payload);
        abort 0
    });
}

#[test, expected_failure(abort_code = composite::EGrantInComposite)]
fun composite_enable_step_with_bits_aborts() {
    with_dao!(|dao| {
        let mut frame = composite::new_frame(dao.id(), &mut tx_context::dummy());
        let payload = enable_proposal_type::new(
            b"Target".to_ascii_string(),
            type_name::with_defining_ids<Target>(),
            config_at(5_000, permissions::board_add()),
        );
        composite::add_enable_proposal_type_step(&mut frame, dao, payload);
        abort 0
    });
}

fun update_payload(): UpdateProposalConfig {
    update_proposal_config::new(
        b"Granted".to_ascii_string(),
        option::none(),
        option::some(6_000),
        option::none(),
        option::none(),
        option::none(),
        option::none(),
        option::none(),
    )
}

/// Make UpdateProposalConfig composable so its steps reach the typed check.
fun make_update_config_composable(dao: &mut DAO) {
    let config = dao.type_config<UpdateProposalConfig>().with_composable_allowed(true);
    dao.test_update_config<UpdateProposalConfig>(config);
}

#[test, expected_failure(abort_code = composite::EGrantInComposite)]
fun composite_update_step_changing_bits_aborts() {
    with_dao!(|dao| {
        make_update_config_composable(dao);
        let mut frame = composite::new_frame(dao.id(), &mut tx_context::dummy());
        let payload = update_payload().with_permissions(permissions::board_add());
        composite::add_update_proposal_config_step(&mut frame, dao, payload);
        abort 0
    });
}

#[test]
/// An UpdateProposalConfig step that leaves the bits alone, either by not
/// setting them or by restating the current ones, still composes.
fun composite_update_step_keeping_bits_composes() {
    with_dao!(|dao| {
        make_update_config_composable(dao);
        let mut frame = composite::new_frame(dao.id(), &mut tx_context::dummy());
        composite::add_update_proposal_config_step(&mut frame, dao, update_payload());
        let restated = update_payload().with_permissions(
            permissions::board_add() | permissions::pause(),
        );
        composite::add_update_proposal_config_step(&mut frame, dao, restated);
        sui::test_utils::destroy(frame);
    });
}

#[test, expected_failure(abort_code = dao::EFixedPermissions)]
/// A framework type cannot be enabled with bits other than its fixed set.
fun framework_type_enabled_with_other_bits_aborts() {
    with_dao!(|dao| {
        let r = req<EnableProposalType>(dao);
        let config = config_at(8_000, permissions::treasury_withdraw());
        dao.enable_proposal_type<armature::spawn_dao::SpawnDAO, EnableProposalType>(
            b"SpawnDAO".to_ascii_string(),
            config,
            &r,
        );
        abort 0
    });
}

#[test]
/// A framework type enabled with no bits gets its fixed set, and its config
/// must meet the floor those bits need.
fun framework_type_enabled_without_bits_gets_fixed_set() {
    with_dao!(|dao| {
        let r = req<EnableProposalType>(dao);
        dao.enable_proposal_type<armature::spawn_dao::SpawnDAO, EnableProposalType>(
            b"SpawnDAO".to_ascii_string(),
            config_at(8_000, 0),
            &r,
        );
        proposal::consume_execution_request_for_testing(r);
        let config = dao.type_config<armature::spawn_dao::SpawnDAO>();
        assert!(config.permissions() == permissions::migrate());
    });
}

#[test, expected_failure(abort_code = dao::EThresholdBelowMinimum)]
/// SpawnDAO carries MIGRATE, so a config below 80% cannot enable it.
fun framework_type_fixed_bits_need_their_floor() {
    with_dao!(|dao| {
        let r = req<EnableProposalType>(dao);
        dao.enable_proposal_type<armature::spawn_dao::SpawnDAO, EnableProposalType>(
            b"SpawnDAO".to_ascii_string(),
            config_at(5_000, 0),
            &r,
        );
        abort 0
    });
}

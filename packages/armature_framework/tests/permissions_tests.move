#[test_only]
module armature::permissions_tests;

use armature::capability_vault;
use armature::composite;
use armature::composite_payload::CompositePayload;
use armature::controller;
use armature::emergency::EmergencyFreeze;
use armature::enable_bypass_type::EnableBypassType;
use armature::enable_proposal_type::{Self, EnableProposalType};
use armature::external_execution;
use armature::governance;
use armature::ou::{Self, OU};
use armature::permissions;
use armature::proposal::{Self, ExecutionRequest};
use armature::update_proposal_config::{Self, UpdateProposalConfig};
use std::internal;
use std::string;
use std::type_name;
use sui::clock;
use sui::test_scenario;

const CREATOR: address = @0xA;

/// A type granted BOARD_ADD and PAUSE.
public struct Granted has drop, store {}

/// A type granted nothing.
public struct Ungranted has drop, store {}

/// A type with no slot on the OU.
public struct Unknown has drop, store {}

fun base_config(): proposal::ProposalConfig {
    proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0)
}

fun create_ou(scenario: &mut test_scenario::Scenario) {
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR]);
        ou::create(
            &init,
            string::utf8(b"Test OU"),
            string::utf8(b"https://example.com/logo.png"),
            scenario.ctx(),
        );
    };
    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared<OU>();
        ou.test_enable_type<Granted>(
            b"Granted".to_ascii_string(),
            base_config().with_permissions(permissions::board_add() | permissions::pause()),
        );
        ou.test_enable_type<Ungranted>(b"Ungranted".to_ascii_string(), base_config());
        test_scenario::return_shared(ou);
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

// === ou::assert_permitted ===

fun permitted<P>(ou: &OU, bits: u64): ExecutionRequest<P> {
    proposal::new_permitted_request_for_testing<P>(ou.id(), fake_id(), bits)
}

#[test]
/// A request passes for any subset of the bits it carries.
fun assert_permitted_passes_for_carried_bits() {
    with_ou!(|ou| {
        let req = permitted<Granted>(ou, permissions::board_add() | permissions::pause());
        ou.assert_permitted(permissions::board_add(), &req);
        ou.assert_permitted(permissions::pause(), &req);
        ou.assert_permitted(permissions::board_add() | permissions::pause(), &req);
        req.assert_permitted(0);
        assert!(!ou.is_permitted(permissions::board_remove(), &req));
        proposal::consume_execution_request_for_testing(req);
    });
}

#[test, expected_failure(abort_code = proposal::EPermissionDenied)]
/// A request carrying no bits is denied.
fun assert_permitted_denies_request_without_bit() {
    with_ou!(|ou| {
        let req = permitted<Ungranted>(ou, 0);
        ou.assert_permitted(permissions::board_add(), &req);
        abort 0
    });
}

#[test, expected_failure(abort_code = proposal::EPermissionDenied)]
/// Holding some of the requested bits is not enough.
fun assert_permitted_denies_partial_grant() {
    with_ou!(|ou| {
        let req = permitted<Granted>(ou, permissions::board_add());
        ou.assert_permitted(permissions::board_add() | permissions::board_remove(), &req);
        abort 0
    });
}

#[test, expected_failure(abort_code = ou::EOUIdMismatch)]
/// A request for another OU is rejected even if it carries the bit.
fun assert_permitted_rejects_cross_ou_request() {
    with_ou!(|ou| {
        let req = proposal::new_permitted_request_for_testing<Granted>(
            fake_id(),
            fake_id(),
            permissions::board_add(),
        );
        assert!(!ou.is_permitted(permissions::board_add(), &req));
        ou.assert_permitted(permissions::board_add(), &req);
        abort 0
    });
}

#[test]
/// The vote path mints requests with the type's current slot bits: a grant
/// or revocation applies from the next execution on.
fun vote_path_request_carries_current_slot_bits() {
    let mut scenario = test_scenario::begin(CREATOR);
    let clock = clock::create_for_testing(scenario.ctx());
    create_ou(&mut scenario);
    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared<OU>();
        let freeze = scenario.take_shared<EmergencyFreeze>();

        let t1 = armature::board_voting::submit_vote_execute(
            &mut ou,
            option::none(),
            Granted {},
            &freeze,
            &clock,
            scenario.ctx(),
        );
        assert!(
            t1.ticket_request(internal::permit()).req_permissions()
                == permissions::board_add() | permissions::pause(),
        );
        t1.discharge(internal::permit());

        ou.test_update_config<Granted>(base_config());
        let t2 = armature::board_voting::submit_vote_execute(
            &mut ou,
            option::none(),
            Granted {},
            &freeze,
            &clock,
            scenario.ctx(),
        );
        assert!(t2.ticket_request(internal::permit()).req_permissions() == 0);
        t2.discharge(internal::permit());

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(ou);
    };
    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// A privileged request passes every bit, even for a type with no slot.
fun assert_permitted_passes_privileged_request() {
    let mut scenario = test_scenario::begin(CREATOR);
    create_ou(&mut scenario);
    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared<OU>();
        let req = proposal::new_privileged_request_for_testing<Unknown>(ou.id(), fake_id());
        ou.assert_permitted(permissions::all(), &req);
        proposal::consume_execution_request_for_testing(req);
        test_scenario::return_shared(ou);
    };
    scenario.end();
}

#[test, expected_failure(abort_code = ou::EOUIdMismatch)]
/// Privilege is scoped to the controlled SubOU: it does not carry to another OU.
fun assert_permitted_privileged_request_is_ou_scoped() {
    let mut scenario = test_scenario::begin(CREATOR);
    create_ou(&mut scenario);
    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared<OU>();
        let req = proposal::new_privileged_request_for_testing<Unknown>(fake_id(), fake_id());
        ou.assert_permitted(0, &req);
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
    create_ou(&mut scenario);
    scenario.next_tx(CREATOR);
    let (ou_id, freeze_id) = {
        let ou = scenario.take_shared<OU>();
        let ou_id = ou.id();
        let freeze_id = ou.emergency_freeze_id();
        test_scenario::return_shared(ou);
        (ou_id, freeze_id)
    };

    // Controller override on a SubOU.
    {
        let init = governance::init_board(vector[CREATOR]);
        let (mut subou, freeze_cap) = ou::create_subou(
            &init,
            string::utf8(b"SubOU"),
            string::utf8(b"https://example.com/sub.png"),
            scenario.ctx(),
        );
        let control = capability_vault::new_subou_control_for_testing(
            object::id(&subou),
            scenario.ctx(),
        );
        subou.set_controller_for_testing(object::id(&control));
        let req = controller::privileged_submit(
            &control,
            &subou,
            b"Unknown".to_ascii_string(),
            option::none(),
            Unknown {},
            scenario.ctx(),
        );
        assert!(req.req_is_privileged());
        subou.assert_permitted(permissions::all(), &req);
        controller::privileged_consume(req, &control);

        sui::test_utils::destroy(control);
        sui::test_utils::destroy(freeze_cap);
        transfer::public_share_object(subou);
    };

    // Bypass ticket for a granted type: unprivileged, held to its own bits.
    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared_by_id<OU>(ou_id);
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(freeze_id);
        let cap = proposal::new_external_execution_cap_for_testing<Granted>(
            ou.id(),
            scenario.ctx(),
        );
        let ticket = external_execution::ticket_from_cap(
            &cap,
            &mut ou,
            &freeze,
            option::none(),
            Granted {},
            internal::permit(),
            &clock,
            scenario.ctx(),
        );
        assert!(!ticket.ticket_request(internal::permit()).req_is_privileged());
        assert!(
            ou.is_permitted(permissions::board_add(), ticket.ticket_request(internal::permit())),
        );
        assert!(
            !ou.is_permitted(
                permissions::treasury_withdraw(),
                ticket.ticket_request(internal::permit()),
            ),
        );
        ticket.discharge(internal::permit());
        proposal::destroy_external_execution_cap_for_testing(cap);
        test_scenario::return_shared(freeze);
        test_scenario::return_shared(ou);
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

fun req<P>(ou: &OU): ExecutionRequest<P> {
    proposal::new_execution_request_for_testing<P>(ou.id(), fake_id())
}

/// Run `f` against the test OU in its own transaction.
macro fun with_ou($f: |&mut OU|) {
    let mut scenario = test_scenario::begin(CREATOR);
    create_ou(&mut scenario);
    scenario.next_tx(CREATOR);
    let mut ou = scenario.take_shared<OU>();
    $f(&mut ou);
    test_scenario::return_shared(ou);
    scenario.end();
}

fun enable_target<P>(ou: &mut OU, config: proposal::ProposalConfig) {
    let r = req<P>(ou);
    ou.enable_proposal_type<Target, P>(b"Target".to_ascii_string(), config, &r);
    proposal::consume_execution_request_for_testing(r);
}

fun update_target<P>(ou: &mut OU, config: proposal::ProposalConfig) {
    let r = req<P>(ou);
    ou.update_proposal_config(type_name::with_defining_ids<Target>(), config, &r);
    proposal::consume_execution_request_for_testing(r);
}

#[test]
/// The floor of a mask is 80% iff it holds a high-impact bit.
fun permission_floor_values() {
    assert!(ou::permission_floor(0) == 0);
    assert!(
        ou::permission_floor(
            permissions::board_add() | permissions::board_remove() | permissions::board_set()
            | permissions::pause() | permissions::metadata() | permissions::vault_store()
            | permissions::emergency_freeze(),
        ) == 0,
    );
    assert!(ou::permission_floor(permissions::vault_borrow()) == 8_000);
    assert!(ou::permission_floor(permissions::type_admin()) == 8_000);
    assert!(ou::permission_floor(permissions::migrate()) == 8_000);
    assert!(ou::permission_floor(permissions::treasury_withdraw()) == 8_000);
    assert!(ou::permission_floor(permissions::vault_extract() | permissions::pause()) == 8_000);
}

#[test]
/// EnableProposalType may grant low bits; the slot stores them.
fun enable_proposal_type_grants_low_bits() {
    with_ou!(|ou| {
        enable_target<EnableProposalType>(ou, config_at(5_000, permissions::board_add()));
        assert!(ou.type_config<Target>().permissions() == permissions::board_add());
    });
}

#[test]
/// EnableProposalType sits at the 80% floor, so it may grant an 80% bit.
fun enable_proposal_type_grants_high_bits() {
    with_ou!(|ou| {
        enable_target<EnableProposalType>(ou, config_at(8_000, permissions::treasury_withdraw()));
        assert!(ou.type_config<Target>().has_permission(permissions::treasury_withdraw()));
    });
}

#[test]
/// EnableBypassType (80%) may grant an 80% bit to a config at 80%.
fun enable_bypass_type_grants_high_bits() {
    with_ou!(|ou| {
        enable_target<EnableBypassType>(ou, config_at(8_000, permissions::treasury_withdraw()));
        assert!(ou.type_config<Target>().has_permission(permissions::treasury_withdraw()));
    });
}

#[test, expected_failure(abort_code = ou::EThresholdBelowMinimum)]
/// A config holding an 80% bit must itself require 80% approval.
fun enable_with_high_bits_under_floor_aborts() {
    with_ou!(|ou| {
        enable_target<EnableBypassType>(ou, config_at(7_999, permissions::vault_extract()));
    });
}

#[test, expected_failure(abort_code = ou::EPermissionChangeNotAllowed)]
/// Only the three meta-types may grant bits: an ordinary type cannot enable a
/// type with bits, whatever bits it holds itself.
fun enable_by_non_meta_type_with_bits_aborts() {
    with_ou!(|ou| {
        enable_target<Granted>(ou, config_at(5_000, permissions::board_add()));
    });
}

#[test]
/// Without bits, the grant rules do not apply to the requester.
fun enable_by_non_meta_type_without_bits_passes() {
    with_ou!(|ou| {
        enable_target<Granted>(ou, config_at(5_000, 0));
        assert!(ou.is_type_enabled<Target>());
    });
}

#[test]
/// UpdateProposalConfig (80%) grants an 80% bit, and can later take it away.
fun update_proposal_config_grants_and_revokes_high_bits() {
    with_ou!(|ou| {
        enable_target<EnableProposalType>(ou, config_at(5_000, 0));
        update_target<UpdateProposalConfig>(ou, config_at(8_000, permissions::migrate()));
        assert!(ou.type_config<Target>().permissions() == permissions::migrate());
        update_target<UpdateProposalConfig>(ou, config_at(8_000, 0));
        assert!(ou.type_config<Target>().permissions() == 0);
    });
}

#[test, expected_failure(abort_code = ou::EThresholdBelowMinimum)]
/// Lowering the threshold of a type that holds an 80% bit below 80% aborts.
fun update_lowering_threshold_under_permission_floor_aborts() {
    with_ou!(|ou| {
        enable_target<EnableBypassType>(ou, config_at(8_000, permissions::type_admin()));
        update_target<UpdateProposalConfig>(ou, config_at(5_000, permissions::type_admin()));
    });
}

#[test, expected_failure(abort_code = ou::EPermissionChangeNotAllowed)]
/// A non-meta type cannot change bits through update_proposal_config.
fun update_bits_by_non_meta_type_aborts() {
    with_ou!(|ou| {
        enable_target<EnableProposalType>(ou, config_at(5_000, 0));
        update_target<Granted>(ou, config_at(5_000, permissions::board_add()));
    });
}

#[test]
/// A non-meta type can rewrite other fields while leaving the bits alone
/// (the TYPE_ADMIN gate on this mutator comes with ARMATURE-27).
fun update_without_bit_change_by_non_meta_type_passes() {
    with_ou!(|ou| {
        enable_target<EnableProposalType>(ou, config_at(5_000, permissions::board_add()));
        update_target<Granted>(ou, config_at(6_000, permissions::board_add()));
        assert!(ou.type_config<Target>().approval_threshold() == 6_000);
    });
}

#[test, expected_failure(abort_code = ou::EFixedPermissions)]
/// UpdateProposalConfig cannot change its own bits: framework bits are fixed.
fun update_proposal_config_self_grant_aborts() {
    with_ou!(|ou| {
        let r = req<UpdateProposalConfig>(ou);
        let name = type_name::with_defining_ids<UpdateProposalConfig>();
        let config = ou.type_config<UpdateProposalConfig>().with_permissions(permissions::pause());
        ou.update_proposal_config(name, config, &r);
        abort 0
    });
}

#[test, expected_failure(abort_code = ou::EThresholdBelowMinimum)]
/// A type's own floor holds when ou is called directly, not only via admin_ops.
fun type_floor_holds_on_direct_update() {
    with_ou!(|ou| {
        let r = req<UpdateProposalConfig>(ou);
        let name = type_name::with_defining_ids<EnableProposalType>();
        ou.update_proposal_config(name, config_at(7_999, permissions::type_admin()), &r);
        abort 0
    });
}

#[test]
/// A privileged (controller) request may change bits without the grant rules.
fun privileged_request_may_change_bits() {
    with_ou!(|ou| {
        enable_target<EnableProposalType>(ou, config_at(8_000, 0));
        let r = proposal::new_privileged_request_for_testing<Unknown>(ou.id(), fake_id());
        let name = type_name::with_defining_ids<Target>();
        ou.update_proposal_config(name, config_at(8_000, permissions::vault_extract()), &r);
        proposal::consume_execution_request_for_testing(r);
        assert!(ou.type_config<Target>().has_permission(permissions::vault_extract()));
    });
}

#[test, expected_failure(abort_code = ou::EFixedPermissions)]
/// CompositePayload can never hold bits, even via a privileged request.
fun composite_payload_cannot_hold_bits() {
    with_ou!(|ou| {
        let r = proposal::new_privileged_request_for_testing<Unknown>(ou.id(), fake_id());
        let name = type_name::with_defining_ids<CompositePayload>();
        let config = ou.type_config<CompositePayload>().with_permissions(permissions::board_add());
        ou.update_proposal_config(name, config, &r);
        abort 0
    });
}

// === Composite: grants are standalone-only ===

#[test, expected_failure(abort_code = composite::EUseTypedStep)]
fun add_step_rejects_enable_proposal_type() {
    with_ou!(|ou| {
        let mut frame = composite::new_frame(ou.id(), &mut tx_context::dummy());
        let payload = enable_proposal_type::new(
            b"Target".to_ascii_string(),
            type_name::with_defining_ids<Target>(),
            config_at(5_000, 0),
        );
        composite::add_step(&mut frame, ou, payload);
        abort 0
    });
}

#[test, expected_failure(abort_code = composite::EGrantInComposite)]
fun composite_enable_step_with_bits_aborts() {
    with_ou!(|ou| {
        let mut frame = composite::new_frame(ou.id(), &mut tx_context::dummy());
        let payload = enable_proposal_type::new(
            b"Target".to_ascii_string(),
            type_name::with_defining_ids<Target>(),
            config_at(5_000, permissions::board_add()),
        );
        composite::add_enable_proposal_type_step(&mut frame, ou, payload);
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
fun make_update_config_composable(ou: &mut OU) {
    let config = ou.type_config<UpdateProposalConfig>().with_composable_allowed(true);
    ou.test_update_config<UpdateProposalConfig>(config);
}

#[test, expected_failure(abort_code = composite::EGrantInComposite)]
fun composite_update_step_changing_bits_aborts() {
    with_ou!(|ou| {
        make_update_config_composable(ou);
        let mut frame = composite::new_frame(ou.id(), &mut tx_context::dummy());
        let payload = update_payload().with_permissions(permissions::board_add());
        composite::add_update_proposal_config_step(&mut frame, ou, payload);
        abort 0
    });
}

#[test, expected_failure(abort_code = composite::EGrantInComposite)]
/// A borrow scope is a grant too: an EnableProposalType step may not carry one.
fun composite_enable_step_with_scope_aborts() {
    with_ou!(|ou| {
        let mut frame = composite::new_frame(ou.id(), &mut tx_context::dummy());
        let payload = enable_proposal_type::new(
            b"Target".to_ascii_string(),
            type_name::with_defining_ids<Target>(),
            config_at(5_000, 0).with_borrow_scope(vector[type_name::with_defining_ids<Target>()]),
        );
        composite::add_enable_proposal_type_step(&mut frame, ou, payload);
        abort 0
    });
}

#[test, expected_failure(abort_code = composite::EGrantInComposite)]
/// An UpdateProposalConfig step may not change the target's borrow scope.
fun composite_update_step_changing_scope_aborts() {
    with_ou!(|ou| {
        make_update_config_composable(ou);
        let mut frame = composite::new_frame(ou.id(), &mut tx_context::dummy());
        let payload = update_payload().with_borrow_scope(vector[
            type_name::with_defining_ids<Target>(),
        ]);
        composite::add_update_proposal_config_step(&mut frame, ou, payload);
        abort 0
    });
}

#[test]
/// An UpdateProposalConfig step that leaves the bits alone, either by not
/// setting them or by restating the current ones, still composes.
fun composite_update_step_keeping_bits_composes() {
    with_ou!(|ou| {
        make_update_config_composable(ou);
        let mut frame = composite::new_frame(ou.id(), &mut tx_context::dummy());
        composite::add_update_proposal_config_step(&mut frame, ou, update_payload());
        let restated = update_payload().with_permissions(
            permissions::board_add() | permissions::pause(),
        );
        composite::add_update_proposal_config_step(&mut frame, ou, restated);
        sui::test_utils::destroy(frame);
    });
}

#[test, expected_failure(abort_code = ou::EFixedPermissions)]
/// A framework type cannot be enabled with bits other than its fixed set.
fun framework_type_enabled_with_other_bits_aborts() {
    with_ou!(|ou| {
        let r = req<EnableProposalType>(ou);
        let config = config_at(8_000, permissions::treasury_withdraw());
        ou.enable_proposal_type<armature::spawn_ou::SpawnOU, EnableProposalType>(
            b"SpawnOU".to_ascii_string(),
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
    with_ou!(|ou| {
        let r = req<EnableProposalType>(ou);
        ou.enable_proposal_type<armature::spawn_ou::SpawnOU, EnableProposalType>(
            b"SpawnOU".to_ascii_string(),
            config_at(8_000, 0),
            &r,
        );
        proposal::consume_execution_request_for_testing(r);
        let config = ou.type_config<armature::spawn_ou::SpawnOU>();
        assert!(config.permissions() == permissions::migrate());
    });
}

#[test, expected_failure(abort_code = ou::EThresholdBelowMinimum)]
/// SpawnOU carries MIGRATE, so a config below 80% cannot enable it.
fun framework_type_fixed_bits_need_their_floor() {
    with_ou!(|ou| {
        let r = req<EnableProposalType>(ou);
        ou.enable_proposal_type<armature::spawn_ou::SpawnOU, EnableProposalType>(
            b"SpawnOU".to_ascii_string(),
            config_at(5_000, 0),
            &r,
        );
        abort 0
    });
}

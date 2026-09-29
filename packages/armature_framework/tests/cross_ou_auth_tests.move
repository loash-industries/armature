#[test_only]
/// Regressions for authority crossing between OUs: a caller must not be able
/// to act on one OU using an object or request that belongs to another.
/// Covers forged SubOUControls (ARMATURE-37), foreign EmergencyFreeze objects
/// (ARMATURE-38), unrelated-OU vault deposits (ARMATURE-39) and composite
/// steps run against the wrong or a paused OU (ARMATURE-40).
module armature::cross_ou_auth_tests;

use armature::board_voting;
use armature::capability_vault::{Self, CapabilityVault, SubOUControl};
use armature::composite::{Self, CompositeFrame};
use armature::composite_payload::CompositePayload;
use armature::controller;
use armature::emergency::{Self, EmergencyFreeze, FreezeAdminCap};
use armature::external_execution;
use armature::governance;
use armature::ou::{Self, OU};
use armature::permissions;
use armature::proposal::{Self, Proposal};
use armature::treasury_vault::TreasuryVault;
use std::internal;
use std::string;
use std::type_name;
use sui::clock::{Self, Clock};
use sui::coin;
use sui::sui::SUI;
use sui::test_scenario::{Self, Scenario};

const VICTIM: address = @0xA;
const ATTACKER: address = @0xBAD;

/// Payload type the attacker's OU enables with whatever bits it likes.
public struct AtkPayload has drop, store {}

/// Payload type enabled on the victim OU.
public struct VPayload has drop, store {}

public struct Junk has key, store { id: UID }

// === Helpers ===

fun make_ou(s: &mut Scenario, sender: address): ID {
    s.next_tx(sender);
    let init = governance::init_board(vector[sender]);
    ou::create(&init, string::utf8(b"OU"), string::utf8(b""), s.ctx())
}

/// A SubOU of `parent_id` whose registered SubOUControl sits in the
/// parent's vault. Returns (subou_id, control_id).
fun make_subou(s: &mut Scenario, parent_id: ID): (ID, ID) {
    s.next_tx(VICTIM);
    let parent = s.take_shared_by_id<OU>(parent_id);
    let mut parent_vault = s.take_shared_by_id<CapabilityVault>(parent.capability_vault_id());
    let init = governance::init_board(vector[VICTIM]);
    let (subou, freeze_cap) = ou::create_subou(
        &init,
        string::utf8(b"SubOU"),
        string::utf8(b""),
        s.ctx(),
    );
    let subou_id = object::id(&subou);
    let control = capability_vault::new_subou_control_for_testing(subou_id, s.ctx());
    let control_id = object::id(&control);
    parent_vault.store_cap_for_testing(control);
    ou::share_subou(subou, control_id);
    sui::test_utils::destroy(freeze_cap);
    test_scenario::return_shared(parent_vault);
    test_scenario::return_shared(parent);
    (subou_id, control_id)
}

fun zero_delay(): proposal::ProposalConfig {
    proposal::new_config(5_000, 5_000, 0, 3_600_000, 0, 0)
}

fun enable<T>(s: &mut Scenario, ou_id: ID, config: proposal::ProposalConfig) {
    s.next_tx(VICTIM);
    let mut ou = s.take_shared_by_id<OU>(ou_id);
    ou.test_enable_type<T>(b"T".to_ascii_string(), config);
    test_scenario::return_shared(ou);
}

fun fund(s: &mut Scenario, ou_id: ID, amount: u64) {
    s.next_tx(VICTIM);
    let ou = s.take_shared_by_id<OU>(ou_id);
    let mut treasury = s.take_shared_by_id<TreasuryVault>(ou.treasury_id());
    treasury.deposit(coin::mint_for_testing<SUI>(amount, s.ctx()), s.ctx());
    test_scenario::return_shared(treasury);
    test_scenario::return_shared(ou);
}

fun freeze_id_of(s: &mut Scenario, ou_id: ID): ID {
    s.next_tx(VICTIM);
    let ou = s.take_shared_by_id<OU>(ou_id);
    let id = ou.emergency_freeze_id();
    test_scenario::return_shared(ou);
    id
}

// === ARMATURE-37: SubOUControl must be the OU's registered controller ===

#[test, expected_failure(abort_code = controller::ENotController)]
/// The original exploit: the attacker's own OU mints a SubOUControl bound to
/// the victim and tries to drive the victim with it. privileged_submit now
/// rejects any control that is not the victim's registered controller.
fun forged_control_cannot_privileged_submit() {
    let mut s = test_scenario::begin(VICTIM);
    let clock = clock::create_for_testing(s.ctx());
    let victim_id = make_ou(&mut s, VICTIM);
    fund(&mut s, victim_id, 1_000);
    let atk_id = make_ou(&mut s, ATTACKER);
    enable<AtkPayload>(
        &mut s,
        atk_id,
        zero_delay()
            .with_permissions(permissions::vault_extract() | permissions::vault_borrow())
            .with_borrow_scope(vector[type_name::with_defining_ids<SubOUControl>()]),
    );

    s.next_tx(ATTACKER);
    let mut atk_ou = s.take_shared_by_id<OU>(atk_id);
    let atk_freeze = s.take_shared_by_id<EmergencyFreeze>(atk_ou.emergency_freeze_id());
    let mut atk_vault = s.take_shared_by_id<CapabilityVault>(atk_ou.capability_vault_id());
    let victim_ou = s.take_shared_by_id<OU>(victim_id);
    let ticket = board_voting::submit_vote_execute(
        &mut atk_ou,
        option::none(),
        AtkPayload {},
        &atk_freeze,
        &clock,
        s.ctx(),
    );
    let req = ticket.ticket_request(internal::permit());
    let control_id = atk_vault.create_subou_control(victim_id, req, s.ctx());
    let control = atk_vault.borrow_cap<SubOUControl, AtkPayload>(control_id, req);
    let _vreq = controller::privileged_submit(
        control,
        &victim_ou,
        b"x".to_ascii_string(),
        option::none(),
        AtkPayload {},
        s.ctx(),
    );
    abort 0
}

#[test, expected_failure(abort_code = controller::ENotController)]
/// A control bound to the SubOU but not registered on it cannot reclaim caps.
fun unregistered_control_cannot_privileged_extract() {
    let mut s = test_scenario::begin(VICTIM);
    let parent_id = make_ou(&mut s, VICTIM);
    let (subou_id, _) = make_subou(&mut s, parent_id);

    s.next_tx(VICTIM);
    let subou = s.take_shared_by_id<OU>(subou_id);
    let mut subou_vault = s.take_shared_by_id<CapabilityVault>(subou.capability_vault_id());
    let cap = Junk { id: object::new(s.ctx()) };
    let cap_id = object::id(&cap);
    subou_vault.store_cap_for_testing(cap);
    let stray = capability_vault::new_subou_control_for_testing(subou_id, s.ctx());
    let _cap: Junk = controller::privileged_extract(&mut subou_vault, cap_id, &subou, &stray);
    abort 0
}

#[test]
/// The registered control still reclaims caps from its SubOU.
fun registered_control_privileged_extract_succeeds() {
    let mut s = test_scenario::begin(VICTIM);
    let parent_id = make_ou(&mut s, VICTIM);
    let (subou_id, control_id) = make_subou(&mut s, parent_id);

    s.next_tx(VICTIM);
    {
        let parent = s.take_shared_by_id<OU>(parent_id);
        let mut parent_vault = s.take_shared_by_id<CapabilityVault>(parent.capability_vault_id());
        let subou = s.take_shared_by_id<OU>(subou_id);
        let mut subou_vault = s.take_shared_by_id<CapabilityVault>(subou.capability_vault_id());
        let cap = Junk { id: object::new(s.ctx()) };
        let cap_id = object::id(&cap);
        subou_vault.store_cap_for_testing(cap);

        let req = proposal::new_permitted_request_for_testing<VPayload>(
            parent_id,
            object::id_from_address(@0x1),
            permissions::vault_borrow(),
        );
        let req = proposal::with_borrow_scope_for_testing(
            req,
            vector[type_name::with_defining_ids<SubOUControl>()],
        );
        let (control, loan) = parent_vault.loan_cap<SubOUControl, VPayload>(control_id, &req);
        let reclaimed: Junk = controller::privileged_extract(
            &mut subou_vault,
            cap_id,
            &subou,
            &control,
        );
        assert!(!subou_vault.contains(cap_id));
        parent_vault.return_cap(control, loan);
        proposal::consume_execution_request_for_testing(req);

        sui::test_utils::destroy(reclaimed);
        test_scenario::return_shared(subou_vault);
        test_scenario::return_shared(subou);
        test_scenario::return_shared(parent_vault);
        test_scenario::return_shared(parent);
    };
    s.end();
}

#[test, expected_failure(abort_code = controller::ENotController)]
/// After spin-out clears the controller, the old control no longer passes.
fun cleared_controller_rejects_old_control() {
    let mut s = test_scenario::begin(VICTIM);
    let parent_id = make_ou(&mut s, VICTIM);
    let (subou_id, control_id) = make_subou(&mut s, parent_id);

    s.next_tx(VICTIM);
    let parent = s.take_shared_by_id<OU>(parent_id);
    let parent_vault = s.take_shared_by_id<CapabilityVault>(parent.capability_vault_id());
    let mut subou = s.take_shared_by_id<OU>(subou_id);
    let preq = proposal::new_privileged_request_for_testing<VPayload>(
        subou_id,
        object::id_from_address(@0x1),
    );
    subou.clear_controller(&preq);
    proposal::consume_execution_request_for_testing(preq);

    let req = proposal::new_permitted_request_for_testing<VPayload>(
        parent_id,
        object::id_from_address(@0x1),
        permissions::vault_borrow(),
    );
    let req = proposal::with_borrow_scope_for_testing(
        req,
        vector[type_name::with_defining_ids<SubOUControl>()],
    );
    let control = parent_vault.borrow_cap<SubOUControl, VPayload>(control_id, &req);
    let _r = controller::privileged_submit(
        control,
        &subou,
        b"x".to_ascii_string(),
        option::none(),
        VPayload {},
        s.ctx(),
    );
    abort 0
}

// === ARMATURE-38: the freeze object must be the OU's own ===

/// Victim with VPayload enabled (and composable) and frozen on its own freeze;
/// an unrelated OU whose freeze is untouched. Returns (victim_id, foreign_freeze_id).
fun frozen_victim(s: &mut Scenario, clock: &mut Clock): (ID, ID) {
    let victim_id = make_ou(s, VICTIM);
    let other_id = make_ou(s, ATTACKER);
    enable<VPayload>(s, victim_id, zero_delay().with_composable_allowed(true));
    clock.set_for_testing(1_000);
    let victim_freeze_id = freeze_id_of(s, victim_id);
    s.next_tx(VICTIM);
    {
        let mut freeze = s.take_shared_by_id<EmergencyFreeze>(victim_freeze_id);
        let cap = s.take_from_sender<FreezeAdminCap>();
        freeze.freeze_type<VPayload>(&cap, clock);
        s.return_to_sender(cap);
        test_scenario::return_shared(freeze);
    };
    (victim_id, freeze_id_of(s, other_id))
}

#[test, expected_failure(abort_code = emergency::EOUMismatch)]
fun foreign_freeze__submit_vote_execute_aborts() {
    let mut s = test_scenario::begin(VICTIM);
    let mut clock = clock::create_for_testing(s.ctx());
    let (victim_id, foreign_id) = frozen_victim(&mut s, &mut clock);

    s.next_tx(VICTIM);
    let mut ou = s.take_shared_by_id<OU>(victim_id);
    let foreign = s.take_shared_by_id<EmergencyFreeze>(foreign_id);
    let _t = board_voting::submit_vote_execute(
        &mut ou,
        option::none(),
        VPayload {},
        &foreign,
        &clock,
        s.ctx(),
    );
    abort 0
}

#[test, expected_failure(abort_code = emergency::EOUMismatch)]
fun foreign_freeze__ticket_from_vote_aborts() {
    let mut s = test_scenario::begin(VICTIM);
    let mut clock = clock::create_for_testing(s.ctx());
    let (victim_id, foreign_id) = frozen_victim(&mut s, &mut clock);

    s.next_tx(VICTIM);
    {
        let ou = s.take_shared_by_id<OU>(victim_id);
        board_voting::submit_proposal(&ou, option::none(), VPayload {}, &clock, s.ctx());
        test_scenario::return_shared(ou);
    };
    s.next_tx(VICTIM);
    {
        let ou = s.take_shared_by_id<OU>(victim_id);
        let mut prop = s.take_shared<Proposal<VPayload>>();
        board_voting::vote(&mut prop, &ou, true, &clock, s.ctx());
        test_scenario::return_shared(prop);
        test_scenario::return_shared(ou);
    };
    s.next_tx(VICTIM);
    let mut ou = s.take_shared_by_id<OU>(victim_id);
    let foreign = s.take_shared_by_id<EmergencyFreeze>(foreign_id);
    let prop = s.take_shared<Proposal<VPayload>>();
    let _t = board_voting::ticket_from_vote(&mut ou, prop, &foreign, &clock, s.ctx());
    abort 0
}

#[test, expected_failure(abort_code = emergency::EOUMismatch)]
fun foreign_freeze__ticket_from_cap_aborts() {
    let mut s = test_scenario::begin(VICTIM);
    let mut clock = clock::create_for_testing(s.ctx());
    let (victim_id, foreign_id) = frozen_victim(&mut s, &mut clock);

    s.next_tx(VICTIM);
    let mut ou = s.take_shared_by_id<OU>(victim_id);
    let foreign = s.take_shared_by_id<EmergencyFreeze>(foreign_id);
    let cap = proposal::new_external_execution_cap_for_testing<VPayload>(victim_id, s.ctx());
    let _t = external_execution::ticket_from_cap(
        &cap,
        &mut ou,
        &foreign,
        option::none(),
        VPayload {},
        internal::permit(),
        &clock,
        s.ctx(),
    );
    abort 0
}

#[test, expected_failure(abort_code = emergency::EOUMismatch)]
fun foreign_freeze__advance_step_aborts() {
    let mut s = test_scenario::begin(VICTIM);
    let mut clock = clock::create_for_testing(s.ctx());
    let (victim_id, foreign_id) = frozen_victim(&mut s, &mut clock);
    passed_composite(&mut s, &clock, victim_id);

    s.next_tx(VICTIM);
    let mut ou = s.take_shared_by_id<OU>(victim_id);
    let own = s.take_shared_by_id<EmergencyFreeze>(ou.emergency_freeze_id());
    let foreign = s.take_shared_by_id<EmergencyFreeze>(foreign_id);
    let mut frame = s.take_shared<CompositeFrame>();
    let prop = s.take_shared<Proposal<CompositePayload>>();
    // The composite type itself is not frozen, so the victim's own freeze passes here.
    let ticket = board_voting::ticket_from_vote(&mut ou, prop, &own, &clock, s.ctx());
    let pipeline = composite::begin_pipeline(&ou, &frame, ticket);
    let (_t, _p) = composite::advance_step<VPayload>(
        &mut ou,
        &mut frame,
        pipeline,
        &foreign,
        &clock,
    );
    abort 0
}

// === ARMATURE-39: only the controller may push caps into a SubOU vault ===

#[test, expected_failure(abort_code = controller::ENotController)]
/// A request from an OU that does not hold the SubOU's registered control
/// cannot deposit into the SubOU's vault.
fun unrelated_ou_cannot_deposit_into_subou_vault() {
    let mut s = test_scenario::begin(VICTIM);
    let parent_id = make_ou(&mut s, VICTIM);
    let (subou_id, _) = make_subou(&mut s, parent_id);
    let atk_id = make_ou(&mut s, ATTACKER);

    s.next_tx(ATTACKER);
    let atk = s.take_shared_by_id<OU>(atk_id);
    let atk_vault = s.take_shared_by_id<CapabilityVault>(atk.capability_vault_id());
    let subou = s.take_shared_by_id<OU>(subou_id);
    let mut subou_vault = s.take_shared_by_id<CapabilityVault>(subou.capability_vault_id());
    let req = proposal::new_permitted_request_for_testing<AtkPayload>(
        atk_id,
        object::id_from_address(@0x1),
        permissions::vault_extract(),
    );
    controller::receive_cap_from_controller(
        &mut subou_vault,
        Junk { id: object::new(s.ctx()) },
        &subou,
        &atk_vault,
        &req,
    );
    abort 0
}

#[test, expected_failure(abort_code = controller::ENotController)]
/// An org has no controller, so nothing can be pushed into its vault
/// this way.
fun cannot_deposit_into_org_vault() {
    let mut s = test_scenario::begin(VICTIM);
    let victim_id = make_ou(&mut s, VICTIM);
    let atk_id = make_ou(&mut s, ATTACKER);

    s.next_tx(ATTACKER);
    let atk = s.take_shared_by_id<OU>(atk_id);
    let atk_vault = s.take_shared_by_id<CapabilityVault>(atk.capability_vault_id());
    let victim = s.take_shared_by_id<OU>(victim_id);
    let mut victim_vault = s.take_shared_by_id<CapabilityVault>(victim.capability_vault_id());
    let req = proposal::new_permitted_request_for_testing<AtkPayload>(
        atk_id,
        object::id_from_address(@0x1),
        permissions::vault_extract(),
    );
    controller::receive_cap_from_controller(
        &mut victim_vault,
        Junk { id: object::new(s.ctx()) },
        &victim,
        &atk_vault,
        &req,
    );
    abort 0
}

#[test, expected_failure(abort_code = controller::EControlMismatch)]
/// The controller vault must belong to the request's OU: a request from an
/// unrelated OU cannot borrow the real controller's vault as its credential.
fun controller_vault_must_match_request() {
    let mut s = test_scenario::begin(VICTIM);
    let parent_id = make_ou(&mut s, VICTIM);
    let (subou_id, _) = make_subou(&mut s, parent_id);
    let atk_id = make_ou(&mut s, ATTACKER);

    s.next_tx(ATTACKER);
    let parent = s.take_shared_by_id<OU>(parent_id);
    let parent_vault = s.take_shared_by_id<CapabilityVault>(parent.capability_vault_id());
    let subou = s.take_shared_by_id<OU>(subou_id);
    let mut subou_vault = s.take_shared_by_id<CapabilityVault>(subou.capability_vault_id());
    let req = proposal::new_permitted_request_for_testing<AtkPayload>(
        atk_id,
        object::id_from_address(@0x1),
        permissions::vault_extract(),
    );
    controller::receive_cap_from_controller(
        &mut subou_vault,
        Junk { id: object::new(s.ctx()) },
        &subou,
        &parent_vault,
        &req,
    );
    abort 0
}

// === ARMATURE-40: advance_step runs only on the pipeline's own, live OU ===

/// Submit and pass a one-step VPayload composite on `ou_id`.
fun passed_composite(s: &mut Scenario, clock: &Clock, ou_id: ID) {
    s.next_tx(VICTIM);
    {
        let mut ou = s.take_shared_by_id<OU>(ou_id);
        ou.test_update_config<CompositePayload>(zero_delay());
        let mut frame = composite::new_frame(ou_id, s.ctx());
        composite::add_step(&mut frame, &ou, VPayload {});
        composite::submit_composite(&ou, frame, option::none(), clock, s.ctx());
        test_scenario::return_shared(ou);
    };
    s.next_tx(VICTIM);
    {
        let ou = s.take_shared_by_id<OU>(ou_id);
        let mut prop = s.take_shared<Proposal<CompositePayload>>();
        board_voting::vote(&mut prop, &ou, true, clock, s.ctx());
        test_scenario::return_shared(prop);
        test_scenario::return_shared(ou);
    };
}

/// Victim with a passed VPayload composite (no bits) and an attacker OU that
/// enables the same type with TREASURY_WITHDRAW. Returns (victim_id, atk_id).
fun composite_setup(s: &mut Scenario, clock: &mut Clock): (ID, ID) {
    let victim_id = make_ou(s, VICTIM);
    fund(s, victim_id, 1_000);
    let atk_id = make_ou(s, ATTACKER);
    enable<VPayload>(s, victim_id, zero_delay().with_composable_allowed(true));
    enable<VPayload>(
        s,
        atk_id,
        zero_delay()
            .with_composable_allowed(true)
            .with_permissions(permissions::treasury_withdraw()),
    );
    clock.set_for_testing(1_000);
    passed_composite(s, clock, victim_id);
    (victim_id, atk_id)
}

#[test, expected_failure(abort_code = composite::EOUIdMismatch)]
/// Passing another OU to advance_step would take that OU's config (and its
/// permission bits) for the victim's step.
fun advance_step_with_foreign_ou_aborts() {
    let mut s = test_scenario::begin(VICTIM);
    let mut clock = clock::create_for_testing(s.ctx());
    let (victim_id, atk_id) = composite_setup(&mut s, &mut clock);

    s.next_tx(VICTIM);
    let mut victim = s.take_shared_by_id<OU>(victim_id);
    let mut atk = s.take_shared_by_id<OU>(atk_id);
    let freeze = s.take_shared_by_id<EmergencyFreeze>(victim.emergency_freeze_id());
    let mut frame = s.take_shared<CompositeFrame>();
    let prop = s.take_shared<Proposal<CompositePayload>>();
    let ticket = board_voting::ticket_from_vote(&mut victim, prop, &freeze, &clock, s.ctx());
    let pipeline = composite::begin_pipeline(&victim, &frame, ticket);
    let (_t, _p) = composite::advance_step<VPayload>(
        &mut atk,
        &mut frame,
        pipeline,
        &freeze,
        &clock,
    );
    abort 0
}

#[test, expected_failure(abort_code = composite::EOUIdMismatch)]
fun begin_pipeline_with_foreign_ou_aborts() {
    let mut s = test_scenario::begin(VICTIM);
    let mut clock = clock::create_for_testing(s.ctx());
    let (victim_id, atk_id) = composite_setup(&mut s, &mut clock);

    s.next_tx(VICTIM);
    let mut victim = s.take_shared_by_id<OU>(victim_id);
    let atk = s.take_shared_by_id<OU>(atk_id);
    let freeze = s.take_shared_by_id<EmergencyFreeze>(victim.emergency_freeze_id());
    let frame = s.take_shared<CompositeFrame>();
    let prop = s.take_shared<Proposal<CompositePayload>>();
    let ticket = board_voting::ticket_from_vote(&mut victim, prop, &freeze, &clock, s.ctx());
    let _p = composite::begin_pipeline(&atk, &frame, ticket);
    abort 0
}

#[test, expected_failure(abort_code = composite::EExecutionPaused)]
fun advance_step_after_execution_pause_aborts() {
    let mut s = test_scenario::begin(VICTIM);
    let mut clock = clock::create_for_testing(s.ctx());
    let (victim_id, _) = composite_setup(&mut s, &mut clock);

    s.next_tx(VICTIM);
    let mut ou = s.take_shared_by_id<OU>(victim_id);
    let freeze = s.take_shared_by_id<EmergencyFreeze>(ou.emergency_freeze_id());
    let mut frame = s.take_shared<CompositeFrame>();
    let prop = s.take_shared<Proposal<CompositePayload>>();
    let ticket = board_voting::ticket_from_vote(&mut ou, prop, &freeze, &clock, s.ctx());
    let pipeline = composite::begin_pipeline(&ou, &frame, ticket);
    let preq = proposal::new_permitted_request_for_testing<VPayload>(
        victim_id,
        object::id_from_address(@0x1),
        permissions::pause(),
    );
    ou.set_execution_paused(true, &preq);
    proposal::consume_execution_request_for_testing(preq);
    let (_t, _p) = composite::advance_step<VPayload>(
        &mut ou,
        &mut frame,
        pipeline,
        &freeze,
        &clock,
    );
    abort 0
}

#[test, expected_failure(abort_code = composite::EControllerPaused)]
fun advance_step_after_controller_pause_aborts() {
    let mut s = test_scenario::begin(VICTIM);
    let mut clock = clock::create_for_testing(s.ctx());
    let (victim_id, _) = composite_setup(&mut s, &mut clock);

    s.next_tx(VICTIM);
    let mut ou = s.take_shared_by_id<OU>(victim_id);
    let freeze = s.take_shared_by_id<EmergencyFreeze>(ou.emergency_freeze_id());
    let mut frame = s.take_shared<CompositeFrame>();
    let prop = s.take_shared<Proposal<CompositePayload>>();
    let ticket = board_voting::ticket_from_vote(&mut ou, prop, &freeze, &clock, s.ctx());
    let pipeline = composite::begin_pipeline(&ou, &frame, ticket);
    let preq = proposal::new_privileged_request_for_testing<VPayload>(
        victim_id,
        object::id_from_address(@0x1),
    );
    ou.set_controller_paused(true, &preq);
    proposal::consume_execution_request_for_testing(preq);
    let (_t, _p) = composite::advance_step<VPayload>(
        &mut ou,
        &mut frame,
        pipeline,
        &freeze,
        &clock,
    );
    abort 0
}

#[test, expected_failure(abort_code = composite::ETypeNotEnabled)]
fun advance_step_after_type_disabled_aborts() {
    let mut s = test_scenario::begin(VICTIM);
    let mut clock = clock::create_for_testing(s.ctx());
    let (victim_id, _) = composite_setup(&mut s, &mut clock);

    s.next_tx(VICTIM);
    let mut ou = s.take_shared_by_id<OU>(victim_id);
    let freeze = s.take_shared_by_id<EmergencyFreeze>(ou.emergency_freeze_id());
    let mut frame = s.take_shared<CompositeFrame>();
    let prop = s.take_shared<Proposal<CompositePayload>>();
    let ticket = board_voting::ticket_from_vote(&mut ou, prop, &freeze, &clock, s.ctx());
    let pipeline = composite::begin_pipeline(&ou, &frame, ticket);
    ou.test_disable_type<VPayload>();
    let (_t, _p) = composite::advance_step<VPayload>(
        &mut ou,
        &mut frame,
        pipeline,
        &freeze,
        &clock,
    );
    abort 0
}

#[test]
/// The happy path is unchanged: the victim's own OU advances its step with
/// the victim's own (empty) bits.
fun advance_step_on_own_ou_succeeds() {
    let mut s = test_scenario::begin(VICTIM);
    let mut clock = clock::create_for_testing(s.ctx());
    let (victim_id, _) = composite_setup(&mut s, &mut clock);

    s.next_tx(VICTIM);
    {
        let mut ou = s.take_shared_by_id<OU>(victim_id);
        let freeze = s.take_shared_by_id<EmergencyFreeze>(ou.emergency_freeze_id());
        let mut frame = s.take_shared<CompositeFrame>();
        let prop = s.take_shared<Proposal<CompositePayload>>();
        let ticket = board_voting::ticket_from_vote(&mut ou, prop, &freeze, &clock, s.ctx());
        let pipeline = composite::begin_pipeline(&ou, &frame, ticket);
        let (step, pipeline) = composite::advance_step<VPayload>(
            &mut ou,
            &mut frame,
            pipeline,
            &freeze,
            &clock,
        );
        let req = step.ticket_request(internal::permit());
        assert!(req.req_ou_id() == victim_id);
        assert!(!req.req_has_permission(permissions::treasury_withdraw()));
        step.discharge(internal::permit());
        composite::finalize_pipeline(pipeline);
        test_scenario::return_shared(frame);
        test_scenario::return_shared(freeze);
        test_scenario::return_shared(ou);
    };
    clock.destroy_for_testing();
    s.end();
}

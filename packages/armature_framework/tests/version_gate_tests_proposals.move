/// ARMATURE-45: one abort test per gated function, part 2 (proposal flow:
/// `proposal`, `board_voting`, `external_execution`, `controller`,
/// `composite`). See `version_gate_tests` for the conventions and helpers.
#[test_only]
module armature::version_gate_tests_proposals;

use armature::board_voting;
use armature::capability_vault::{Self, CapabilityVault};
use armature::composite::{Self, CompositeFrame, Pipeline};
use armature::composite_payload::{Self, CompositePayload};
use armature::controller;
use armature::disable_bypass_type;
use armature::emergency::EmergencyFreeze;
use armature::enable_bypass_type;
use armature::enable_proposal_type;
use armature::external_execution;
use armature::ou::OU;
use armature::proposal::{Self, ExecutionTicket, Proposal};
use armature::update_proposal_config;
use armature::version;
use armature::version_gate_tests::{
    begin,
    config,
    creator,
    new_cap,
    other_id,
    request,
    retired,
    retired_ou,
    retired_request,
    retired_ticket,
    retired_vault,
    second_vault,
    ticket,
    TestCap
};
use std::internal;
use std::type_name;
use sui::clock;
use sui::test_scenario::{Self as ts, Scenario};

/// Payload type defined here, so this module can mint its `Permit`.
public struct Payload has drop, store {}

fun type_key(): std::ascii::String { b"Payload".to_ascii_string() }

/// Share a live `Proposal<Payload>` on the scenario's OU, then start a fresh
/// transaction.
fun share_proposal(sc: &mut Scenario, ou_id: ID) {
    let ou = sc.take_shared<OU>();
    let clock = clock::create_for_testing(sc.ctx());
    proposal::create(
        ou_id,
        type_key(),
        creator(),
        option::none(),
        Payload {},
        config(),
        ou.governance(),
        true,
        version::min_supported(),
        &clock,
        sc.ctx(),
    );
    clock.destroy_for_testing();
    ts::return_shared(ou);
    sc.next_tx(creator());
}

fun retired_proposal(sc: &Scenario): Proposal<Payload> {
    let mut prop = sc.take_shared<Proposal<Payload>>();
    prop.set_proposal_min_version_for_testing(retired());
    prop
}

/// A sealed, empty frame for `ou_id` at MIN_SUPPORTED.
fun sealed_frame(sc: &mut Scenario, ou_id: ID): CompositeFrame {
    let mut frame = composite::new_frame(ou_id, sc.ctx());
    composite::seal_frame(&mut frame);
    frame
}

/// A live composite ticket for `ou_id` whose payload matches `frame` (empty).
fun composite_ticket(frame: &CompositeFrame, ou_id: ID): ExecutionTicket<CompositePayload> {
    let payload = composite_payload::new(object::id(frame), vector[], vector[]);
    proposal::new_composite_ticket_for_testing(ou_id, other_id(), payload)
}

/// A live pipeline begun from `frame` (sealed, empty) on `ou`.
fun pipeline_for(ou: &OU, frame: &CompositeFrame): Pipeline {
    composite::begin_pipeline(ou, frame, composite_ticket(frame, ou.id()))
}

fun retired_frame(sc: &mut Scenario, ou_id: ID): CompositeFrame {
    let mut frame = composite::new_frame(ou_id, sc.ctx());
    frame.set_min_version_for_testing(retired());
    frame
}

// === proposal ===

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun delete_expired_proposal_retired() {
    let (mut sc, ou_id) = begin();
    share_proposal(&mut sc, ou_id);
    let clock = clock::create_for_testing(sc.ctx());
    let prop = retired_proposal(&sc);
    proposal::delete_expired_proposal(prop, &clock);
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun ticket_request_retired() {
    let t = retired_ticket(other_id(), Payload {});
    let _ = t.ticket_request(internal::permit());
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun discharge_retired() {
    let t = retired_ticket(other_id(), Payload {});
    t.discharge(internal::permit());
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun discharge_returning_payload_retired() {
    let t = retired_ticket(other_id(), Payload {});
    let _ = t.discharge_returning_payload(internal::permit());
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun enforce_proposal_version_retired() {
    let (mut sc, ou_id) = begin();
    share_proposal(&mut sc, ou_id);
    let mut prop = retired_proposal(&sc);
    prop.enforce_proposal_version();
    abort
}

// === board_voting ===

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun submit_proposal_retired() {
    let (mut sc, _) = begin();
    let clock = clock::create_for_testing(sc.ctx());
    let ou = retired_ou(&sc);
    board_voting::submit_proposal(&ou, option::none(), Payload {}, &clock, sc.ctx());
    abort
}

/// The proposal's floor is raised; it is checked before the (live) OU.
#[test, expected_failure(abort_code = version::EVersionRetired)]
fun vote_retired() {
    let (mut sc, ou_id) = begin();
    share_proposal(&mut sc, ou_id);
    let clock = clock::create_for_testing(sc.ctx());
    let ou = sc.take_shared<OU>();
    let mut prop = retired_proposal(&sc);
    board_voting::vote(&mut prop, &ou, true, &clock, sc.ctx());
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun submit_vote_execute_retired() {
    let (mut sc, _) = begin();
    let clock = clock::create_for_testing(sc.ctx());
    let freeze = sc.take_shared<EmergencyFreeze>();
    let mut ou = retired_ou(&sc);
    let _t = board_voting::submit_vote_execute(
        &mut ou,
        option::none(),
        Payload {},
        &freeze,
        &clock,
        sc.ctx(),
    );
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun submit_vote_execute_readonly_retired() {
    let (mut sc, _) = begin();
    let clock = clock::create_for_testing(sc.ctx());
    let freeze = sc.take_shared<EmergencyFreeze>();
    let ou = retired_ou(&sc);
    let _t = board_voting::submit_vote_execute_readonly(
        &ou,
        option::none(),
        Payload {},
        &freeze,
        &clock,
        sc.ctx(),
    );
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun ticket_from_vote_retired() {
    let (mut sc, ou_id) = begin();
    share_proposal(&mut sc, ou_id);
    let clock = clock::create_for_testing(sc.ctx());
    let freeze = sc.take_shared<EmergencyFreeze>();
    let prop = sc.take_shared<Proposal<Payload>>();
    let mut ou = retired_ou(&sc);
    let _t = board_voting::ticket_from_vote(&mut ou, prop, &freeze, &clock, sc.ctx());
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun ticket_from_vote_readonly_retired() {
    let (mut sc, ou_id) = begin();
    share_proposal(&mut sc, ou_id);
    let clock = clock::create_for_testing(sc.ctx());
    let freeze = sc.take_shared<EmergencyFreeze>();
    let prop = sc.take_shared<Proposal<Payload>>();
    let ou = retired_ou(&sc);
    let _t = board_voting::ticket_from_vote_readonly(&ou, prop, &freeze, &clock, sc.ctx());
    abort
}

// === external_execution ===

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun ticket_from_cap_retired() {
    let (mut sc, ou_id) = begin();
    let clock = clock::create_for_testing(sc.ctx());
    let cap = proposal::new_external_execution_cap_for_testing<Payload>(ou_id, sc.ctx());
    let freeze = sc.take_shared<EmergencyFreeze>();
    let mut ou = retired_ou(&sc);
    let _t = external_execution::ticket_from_cap(
        &cap,
        &mut ou,
        &freeze,
        option::none(),
        Payload {},
        internal::permit(),
        &clock,
        sc.ctx(),
    );
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun ticket_from_cap_readonly_retired() {
    let (mut sc, ou_id) = begin();
    let clock = clock::create_for_testing(sc.ctx());
    let cap = proposal::new_external_execution_cap_for_testing<Payload>(ou_id, sc.ctx());
    let freeze = sc.take_shared<EmergencyFreeze>();
    let ou = retired_ou(&sc);
    let _t = external_execution::ticket_from_cap_readonly(
        &cap,
        &ou,
        &freeze,
        option::none(),
        Payload {},
        internal::permit(),
        &clock,
        sc.ctx(),
    );
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun execute_enable_bypass_type_retired() {
    let (mut sc, ou_id) = begin();
    let mut vault = sc.take_shared<CapabilityVault>();
    let mut ou = retired_ou(&sc);
    let payload = enable_bypass_type::new(
        type_key(),
        type_name::with_defining_ids<Payload>(),
        config(),
    );
    external_execution::execute_enable_bypass_type<Payload>(
        &mut ou,
        &mut vault,
        ticket(ou_id, payload),
        sc.ctx(),
    );
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun execute_disable_bypass_type_retired() {
    let (sc, ou_id) = begin();
    let mut vault = sc.take_shared<CapabilityVault>();
    let mut ou = retired_ou(&sc);
    let payload = disable_bypass_type::new(type_key(), other_id());
    external_execution::execute_disable_bypass_type<Payload>(
        &mut ou,
        &mut vault,
        ticket(ou_id, payload),
    );
    abort
}

// === controller ===

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun privileged_submit_retired() {
    let (mut sc, ou_id) = begin();
    let control = capability_vault::new_subou_control_for_testing(ou_id, sc.ctx());
    let subou = retired_ou(&sc);
    let _req = controller::privileged_submit(
        &control,
        &subou,
        type_key(),
        option::none(),
        Payload {},
        sc.ctx(),
    );
    abort
}

/// The request is stamped above VERSION.
#[test, expected_failure(abort_code = version::EVersionRetired)]
fun privileged_consume_retired() {
    let (mut sc, ou_id) = begin();
    let control = capability_vault::new_subou_control_for_testing(ou_id, sc.ctx());
    controller::privileged_consume(retired_request<Payload>(ou_id), &control);
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun privileged_extract_retired() {
    let (mut sc, ou_id) = begin();
    let control = capability_vault::new_subou_control_for_testing(ou_id, sc.ctx());
    let subou = sc.take_shared<OU>();
    let mut subou_vault = retired_vault(&sc);
    let _cap = controller::privileged_extract<TestCap>(
        &mut subou_vault,
        other_id(),
        &subou,
        &control,
    );
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun receive_cap_from_controller_retired() {
    let (mut sc, _) = begin();
    let cap = new_cap(&mut sc);
    let controller_vault = second_vault(&mut sc, other_id());
    let subou = sc.take_shared<OU>();
    let mut subou_vault = retired_vault(&sc);
    let req = request<Payload>(other_id());
    controller::receive_cap_from_controller(
        &mut subou_vault,
        cap,
        &subou,
        &controller_vault,
        &req,
    );
    abort
}

// === composite ===

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun add_step_retired() {
    let (mut sc, ou_id) = begin();
    let mut frame = retired_frame(&mut sc, ou_id);
    let ou = sc.take_shared<OU>();
    composite::add_step(&mut frame, &ou, Payload {});
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun add_enable_proposal_type_step_retired() {
    let (mut sc, ou_id) = begin();
    let mut frame = retired_frame(&mut sc, ou_id);
    let ou = sc.take_shared<OU>();
    let payload = enable_proposal_type::new(
        type_key(),
        type_name::with_defining_ids<Payload>(),
        config(),
    );
    composite::add_enable_proposal_type_step(&mut frame, &ou, payload);
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun add_update_proposal_config_step_retired() {
    let (mut sc, ou_id) = begin();
    let mut frame = retired_frame(&mut sc, ou_id);
    let ou = sc.take_shared<OU>();
    let payload = update_proposal_config::new(
        type_key(),
        option::none(),
        option::none(),
        option::none(),
        option::none(),
        option::none(),
        option::none(),
        option::none(),
    );
    composite::add_update_proposal_config_step(&mut frame, &ou, payload);
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun submit_composite_retired() {
    let (mut sc, ou_id) = begin();
    let clock = clock::create_for_testing(sc.ctx());
    let frame = composite::new_frame(ou_id, sc.ctx());
    let ou = retired_ou(&sc);
    composite::submit_composite(&ou, frame, option::none(), &clock, sc.ctx());
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun begin_pipeline_retired() {
    let (mut sc, ou_id) = begin();
    let frame = sealed_frame(&mut sc, ou_id);
    let ou = retired_ou(&sc);
    let _pipeline = composite::begin_pipeline(&ou, &frame, composite_ticket(&frame, ou_id));
    abort
}

/// The pipeline was begun while the OU was live; the OU's floor rose after.
#[test, expected_failure(abort_code = version::EVersionRetired)]
fun advance_step_retired() {
    let (mut sc, ou_id) = begin();
    let clock = clock::create_for_testing(sc.ctx());
    let mut frame = sealed_frame(&mut sc, ou_id);
    let freeze = sc.take_shared<EmergencyFreeze>();
    let mut ou = sc.take_shared<OU>();
    let pipeline = pipeline_for(&ou, &frame);
    ou.set_min_version_for_testing(retired());
    let (_t, _pipeline) = composite::advance_step<Payload>(
        &mut ou,
        &mut frame,
        pipeline,
        &freeze,
        &clock,
    );
    abort
}

/// The pipeline is stamped above VERSION (a newer release began it).
#[test, expected_failure(abort_code = version::EVersionRetired)]
fun finalize_pipeline_retired() {
    let (mut sc, ou_id) = begin();
    let frame = sealed_frame(&mut sc, ou_id);
    let ou = sc.take_shared<OU>();
    let pipeline = composite::pipeline_with_min_version_for_testing(
        pipeline_for(&ou, &frame),
        retired(),
    );
    composite::finalize_pipeline(pipeline);
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun delete_exhausted_frame_retired() {
    let (mut sc, ou_id) = begin();
    let frame = retired_frame(&mut sc, ou_id);
    composite::delete_exhausted_frame(frame);
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun enforce_version_retired_composite() {
    let (mut sc, ou_id) = begin();
    let mut frame = retired_frame(&mut sc, ou_id);
    frame.enforce_version();
    abort
}

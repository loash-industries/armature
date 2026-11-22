/// ARMATURE-47: the version gate works both ways.
///
/// Hot potatoes are stamped with `version::raised(...)` of the floors they came
/// from, and consumers reject a stamp below `MIN_SUPPORTED`
/// (`version::EMintedByRetiredVersion`). Only a retired release can mint such a
/// stamp, so this stops current code from spending authority that retired code
/// minted. Unsealed composite frames are owned and can't be swept, so they are
/// never raised: building on or submitting one below `MIN_SUPPORTED` aborts.
///
/// A stale stamp is `version::stale_stamp_for_testing()` (`MIN_SUPPORTED - 1`).
#[test_only]
module armature::version_stamp_tests;

use armature::capability_vault::CapabilityVault;
use armature::composite::{Self, CompositeFrame};
use armature::composite_payload;
use armature::ou::OU;
use armature::proposal::{Self, Proposal};
use armature::treasury_vault::TreasuryVault;
use armature::version;
use armature::version_gate_tests::{
    begin,
    config,
    creator,
    new_cap,
    other_id,
    request,
    ticket,
    TestCap
};
use std::internal;
use std::type_name;
use sui::clock;
use sui::sui::SUI;
use sui::test_scenario as ts;

public struct Payload has drop, store {}

fun stale(): u64 { version::stale_stamp_for_testing() }

// === version ===

#[test]
fun stamp_at_min_supported_is_accepted() {
    version::assert_stamp_supported(version::min_supported());
    version::assert_stamp_supported(version::current());
}

#[test, expected_failure(abort_code = version::EMintedByRetiredVersion)]
fun stamp_below_min_supported_aborts() {
    version::assert_stamp_supported(stale());
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun stamp_above_version_aborts_retired() {
    version::assert_stamp_supported(version::retired_floor_for_testing());
}

// === Minting raises the stamp ===

#[test]
fun new_request_is_stamped_at_least_min_supported() {
    let req = proposal::new_execution_request<Payload>(other_id(), other_id(), stale());
    assert!(req.req_min_version() == version::min_supported());
    proposal::consume(req);
}

#[test]
fun privileged_request_is_stamped_at_least_min_supported() {
    let mut sc = ts::begin(creator());
    let req = proposal::privileged_execute<Payload>(
        other_id(),
        b"Payload".to_ascii_string(),
        creator(),
        option::none(),
        &Payload {},
        0,
        vector[],
        true,
        stale(),
        sc.ctx(),
    );
    assert!(req.req_min_version() == version::min_supported());
    proposal::consume(req);
    sc.end();
}

#[test]
fun composite_ticket_is_stamped_at_least_min_supported() {
    let t = proposal::new_ticket_composite(
        other_id(),
        other_id(),
        Payload {},
        0,
        vector[],
        stale(),
    );
    assert!(t.ticket_min_version() == version::min_supported());
    t.discharge(internal::permit());
}

#[test]
fun proposal_from_unswept_ou_starts_at_min_supported() {
    let (mut sc, ou_id) = begin();
    let mut ou = sc.take_shared<OU>();
    ou.set_min_version_for_testing(stale());
    let clock = clock::create_for_testing(sc.ctx());
    proposal::create(
        ou_id,
        b"Payload".to_ascii_string(),
        creator(),
        option::none(),
        Payload {},
        config(),
        ou.governance(),
        true,
        ou.min_version(),
        &clock,
        sc.ctx(),
    );
    clock.destroy_for_testing();
    ts::return_shared(ou);
    sc.next_tx(creator());
    let prop = sc.take_shared<Proposal<Payload>>();
    assert!(prop.proposal_min_version() == version::min_supported());
    ts::return_shared(prop);
    sc.end();
}

#[test]
fun loan_from_unswept_vault_is_stamped_at_least_min_supported() {
    let (mut sc, ou_id) = begin();
    let mut vault = sc.take_shared<CapabilityVault>();
    vault.set_min_version_for_testing(stale());
    let cap = new_cap(&mut sc);
    let cap_id = object::id(&cap);
    vault.store_cap_for_testing(cap);
    let req = proposal::with_borrow_scope_for_testing(
        request<Payload>(ou_id),
        vector[type_name::with_defining_ids<TestCap>()],
    );
    let (cap, loan) = vault.loan_cap<TestCap, Payload>(cap_id, &req);
    assert!(loan.loan_min_version() == version::min_supported());
    vault.return_cap(cap, loan);
    proposal::consume_execution_request_for_testing(req);
    ts::return_shared(vault);
    sc.end();
}

#[test]
fun pipeline_takes_the_ou_floor() {
    let (mut sc, ou_id) = begin();
    let ou = sc.take_shared<OU>();
    let mut frame = composite::new_frame(ou_id, sc.ctx());
    composite::seal_frame(&mut frame);
    let payload = composite_payload::new(object::id(&frame), vector[], vector[]);
    let t = proposal::new_composite_ticket_for_testing(ou_id, other_id(), payload);
    let pipeline = composite::begin_pipeline(&ou, &frame, t);
    assert!(pipeline.pipeline_min_version() == version::min_supported());
    composite::finalize_pipeline(pipeline);
    transfer::public_share_object(frame);
    ts::return_shared(ou);
    sc.end();
}

// === Consumers reject stale stamps ===

#[test, expected_failure(abort_code = version::EMintedByRetiredVersion)]
fun ticket_request_rejects_stale_ticket() {
    let t = proposal::ticket_with_min_version_for_testing(ticket(other_id(), Payload {}), stale());
    let _ = t.ticket_request(internal::permit());
    abort
}

#[test, expected_failure(abort_code = version::EMintedByRetiredVersion)]
fun discharge_rejects_stale_ticket() {
    let t = proposal::ticket_with_min_version_for_testing(ticket(other_id(), Payload {}), stale());
    t.discharge(internal::permit());
    abort
}

#[test, expected_failure(abort_code = version::EMintedByRetiredVersion)]
fun discharge_returning_payload_rejects_stale_ticket() {
    let t = proposal::ticket_with_min_version_for_testing(ticket(other_id(), Payload {}), stale());
    let _ = t.discharge_returning_payload(internal::permit());
    abort
}

#[test, expected_failure(abort_code = version::EMintedByRetiredVersion)]
fun consume_rejects_stale_request() {
    let req = proposal::with_min_version_for_testing(request<Payload>(other_id()), stale());
    proposal::consume(req);
    abort
}

/// The audit scenario: authority minted from an OU nobody swept, spent against
/// a treasury that is already at the new floor.
#[test, expected_failure(abort_code = version::EMintedByRetiredVersion)]
fun withdraw_rejects_stale_request_on_raised_treasury() {
    let (mut sc, ou_id) = begin();
    let mut treasury = sc.take_shared<TreasuryVault>();
    let req = proposal::with_min_version_for_testing(request<Payload>(ou_id), stale());
    let _coin = treasury.withdraw<SUI, Payload>(1, &req, sc.ctx());
    abort
}

#[test, expected_failure(abort_code = version::EMintedByRetiredVersion)]
fun return_cap_rejects_stale_loan() {
    let (mut sc, ou_id) = begin();
    let mut vault = sc.take_shared<CapabilityVault>();
    let cap = new_cap(&mut sc);
    let cap_id = object::id(&cap);
    vault.store_cap_for_testing(cap);
    let req = proposal::with_borrow_scope_for_testing(
        request<Payload>(ou_id),
        vector[type_name::with_defining_ids<TestCap>()],
    );
    let (cap, loan) = vault.loan_cap<TestCap, Payload>(cap_id, &req);
    let loan = armature::capability_vault::cap_loan_with_min_version_for_testing(loan, stale());
    vault.return_cap(cap, loan);
    abort
}

#[test, expected_failure(abort_code = version::EMintedByRetiredVersion)]
fun finalize_pipeline_rejects_stale_pipeline() {
    let (mut sc, ou_id) = begin();
    let ou = sc.take_shared<OU>();
    let mut frame = composite::new_frame(ou_id, sc.ctx());
    composite::seal_frame(&mut frame);
    let payload = composite_payload::new(object::id(&frame), vector[], vector[]);
    let t = proposal::new_composite_ticket_for_testing(ou_id, other_id(), payload);
    let pipeline = composite::pipeline_with_min_version_for_testing(
        composite::begin_pipeline(&ou, &frame, t),
        stale(),
    );
    composite::finalize_pipeline(pipeline);
    abort
}

// === Unsealed frames ===

fun stale_frame(sc: &mut ts::Scenario, ou_id: ID): CompositeFrame {
    let mut frame = composite::new_frame(ou_id, sc.ctx());
    frame.set_min_version_for_testing(stale());
    frame
}

#[test, expected_failure(abort_code = version::EMintedByRetiredVersion)]
fun add_step_rejects_frame_built_by_retired_release() {
    let (mut sc, ou_id) = begin();
    let mut frame = stale_frame(&mut sc, ou_id);
    let ou = sc.take_shared<OU>();
    composite::add_step(&mut frame, &ou, Payload {});
    abort
}

#[test, expected_failure(abort_code = version::EMintedByRetiredVersion)]
fun submit_composite_rejects_frame_built_by_retired_release() {
    let (mut sc, ou_id) = begin();
    let clock = clock::create_for_testing(sc.ctx());
    let frame = stale_frame(&mut sc, ou_id);
    let ou = sc.take_shared<OU>();
    composite::submit_composite(&ou, frame, option::none(), &clock, sc.ctx());
    abort
}

/// The owner can't launder a stale unsealed frame through `enforce_version`.
#[test, expected_failure(abort_code = version::EMintedByRetiredVersion)]
fun enforce_version_refuses_stale_unsealed_frame() {
    let (mut sc, ou_id) = begin();
    let mut frame = stale_frame(&mut sc, ou_id);
    frame.enforce_version();
    abort
}

#[test]
fun enforce_version_leaves_current_unsealed_frame_alone() {
    let (mut sc, ou_id) = begin();
    let mut frame = composite::new_frame(ou_id, sc.ctx());
    frame.enforce_version();
    assert!(frame.min_version() == version::min_supported());
    composite::seal_frame(&mut frame);
    transfer::public_share_object(frame);
    sc.end();
}

#[test]
fun enforce_version_raises_sealed_frame() {
    let (mut sc, ou_id) = begin();
    let mut frame = stale_frame(&mut sc, ou_id);
    composite::seal_frame(&mut frame);
    frame.enforce_version();
    assert!(frame.min_version() == version::min_supported());
    transfer::public_share_object(frame);
    sc.end();
}

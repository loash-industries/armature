/// ARMATURE-45: the `version` module, `enforce_version`, floor inheritance at
/// creation, and hot-potato stamps. One abort test per gated function lives in
/// `version_gate_tests`.
#[test_only]
module armature::version_tests;

use armature::capability_vault::CapabilityVault;
use armature::charter::Charter;
use armature::emergency::EmergencyFreeze;
use armature::governance;
use armature::ou::{Self, OU};
use armature::proposal;
use armature::remove_member::RemoveMember;
use armature::treasury_vault::TreasuryVault;
use armature::version;
use std::string;
use sui::test_scenario::{Self as ts, Scenario};

const CREATOR: address = @0xA;
const MEMBER: address = @0xB;

fun create_ou(scenario: &mut Scenario): ID {
    scenario.next_tx(CREATOR);
    ou::create(
        &governance::init_board(vector[CREATOR, MEMBER]),
        string::utf8(b"OU"),
        string::utf8(b"u"),
        scenario.ctx(),
    )
}

// === version module ===

#[test]
fun constants_are_sane() {
    assert!(version::min_supported() <= version::current());
    assert!(version::is_supported(version::current()));
    assert!(version::is_supported(version::min_supported()));
    assert!(!version::is_supported(version::retired_floor_for_testing()));
}

#[test]
fun raised_never_lowers() {
    let min = version::min_supported();
    assert!(version::raised(0) == min);
    assert!(version::raised(min) == min);
    assert!(version::raised(min + 7) == min + 7);
    assert!(version::floor_for_new(0) == min);
    assert!(version::floor_for_new(min + 3) == min + 3);
}

#[test]
fun assert_supported_passes_up_to_current() {
    version::assert_supported(0);
    version::assert_supported(version::current());
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun assert_supported_aborts_above_current() {
    version::assert_supported(version::retired_floor_for_testing());
}

// === Creation ===

/// A new OU and its four companions start at MIN_SUPPORTED.
#[test]
fun new_ou_and_companions_start_at_min_supported() {
    let mut sc = ts::begin(CREATOR);
    create_ou(&mut sc);
    sc.next_tx(CREATOR);
    let min = version::min_supported();
    let ou = sc.take_shared<OU>();
    let treasury = sc.take_shared<TreasuryVault>();
    let vault = sc.take_shared<CapabilityVault>();
    let charter = sc.take_shared<Charter>();
    let freeze = sc.take_shared<EmergencyFreeze>();
    assert!(ou.min_version() == min);
    assert!(treasury.min_version() == min);
    assert!(vault.min_version() == min);
    assert!(charter.min_version() == min);
    assert!(freeze.min_version() == min);
    ts::return_shared(freeze);
    ts::return_shared(charter);
    ts::return_shared(vault);
    ts::return_shared(treasury);
    ts::return_shared(ou);
    sc.end();
}

/// `create_with_floor` (SpawnOU successors) gives the OU and every companion
/// the parent's floor when it is above MIN_SUPPORTED, and MIN_SUPPORTED below.
#[test]
fun create_with_floor_inherits_the_parent_floor() {
    let mut sc = ts::begin(CREATOR);
    sc.next_tx(CREATOR);
    let high = version::min_supported() + 5;
    ou::create_with_floor(
        &governance::init_board(vector[CREATOR]),
        string::utf8(b"Successor"),
        string::utf8(b"u"),
        high,
        sc.ctx(),
    );
    sc.next_tx(CREATOR);
    let ou = sc.take_shared<OU>();
    let treasury = sc.take_shared<TreasuryVault>();
    let vault = sc.take_shared<CapabilityVault>();
    let charter = sc.take_shared<Charter>();
    let freeze = sc.take_shared<EmergencyFreeze>();
    assert!(ou.min_version() == high);
    assert!(treasury.min_version() == high);
    assert!(vault.min_version() == high);
    assert!(charter.min_version() == high);
    assert!(freeze.min_version() == high);
    ts::return_shared(freeze);
    ts::return_shared(charter);
    ts::return_shared(vault);
    ts::return_shared(treasury);
    ts::return_shared(ou);
    sc.end();
}

#[test]
fun create_with_floor_never_goes_below_min_supported() {
    let mut sc = ts::begin(CREATOR);
    sc.next_tx(CREATOR);
    ou::create_with_floor(
        &governance::init_board(vector[CREATOR]),
        string::utf8(b"Successor"),
        string::utf8(b"u"),
        0,
        sc.ctx(),
    );
    sc.next_tx(CREATOR);
    let ou = sc.take_shared<OU>();
    assert!(ou.min_version() == version::min_supported());
    ts::return_shared(ou);
    sc.end();
}

// === enforce_version ===

/// enforce raises a floor below MIN_SUPPORTED and emits VersionFloorRaised.
#[test]
fun enforce_raises_a_low_floor_and_emits() {
    let mut sc = ts::begin(CREATOR);
    let ou_id = create_ou(&mut sc);
    sc.next_tx(CREATOR);
    {
        let mut ou = sc.take_shared<OU>();
        ou.set_min_version_for_testing(0);
        ou.enforce_version();
        assert!(ou.min_version() == version::min_supported());
        let events = sui::event::events_by_type<version::VersionFloorRaised>();
        assert!(events.length() == 1);
        let (id, old_floor, new_floor) = version::floor_raised_event_for_testing(&events[0]);
        assert!(id == ou_id && old_floor == 0 && new_floor == version::min_supported());
        ts::return_shared(ou);
    };
    let effects = sc.next_tx(CREATOR);
    assert!(effects.num_user_events() == 1);
    sc.end();
}

/// enforce never lowers a floor and emits nothing when the floor doesn't move.
#[test]
fun enforce_never_lowers_and_is_quiet_at_the_floor() {
    let mut sc = ts::begin(CREATOR);
    create_ou(&mut sc);
    sc.next_tx(CREATOR);
    {
        let mut ou = sc.take_shared<OU>();
        ou.enforce_version();
        assert!(ou.min_version() == version::min_supported());
        ts::return_shared(ou);
    };
    let effects = sc.next_tx(CREATOR);
    assert!(effects.num_user_events() == 0);
    sc.end();
}

/// A retired release can't run enforce either: it aborts rather than act.
#[test, expected_failure(abort_code = version::EVersionRetired)]
fun enforce_aborts_on_a_retired_object() {
    let mut sc = ts::begin(CREATOR);
    create_ou(&mut sc);
    sc.next_tx(CREATOR);
    let mut ou = sc.take_shared<OU>();
    ou.set_min_version_for_testing(version::retired_floor_for_testing());
    ou.enforce_version();
    abort
}

/// A gated &mut path raises a low floor on its own (objects in use move forward).
#[test]
fun gated_mut_path_raises_the_floor() {
    let mut sc = ts::begin(CREATOR);
    let ou_id = create_ou(&mut sc);
    sc.next_tx(CREATOR);
    let mut ou = sc.take_shared<OU>();
    ou.set_min_version_for_testing(0);
    let req = proposal::new_execution_request_for_testing<RemoveMember>(ou_id, @0x1.to_id());
    ou.remove_board_member_governance(MEMBER, &req);
    proposal::consume_execution_request_for_testing(req);
    assert!(ou.min_version() == version::min_supported());
    ts::return_shared(ou);
    sc.end();
}

// === Retired objects and hot potatoes ===

/// A gated call on an object whose floor is above VERSION aborts.
#[test, expected_failure(abort_code = version::EVersionRetired)]
fun gated_call_on_retired_object_aborts() {
    let mut sc = ts::begin(CREATOR);
    let ou_id = create_ou(&mut sc);
    sc.next_tx(CREATOR);
    let mut ou = sc.take_shared<OU>();
    ou.set_min_version_for_testing(version::retired_floor_for_testing());
    let req = proposal::new_execution_request_for_testing<RemoveMember>(ou_id, @0x1.to_id());
    ou.remove_board_member_governance(MEMBER, &req);
    abort
}

/// A request stamped above VERSION is refused even on an object this release
/// may act on: an old consumer can't finish work begun on a newer floor.
#[test, expected_failure(abort_code = version::EVersionRetired)]
fun retired_request_on_live_object_aborts() {
    let mut sc = ts::begin(CREATOR);
    let ou_id = create_ou(&mut sc);
    sc.next_tx(CREATOR);
    let mut ou = sc.take_shared<OU>();
    let req = proposal::with_min_version_for_testing(
        proposal::new_execution_request_for_testing<RemoveMember>(ou_id, @0x1.to_id()),
        version::retired_floor_for_testing(),
    );
    ou.remove_board_member_governance(MEMBER, &req);
    abort
}

/// Getters stay ungated, so old-linked dependents can still read a retired object.
#[test]
fun getters_work_on_a_retired_object() {
    let mut sc = ts::begin(CREATOR);
    create_ou(&mut sc);
    sc.next_tx(CREATOR);
    let mut ou = sc.take_shared<OU>();
    ou.set_min_version_for_testing(version::retired_floor_for_testing());
    assert!(ou.is_governance_member(CREATOR));
    assert!(ou.status().is_active());
    let _ = ou.id();
    ts::return_shared(ou);
    sc.end();
}

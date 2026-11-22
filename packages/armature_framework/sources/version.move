/// Version gating (ARMATURE-45).
///
/// On Sui every published version of a package stays callable forever, and a
/// struct made by one version is the same type in all of them. So a fix to a
/// public function means nothing unless the old copy can be switched off. This
/// module is how the framework switches old copies off, object by object.
///
/// - `VERSION` is this release's package version. Bump it on every upgrade.
/// - `MIN_SUPPORTED` is the oldest version this release still trusts. A routine
/// upgrade leaves it alone; a security upgrade raises it to `VERSION`.
/// - Every shared framework object stores `min_version`, the oldest version
/// allowed to act on it. A new object starts at `MIN_SUPPORTED`, or at its
/// parent's floor if that is higher.
/// - Every function that changes framework state checks
/// `VERSION >= min_version` first (`assert_supported`) and aborts with
/// `EVersionRetired` otherwise. Paths that take the object `&mut` also raise
/// its floor to `MIN_SUPPORTED` (`check_and_raise`), so objects in use move
/// forward on their own.
/// - Hot potatoes (`ExecutionRequest`, `CapLoan`, `Pipeline`, `AssetTransfer`)
/// copy the floor of the object they came from, and every consumer checks it,
/// so retired code cannot finish work that started on a newer floor.
/// - Each object module has a permissionless `enforce_version`, which only
/// raises the floor to `MIN_SUPPORTED`. A security upgrade is followed by a
/// sweep that calls it on every live object. There is no admin key and no
/// global shared object: the floor comes from code the UpgradeCap holder
/// published.
///
/// Design: "Version gating for armature_framework" (linked from ARMATURE-45).
module armature::version;

use sui::event;

// === Constants ===

/// This release's package version. Bump on every upgrade, routine or security.
const VERSION: u64 = 1;

/// The oldest package version this release still trusts. Leave it on a routine
/// upgrade; set it to `VERSION` on a security upgrade, then sweep `enforce_version`.
const MIN_SUPPORTED: u64 = 1;

// === Errors ===

/// This package version is retired for the object (or hot potato) it was given:
/// the object's `min_version` is above `VERSION`. Call the newest package.
const EVersionRetired: u64 = 0;

// === Events ===

/// Emitted when an object's floor moves up, through `enforce_version` or any
/// gated `&mut` path. Lets an indexer track a sweep and list objects still below
/// `MIN_SUPPORTED`.
public struct VersionFloorRaised has copy, drop {
    object_id: ID,
    old_floor: u64,
    new_floor: u64,
}

// === Public ===

/// This release's package version.
public fun current(): u64 { VERSION }

/// The oldest package version this release trusts.
public fun min_supported(): u64 { MIN_SUPPORTED }

/// Whether this release may act on something whose floor is `min_version`.
public fun is_supported(min_version: u64): bool { VERSION >= min_version }

// === Package ===

/// Abort with `EVersionRetired` unless this release may act on something whose
/// floor is `min_version`.
public(package) fun assert_supported(min_version: u64) {
    assert!(VERSION >= min_version, EVersionRetired);
}

/// `min_version` raised to this release's `MIN_SUPPORTED`; never lowered.
public(package) fun raised(min_version: u64): u64 {
    if (min_version < MIN_SUPPORTED) MIN_SUPPORTED else min_version
}

/// The floor for an object created under a parent whose floor is
/// `parent_floor` (`MIN_SUPPORTED` when there is no parent).
public(package) fun floor_for_new(parent_floor: u64): u64 { raised(parent_floor) }

/// Check `min_version` and return it raised to `MIN_SUPPORTED`, emitting
/// `VersionFloorRaised` when it moves. For gated `&mut` paths and
/// `enforce_version`: assign the result back to the object's field.
public(package) fun check_and_raise(object_id: ID, min_version: u64): u64 {
    assert_supported(min_version);
    let new_floor = raised(min_version);
    if (new_floor != min_version) {
        event::emit(VersionFloorRaised { object_id, old_floor: min_version, new_floor });
    };
    new_floor
}

// === Test helpers ===

/// A floor this release can't act on: `VERSION + 1`.
#[test_only]
public fun retired_floor_for_testing(): u64 { VERSION + 1 }

#[test_only]
public fun floor_raised_event_for_testing(e: &VersionFloorRaised): (ID, u64, u64) {
    (e.object_id, e.old_floor, e.new_floor)
}

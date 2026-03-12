module armature::emergency;

use sui::clock::Clock;
use sui::event;
use sui::vec_map::{Self, VecMap};

// === Errors ===

const EDAOMismatch: u64 = 0;
const EProtectedType: u64 = 1;
const EFrozen: u64 = 2;
const ENotFrozen: u64 = 3;

// === Constants ===

const DEFAULT_MAX_FREEZE_DURATION_MS: u64 = 604_800_000; // 7 days

/// Protected type keys that cannot be frozen.
const PROTECTED_TRANSFER_FREEZE_ADMIN: vector<u8> = b"TransferFreezeAdmin";
const PROTECTED_UNFREEZE_PROPOSAL_TYPE: vector<u8> = b"UnfreezeProposalType";

// === Structs ===

/// Tracks frozen proposal types and their expiry times.
/// Created as a shared object during DAO creation.
public struct EmergencyFreeze has key, store {
    id: UID,
    dao_id: ID,
    frozen_types: VecMap<std::ascii::String, u64>,
    max_freeze_duration_ms: u64,
}

/// Admin capability for triggering emergency freezes.
/// Transferred to the DAO creator at creation time.
public struct FreezeAdminCap has key, store {
    id: UID,
    dao_id: ID,
}

// === Events ===

public struct TypeFrozen has copy, drop {
    dao_id: ID,
    type_key: std::ascii::String,
    expiry_ms: u64,
}

public struct TypeUnfrozen has copy, drop {
    dao_id: ID,
    type_key: std::ascii::String,
}

// === Constructor ===

/// Create a new EmergencyFreeze. Only callable within the framework package.
public(package) fun new(dao_id: ID, ctx: &mut TxContext): EmergencyFreeze {
    EmergencyFreeze {
        id: object::new(ctx),
        dao_id,
        frozen_types: vec_map::empty(),
        max_freeze_duration_ms: DEFAULT_MAX_FREEZE_DURATION_MS,
    }
}

/// Create the FreezeAdminCap. Only callable within the framework package.
public(package) fun new_admin_cap(dao_id: ID, ctx: &mut TxContext): FreezeAdminCap {
    FreezeAdminCap {
        id: object::new(ctx),
        dao_id,
    }
}

/// Share the freeze object as a shared object.
#[allow(lint(share_owned, custom_state_change))]
public(package) fun share(freeze: EmergencyFreeze) {
    transfer::share_object(freeze);
}

/// Transfer the FreezeAdminCap to a recipient. Only callable within the framework package.
#[allow(lint(custom_state_change))]
public(package) fun transfer_admin_cap(cap: FreezeAdminCap, recipient: address) {
    transfer::transfer(cap, recipient);
}

// === Accessors ===

/// Returns the DAO ID this freeze tracker belongs to.
public fun dao_id(self: &EmergencyFreeze): ID { self.dao_id }

/// Returns the max freeze duration in milliseconds.
public fun max_freeze_duration_ms(self: &EmergencyFreeze): u64 { self.max_freeze_duration_ms }

/// Returns the DAO ID the admin cap is bound to.
public fun admin_cap_dao_id(self: &FreezeAdminCap): ID { self.dao_id }

/// Returns the frozen types map (type_key → expiry_ms).
public fun frozen_types(self: &EmergencyFreeze): &VecMap<std::ascii::String, u64> {
    &self.frozen_types
}

/// Check if a type is currently frozen. Compares expiry against the clock.
/// Returns true only if the type is in frozen_types AND the freeze has not expired.
public fun is_frozen(self: &EmergencyFreeze, type_key: &std::ascii::String, clock: &Clock): bool {
    if (!self.frozen_types.contains(type_key)) {
        return false
    };
    let expiry_ms = *self.frozen_types.get(type_key);
    clock.timestamp_ms() < expiry_ms
}

/// Assert that a type is not frozen. Aborts with EFrozen if it is.
public fun assert_not_frozen(self: &EmergencyFreeze, type_key: &std::ascii::String, clock: &Clock) {
    assert!(!self.is_frozen(type_key, clock), EFrozen);
}

// === Freeze ===

/// Freeze a proposal type. Only the FreezeAdminCap holder can call this.
/// The freeze expires at `now + max_freeze_duration_ms`.
/// Cannot freeze protected types (TransferFreezeAdmin, UnfreezeProposalType).
public fun freeze_type(
    self: &mut EmergencyFreeze,
    cap: &FreezeAdminCap,
    type_key: std::ascii::String,
    clock: &Clock,
) {
    assert!(cap.dao_id == self.dao_id, EDAOMismatch);
    assert!(!is_protected(&type_key), EProtectedType);

    let expiry_ms = clock.timestamp_ms() + self.max_freeze_duration_ms;

    if (self.frozen_types.contains(&type_key)) {
        let entry = self.frozen_types.get_mut(&type_key);
        *entry = expiry_ms;
    } else {
        self.frozen_types.insert(type_key, expiry_ms);
    };

    event::emit(TypeFrozen {
        dao_id: self.dao_id,
        type_key,
        expiry_ms,
    });
}

// === Unfreeze ===

/// Unfreeze a type using the FreezeAdminCap.
public fun unfreeze_type(
    self: &mut EmergencyFreeze,
    cap: &FreezeAdminCap,
    type_key: std::ascii::String,
) {
    assert!(cap.dao_id == self.dao_id, EDAOMismatch);
    assert!(self.frozen_types.contains(&type_key), ENotFrozen);

    self.frozen_types.remove(&type_key);

    event::emit(TypeUnfrozen {
        dao_id: self.dao_id,
        type_key,
    });
}

/// Unfreeze a type via governance (UnfreezeProposalType execution).
/// Only callable within the framework package.
public(package) fun governance_unfreeze(self: &mut EmergencyFreeze, type_key: std::ascii::String) {
    assert!(self.frozen_types.contains(&type_key), ENotFrozen);

    self.frozen_types.remove(&type_key);

    event::emit(TypeUnfrozen {
        dao_id: self.dao_id,
        type_key,
    });
}

/// Update the max freeze duration. Only callable within the framework package.
public(package) fun set_max_freeze_duration_ms(self: &mut EmergencyFreeze, new_max: u64) {
    self.max_freeze_duration_ms = new_max;
}

// === Internal ===

/// Returns true if the type_key is a protected type that cannot be frozen.
fun is_protected(type_key: &std::ascii::String): bool {
    *type_key == PROTECTED_TRANSFER_FREEZE_ADMIN.to_ascii_string()
        || *type_key == PROTECTED_UNFREEZE_PROPOSAL_TYPE.to_ascii_string()
}

// === Test Helpers ===

#[test_only]
public fun new_for_testing(dao_id: ID, ctx: &mut TxContext): EmergencyFreeze {
    new(dao_id, ctx)
}

#[test_only]
public fun new_admin_cap_for_testing(dao_id: ID, ctx: &mut TxContext): FreezeAdminCap {
    new_admin_cap(dao_id, ctx)
}

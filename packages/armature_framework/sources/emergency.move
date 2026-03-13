module armature::emergency;

use armature::proposal::ExecutionRequest;
use sui::clock::Clock;
use sui::event;
use sui::vec_map::{Self, VecMap};
use sui::vec_set::{Self, VecSet};

// === Errors ===

const EDAOMismatch: u64 = 0;
const EProtectedType: u64 = 1;
const EFrozen: u64 = 2;
const ENotFrozen: u64 = 3;
const EMandatoryExemptType: u64 = 4;

// === Constants ===

const DEFAULT_MAX_FREEZE_DURATION_MS: u64 = 604_800_000; // 7 days

/// Mandatory freeze-exempt type keys that can never be removed from the exempt set.
const MANDATORY_EXEMPT_TYPES: vector<vector<u8>> = vector[
    b"TransferFreezeAdmin",
    b"UnfreezeProposalType",
];

// === Structs ===

/// Tracks frozen proposal types and their expiry times.
/// Created as a shared object during DAO creation.
public struct EmergencyFreeze has key, store {
    id: UID,
    dao_id: ID,
    frozen_types: VecMap<std::ascii::String, u64>,
    max_freeze_duration_ms: u64,
    freeze_exempt_types: VecSet<std::ascii::String>,
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

public struct FreezeExemptTypeAdded has copy, drop {
    dao_id: ID,
    type_key: std::ascii::String,
}

public struct FreezeExemptTypeRemoved has copy, drop {
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
        freeze_exempt_types: default_exempt_types(),
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

/// Returns true if no types are currently frozen.
public fun is_empty(self: &EmergencyFreeze): bool {
    self.frozen_types.is_empty()
}

/// Returns the set of freeze-exempt types.
public fun freeze_exempt_types(self: &EmergencyFreeze): &VecSet<std::ascii::String> {
    &self.freeze_exempt_types
}

/// Destroy an EmergencyFreeze object.
public(package) fun destroy(freeze: EmergencyFreeze) {
    let EmergencyFreeze {
        id,
        dao_id: _,
        frozen_types,
        max_freeze_duration_ms: _,
        freeze_exempt_types: _,
    } = freeze;
    assert!(frozen_types.is_empty());
    id.delete();
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
    assert!(!self.freeze_exempt_types.contains(&type_key), EProtectedType);

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

// === Governance Mutators (ExecutionRequest-gated) ===

/// Unfreeze a proposal type via governance. Authorized by ExecutionRequest.
public fun governance_unfreeze_type<P>(
    self: &mut EmergencyFreeze,
    type_key: std::ascii::String,
    _req: &ExecutionRequest<P>,
) {
    assert!(self.dao_id == _req.req_dao_id(), EDAOMismatch);
    assert!(self.frozen_types.contains(&type_key), ENotFrozen);

    self.frozen_types.remove(&type_key);

    event::emit(TypeUnfrozen {
        dao_id: self.dao_id,
        type_key,
    });
}

/// Update the max freeze duration via governance. Authorized by ExecutionRequest.
public fun update_freeze_duration<P>(
    self: &mut EmergencyFreeze,
    new_max: u64,
    _req: &ExecutionRequest<P>,
) {
    assert!(self.dao_id == _req.req_dao_id(), EDAOMismatch);
    self.max_freeze_duration_ms = new_max;
}

/// Unfreeze all currently frozen types. Authorized by ExecutionRequest.
/// Used as a side effect during FreezeAdminCap transfer.
public fun unfreeze_all<P>(self: &mut EmergencyFreeze, _req: &ExecutionRequest<P>) {
    assert!(self.dao_id == _req.req_dao_id(), EDAOMismatch);

    let dao_id = self.dao_id;
    let keys = self.frozen_types.keys();
    let mut i = 0;
    while (i < keys.length()) {
        let type_key = keys[i];
        self.frozen_types.remove(&type_key);
        event::emit(TypeUnfrozen { dao_id, type_key });
        i = i + 1;
    };
}

/// Add a type to the freeze-exempt set via governance.
public fun add_freeze_exempt_type<P>(
    self: &mut EmergencyFreeze,
    type_key: std::ascii::String,
    req: &ExecutionRequest<P>,
) {
    assert!(self.dao_id == req.req_dao_id(), EDAOMismatch);
    self.freeze_exempt_types.insert(type_key);
    event::emit(FreezeExemptTypeAdded { dao_id: self.dao_id, type_key });
}

/// Remove a type from the freeze-exempt set via governance.
/// Cannot remove mandatory exempt types (TransferFreezeAdmin, UnfreezeProposalType).
public fun remove_freeze_exempt_type<P>(
    self: &mut EmergencyFreeze,
    type_key: std::ascii::String,
    req: &ExecutionRequest<P>,
) {
    assert!(self.dao_id == req.req_dao_id(), EDAOMismatch);
    assert!(!is_mandatory_exempt(&type_key), EMandatoryExemptType);
    self.freeze_exempt_types.remove(&type_key);
    event::emit(FreezeExemptTypeRemoved { dao_id: self.dao_id, type_key });
}

// === Internal ===

/// Returns true if the type_key is a mandatory freeze-exempt type that cannot be removed.
fun is_mandatory_exempt(type_key: &std::ascii::String): bool {
    let types = MANDATORY_EXEMPT_TYPES;
    let mut i = 0;
    while (i < types.length()) {
        if (types[i].to_ascii_string() == *type_key) return true;
        i = i + 1;
    };
    false
}

/// Build the default set of freeze-exempt types from mandatory constants.
fun default_exempt_types(): VecSet<std::ascii::String> {
    let types = MANDATORY_EXEMPT_TYPES;
    let mut exempt = vec_set::empty();
    let mut i = 0;
    while (i < types.length()) {
        exempt.insert(types[i].to_ascii_string());
        i = i + 1;
    };
    exempt
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

#[test_only]
public fun add_exempt_type_for_testing(self: &mut EmergencyFreeze, type_key: std::ascii::String) {
    self.freeze_exempt_types.insert(type_key);
}

#[test_only]
public fun remove_exempt_type_for_testing(
    self: &mut EmergencyFreeze,
    type_key: std::ascii::String,
) {
    assert!(!is_mandatory_exempt(&type_key), EMandatoryExemptType);
    self.freeze_exempt_types.remove(&type_key);
}

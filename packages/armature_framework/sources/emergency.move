module armature::emergency;

use armature::permissions;
use armature::proposal::ExecutionRequest;
use armature::transfer_freeze_admin::TransferFreezeAdmin;
use armature::unfreeze_proposal_type::UnfreezeProposalType;
use std::type_name::{Self, TypeName};
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

// === Structs ===

/// Tracks frozen proposal types and their expiry times.
/// Created as a shared object during DAO creation.
///
/// Both collections are keyed by the payload's canonical `TypeName`
/// (`type_name::with_defining_ids`), the same key as the DAO's type slots, so
/// freezing `PlaceLimitOrder<CRED>` affects only that instantiation.
public struct EmergencyFreeze has key, store {
    id: UID,
    dao_id: ID,
    frozen_types: VecMap<TypeName, u64>,
    max_freeze_duration_ms: u64,
    freeze_exempt_types: VecSet<TypeName>,
}

/// Admin capability for triggering emergency freezes.
/// Transferred to the DAO creator at creation time.
public struct FreezeAdminCap has key, store {
    id: UID,
    dao_id: ID,
}

// === Events ===

// `type_name` is the canonical Move type as a string, matching `dao::TypeSlotAdded`.

public struct TypeFrozen has copy, drop {
    dao_id: ID,
    type_name: std::ascii::String,
    expiry_ms: u64,
}

public struct TypeUnfrozen has copy, drop {
    dao_id: ID,
    type_name: std::ascii::String,
}

public struct FreezeExemptTypeAdded has copy, drop {
    dao_id: ID,
    type_name: std::ascii::String,
}

public struct FreezeExemptTypeRemoved has copy, drop {
    dao_id: ID,
    type_name: std::ascii::String,
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

/// Returns the frozen types map (type name → expiry_ms).
public fun frozen_types(self: &EmergencyFreeze): &VecMap<TypeName, u64> {
    &self.frozen_types
}

/// Returns true if no types are currently frozen.
public fun is_empty(self: &EmergencyFreeze): bool {
    self.frozen_types.is_empty()
}

/// Returns the set of freeze-exempt types.
public fun freeze_exempt_types(self: &EmergencyFreeze): &VecSet<TypeName> {
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

/// Check if proposal type `P` is currently frozen. Compares expiry against the clock.
/// Returns true only if the type is in frozen_types AND the freeze has not expired.
public fun is_frozen<P>(self: &EmergencyFreeze, clock: &Clock): bool {
    self.is_frozen_by_name(&type_name::with_defining_ids<P>(), clock)
}

/// `is_frozen` for a type identified by its canonical `TypeName`.
public fun is_frozen_by_name(self: &EmergencyFreeze, name: &TypeName, clock: &Clock): bool {
    if (!self.frozen_types.contains(name)) {
        return false
    };
    let expiry_ms = *self.frozen_types.get(name);
    clock.timestamp_ms() < expiry_ms
}

/// Assert that proposal type `P` is not frozen. Aborts with EFrozen if it is.
public fun assert_not_frozen<P>(self: &EmergencyFreeze, clock: &Clock) {
    assert!(!self.is_frozen<P>(clock), EFrozen);
}

/// Returns true if `name` is freeze-exempt.
public fun is_exempt_by_name(self: &EmergencyFreeze, name: &TypeName): bool {
    self.freeze_exempt_types.contains(name)
}

// === Freeze ===

/// Freeze proposal type `P`. Only the FreezeAdminCap holder can call this.
/// The freeze expires at `now + max_freeze_duration_ms`.
/// Cannot freeze exempt types (always including TransferFreezeAdmin and UnfreezeProposalType).
public fun freeze_type<P>(self: &mut EmergencyFreeze, cap: &FreezeAdminCap, clock: &Clock) {
    assert!(cap.dao_id == self.dao_id, EDAOMismatch);
    let name = type_name::with_defining_ids<P>();
    assert!(!self.freeze_exempt_types.contains(&name), EProtectedType);

    let expiry_ms = clock.timestamp_ms() + self.max_freeze_duration_ms;

    if (self.frozen_types.contains(&name)) {
        let entry = self.frozen_types.get_mut(&name);
        *entry = expiry_ms;
    } else {
        self.frozen_types.insert(name, expiry_ms);
    };

    event::emit(TypeFrozen {
        dao_id: self.dao_id,
        type_name: name.into_string(),
        expiry_ms,
    });
}

// === Unfreeze ===

/// Unfreeze proposal type `P` using the FreezeAdminCap.
public fun unfreeze_type<P>(self: &mut EmergencyFreeze, cap: &FreezeAdminCap) {
    assert!(cap.dao_id == self.dao_id, EDAOMismatch);
    self.remove_frozen(type_name::with_defining_ids<P>());
}

/// Unfreeze a type via governance (UnfreezeProposalType execution).
/// Only callable within the framework package.
public(package) fun governance_unfreeze(self: &mut EmergencyFreeze, name: TypeName) {
    self.remove_frozen(name);
}

/// Update the max freeze duration. Only callable within the framework package.
public(package) fun set_max_freeze_duration_ms(self: &mut EmergencyFreeze, new_max: u64) {
    self.max_freeze_duration_ms = new_max;
}

// === Governance Mutators (ExecutionRequest-gated) ===

/// Unfreeze a proposal type via governance. Authorized by ExecutionRequest.
/// Requires FREEZE (`proposal::assert_permitted`).
public fun governance_unfreeze_type<P>(
    self: &mut EmergencyFreeze,
    name: TypeName,
    req: &ExecutionRequest<P>,
) {
    assert!(self.dao_id == req.req_dao_id(), EDAOMismatch);
    req.assert_permitted(permissions::emergency_freeze());
    self.remove_frozen(name);
}

/// Update the max freeze duration via governance. Authorized by ExecutionRequest.
/// Requires FREEZE (`proposal::assert_permitted`).
public fun update_freeze_duration<P>(
    self: &mut EmergencyFreeze,
    new_max: u64,
    req: &ExecutionRequest<P>,
) {
    assert!(self.dao_id == req.req_dao_id(), EDAOMismatch);
    req.assert_permitted(permissions::emergency_freeze());
    self.max_freeze_duration_ms = new_max;
}

/// Unfreeze all currently frozen types. Authorized by ExecutionRequest.
/// Used as a side effect during FreezeAdminCap transfer.
/// Requires FREEZE (`proposal::assert_permitted`).
public fun unfreeze_all<P>(self: &mut EmergencyFreeze, req: &ExecutionRequest<P>) {
    assert!(self.dao_id == req.req_dao_id(), EDAOMismatch);
    req.assert_permitted(permissions::emergency_freeze());

    let dao_id = self.dao_id;
    let names = self.frozen_types.keys();
    let mut i = 0;
    while (i < names.length()) {
        let name = names[i];
        self.frozen_types.remove(&name);
        event::emit(TypeUnfrozen { dao_id, type_name: name.into_string() });
        i = i + 1;
    };
}

/// Add a type to the freeze-exempt set via governance.
/// Requires FREEZE (`proposal::assert_permitted`).
public fun add_freeze_exempt_type<P>(
    self: &mut EmergencyFreeze,
    name: TypeName,
    req: &ExecutionRequest<P>,
) {
    assert!(self.dao_id == req.req_dao_id(), EDAOMismatch);
    req.assert_permitted(permissions::emergency_freeze());
    self.freeze_exempt_types.insert(name);
    event::emit(FreezeExemptTypeAdded { dao_id: self.dao_id, type_name: name.into_string() });
}

/// Remove a type from the freeze-exempt set via governance.
/// Cannot remove mandatory exempt types (TransferFreezeAdmin, UnfreezeProposalType).
/// Requires FREEZE (`proposal::assert_permitted`).
public fun remove_freeze_exempt_type<P>(
    self: &mut EmergencyFreeze,
    name: TypeName,
    req: &ExecutionRequest<P>,
) {
    assert!(self.dao_id == req.req_dao_id(), EDAOMismatch);
    req.assert_permitted(permissions::emergency_freeze());
    assert!(!is_mandatory_exempt(&name), EMandatoryExemptType);
    self.freeze_exempt_types.remove(&name);
    event::emit(FreezeExemptTypeRemoved { dao_id: self.dao_id, type_name: name.into_string() });
}

// === Mandatory Exemptions ===

/// Returns true if `name` is a mandatory freeze-exempt type. These are resolved
/// from the framework's own payload structs, so they cannot be spoofed by a
/// same-named type in another package and can never be frozen or un-exempted.
public fun is_mandatory_exempt(name: &TypeName): bool {
    let n = *name;
    n == type_name::with_defining_ids<TransferFreezeAdmin>()
        || n == type_name::with_defining_ids<UnfreezeProposalType>()
}

// === Internal ===

/// Remove a frozen entry, aborting with ENotFrozen if absent, and emit TypeUnfrozen.
fun remove_frozen(self: &mut EmergencyFreeze, name: TypeName) {
    assert!(self.frozen_types.contains(&name), ENotFrozen);
    self.frozen_types.remove(&name);
    event::emit(TypeUnfrozen { dao_id: self.dao_id, type_name: name.into_string() });
}

/// Build the default set of freeze-exempt types: the mandatory exemptions.
fun default_exempt_types(): VecSet<TypeName> {
    let mut exempt = vec_set::empty();
    exempt.insert(type_name::with_defining_ids<TransferFreezeAdmin>());
    exempt.insert(type_name::with_defining_ids<UnfreezeProposalType>());
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
public fun add_exempt_type_for_testing<T>(self: &mut EmergencyFreeze) {
    self.freeze_exempt_types.insert(type_name::with_defining_ids<T>());
}

#[test_only]
public fun remove_exempt_type_for_testing<T>(self: &mut EmergencyFreeze) {
    let name = type_name::with_defining_ids<T>();
    assert!(!is_mandatory_exempt(&name), EMandatoryExemptType);
    self.freeze_exempt_types.remove(&name);
}

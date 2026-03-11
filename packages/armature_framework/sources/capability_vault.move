module armature::capability_vault;

use sui::vec_set::{Self, VecSet};

// === Structs ===

/// Stores arbitrary capabilities as dynamic object fields.
/// Created as a shared object during DAO creation.
public struct CapabilityVault has key, store {
    id: UID,
    dao_id: ID,
    cap_types: VecSet<std::ascii::String>,
    cap_ids: VecSet<ID>,
}

// === Constructor ===

/// Create a new empty CapabilityVault. Only callable within the framework package.
public(package) fun new(dao_id: ID, ctx: &mut TxContext): CapabilityVault {
    CapabilityVault {
        id: object::new(ctx),
        dao_id,
        cap_types: vec_set::empty(),
        cap_ids: vec_set::empty(),
    }
}

/// Share the vault as a shared object.
#[allow(lint(share_owned, custom_state_change))]
public(package) fun share(vault: CapabilityVault) {
    transfer::share_object(vault);
}

// === Accessors ===

/// Returns the DAO ID this vault belongs to.
public fun dao_id(self: &CapabilityVault): ID { self.dao_id }

/// Returns the set of capability type names stored.
public fun cap_types(self: &CapabilityVault): &VecSet<std::ascii::String> { &self.cap_types }

/// Returns the set of capability object IDs stored.
public fun cap_ids(self: &CapabilityVault): &VecSet<ID> { &self.cap_ids }

module armature::treasury_vault;

use sui::vec_set::{Self, VecSet};

// === Structs ===

/// Multi-coin treasury vault. Stores `Balance<T>` as dynamic fields keyed by type name.
/// Created as a shared object during DAO creation.
public struct TreasuryVault has key, store {
    id: UID,
    dao_id: ID,
    coin_types: VecSet<std::ascii::String>,
}

// === Constructor ===

/// Create a new empty TreasuryVault. Only callable within the framework package.
public(package) fun new(dao_id: ID, ctx: &mut TxContext): TreasuryVault {
    TreasuryVault {
        id: object::new(ctx),
        dao_id,
        coin_types: vec_set::empty(),
    }
}

/// Share the vault as a shared object.
#[allow(lint(share_owned, custom_state_change))]
public(package) fun share(vault: TreasuryVault) {
    transfer::share_object(vault);
}

// === Accessors ===

/// Returns the DAO ID this vault belongs to.
public fun dao_id(self: &TreasuryVault): ID { self.dao_id }

/// Returns the set of coin type names currently held.
public fun coin_types(self: &TreasuryVault): &VecSet<std::ascii::String> { &self.coin_types }

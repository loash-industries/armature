module armature_proposals::transfer_assets;

use std::type_name::TypeName;

/// Move treasury and capability vault contents to a target DAO.
/// Subject to per-call asset limits (max 50 combined).
public struct TransferAssets has store {
    target_dao_id: ID,
    target_treasury_id: ID,
    target_vault_id: ID,
    coin_types: vector<TypeName>,
    cap_ids: vector<ID>,
}

// === Constructor ===

public fun new(
    target_dao_id: ID,
    target_treasury_id: ID,
    target_vault_id: ID,
    coin_types: vector<TypeName>,
    cap_ids: vector<ID>,
): TransferAssets {
    TransferAssets { target_dao_id, target_treasury_id, target_vault_id, coin_types, cap_ids }
}

// === Accessors ===

public fun target_dao_id(self: &TransferAssets): ID { self.target_dao_id }

public fun target_treasury_id(self: &TransferAssets): ID { self.target_treasury_id }

public fun target_vault_id(self: &TransferAssets): ID { self.target_vault_id }

public fun coin_types(self: &TransferAssets): &vector<TypeName> { &self.coin_types }

public fun cap_ids(self: &TransferAssets): &vector<ID> { &self.cap_ids }

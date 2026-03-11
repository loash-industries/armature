module armature_proposals::transfer_cap_to_subdao;

/// Transfer a capability from this DAO's vault to a SubDAO's vault.
public struct TransferCapToSubDAO has store {
    cap_id: ID,
    target_subdao: ID,
}

// === Constructor ===

public fun new(cap_id: ID, target_subdao: ID): TransferCapToSubDAO {
    TransferCapToSubDAO { cap_id, target_subdao }
}

// === Accessors ===

public fun cap_id(self: &TransferCapToSubDAO): ID { self.cap_id }
public fun target_subdao(self: &TransferCapToSubDAO): ID { self.target_subdao }

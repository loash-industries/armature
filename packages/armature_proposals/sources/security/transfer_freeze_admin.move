module armature_proposals::transfer_freeze_admin;

/// Transfer the FreezeAdminCap to a new address.
/// Unfreezes all currently frozen types as a side effect.
/// Cannot itself be frozen.
public struct TransferFreezeAdmin has store {
    new_admin: address,
}

// === Constructor ===

public fun new(new_admin: address): TransferFreezeAdmin {
    TransferFreezeAdmin { new_admin }
}

// === Accessors ===

public fun new_admin(self: &TransferFreezeAdmin): address { self.new_admin }

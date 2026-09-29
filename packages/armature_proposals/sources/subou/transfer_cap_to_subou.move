module armature_proposals::transfer_cap_to_subou;

use std::internal::{Self, Permit};

/// Transfer a capability from this OU's vault to a SubOU's vault.
public struct TransferCapToSubOU has drop, store {
    cap_id: ID,
    target_subou: ID,
}

// === Constructor ===

public fun new(cap_id: ID, target_subou: ID): TransferCapToSubOU {
    TransferCapToSubOU { cap_id, target_subou }
}

// === Accessors ===

public fun cap_id(self: &TransferCapToSubOU): ID { self.cap_id }

public fun target_subou(self: &TransferCapToSubOU): ID { self.target_subou }

// === Handler authority ===

/// `Permit<TransferCapToSubOU>` for this package's handler: the only way to spend or close
/// an `ExecutionTicket<TransferCapToSubOU>` (see `proposal::ticket_request`).
public(package) fun permit(): Permit<TransferCapToSubOU> { internal::permit() }

module armature_proposals::reclaim_cap_from_subou;

use std::internal::{Self, Permit};

/// Reclaim a capability from a SubOU's vault using SubOUControl authority.
/// Proposed on the controller OU, not the SubOU.
public struct ReclaimCapFromSubOU has drop, store {
    subou_id: ID,
    cap_id: ID,
    control_id: ID,
}

// === Constructor ===

public fun new(subou_id: ID, cap_id: ID, control_id: ID): ReclaimCapFromSubOU {
    ReclaimCapFromSubOU { subou_id, cap_id, control_id }
}

// === Accessors ===

public fun subou_id(self: &ReclaimCapFromSubOU): ID { self.subou_id }

public fun cap_id(self: &ReclaimCapFromSubOU): ID { self.cap_id }

public fun control_id(self: &ReclaimCapFromSubOU): ID { self.control_id }

// === Handler authority ===

/// `Permit<ReclaimCapFromSubOU>` for this package's handler: the only way to spend or close
/// an `ExecutionTicket<ReclaimCapFromSubOU>` (see `proposal::ticket_request`).
public(package) fun permit(): Permit<ReclaimCapFromSubOU> { internal::permit() }

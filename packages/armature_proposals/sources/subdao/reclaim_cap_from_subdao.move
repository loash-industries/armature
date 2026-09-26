module armature_proposals::reclaim_cap_from_subdao;

use std::internal::{Self, Permit};

/// Reclaim a capability from a SubDAO's vault using SubDAOControl authority.
/// Proposed on the controller DAO, not the SubDAO.
public struct ReclaimCapFromSubDAO has drop, store {
    subdao_id: ID,
    cap_id: ID,
    control_id: ID,
}

// === Constructor ===

public fun new(subdao_id: ID, cap_id: ID, control_id: ID): ReclaimCapFromSubDAO {
    ReclaimCapFromSubDAO { subdao_id, cap_id, control_id }
}

// === Accessors ===

public fun subdao_id(self: &ReclaimCapFromSubDAO): ID { self.subdao_id }

public fun cap_id(self: &ReclaimCapFromSubDAO): ID { self.cap_id }

public fun control_id(self: &ReclaimCapFromSubDAO): ID { self.control_id }

// === Handler authority ===

/// `Permit<ReclaimCapFromSubDAO>` for this package's handler: the only way to spend or close
/// an `ExecutionTicket<ReclaimCapFromSubDAO>` (see `proposal::ticket_request`).
public(package) fun permit(): Permit<ReclaimCapFromSubDAO> { internal::permit() }

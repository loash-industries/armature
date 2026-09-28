module armature_proposals::controller_batch_add_members;

use std::internal::{Self, Permit};

/// Add multiple members to a managed sub-DAO's board via SubDAOControl authority.
/// Proposed on the controller DAO; executes atomically on the target sub-DAO
/// using the privileged_submit pattern.
public struct ControllerBatchAddMembers has drop, store {
    control_id: ID,
    members: vector<address>,
}

// === Constructor ===

public fun new(control_id: ID, members: vector<address>): ControllerBatchAddMembers {
    ControllerBatchAddMembers { control_id, members }
}

// === Accessors ===

public fun control_id(self: &ControllerBatchAddMembers): ID { self.control_id }

public fun members(self: &ControllerBatchAddMembers): &vector<address> { &self.members }

// === Handler authority ===

/// `Permit<ControllerBatchAddMembers>` for this package's handler: the only way to spend or close
/// an `ExecutionTicket<ControllerBatchAddMembers>` (see `proposal::ticket_request`).
public(package) fun permit(): Permit<ControllerBatchAddMembers> { internal::permit() }

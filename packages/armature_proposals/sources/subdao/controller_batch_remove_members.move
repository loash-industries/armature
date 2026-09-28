module armature_proposals::controller_batch_remove_members;

use std::internal::{Self, Permit};

/// Remove multiple members from a managed sub-DAO's board via SubDAOControl authority.
/// Proposed on the controller DAO; executes atomically on the target sub-DAO
/// using the privileged_submit pattern.
public struct ControllerBatchRemoveMembers has drop, store {
    control_id: ID,
    members: vector<address>,
}

// === Constructor ===

public fun new(control_id: ID, members: vector<address>): ControllerBatchRemoveMembers {
    ControllerBatchRemoveMembers { control_id, members }
}

// === Accessors ===

public fun control_id(self: &ControllerBatchRemoveMembers): ID { self.control_id }

public fun members(self: &ControllerBatchRemoveMembers): &vector<address> { &self.members }

// === Handler authority ===

/// `Permit<ControllerBatchRemoveMembers>` for this package's handler: the only way to spend or
/// close
/// an `ExecutionTicket<ControllerBatchRemoveMembers>` (see `proposal::ticket_request`).
public(package) fun permit(): Permit<ControllerBatchRemoveMembers> { internal::permit() }

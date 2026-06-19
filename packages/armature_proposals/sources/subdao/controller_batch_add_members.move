module armature_proposals::controller_batch_add_members;

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

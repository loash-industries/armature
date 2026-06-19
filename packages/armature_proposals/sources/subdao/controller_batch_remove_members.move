module armature_proposals::controller_batch_remove_members;

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

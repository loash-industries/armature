module armature_proposals::controller_add_member;

/// Add a member to a managed sub-DAO's board via SubDAOControl authority.
/// Proposed on the controller DAO; executes atomically on the target sub-DAO
/// using the submit_vote_execute pattern.
public struct ControllerAddMember has copy, drop, store {
    control_id: ID,
    member: address,
}

// === Constructor ===

public fun new(control_id: ID, member: address): ControllerAddMember {
    ControllerAddMember { control_id, member }
}

// === Accessors ===

public fun control_id(self: &ControllerAddMember): ID { self.control_id }

public fun member(self: &ControllerAddMember): address { self.member }

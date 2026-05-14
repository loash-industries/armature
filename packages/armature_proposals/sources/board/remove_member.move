module armature_proposals::remove_member;

/// Remove a single member from the board.
/// Lighter-weight alternative to SetBoard when only one address needs to be removed.
public struct RemoveMember has copy, drop, store {
    member: address,
}

// === Constructor ===

public fun new(member: address): RemoveMember {
    RemoveMember { member }
}

// === Accessors ===

public fun member(self: &RemoveMember): address { self.member }

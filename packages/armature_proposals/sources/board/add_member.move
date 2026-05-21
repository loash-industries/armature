module armature_proposals::add_member;

/// Add a single member to the board.
/// Lighter-weight alternative to SetBoard when only one address needs to be added.
public struct AddMember has copy, drop, store {
    member: address,
}

// === Constructor ===

public fun new(member: address): AddMember {
    AddMember { member }
}

// === Accessors ===

public fun member(self: &AddMember): address { self.member }

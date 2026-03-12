module armature_proposals::set_board;

/// Replace the entire board member set.
/// Used by the board itself or by a controller DAO via SubDAOControl bypass.
public struct SetBoard has store {
    new_members: vector<address>,
}

// === Constructor ===

public fun new(new_members: vector<address>): SetBoard {
    SetBoard { new_members }
}

// === Accessors ===

public fun new_members(self: &SetBoard): &vector<address> { &self.new_members }

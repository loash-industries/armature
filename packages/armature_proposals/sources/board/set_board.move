module armature_proposals::set_board;

/// Replace the entire board member set and update seat_count.
/// Used by the board itself or by a controller DAO via SubDAOControl bypass.
public struct SetBoard has store {
    new_members: vector<address>,
    new_seat_count: u8,
}

// === Constructor ===

public fun new(new_members: vector<address>, new_seat_count: u8): SetBoard {
    SetBoard { new_members, new_seat_count }
}

// === Accessors ===

public fun new_members(self: &SetBoard): &vector<address> { &self.new_members }

public fun new_seat_count(self: &SetBoard): u8 { self.new_seat_count }

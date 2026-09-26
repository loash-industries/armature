module armature::set_board;

/// Change the board in one step: add `to_add` and remove `to_remove`.
/// Used by the board itself or by a controller DAO via SubDAOControl bypass.
///
/// The change is expressed as a diff rather than a full replacement list
/// because the roster is a Table, which cannot be enumerated on-chain.
public struct SetBoard has drop, store {
    to_add: vector<address>,
    to_remove: vector<address>,
}

// === Constructor ===

public fun new(to_add: vector<address>, to_remove: vector<address>): SetBoard {
    SetBoard { to_add, to_remove }
}

// === Accessors ===

public fun to_add(self: &SetBoard): &vector<address> { &self.to_add }

public fun to_remove(self: &SetBoard): &vector<address> { &self.to_remove }

module armature_proposals::create_subdao;

use std::string::String;
use std::type_name::TypeName;

/// Create a new Board-governance SubDAO controlled by this DAO.
public struct CreateSubDAO has store {
    initial_board: vector<address>,
    seat_count: u8,
    metadata_ipfs: String,
    enabled_proposals: vector<TypeName>,
}

// === Constructor ===

public fun new(
    initial_board: vector<address>,
    seat_count: u8,
    metadata_ipfs: String,
    enabled_proposals: vector<TypeName>,
): CreateSubDAO {
    CreateSubDAO { initial_board, seat_count, metadata_ipfs, enabled_proposals }
}

// === Accessors ===

public fun initial_board(self: &CreateSubDAO): &vector<address> { &self.initial_board }

public fun seat_count(self: &CreateSubDAO): u8 { self.seat_count }

public fun metadata_ipfs(self: &CreateSubDAO): &String { &self.metadata_ipfs }

public fun enabled_proposals(self: &CreateSubDAO): &vector<TypeName> { &self.enabled_proposals }

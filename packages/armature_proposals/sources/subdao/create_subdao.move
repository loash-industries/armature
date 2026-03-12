module armature_proposals::create_subdao;

use std::string::String;

/// Create a new Board-governance SubDAO controlled by this DAO.
public struct CreateSubDAO has store {
    name: String,
    description: String,
    initial_board: vector<address>,
    metadata_ipfs: String,
}

// === Constructor ===

public fun new(
    name: String,
    description: String,
    initial_board: vector<address>,
    metadata_ipfs: String,
): CreateSubDAO {
    CreateSubDAO { name, description, initial_board, metadata_ipfs }
}

// === Accessors ===

public fun name(self: &CreateSubDAO): &String { &self.name }

public fun description(self: &CreateSubDAO): &String { &self.description }

public fun initial_board(self: &CreateSubDAO): &vector<address> { &self.initial_board }

public fun metadata_ipfs(self: &CreateSubDAO): &String { &self.metadata_ipfs }

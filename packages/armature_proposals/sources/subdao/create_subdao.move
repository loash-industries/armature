module armature_proposals::create_subdao;

use std::string::String;

/// Create a new Board-governance SubDAO controlled by this DAO.
public struct CreateSubDAO has drop, store {
    name: String,
    initial_board: vector<address>,
    metadata_uri: String,
}

// === Constructor ===

public fun new(name: String, initial_board: vector<address>, metadata_uri: String): CreateSubDAO {
    CreateSubDAO { name, initial_board, metadata_uri }
}

// === Accessors ===

public fun name(self: &CreateSubDAO): &String { &self.name }

public fun initial_board(self: &CreateSubDAO): &vector<address> { &self.initial_board }

public fun metadata_uri(self: &CreateSubDAO): &String { &self.metadata_uri }

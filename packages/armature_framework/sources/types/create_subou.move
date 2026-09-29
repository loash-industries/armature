module armature::create_subou;

use std::internal::{Self, Permit};
use std::string::String;

/// Create a new Board-governance SubOU controlled by this OU.
public struct CreateSubOU has drop, store {
    name: String,
    initial_board: vector<address>,
    metadata_uri: String,
}

// === Constructor ===

public fun new(name: String, initial_board: vector<address>, metadata_uri: String): CreateSubOU {
    CreateSubOU { name, initial_board, metadata_uri }
}

// === Accessors ===

public fun name(self: &CreateSubOU): &String { &self.name }

public fun initial_board(self: &CreateSubOU): &vector<address> { &self.initial_board }

public fun metadata_uri(self: &CreateSubOU): &String { &self.metadata_uri }

// === Handler authority ===

/// `Permit<CreateSubOU>` for this package's handler: the only way to spend or close
/// an `ExecutionTicket<CreateSubOU>` (see `proposal::ticket_request`).
public(package) fun permit(): Permit<CreateSubOU> { internal::permit() }

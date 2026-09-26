module armature::update_metadata;

use std::internal::{Self, Permit};
use std::string::String;

/// Update the DAO's metadata IPFS CID.
public struct UpdateMetadata has copy, drop, store {
    new_ipfs_cid: String,
}

// === Constructor ===

public fun new(new_ipfs_cid: String): UpdateMetadata {
    UpdateMetadata { new_ipfs_cid }
}

// === Accessors ===

public fun new_ipfs_cid(self: &UpdateMetadata): &String { &self.new_ipfs_cid }

// === Handler authority ===

/// `Permit<UpdateMetadata>` for this package's handler: the only way to spend or close
/// an `ExecutionTicket<UpdateMetadata>` (see `proposal::ticket_request`).
public(package) fun permit(): Permit<UpdateMetadata> { internal::permit() }

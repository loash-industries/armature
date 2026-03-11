module armature_proposals::update_metadata;

use std::string::String;

/// Update the DAO's metadata IPFS CID.
public struct UpdateMetadata has store {
    new_ipfs_cid: String,
}

// === Constructor ===

public fun new(new_ipfs_cid: String): UpdateMetadata {
    UpdateMetadata { new_ipfs_cid }
}

// === Accessors ===

public fun new_ipfs_cid(self: &UpdateMetadata): &String { &self.new_ipfs_cid }

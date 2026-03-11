module armature_proposals::spawn_dao;

use std::string::String;
use armature::governance::GovernanceTypeInit;

/// Create a successor DAO and transition this DAO to Migrating status.
public struct SpawnDAO has store {
    governance_init: GovernanceTypeInit,
    metadata_ipfs: String,
}

// === Constructor ===

public fun new(governance_init: GovernanceTypeInit, metadata_ipfs: String): SpawnDAO {
    SpawnDAO { governance_init, metadata_ipfs }
}

// === Accessors ===

public fun governance_init(self: &SpawnDAO): &GovernanceTypeInit { &self.governance_init }
public fun metadata_ipfs(self: &SpawnDAO): &String { &self.metadata_ipfs }

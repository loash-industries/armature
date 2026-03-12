module armature_proposals::spawn_dao;

use armature::governance::GovernanceTypeInit;
use std::string::String;

/// Create a successor DAO and transition this DAO to Migrating status.
public struct SpawnDAO has store {
    governance_init: GovernanceTypeInit,
    name: String,
    description: String,
    metadata_ipfs: String,
}

// === Constructor ===

public fun new(
    governance_init: GovernanceTypeInit,
    name: String,
    description: String,
    metadata_ipfs: String,
): SpawnDAO {
    SpawnDAO { governance_init, name, description, metadata_ipfs }
}

// === Accessors ===

public fun governance_init(self: &SpawnDAO): &GovernanceTypeInit { &self.governance_init }

public fun name(self: &SpawnDAO): &String { &self.name }

public fun description(self: &SpawnDAO): &String { &self.description }

public fun metadata_ipfs(self: &SpawnDAO): &String { &self.metadata_ipfs }

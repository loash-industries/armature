module armature_proposals::spawn_dao;

use armature::governance::GovernanceTypeInit;
use std::string::String;

/// Create a successor DAO and transition this DAO to Migrating status.
public struct SpawnDAO has drop, store {
    governance_init: GovernanceTypeInit,
    name: String,
    metadata_uri: String,
}

// === Constructor ===

public fun new(governance_init: GovernanceTypeInit, name: String, metadata_uri: String): SpawnDAO {
    SpawnDAO { governance_init, name, metadata_uri }
}

// === Accessors ===

public fun governance_init(self: &SpawnDAO): &GovernanceTypeInit { &self.governance_init }

public fun name(self: &SpawnDAO): &String { &self.name }

public fun metadata_uri(self: &SpawnDAO): &String { &self.metadata_uri }

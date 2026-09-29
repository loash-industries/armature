module armature::spawn_ou;

use armature::governance::GovernanceTypeInit;
use std::internal::{Self, Permit};
use std::string::String;

/// Create a successor OU and transition this OU to Migrating status.
public struct SpawnOU has drop, store {
    governance_init: GovernanceTypeInit,
    name: String,
    metadata_uri: String,
}

// === Constructor ===

public fun new(governance_init: GovernanceTypeInit, name: String, metadata_uri: String): SpawnOU {
    SpawnOU { governance_init, name, metadata_uri }
}

// === Accessors ===

public fun governance_init(self: &SpawnOU): &GovernanceTypeInit { &self.governance_init }

public fun name(self: &SpawnOU): &String { &self.name }

public fun metadata_uri(self: &SpawnOU): &String { &self.metadata_uri }

// === Handler authority ===

/// `Permit<SpawnOU>` for this package's handler: the only way to spend or close
/// an `ExecutionTicket<SpawnOU>` (see `proposal::ticket_request`).
public(package) fun permit(): Permit<SpawnOU> { internal::permit() }

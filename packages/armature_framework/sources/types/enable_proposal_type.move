module armature::enable_proposal_type;

use armature::proposal::ProposalConfig;
use std::internal::{Self, Permit};
use std::type_name::TypeName;

/// Enable a new proposal type on the DAO with mandatory config.
///
/// `type_name` pins the exact Move type the voters approved. The handler
/// (`admin_ops::execute_enable_proposal_type<NewType>`) asserts that
/// `NewType` matches it, so an executor cannot register a different payload
/// type under the display key the board voted on.
///
/// Proposals of this type need an 80% approval threshold (dao floor).
public struct EnableProposalType has drop, store {
    /// Human-readable label shown in events and the UI. Unique per DAO.
    type_key: std::ascii::String,
    /// Canonical Move type (`std::type_name::with_defining_ids<T>()`) being enabled.
    type_name: TypeName,
    config: ProposalConfig,
}

// === Constructor ===

public fun new(
    type_key: std::ascii::String,
    type_name: TypeName,
    config: ProposalConfig,
): EnableProposalType {
    EnableProposalType { type_key, type_name, config }
}

// === Accessors ===

public fun type_key(self: &EnableProposalType): std::ascii::String { self.type_key }

public fun type_name(self: &EnableProposalType): TypeName { self.type_name }

public fun config(self: &EnableProposalType): &ProposalConfig { &self.config }

// === Handler authority ===

/// `Permit<EnableProposalType>` for this package's handler: the only way to spend or close
/// an `ExecutionTicket<EnableProposalType>` (see `proposal::ticket_request`).
public(package) fun permit(): Permit<EnableProposalType> { internal::permit() }

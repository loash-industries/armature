module armature::disable_proposal_type;

use std::internal::{Self, Permit};

/// Disable a proposal type on the DAO.
/// Handler asserts the target type is not undisableable.
public struct DisableProposalType has drop, store {
    type_key: std::ascii::String,
}

// === Constructor ===

public fun new(type_key: std::ascii::String): DisableProposalType {
    DisableProposalType { type_key }
}

// === Accessors ===

public fun type_key(self: &DisableProposalType): std::ascii::String { self.type_key }

// === Handler authority ===

/// `Permit<DisableProposalType>` for this package's handler: the only way to spend or close
/// an `ExecutionTicket<DisableProposalType>` (see `proposal::ticket_request`).
public(package) fun permit(): Permit<DisableProposalType> { internal::permit() }

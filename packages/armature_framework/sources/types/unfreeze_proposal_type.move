module armature::unfreeze_proposal_type;

use std::internal::{Self, Permit};
use std::type_name::{Self, TypeName};

/// Governance-initiated unfreeze of a proposal type.
/// Overrides an admin freeze without requiring the FreezeAdminCap.
/// Cannot itself be frozen.
public struct UnfreezeProposalType has drop, store {
    /// Canonical `TypeName` of the proposal type to unfreeze.
    type_name: TypeName,
}

// === Constructor ===

/// Build a payload that unfreezes proposal type `T`.
public fun new<T>(): UnfreezeProposalType {
    UnfreezeProposalType { type_name: type_name::with_defining_ids<T>() }
}

// === Accessors ===

public fun type_name(self: &UnfreezeProposalType): TypeName { self.type_name }

// === Handler authority ===

/// `Permit<UnfreezeProposalType>` for this package's handler: the only way to spend or close
/// an `ExecutionTicket<UnfreezeProposalType>` (see `proposal::ticket_request`).
public(package) fun permit(): Permit<UnfreezeProposalType> { internal::permit() }

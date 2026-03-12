module armature_proposals::disable_proposal_type;

/// Disable a proposal type on the DAO.
/// Handler asserts the target type is not undisableable.
public struct DisableProposalType has store {
    type_key: std::ascii::String,
}

// === Constructor ===

public fun new(type_key: std::ascii::String): DisableProposalType {
    DisableProposalType { type_key }
}

// === Accessors ===

public fun type_key(self: &DisableProposalType): std::ascii::String { self.type_key }

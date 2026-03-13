module armature_proposals::unfreeze_proposal_type;

/// Governance-initiated unfreeze of a proposal type.
/// Overrides an admin freeze without requiring the FreezeAdminCap.
/// Cannot itself be frozen.
public struct UnfreezeProposalType has store {
    type_key: std::ascii::String,
}

// === Constructor ===

public fun new(type_key: std::ascii::String): UnfreezeProposalType {
    UnfreezeProposalType { type_key }
}

// === Accessors ===

public fun type_key(self: &UnfreezeProposalType): std::ascii::String { self.type_key }

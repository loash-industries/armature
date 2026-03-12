module armature_proposals::unfreeze_proposal_type;

use std::type_name::TypeName;

/// Governance-initiated unfreeze of a proposal type.
/// Overrides an admin freeze without requiring the FreezeAdminCap.
/// Cannot itself be frozen.
public struct UnfreezeProposalType has store {
    type_name: TypeName,
}

// === Constructor ===

public fun new(type_name: TypeName): UnfreezeProposalType {
    UnfreezeProposalType { type_name }
}

// === Accessors ===

public fun type_name(self: &UnfreezeProposalType): TypeName { self.type_name }

module armature_proposals::disable_proposal_type;

use std::type_name::TypeName;

/// Disable a proposal type on the DAO.
/// Handler asserts the target type is not in `dao.undisableable_types`.
public struct DisableProposalType has store {
    type_name: TypeName,
}

// === Constructor ===

public fun new(type_name: TypeName): DisableProposalType {
    DisableProposalType { type_name }
}

// === Accessors ===

public fun type_name(self: &DisableProposalType): TypeName { self.type_name }

module armature_proposals::enable_proposal_type;

use std::type_name::TypeName;
use armature::proposal::ProposalConfig;

/// Enable a new proposal type on the DAO with mandatory config.
/// Handler enforces a 66% approval floor at execution time.
public struct EnableProposalType has store {
    type_name: TypeName,
    config: ProposalConfig,
}

// === Constructor ===

public fun new(type_name: TypeName, config: ProposalConfig): EnableProposalType {
    EnableProposalType { type_name, config }
}

// === Accessors ===

public fun type_name(self: &EnableProposalType): TypeName { self.type_name }
public fun config(self: &EnableProposalType): &ProposalConfig { &self.config }

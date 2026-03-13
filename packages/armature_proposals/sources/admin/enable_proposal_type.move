module armature_proposals::enable_proposal_type;

use armature::proposal::ProposalConfig;

/// Enable a new proposal type on the DAO with mandatory config.
/// Handler enforces a 66% approval floor at execution time.
public struct EnableProposalType has store {
    type_key: std::ascii::String,
    config: ProposalConfig,
}

// === Constructor ===

public fun new(type_key: std::ascii::String, config: ProposalConfig): EnableProposalType {
    EnableProposalType { type_key, config }
}

// === Accessors ===

public fun type_key(self: &EnableProposalType): std::ascii::String { self.type_key }

public fun config(self: &EnableProposalType): &ProposalConfig { &self.config }

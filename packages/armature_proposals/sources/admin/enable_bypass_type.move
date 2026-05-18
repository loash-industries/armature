module armature_proposals::enable_bypass_type;

use armature::proposal::ProposalConfig;

/// Enable a new proposal type on the DAO with bypass-execution authorization.
/// In addition to the standard EnableProposalType effects (register the type,
/// bind the canonical Move type for anti-spoofing), this mints an
/// `ExternalExecutionCap<NewType>` into the DAO's CapabilityVault. Any
/// extension package that gates an external authorization condition can
/// then borrow the cap to mint `ExecutionRequest<NewType>` without a vote.
///
/// Handler enforces an 80% approval floor — strictly more consequential
/// than EnableProposalType (which is 66%) because opting into bypass
/// execution waives the per-proposal vote for every future submission
/// under this type.
public struct EnableBypassType has store {
    type_key: std::ascii::String,
    config: ProposalConfig,
}

// === Constructor ===

public fun new(type_key: std::ascii::String, config: ProposalConfig): EnableBypassType {
    EnableBypassType { type_key, config }
}

// === Accessors ===

public fun type_key(self: &EnableBypassType): std::ascii::String { self.type_key }

public fun config(self: &EnableBypassType): &ProposalConfig { &self.config }

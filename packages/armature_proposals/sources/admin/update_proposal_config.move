module armature_proposals::update_proposal_config;

use std::type_name::TypeName;

/// Update one or more ProposalConfig fields for a given proposal type.
/// Fields set to none are left unchanged.
/// When targeting UpdateProposalConfig itself, the handler enforces
/// an 80% super-majority approval floor at execution time.
public struct UpdateProposalConfig has store {
    target_type: TypeName,
    quorum: Option<u16>,
    approval_threshold: Option<u16>,
    propose_threshold: Option<u64>,
    expiry_ms: Option<u64>,
    execution_delay_ms: Option<u64>,
    cooldown_ms: Option<u64>,
}

// === Constructor ===

public fun new(
    target_type: TypeName,
    quorum: Option<u16>,
    approval_threshold: Option<u16>,
    propose_threshold: Option<u64>,
    expiry_ms: Option<u64>,
    execution_delay_ms: Option<u64>,
    cooldown_ms: Option<u64>,
): UpdateProposalConfig {
    UpdateProposalConfig {
        target_type,
        quorum,
        approval_threshold,
        propose_threshold,
        expiry_ms,
        execution_delay_ms,
        cooldown_ms,
    }
}

// === Accessors ===

public fun target_type(self: &UpdateProposalConfig): TypeName { self.target_type }

public fun quorum(self: &UpdateProposalConfig): Option<u16> { self.quorum }

public fun approval_threshold(self: &UpdateProposalConfig): Option<u16> { self.approval_threshold }

public fun propose_threshold(self: &UpdateProposalConfig): Option<u64> { self.propose_threshold }

public fun expiry_ms(self: &UpdateProposalConfig): Option<u64> { self.expiry_ms }

public fun execution_delay_ms(self: &UpdateProposalConfig): Option<u64> { self.execution_delay_ms }

public fun cooldown_ms(self: &UpdateProposalConfig): Option<u64> { self.cooldown_ms }

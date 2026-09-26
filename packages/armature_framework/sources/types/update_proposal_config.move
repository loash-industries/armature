module armature::update_proposal_config;

use std::internal::{Self, Permit};
use std::type_name::TypeName;

/// Update one or more ProposalConfig fields for a given proposal type.
/// Fields set to none are left unchanged. `permissions` and `borrow_scope` are
/// set with `with_permissions` / `with_borrow_scope`; changing either is
/// subject to the grant rules in `dao::update_proposal_config`.
/// When targeting UpdateProposalConfig itself, the handler enforces
/// an 80% super-majority approval floor at execution time.
public struct UpdateProposalConfig has drop, store {
    target_type_key: std::ascii::String,
    quorum: Option<u16>,
    approval_threshold: Option<u16>,
    propose_threshold: Option<u64>,
    expiry_ms: Option<u64>,
    execution_delay_ms: Option<u64>,
    cooldown_ms: Option<u64>,
    composable_allowed: Option<bool>,
    permissions: Option<u64>,
    borrow_scope: Option<vector<TypeName>>,
}

// === Constructor ===

public fun new(
    target_type_key: std::ascii::String,
    quorum: Option<u16>,
    approval_threshold: Option<u16>,
    propose_threshold: Option<u64>,
    expiry_ms: Option<u64>,
    execution_delay_ms: Option<u64>,
    cooldown_ms: Option<u64>,
    composable_allowed: Option<bool>,
): UpdateProposalConfig {
    UpdateProposalConfig {
        target_type_key,
        quorum,
        approval_threshold,
        propose_threshold,
        expiry_ms,
        execution_delay_ms,
        cooldown_ms,
        composable_allowed,
        permissions: option::none(),
        borrow_scope: option::none(),
    }
}

/// Also replace the target type's permission bits with `bits`.
public fun with_permissions(mut self: UpdateProposalConfig, bits: u64): UpdateProposalConfig {
    self.permissions = option::some(bits);
    self
}

/// Also replace the target type's borrow scope with `scope`.
public fun with_borrow_scope(
    mut self: UpdateProposalConfig,
    scope: vector<TypeName>,
): UpdateProposalConfig {
    self.borrow_scope = option::some(scope);
    self
}

// === Accessors ===

public fun target_type_key(self: &UpdateProposalConfig): std::ascii::String { self.target_type_key }

public fun quorum(self: &UpdateProposalConfig): Option<u16> { self.quorum }

public fun approval_threshold(self: &UpdateProposalConfig): Option<u16> { self.approval_threshold }

public fun propose_threshold(self: &UpdateProposalConfig): Option<u64> { self.propose_threshold }

public fun expiry_ms(self: &UpdateProposalConfig): Option<u64> { self.expiry_ms }

public fun execution_delay_ms(self: &UpdateProposalConfig): Option<u64> { self.execution_delay_ms }

public fun cooldown_ms(self: &UpdateProposalConfig): Option<u64> { self.cooldown_ms }

public fun composable_allowed(self: &UpdateProposalConfig): Option<bool> { self.composable_allowed }

public fun permissions(self: &UpdateProposalConfig): Option<u64> { self.permissions }

public fun borrow_scope(self: &UpdateProposalConfig): Option<vector<TypeName>> {
    self.borrow_scope
}

// === Handler authority ===

/// `Permit<UpdateProposalConfig>` for this package's handler: the only way to spend or close
/// an `ExecutionTicket<UpdateProposalConfig>` (see `proposal::ticket_request`).
public(package) fun permit(): Permit<UpdateProposalConfig> { internal::permit() }

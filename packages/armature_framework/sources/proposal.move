module armature::proposal;

// === Errors ===

const EInvalidQuorum: u64 = 0;
const EInvalidApprovalThreshold: u64 = 1;
const EInvalidExpiryMs: u64 = 2;

// === Constants ===

const MIN_EXPIRY_MS: u64 = 3_600_000; // 1 hour

// === Structs ===

/// Per-proposal-type configuration. Copied into each Proposal at creation time.
public struct ProposalConfig has copy, drop, store {
    quorum: u16,
    approval_threshold: u16,
    propose_threshold: u64,
    expiry_ms: u64,
    execution_delay_ms: u64,
    cooldown_ms: u64,
}

/// Proposal lifecycle status. Transitions are one-directional:
/// Active -> Passed | Expired, Passed -> Executed.
public enum ProposalStatus has copy, drop, store {
    Active,
    Passed,
    Executed,
    Expired,
}

/// Hot-potato authorization token emitted by execute().
/// Must be consumed by the proposal type's handler in the same PTB.
/// P is phantom — it exists only as a type tag to bind the request
/// to the correct handler at the type level.
public struct ExecutionRequest<phantom P> {
    dao_id: ID,
    proposal_id: ID,
}

// === ProposalConfig ===

/// Create and validate a new ProposalConfig.
/// Aborts if quorum not in [1, 10000], approval_threshold not in [5000, 10000],
/// or expiry_ms < 1 hour.
public fun new_config(
    quorum: u16,
    approval_threshold: u16,
    propose_threshold: u64,
    expiry_ms: u64,
    execution_delay_ms: u64,
    cooldown_ms: u64,
): ProposalConfig {
    assert!(quorum >= 1 && quorum <= 10_000, EInvalidQuorum);
    assert!(approval_threshold >= 5_000 && approval_threshold <= 10_000, EInvalidApprovalThreshold);
    assert!(expiry_ms >= MIN_EXPIRY_MS, EInvalidExpiryMs);
    ProposalConfig {
        quorum,
        approval_threshold,
        propose_threshold,
        expiry_ms,
        execution_delay_ms,
        cooldown_ms,
    }
}

public fun quorum(self: &ProposalConfig): u16 { self.quorum }

public fun approval_threshold(self: &ProposalConfig): u16 { self.approval_threshold }

public fun propose_threshold(self: &ProposalConfig): u64 { self.propose_threshold }

public fun expiry_ms(self: &ProposalConfig): u64 { self.expiry_ms }

public fun execution_delay_ms(self: &ProposalConfig): u64 { self.execution_delay_ms }

public fun cooldown_ms(self: &ProposalConfig): u64 { self.cooldown_ms }

// === ExecutionRequest ===

/// Create an ExecutionRequest. Only callable within the framework package.
public(package) fun new_execution_request<P>(dao_id: ID, proposal_id: ID): ExecutionRequest<P> {
    ExecutionRequest { dao_id, proposal_id }
}

public fun req_dao_id<P>(self: &ExecutionRequest<P>): ID { self.dao_id }

public fun req_proposal_id<P>(self: &ExecutionRequest<P>): ID { self.proposal_id }

/// Consume the execution request. Called by handlers to finalize execution.
public fun consume<P>(req: ExecutionRequest<P>) {
    let ExecutionRequest { dao_id: _, proposal_id: _ } = req;
}

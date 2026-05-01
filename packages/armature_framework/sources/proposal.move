module armature::proposal;

use armature::governance::GovernanceConfig;
use armature::utils;
use std::string::String;
use sui::clock::Clock;
use sui::event;
use sui::vec_map::{Self, VecMap};

// === Errors ===

const EInvalidQuorum: u64 = 0;
const EInvalidApprovalThreshold: u64 = 1;
const EInvalidExpiryMs: u64 = 2;
const ENotActive: u64 = 3;
const ENotPassed: u64 = 4;
const EAlreadyVoted: u64 = 5;
const ENotInSnapshot: u64 = 6;
const ENotEligible: u64 = 7;
const EDelayNotElapsed: u64 = 8;
const ECooldownActive: u64 = 9;
const ENotExpired: u64 = 10;
#[allow(unused_const)]
const ETypeNotEnabled: u64 = 11;
const EExecutionPaused: u64 = 12;
const ERequestMismatch: u64 = 13;
const ENotExecuted: u64 = 14;
const EDAONotActive: u64 = 15;

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

/// A shared proposal object. Generic over the payload type P.
/// Created by proposal::create, voted on, then executed or expired.
public struct Proposal<P: store> has key {
    id: UID,
    dao_id: ID,
    type_key: std::ascii::String,
    proposer: address,
    metadata_ipfs: Option<String>,
    payload: P,
    vote_snapshot: VecMap<address, u64>,
    total_snapshot_weight: u64,
    votes_cast: VecMap<address, bool>,
    yes_weight: u64,
    no_weight: u64,
    config: ProposalConfig,
    created_at_ms: u64,
    passed_at_ms: Option<u64>,
    status: ProposalStatus,
}

// === Events ===

public struct ProposalCreated has copy, drop {
    proposal_id: ID,
    dao_id: ID,
    type_key: std::ascii::String,
    proposer: address,
}

public struct VoteCast has copy, drop {
    proposal_id: ID,
    dao_id: ID,
    voter: address,
    approve: bool,
    weight: u64,
}

public struct ProposalPassed has copy, drop {
    proposal_id: ID,
    dao_id: ID,
    yes_weight: u64,
    no_weight: u64,
}

public struct ProposalExecuted has copy, drop {
    proposal_id: ID,
    dao_id: ID,
    executor: address,
}

public struct ProposalExpired has copy, drop {
    proposal_id: ID,
    dao_id: ID,
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

// === ProposalStatus helpers ===

public fun is_active(self: &ProposalStatus): bool {
    match (self) {
        ProposalStatus::Active => true,
        _ => false,
    }
}

public fun is_passed(self: &ProposalStatus): bool {
    match (self) {
        ProposalStatus::Passed => true,
        _ => false,
    }
}

public fun is_executed(self: &ProposalStatus): bool {
    match (self) {
        ProposalStatus::Executed => true,
        _ => false,
    }
}

public fun is_expired(self: &ProposalStatus): bool {
    match (self) {
        ProposalStatus::Expired => true,
        _ => false,
    }
}

// === Proposal ===

/// Return the payload from a proposal. Used by handlers to read execution data.
public fun payload<P: store>(self: &Proposal<P>): &P { &self.payload }

/// Return the DAO ID this proposal belongs to.
public fun dao_id<P: store>(self: &Proposal<P>): ID { self.dao_id }

/// Return the proposal's current status.
public fun status<P: store>(self: &Proposal<P>): &ProposalStatus { &self.status }

/// Return the proposal's type key.
public fun type_key<P: store>(self: &Proposal<P>): std::ascii::String { self.type_key }

/// Return the proposal's yes weight.
public fun yes_weight<P: store>(self: &Proposal<P>): u64 { self.yes_weight }

/// Return the proposal's no weight.
public fun no_weight<P: store>(self: &Proposal<P>): u64 { self.no_weight }

/// Return the total snapshot weight used for quorum/threshold calculations.
public fun total_snapshot_weight<P: store>(self: &Proposal<P>): u64 {
    self.total_snapshot_weight
}

// === Lifecycle: create ===

/// Create a new proposal and share it. Snapshots the current governance weights.
/// The proposer must be in the snapshot (board member for Board governance).
/// `is_dao_active` must be true — prevents proposals on Migrating DAOs.
#[allow(lint(share_owned))]
public(package) fun create<P: store>(
    dao_id: ID,
    type_key: std::ascii::String,
    proposer: address,
    metadata_ipfs: Option<String>,
    payload: P,
    config: ProposalConfig,
    governance: &GovernanceConfig,
    is_dao_active: bool,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(is_dao_active, EDAONotActive);
    let (vote_snapshot, total_snapshot_weight) = governance.board_vote_snapshot();

    let proposal = Proposal<P> {
        id: object::new(ctx),
        dao_id,
        type_key,
        proposer,
        metadata_ipfs,
        payload,
        vote_snapshot,
        total_snapshot_weight,
        votes_cast: vec_map::empty(),
        yes_weight: 0,
        no_weight: 0,
        config,
        created_at_ms: clock.timestamp_ms(),
        passed_at_ms: option::none(),
        status: ProposalStatus::Active,
    };

    let proposal_id = object::id(&proposal);

    event::emit(ProposalCreated {
        proposal_id,
        dao_id,
        type_key,
        proposer,
    });

    transfer::share_object(proposal);
}

// === Lifecycle: vote ===

/// Cast a vote on an active proposal. The voter must be in the snapshot
/// and must not have already voted. If quorum and threshold are met,
/// the proposal transitions to Passed.
public fun vote<P: store>(self: &mut Proposal<P>, approve: bool, clock: &Clock, ctx: &TxContext) {
    assert!(self.status.is_active(), ENotActive);

    let voter = ctx.sender();

    // Voter must be in snapshot
    assert!(self.vote_snapshot.contains(&voter), ENotInSnapshot);

    // No double voting
    assert!(!self.votes_cast.contains(&voter), EAlreadyVoted);

    // Get voter weight from snapshot
    let weight = *self.vote_snapshot.get(&voter);

    // Record vote
    self.votes_cast.insert(voter, approve);
    if (approve) {
        self.yes_weight = self.yes_weight + weight;
    } else {
        self.no_weight = self.no_weight + weight;
    };

    let proposal_id = object::id(self);

    event::emit(VoteCast {
        proposal_id,
        dao_id: self.dao_id,
        voter,
        approve,
        weight,
    });

    // Check if proposal passes: quorum and approval threshold met
    let total_voted = self.yes_weight + self.no_weight;
    let quorum_met = utils::gte_bps(
        total_voted,
        self.total_snapshot_weight,
        (self.config.quorum as u64),
    );

    // approval_threshold is checked against total_snapshot_weight (not total_voted)
    // so that passing guarantees the proposal meets any execution floor of the same
    // percentage. This prevents proposals from being stuck in Passed status when they
    // cannot satisfy execution-time supermajority requirements.
    let threshold_met = utils::gte_bps(
        self.yes_weight,
        self.total_snapshot_weight,
        (self.config.approval_threshold as u64),
    );

    if (quorum_met && threshold_met) {
        self.status = ProposalStatus::Passed;
        self.passed_at_ms = option::some(clock.timestamp_ms());

        event::emit(ProposalPassed {
            proposal_id,
            dao_id: self.dao_id,
            yes_weight: self.yes_weight,
            no_weight: self.no_weight,
        });
    };
}

// === Lifecycle: try_expire ===

/// Attempt to expire an active proposal. Succeeds if the current time
/// exceeds created_at_ms + expiry_ms. Aborts if not Active or not expired.
public fun try_expire<P: store>(self: &mut Proposal<P>, clock: &Clock) {
    assert!(self.status.is_active(), ENotActive);
    let now = clock.timestamp_ms();
    assert!(now >= self.created_at_ms + self.config.expiry_ms, ENotExpired);

    self.status = ProposalStatus::Expired;

    event::emit(ProposalExpired {
        proposal_id: object::id(self),
        dao_id: self.dao_id,
    });
}

// === Lifecycle: execute ===

/// Execute a passed proposal. Returns an ExecutionRequest hot potato.
/// The executor must be a current board member.
/// Checks execution_delay (time since passed) and cooldown (time since last
/// execution of this type in the DAO).
public(package) fun execute<P: store>(
    self: &mut Proposal<P>,
    governance: &GovernanceConfig,
    last_executed_at_ms: Option<u64>,
    execution_paused: bool,
    clock: &Clock,
    ctx: &TxContext,
): ExecutionRequest<P> {
    assert!(!execution_paused, EExecutionPaused);
    assert!(self.status.is_passed(), ENotPassed);

    let executor = ctx.sender();

    // Executor must be a current board member
    assert!(governance.is_board_member(executor), ENotEligible);

    let now = clock.timestamp_ms();
    let passed_at = self.passed_at_ms.destroy_some();

    // Check execution delay
    if (self.config.execution_delay_ms > 0) {
        assert!(now >= passed_at + self.config.execution_delay_ms, EDelayNotElapsed);
    };

    // Check cooldown
    if (self.config.cooldown_ms > 0) {
        if (last_executed_at_ms.is_some()) {
            let last = last_executed_at_ms.destroy_some();
            assert!(now >= last + self.config.cooldown_ms, ECooldownActive);
        };
    };

    self.status = ProposalStatus::Executed;

    let proposal_id = object::id(self);
    let dao_id = self.dao_id;

    event::emit(ProposalExecuted {
        proposal_id,
        dao_id,
        executor,
    });

    ExecutionRequest<P> { dao_id, proposal_id }
}

// === Lifecycle: privileged_create ===

/// Create a privileged proposal directly in Executed status.
/// Used by the controller bypass flow (SubDAOControl-authorized).
/// The proposal is shared for on-chain audit; returns an ExecutionRequest
/// to authorize SubDAO mutations in the same PTB.
#[allow(lint(share_owned, custom_state_change))]
public(package) fun privileged_create<P: store>(
    dao_id: ID,
    type_key: std::ascii::String,
    proposer: address,
    metadata_ipfs: Option<String>,
    payload: P,
    clock: &Clock,
    ctx: &mut TxContext,
): ExecutionRequest<P> {
    let now = clock.timestamp_ms();

    let proposal = Proposal<P> {
        id: object::new(ctx),
        dao_id,
        type_key,
        proposer,
        metadata_ipfs,
        payload,
        vote_snapshot: vec_map::empty(),
        total_snapshot_weight: 0,
        votes_cast: vec_map::empty(),
        yes_weight: 0,
        no_weight: 0,
        config: new_config(10_000, 10_000, 0, MIN_EXPIRY_MS, 0, 0),
        created_at_ms: now,
        passed_at_ms: option::some(now),
        status: ProposalStatus::Executed,
    };

    let proposal_id = object::id(&proposal);

    event::emit(ProposalCreated {
        proposal_id,
        dao_id,
        type_key,
        proposer,
    });

    event::emit(ProposalExecuted {
        proposal_id,
        dao_id,
        executor: proposer,
    });

    transfer::share_object(proposal);

    ExecutionRequest<P> { dao_id, proposal_id }
}

// === ExecutionRequest ===

/// Create an ExecutionRequest. Only callable within the framework package.
public(package) fun new_execution_request<P>(dao_id: ID, proposal_id: ID): ExecutionRequest<P> {
    ExecutionRequest { dao_id, proposal_id }
}

public fun req_dao_id<P>(self: &ExecutionRequest<P>): ID { self.dao_id }

public fun req_proposal_id<P>(self: &ExecutionRequest<P>): ID { self.proposal_id }

/// Consume the execution request. Framework-internal only.
public(package) fun consume<P>(req: ExecutionRequest<P>) {
    let ExecutionRequest { dao_id: _, proposal_id: _ } = req;
}

/// Consume the execution request after validating it matches the proposal.
/// External packages (handlers) must use this instead of consume().
/// Asserts the request was produced for the given proposal and that
/// the proposal has been executed through the governance flow.
public fun finalize<P: store>(req: ExecutionRequest<P>, proposal: &Proposal<P>) {
    assert!(req.dao_id == proposal.dao_id, ERequestMismatch);
    assert!(req.proposal_id == object::id(proposal), ERequestMismatch);
    assert!(proposal.status.is_executed(), ENotExecuted);
    let ExecutionRequest { dao_id: _, proposal_id: _ } = req;
}

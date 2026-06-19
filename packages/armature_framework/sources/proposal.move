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
const ECapDAOMismatch: u64 = 16;
/// ticket_yes_weight or ticket_total_snapshot_weight called on a non-vote-path ticket.
const ENotStandaloneTicket: u64 = 17;
/// delete_executed_proposal called when payload has not been extracted.
const EPayloadNotConsumed: u64 = 18;

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
    /// Whether this type may appear as a step in a composite proposal.
    /// Deny-by-default: false for all types unless explicitly set to true via
    /// UpdateProposalConfig. Floor-gated and governance-sensitive types stay false.
    composable_allowed: bool,
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

/// Capability that authorizes producing an `ExecutionRequest<P>` for a
/// specific DAO without going through a vote. The cap is the on-chain
/// opt-in for bypass execution: a DAO that passes `EnableBypassType<P>`
/// receives one of these in its `CapabilityVault`. Extension packages
/// that wrap an external authorization condition (Character ownership,
/// token balance, attestation, oracle assertion, etc.) borrow the cap
/// and pass it to `external_execution::ticket_from_cap`.
///
/// Scoped per (DAO, proposal type): a cap for tribe Alpha's AutojoinDAO
/// cannot mint a request for tribe Beta, nor for any other proposal type.
/// Construction is framework-internal; outside code cannot fabricate one.
public struct ExternalExecutionCap<phantom P> has key, store {
    id: UID,
    dao_id: ID,
}

/// Hot potato — no abilities. Created only by the three framework mint functions.
/// Carries the owned payload and a package-private closeout tag so that
/// `discharge()` can run the correct finalisation logic regardless of which
/// path minted the ticket.
public struct ExecutionTicket<P> {
    request: ExecutionRequest<P>,
    payload: P,
    closeout: Closeout,
}

/// Package-private: external code cannot construct or hold a Closeout value.
/// `Standalone` captures vote-weight data for approval-floor checks.
public enum Closeout has drop {
    Standalone {
        proposal_id: ID,
        yes_weight: u64,
        total_snapshot_weight: u64,
    },
    Composite,
    External,
}

/// A shared proposal object. Generic over the payload type P.
/// Created by proposal::create, voted on, then executed or expired.
public struct Proposal<P: store> has key {
    id: UID,
    dao_id: ID,
    type_key: std::ascii::String,
    proposer: address,
    metadata_ipfs: Option<String>,
    payload: Option<P>,
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

/// Records the full BCS-serialised payload at proposal creation time.
/// Payload remains queryable via this event even after execution sets
/// Proposal.payload to None. Emitted for both vote-path and external-path proposals.
public struct ProposalPayloadCreated has copy, drop {
    proposal_id: ID,
    dao_id: ID,
    payload_bcs: vector<u8>,
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
        composable_allowed: false,
    }
}

public fun quorum(self: &ProposalConfig): u16 { self.quorum }

public fun approval_threshold(self: &ProposalConfig): u16 { self.approval_threshold }

public fun propose_threshold(self: &ProposalConfig): u64 { self.propose_threshold }

public fun expiry_ms(self: &ProposalConfig): u64 { self.expiry_ms }

public fun execution_delay_ms(self: &ProposalConfig): u64 { self.execution_delay_ms }

public fun cooldown_ms(self: &ProposalConfig): u64 { self.cooldown_ms }

public fun composable_allowed(self: &ProposalConfig): bool { self.composable_allowed }

/// Return a copy of this config with `composable_allowed` set to `allowed`.
/// Used by governance (UpdateProposalConfig) to open a type for composite proposals.
public fun with_composable_allowed(mut self: ProposalConfig, allowed: bool): ProposalConfig {
    self.composable_allowed = allowed;
    self
}

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

/// Return the payload from a proposal. Panics if called post-execution (payload is None).
/// Handlers should read payload via ticket_payload() rather than this accessor.
public fun payload<P: store>(self: &Proposal<P>): &P { self.payload.borrow() }

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

    // Serialise before moving into the Option so the event captures the payload.
    let payload_bcs = std::bcs::to_bytes(&payload);

    let proposal = Proposal<P> {
        id: object::new(ctx),
        dao_id,
        type_key,
        proposer,
        metadata_ipfs,
        payload: option::some(payload),
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

    event::emit(ProposalPayloadCreated { proposal_id, dao_id, payload_bcs });

    transfer::share_object(proposal);
}

/// Like create(), but returns the owned Proposal instead of sharing it.
///
/// INVARIANT: This function may only be called by board_voting::submit_vote_execute.
/// The caller MUST call transfer::share_object on the returned proposal after
/// execution completes. Using transfer::transfer instead would strand an Active
/// proposal in an owned-object state that can never complete its lifecycle, while
/// the ProposalCreated event would still exist on-chain.
public(package) fun create_returning<P: store>(
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
): Proposal<P> {
    assert!(is_dao_active, EDAONotActive);
    let (vote_snapshot, total_snapshot_weight) = governance.board_vote_snapshot();

    let payload_bcs = std::bcs::to_bytes(&payload);

    let proposal = Proposal<P> {
        id: object::new(ctx),
        dao_id,
        type_key,
        proposer,
        metadata_ipfs,
        payload: option::some(payload),
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

    event::emit(ProposalCreated { proposal_id, dao_id, type_key, proposer });
    event::emit(ProposalPayloadCreated { proposal_id, dao_id, payload_bcs });

    proposal
}

/// Share a proposal returned by create_returning. Called by board_voting::submit_vote_execute
/// after executing the proposal, so the Executed object becomes the permanent audit record.
/// Wraps transfer::share_object, which must be called within this module for key-only types.
#[allow(lint(share_owned, custom_state_change))]
public(package) fun share_proposal<P: store>(proposal: Proposal<P>) {
    transfer::share_object(proposal);
}

/// Emit the ProposalPayloadCreated event. Used by external_execution::ticket_from_cap,
/// which must serialise the payload before moving it into the ticket.
public(package) fun emit_payload_created_event(
    proposal_id: ID,
    dao_id: ID,
    payload_bcs: vector<u8>,
) {
    event::emit(ProposalPayloadCreated { proposal_id, dao_id, payload_bcs });
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

    let threshold_met = if (total_voted == 0) {
        false
    } else {
        utils::gte_bps(
            self.yes_weight,
            total_voted,
            (self.config.approval_threshold as u64),
        )
    };

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

/// Execute a passed proposal. Extracts and returns the payload alongside an
/// ExecutionRequest hot potato. The executor must be a current board member.
/// Checks execution_delay (time since passed) and cooldown (time since last
/// execution of this type in the DAO). Callers wrap both return values into a
/// ticket via proposal::new_ticket_standalone.
public(package) fun execute<P: store>(
    self: &mut Proposal<P>,
    governance: &GovernanceConfig,
    last_executed_at_ms: Option<u64>,
    execution_paused: bool,
    clock: &Clock,
    ctx: &TxContext,
): (P, ExecutionRequest<P>) {
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

    // Extract payload from Option, leaving None. Unforgeable replay protection:
    // a second call to execute() would abort because status is already Executed.
    let payload = self.payload.extract();

    (payload, ExecutionRequest<P> { dao_id, proposal_id })
}

// === Lifecycle: privileged_create ===

/// Create a privileged audit proposal in Executed status with no payload.
/// Used by the external-execution bypass flow (ticket_from_cap).
/// The payload lives in the ticket, not in the proposal. Returns an
/// ExecutionRequest for the caller to embed in the ticket.
#[allow(lint(share_owned, custom_state_change))]
public(package) fun privileged_create<P: store>(
    dao_id: ID,
    type_key: std::ascii::String,
    proposer: address,
    metadata_ipfs: Option<String>,
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
        payload: option::none(),
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

/// Create a privileged audit proposal in Executed status WITH a payload stored
/// in the proposal for on-chain audit. Used by the controller bypass flow
/// (SubDAOControl-authorized). Returns an ExecutionRequest to authorize SubDAO
/// mutations in the same PTB.
///
/// Note: because the payload is stored in the proposal, `delete_executed_proposal`
/// cannot be called on it (it asserts `payload.is_none()`). The proposal
/// remains as a permanent audit record, which is the intent for controller operations.
#[allow(lint(share_owned, custom_state_change))]
public(package) fun privileged_create_with_payload<P: store>(
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
        payload: option::some(payload),
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

// === ExternalExecutionCap ===

/// Returns the DAO this cap is scoped to.
public fun cap_dao_id<P>(self: &ExternalExecutionCap<P>): ID { self.dao_id }

/// Create an ExternalExecutionCap, authorized by an active ExecutionRequest.
/// Restricted to `public(package)` so the only caller is the framework's
/// own `external_execution::execute_enable_bypass_type<NewType>` handler.
/// This prevents the cross-type escalation where any caller holding any
/// `ExecutionRequest<Auth>` could mint a cap for an unrelated proposal type.
public(package) fun new_external_execution_cap<Auth, P>(
    req: &ExecutionRequest<Auth>,
    ctx: &mut TxContext,
): ExternalExecutionCap<P> {
    ExternalExecutionCap<P> { id: object::new(ctx), dao_id: req.dao_id }
}

/// Permanently destroy an ExternalExecutionCap.
/// Restricted to `public(package)` so only the framework's
/// `external_execution::execute_disable_bypass_type<NewType>` handler can
/// destroy a cap. The request asserts the cap belongs to the same DAO.
public(package) fun destroy_external_execution_cap<Auth, P>(
    cap: ExternalExecutionCap<P>,
    req: &ExecutionRequest<Auth>,
) {
    assert!(cap.dao_id == req.dao_id, ECapDAOMismatch);
    let ExternalExecutionCap { id, dao_id: _ } = cap;
    id.delete();
}

/// Assert the cap is scoped to the given DAO. Framework-internal —
/// used by `external_execution::ticket_from_cap`.
public(package) fun assert_cap_for_dao<P>(cap: &ExternalExecutionCap<P>, dao_id: ID) {
    assert!(cap.dao_id == dao_id, ECapDAOMismatch);
}

// === ExecutionTicket ===

/// Borrow the payload from a ticket. Borrow ends at last use; safe to call discharge after.
public fun ticket_payload<P>(ticket: &ExecutionTicket<P>): &P {
    &ticket.payload
}

/// Borrow the embedded ExecutionRequest for vault/DAO auth calls.
public fun ticket_request<P>(ticket: &ExecutionTicket<P>): &ExecutionRequest<P> {
    &ticket.request
}

/// Shortcut: DAO ID from the embedded request.
public fun ticket_dao_id<P>(ticket: &ExecutionTicket<P>): ID {
    ticket.request.dao_id
}

/// Returns true iff the ticket was minted via the vote path (Closeout::Standalone).
/// Use this to guard handlers that require a governance vote before reading vote weights.
public fun ticket_is_standalone<P>(ticket: &ExecutionTicket<P>): bool {
    match (&ticket.closeout) {
        Closeout::Standalone { .. } => true,
        _ => false,
    }
}

/// Yes weight at vote time. Only valid for Standalone (vote-path) tickets.
/// Aborts with ENotStandaloneTicket for Composite or External tickets.
/// Call ticket_is_standalone() first if the path is not statically known.
public fun ticket_yes_weight<P>(ticket: &ExecutionTicket<P>): u64 {
    match (&ticket.closeout) {
        Closeout::Standalone { yes_weight, .. } => *yes_weight,
        _ => abort ENotStandaloneTicket,
    }
}

/// Total snapshot weight at vote time. Only valid for Standalone tickets.
/// Aborts with ENotStandaloneTicket for Composite or External tickets.
public fun ticket_total_snapshot_weight<P>(ticket: &ExecutionTicket<P>): u64 {
    match (&ticket.closeout) {
        Closeout::Standalone { total_snapshot_weight, .. } => *total_snapshot_weight,
        _ => abort ENotStandaloneTicket,
    }
}

/// Consume the ticket, enforce the path-appropriate closeout, drop the payload.
/// P must have `drop` — all existing payload types satisfy this.
public fun discharge<P: store + drop>(ticket: ExecutionTicket<P>) {
    let ExecutionTicket { request, payload: _, closeout } = ticket;
    match (closeout) {
        Closeout::Standalone { proposal_id, .. } => {
            assert!(request.proposal_id == proposal_id, ERequestMismatch);
            let ExecutionRequest { dao_id: _, proposal_id: _ } = request;
        },
        Closeout::Composite | Closeout::External => {
            let ExecutionRequest { dao_id: _, proposal_id: _ } = request;
        },
    }
}

/// Like `discharge` but returns the payload instead of dropping it.
/// Use for payload types that lack `drop` (e.g., wrappers around `TreasuryCap`).
public fun discharge_returning_payload<P: store>(ticket: ExecutionTicket<P>): P {
    let ExecutionTicket { request, payload, closeout } = ticket;
    match (closeout) {
        Closeout::Standalone { proposal_id, .. } => {
            assert!(request.proposal_id == proposal_id, ERequestMismatch);
            let ExecutionRequest { dao_id: _, proposal_id: _ } = request;
        },
        Closeout::Composite | Closeout::External => {
            let ExecutionRequest { dao_id: _, proposal_id: _ } = request;
        },
    };
    payload
}

// === Framework-internal ticket constructors ===

/// Called by board_voting::ticket_from_vote.
public(package) fun new_ticket_standalone<P: store>(
    request: ExecutionRequest<P>,
    payload: P,
    yes_weight: u64,
    total_snapshot_weight: u64,
): ExecutionTicket<P> {
    let proposal_id = request.proposal_id;
    ExecutionTicket {
        request,
        payload,
        closeout: Closeout::Standalone { proposal_id, yes_weight, total_snapshot_weight },
    }
}

/// Called by composite::advance_step.
public(package) fun new_ticket_composite<P>(
    dao_id: ID,
    composite_proposal_id: ID,
    payload: P,
): ExecutionTicket<P> {
    ExecutionTicket {
        request: new_execution_request<P>(dao_id, composite_proposal_id),
        payload,
        closeout: Closeout::Composite,
    }
}

/// Called by external_execution::ticket_from_cap.
public(package) fun new_ticket_external<P>(
    request: ExecutionRequest<P>,
    payload: P,
): ExecutionTicket<P> {
    ExecutionTicket { request, payload, closeout: Closeout::External }
}

// === Proposal cleanup ===

/// Delete an executed proposal whose payload has already been consumed.
/// Safe to call by any party — the audit record is preserved in events
/// (ProposalCreated, ProposalExecuted, ProposalPayloadCreated) regardless.
/// The caller receives the Sui storage rebate.
public fun delete_executed_proposal<P: store + drop>(proposal: Proposal<P>) {
    let Proposal {
        id,
        status,
        payload,
        dao_id: _,
        type_key: _,
        proposer: _,
        metadata_ipfs: _,
        vote_snapshot: _,
        total_snapshot_weight: _,
        votes_cast: _,
        yes_weight: _,
        no_weight: _,
        config: _,
        created_at_ms: _,
        passed_at_ms: _,
    } = proposal;
    assert!(status.is_executed(), ENotExecuted);
    assert!(payload.is_none(), EPayloadNotConsumed);
    object::delete(id);
}

// === Test Helpers ===

#[test_only]
/// Mint an ExternalExecutionCap<P> for testing without going through governance.
public fun new_external_execution_cap_for_testing<P>(
    dao_id: ID,
    ctx: &mut TxContext,
): ExternalExecutionCap<P> {
    ExternalExecutionCap<P> { id: object::new(ctx), dao_id }
}

#[test_only]
/// Synthesize an ExecutionRequest<P> for testing. Cross-package tests (e.g.
/// armature_world_bridge) need to thread a request between split-PTB test
/// transactions; production code can never call this because it's #[test_only].
public fun new_execution_request_for_testing<P>(dao_id: ID, proposal_id: ID): ExecutionRequest<P> {
    ExecutionRequest { dao_id, proposal_id }
}

#[test_only]
/// Destroy an ExternalExecutionCap from a test scenario.
public fun destroy_external_execution_cap_for_testing<P>(cap: ExternalExecutionCap<P>) {
    let ExternalExecutionCap { id, dao_id: _ } = cap;
    id.delete();
}

#[test_only]
/// Consume a raw ExecutionRequest in tests (e.g. to drain the hot potato after
/// privileged_create or after manually constructing one via new_execution_request_for_testing).
public fun consume_execution_request_for_testing<P>(req: ExecutionRequest<P>) {
    let ExecutionRequest { dao_id: _, proposal_id: _ } = req;
}

#[test_only]
/// Synthesize an ExecutionTicket<P> with Standalone closeout and given vote weights.
/// Allows tests to exercise approval-floor checks without a real vote.
public fun new_standalone_ticket_for_testing<P: store>(
    dao_id: ID,
    proposal_id: ID,
    payload: P,
    yes_weight: u64,
    total_snapshot_weight: u64,
): ExecutionTicket<P> {
    let request = ExecutionRequest { dao_id, proposal_id };
    ExecutionTicket {
        request,
        payload,
        closeout: Closeout::Standalone { proposal_id, yes_weight, total_snapshot_weight },
    }
}

#[test_only]
/// privileged_create variant that accepts a payload for testing purposes.
/// Returns an ExecutionTicket (Standalone closeout) with zero vote weights.
/// Use for tests that need to construct a zero-weight or crafted Proposal.
public fun privileged_create_for_testing<P: store>(
    dao_id: ID,
    type_key: std::ascii::String,
    proposer: address,
    metadata_ipfs: Option<String>,
    payload: P,
    clock: &Clock,
    ctx: &mut TxContext,
): ExecutionTicket<P> {
    let now = clock.timestamp_ms();

    let proposal = Proposal<P> {
        id: object::new(ctx),
        dao_id,
        type_key,
        proposer,
        metadata_ipfs,
        payload: option::none(),
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

    let request = ExecutionRequest { dao_id, proposal_id };
    ExecutionTicket {
        request,
        payload,
        closeout: Closeout::Standalone { proposal_id, yes_weight: 0, total_snapshot_weight: 0 },
    }
}

#[test_only]
/// Synthesize an ExecutionTicket<P> with Composite closeout.
/// Allows tests to verify ENotStandaloneTicket abort paths.
public fun new_composite_ticket_for_testing<P: store>(
    dao_id: ID,
    proposal_id: ID,
    payload: P,
): ExecutionTicket<P> {
    let request = ExecutionRequest { dao_id, proposal_id };
    ExecutionTicket { request, payload, closeout: Closeout::Composite }
}

#[test_only]
/// Synthesize an ExecutionTicket<P> with External closeout.
/// Allows tests to verify ENotStandaloneTicket abort paths.
public fun new_external_ticket_for_testing<P: store>(
    dao_id: ID,
    proposal_id: ID,
    payload: P,
): ExecutionTicket<P> {
    let request = ExecutionRequest { dao_id, proposal_id };
    ExecutionTicket { request, payload, closeout: Closeout::External }
}

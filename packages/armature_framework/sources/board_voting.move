module armature::board_voting;

use armature::dao::{Self, DAO};
use armature::emergency::EmergencyFreeze;
use armature::enable_proposal_type::EnableProposalType;
use armature::proposal::{Self, ExecutionTicket, Proposal, ProposalConfig};
use std::string::String;
use std::type_name::{Self, TypeName};
use sui::clock::Clock;

// === Errors ===

const EDAONotActive: u64 = 0;
const ETypeNotEnabled: u64 = 1;
const EDAOIdMismatch: u64 = 2;
const EControllerPaused: u64 = 3;
const EProposeThresholdNotMet: u64 = 4;
/// Proposal's approval_threshold is below the hardcoded floor for this type.
/// Enforced at submission time so the proposal never enters the object graph.
const EFloorNotMet: u64 = 6;
/// submit_vote_execute called for a type whose execution_delay_ms > 0.
/// Atomic execution is impossible when a delay is configured — use submit_proposal instead.
const EDelayForbidsAtomicExecution: u64 = 7;
/// submit_vote_execute called but the caller's single vote did not satisfy
/// the proposal type's quorum and approval_threshold requirements.
const EInsufficientVotingWeight: u64 = 8;
/// A `_readonly` entry point was called for a type with cooldown_ms > 0. Cooldown
/// tracking writes the type's slot, so those types must use the `&mut DAO` variant.
const ECooldownRequiresMutableDAO: u64 = 9;

// === Constants ===

/// 66% approval floor for EnableProposalType proposals (basis points).
/// Matches the constant in admin_ops; enforced here at submission time.
const ENABLE_APPROVAL_FLOOR_BPS: u64 = 6_600;

// === Submit ===

/// Submit a new proposal for board governance.
/// Validates: DAO is active, type `P` is enabled, proposer is a board member.
/// The proposal type is identified by `P` itself: its slot on the DAO supplies
/// the ProposalConfig and the display key recorded on the proposal, so a
/// payload of one type can never be submitted under another type's config.
#[allow(lint(share_owned, custom_state_change))]
public fun submit_proposal<P: store>(
    dao: &DAO,
    metadata_ipfs: Option<String>,
    payload: P,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let name = type_name::with_defining_ids<P>();
    assert_submittable(dao, &name);

    let proposer = ctx.sender();
    dao.governance().assert_board_member(proposer);

    let config = dao.type_config_by_name(&name);
    assert_enable_floor(&name, &config);
    assert_propose_threshold(dao, &config, proposer);

    // Status validated above: active or migration-allowed
    proposal::create<P>(
        dao.id(),
        dao.type_display_key_by_name(&name),
        proposer,
        metadata_ipfs,
        payload,
        config,
        dao.governance(),
        true,
        clock,
        ctx,
    );
}

// === Submit + Vote + Execute (atomic) ===

/// Submit a proposal, cast the caller's YES vote, and execute — all in one PTB.
///
/// No Proposal object is created: nobody else votes on it, so the proposal's
/// events (ProposalCreated, ProposalPayloadCreated, VoteCast, ProposalPassed,
/// ProposalExecuted) are the audit record, under a freshly minted proposal ID.
///
/// Requires:
///   - execution_delay_ms = 0 for this proposal type (EDelayForbidsAtomicExecution)
///   - The caller's single vote satisfies quorum and approval_threshold (EInsufficientVotingWeight)
///
/// All other validation mirrors submit_proposal + ticket_from_vote in order.
/// Returns a Standalone ExecutionTicket<P>; execution-time floor checks in
/// handlers (e.g. assert_approval_floor_ticket for EnableBypassType) apply identically.
///
/// Security note: the inter-PTB observation and emergency-freeze windows present
/// in the standard two-PTB path are eliminated. Governance-sensitive types
/// (SetBoard, AddMember, RemoveMember, UpdateProposalConfig, EnableProposalType)
/// MUST be configured with execution_delay_ms > 0 so this path cannot be used for them.
///
/// Records the execution timestamp in the type's slot for cooldown tracking. For
/// types with cooldown_ms = 0 prefer `submit_vote_execute_readonly`, which leaves
/// the DAO untouched.
public fun submit_vote_execute<P: store>(
    dao: &mut DAO,
    metadata_ipfs: Option<String>,
    payload: P,
    freeze: &EmergencyFreeze,
    clock: &Clock,
    ctx: &mut TxContext,
): ExecutionTicket<P> {
    let ticket = submit_vote_execute_core(dao, metadata_ipfs, payload, freeze, clock, false, ctx);
    dao.record_execution(type_name::with_defining_ids<P>(), clock.timestamp_ms());
    ticket
}

/// `submit_vote_execute` for types with cooldown_ms = 0, taking the DAO by
/// immutable reference. Nothing on the DAO is written: the last-executed
/// timestamp only feeds cooldown checks, so it is not recorded. A PTB that uses
/// only read-only entry points can pass the DAO as an immutable shared input,
/// which is neither versioned nor rewritten and takes no write lock, so
/// concurrent executions stop contending on the DAO.
///
/// Aborts with ECooldownRequiresMutableDAO if the type's cooldown_ms > 0.
public fun submit_vote_execute_readonly<P: store>(
    dao: &DAO,
    metadata_ipfs: Option<String>,
    payload: P,
    freeze: &EmergencyFreeze,
    clock: &Clock,
    ctx: &mut TxContext,
): ExecutionTicket<P> {
    submit_vote_execute_core(dao, metadata_ipfs, payload, freeze, clock, true, ctx)
}

// === Execute ===

/// Mint an ExecutionTicket for a passed proposal. Replaces authorize_execution.
/// Validates: DAO is active, proposal belongs to this DAO, type still enabled,
/// type not frozen. Records the execution timestamp for cooldown tracking.
public fun ticket_from_vote<P: store>(
    dao: &mut DAO,
    prop: &mut Proposal<P>,
    freeze: &EmergencyFreeze,
    clock: &Clock,
    ctx: &TxContext,
): ExecutionTicket<P> {
    let ticket = ticket_from_vote_core(dao, prop, freeze, clock, false, ctx);
    dao.record_execution(type_name::with_defining_ids<P>(), clock.timestamp_ms());
    ticket
}

/// `ticket_from_vote` for types with cooldown_ms = 0, taking the DAO by immutable
/// reference and recording nothing on it (see `submit_vote_execute_readonly`).
///
/// Aborts with ECooldownRequiresMutableDAO if either the type's current config or
/// the config snapshotted on the proposal has cooldown_ms > 0.
public fun ticket_from_vote_readonly<P: store>(
    dao: &DAO,
    prop: &mut Proposal<P>,
    freeze: &EmergencyFreeze,
    clock: &Clock,
    ctx: &TxContext,
): ExecutionTicket<P> {
    ticket_from_vote_core(dao, prop, freeze, clock, true, ctx)
}

// === Internal ===

/// Shared body of `submit_vote_execute` and `submit_vote_execute_readonly`:
/// every check and effect except recording the execution timestamp.
fun submit_vote_execute_core<P: store>(
    dao: &DAO,
    metadata_ipfs: Option<String>,
    payload: P,
    freeze: &EmergencyFreeze,
    clock: &Clock,
    readonly: bool,
    ctx: &mut TxContext,
): ExecutionTicket<P> {
    // --- Validation from submit_proposal ---

    let name = type_name::with_defining_ids<P>();
    assert_submittable(dao, &name);

    let proposer = ctx.sender();
    dao.governance().assert_board_member(proposer);

    let config = dao.type_config_by_name(&name);
    let display_key = dao.type_display_key_by_name(&name);
    assert_enable_floor(&name, &config);
    assert_propose_threshold(dao, &config, proposer);

    // Atomic execution is impossible when a delay is configured. Reject here
    // before any state mutation rather than letting execute() produce EDelayNotElapsed.
    assert!(config.execution_delay_ms() == 0, EDelayForbidsAtomicExecution);
    assert!(!readonly || config.cooldown_ms() == 0, ECooldownRequiresMutableDAO);

    // --- Validation from ticket_from_vote ---

    assert!(!dao.is_controller_paused(), EControllerPaused);
    freeze.assert_not_frozen(&display_key, clock);

    // --- Vote: the proposer's YES must pass on its own ---

    // Board governance weighs each member 1 (see governance::board_vote_snapshot).
    let yes_weight = 1;
    let total_snapshot_weight = dao.governance().board_vote_total_weight();
    assert!(config.passes(yes_weight, 0, total_snapshot_weight), EInsufficientVotingWeight);

    // --- Execute ---

    proposal::execute_single_vote(
        dao.id(),
        display_key,
        proposer,
        metadata_ipfs,
        payload,
        &config,
        yes_weight,
        total_snapshot_weight,
        dao.last_executed_ms_by_name(&name),
        dao.is_execution_paused(),
        clock,
        ctx,
    )
}

/// Shared body of `ticket_from_vote` and `ticket_from_vote_readonly`: every
/// check and effect except recording the execution timestamp.
fun ticket_from_vote_core<P: store>(
    dao: &DAO,
    prop: &mut Proposal<P>,
    freeze: &EmergencyFreeze,
    clock: &Clock,
    readonly: bool,
    ctx: &TxContext,
): ExecutionTicket<P> {
    let name = type_name::with_defining_ids<P>();
    let is_active = dao.status().is_active();
    let is_migration_ok =
        dao.status().is_migrating()
        && dao::is_migration_allowed_type(&name);
    assert!(is_active || is_migration_ok, EDAONotActive);
    assert!(prop.dao_id() == dao.id(), EDAOIdMismatch);
    assert!(dao.is_type_name_enabled(&name), ETypeNotEnabled);
    assert!(!dao.is_controller_paused(), EControllerPaused);
    // Both configs matter: execute() enforces the proposal's snapshot, and the
    // slot's current config is what later executions of this type check against.
    assert!(
        !readonly || (dao.type_config_by_name(&name).cooldown_ms() == 0
            && prop.config().cooldown_ms() == 0),
        ECooldownRequiresMutableDAO,
    );
    // Checks the display key recorded at submission, not the slot's current key.
    // If the type was disabled and re-enabled under a new key while this proposal
    // was pending, a freeze on the new key does not block it. The re-enable itself
    // requires an EnableProposalType vote (66% floor).
    freeze.assert_not_frozen(&prop.type_key(), clock);

    let last_ms = dao.last_executed_ms_by_name(&name);

    // Read vote weights before execute() mutates proposal state.
    let yes_weight = prop.yes_weight();
    let total_snapshot_weight = prop.total_snapshot_weight();

    let (payload, req) = proposal::execute(
        prop,
        dao.governance(),
        last_ms,
        dao.is_execution_paused(),
        clock,
        ctx,
    );

    proposal::new_ticket_standalone(req, payload, yes_weight, total_snapshot_weight)
}

/// DAO must be Active, or Migrating with a migration-allowed type; the type
/// must have a slot.
fun assert_submittable(dao: &DAO, name: &TypeName) {
    let is_active = dao.status().is_active();
    let is_migration_ok =
        dao.status().is_migrating()
        && dao::is_migration_allowed_type(name);
    assert!(is_active || is_migration_ok, EDAONotActive);
    assert!(dao.is_type_name_enabled(name), ETypeNotEnabled);
}

/// Submission-time floor enforcement for EnableProposalType.
/// The proposal's approval_threshold must be >= 66% so that the vote guarantee
/// (yes/total_voted >= threshold >= floor) is locked in at proposal creation time
/// rather than re-checked at execution (where only the ticket, not the proposal, is live).
fun assert_enable_floor(name: &TypeName, config: &ProposalConfig) {
    if (*name == type_name::with_defining_ids<EnableProposalType>()) {
        assert!((config.approval_threshold() as u64) >= ENABLE_APPROVAL_FLOOR_BPS, EFloorNotMet);
    };
}

fun assert_propose_threshold(dao: &DAO, config: &ProposalConfig, proposer: address) {
    if (config.propose_threshold() > 0) {
        let weight = dao.governance().proposer_weight(proposer);
        assert!(weight >= config.propose_threshold(), EProposeThresholdNotMet);
    };
}

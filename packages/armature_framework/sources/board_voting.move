module armature::board_voting;

use armature::dao::{Self, DAO};
use armature::emergency::EmergencyFreeze;
use armature::proposal::{Self, ExecutionTicket, Proposal};
use std::string::String;
use std::type_name;
use sui::clock::Clock;

// === Errors ===

const EDAONotActive: u64 = 0;
const ETypeNotEnabled: u64 = 1;
const EDAOIdMismatch: u64 = 2;
const EControllerPaused: u64 = 3;
const EProposeThresholdNotMet: u64 = 4;
/// Submitted payload type P does not match the Move type bound to this type_key.
const ETypeMismatch: u64 = 5;
/// Proposal's approval_threshold is below the hardcoded floor for this type.
/// Enforced at submission time so the proposal never enters the object graph.
const EFloorNotMet: u64 = 6;
/// submit_vote_execute called for a type whose execution_delay_ms > 0.
/// Atomic execution is impossible when a delay is configured — use submit_proposal instead.
const EDelayForbidsAtomicExecution: u64 = 7;
/// submit_vote_execute called but the caller's single vote did not satisfy
/// the proposal type's quorum and approval_threshold requirements.
const EInsufficientVotingWeight: u64 = 8;

// === Constants ===

/// 66% approval floor for EnableProposalType proposals (basis points).
/// Matches the constant in admin_ops; enforced here at submission time.
const ENABLE_APPROVAL_FLOOR_BPS: u64 = 6_600;

// === Submit ===

/// Submit a new proposal for board governance.
/// Validates: DAO is active, type is enabled, proposer is a board member.
/// Looks up the ProposalConfig for the given type_key from the DAO.
#[allow(lint(share_owned, custom_state_change))]
public fun submit_proposal<P: store>(
    dao: &DAO,
    type_key: std::ascii::String,
    metadata_ipfs: Option<String>,
    payload: P,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let is_active = dao.status().is_active();
    let is_migration_ok =
        dao.status().is_migrating()
        && dao::is_migration_allowed_type(&type_key);
    assert!(is_active || is_migration_ok, EDAONotActive);
    assert!(dao.enabled_proposal_types().contains(&type_key), ETypeNotEnabled);

    // If the type_key has a bound Move type, verify P matches to prevent spoofing.
    if (dao.has_type_binding(&type_key)) {
        let actual = type_name::with_defining_ids<P>().into_string();
        assert!(dao.type_binding_for(&type_key) == actual, ETypeMismatch);
    };

    let proposer = ctx.sender();
    dao.governance().assert_board_member(proposer);

    let config = *dao.proposal_configs().get(&type_key);

    // Submission-time floor enforcement for EnableProposalType.
    // The proposal's approval_threshold must be >= 66% so that the vote guarantee
    // (yes/total_voted >= threshold >= floor) is locked in at proposal creation time
    // rather than re-checked at execution (where only the ticket, not the proposal, is live).
    if (type_key == b"EnableProposalType".to_ascii_string()) {
        assert!((config.approval_threshold() as u64) >= ENABLE_APPROVAL_FLOOR_BPS, EFloorNotMet);
    };

    if (config.propose_threshold() > 0) {
        let weight = dao.governance().proposer_weight(proposer);
        assert!(weight >= config.propose_threshold(), EProposeThresholdNotMet);
    };

    // Status validated above: active or migration-allowed
    let status_ok = true;
    proposal::create<P>(
        dao.id(),
        type_key,
        proposer,
        metadata_ipfs,
        payload,
        config,
        dao.governance(),
        status_ok,
        clock,
        ctx,
    );
}

// === Submit + Vote + Execute (atomic) ===

/// Submit a proposal, cast the caller's YES vote, and execute — all in one PTB.
///
/// The proposal is kept owned (never shared while Active) so the vote and
/// execution can happen in the same transaction. After execution the proposal is
/// shared as a permanent Executed audit record, identical to the standard path.
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
public fun submit_vote_execute<P: store>(
    dao: &mut DAO,
    type_key: std::ascii::String,
    metadata_ipfs: Option<String>,
    payload: P,
    freeze: &EmergencyFreeze,
    clock: &Clock,
    ctx: &mut TxContext,
): ExecutionTicket<P> {
    // --- Validation from submit_proposal ---

    let is_active = dao.status().is_active();
    let is_migration_ok =
        dao.status().is_migrating()
        && dao::is_migration_allowed_type(&type_key);
    assert!(is_active || is_migration_ok, EDAONotActive);
    assert!(dao.enabled_proposal_types().contains(&type_key), ETypeNotEnabled);

    if (dao.has_type_binding(&type_key)) {
        let actual = type_name::with_defining_ids<P>().into_string();
        assert!(dao.type_binding_for(&type_key) == actual, ETypeMismatch);
    };

    let proposer = ctx.sender();
    dao.governance().assert_board_member(proposer);

    let config = *dao.proposal_configs().get(&type_key);

    // Submission-time floor for EnableProposalType (mirrors submit_proposal).
    if (type_key == b"EnableProposalType".to_ascii_string()) {
        assert!((config.approval_threshold() as u64) >= ENABLE_APPROVAL_FLOOR_BPS, EFloorNotMet);
    };

    if (config.propose_threshold() > 0) {
        let weight = dao.governance().proposer_weight(proposer);
        assert!(weight >= config.propose_threshold(), EProposeThresholdNotMet);
    };

    // Atomic execution is impossible when a delay is configured. Reject here
    // before any state mutation rather than letting execute() produce EDelayNotElapsed.
    assert!(config.execution_delay_ms() == 0, EDelayForbidsAtomicExecution);

    // --- Validation from ticket_from_vote ---

    assert!(!dao.is_controller_paused(), EControllerPaused);
    freeze.assert_not_frozen(&type_key, clock);

    let last_executed_at = dao.last_executed_at();
    let last_ms = if (last_executed_at.contains(&type_key)) {
        option::some(*last_executed_at.get(&type_key))
    } else {
        option::none()
    };

    // --- Create owned proposal (never shared while Active) ---

    let mut prop = proposal::create_returning<P>(
        dao.id(),
        type_key,
        proposer,
        metadata_ipfs,
        payload,
        config,
        dao.governance(),
        true,
        clock,
        ctx,
    );

    // --- Vote ---

    proposal::vote(&mut prop, true, clock, ctx);

    assert!(prop.status().is_passed(), EInsufficientVotingWeight);

    // --- Execute ---

    let yes_weight = prop.yes_weight();
    let total_snapshot_weight = prop.total_snapshot_weight();

    let (payload_out, req) = proposal::execute(
        &mut prop,
        dao.governance(),
        last_ms,
        dao.is_execution_paused(),
        clock,
        ctx,
    );

    dao.record_execution(type_key, clock.timestamp_ms());

    // Share the Executed proposal as the permanent audit record.
    // transfer::share_object cannot be called from outside proposal.move for key-only types.
    proposal::share_proposal(prop);

    proposal::new_ticket_standalone(req, payload_out, yes_weight, total_snapshot_weight)
}

// === Execute ===

/// Mint an ExecutionTicket for a passed proposal. Replaces authorize_execution.
/// Validates: DAO is active, proposal belongs to this DAO, type not frozen.
/// Records the execution timestamp for cooldown tracking.
public fun ticket_from_vote<P: store>(
    dao: &mut DAO,
    prop: &mut Proposal<P>,
    freeze: &EmergencyFreeze,
    clock: &Clock,
    ctx: &TxContext,
): ExecutionTicket<P> {
    let type_key = prop.type_key();
    let is_active = dao.status().is_active();
    let is_migration_ok =
        dao.status().is_migrating()
        && dao::is_migration_allowed_type(&type_key);
    assert!(is_active || is_migration_ok, EDAONotActive);
    assert!(prop.dao_id() == dao.id(), EDAOIdMismatch);
    assert!(!dao.is_controller_paused(), EControllerPaused);
    freeze.assert_not_frozen(&type_key, clock);

    let last_executed_at = dao.last_executed_at();
    let last_ms = if (last_executed_at.contains(&type_key)) {
        option::some(*last_executed_at.get(&type_key))
    } else {
        option::none()
    };

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

    dao.record_execution(type_key, clock.timestamp_ms());

    proposal::new_ticket_standalone(req, payload, yes_weight, total_snapshot_weight)
}

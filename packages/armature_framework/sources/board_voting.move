module armature::board_voting;

use armature::ou::{Self, OU};
use armature::emergency::EmergencyFreeze;
use armature::enable_proposal_type::EnableProposalType;
use armature::proposal::{Self, ExecutionTicket, Proposal, ProposalConfig};
use std::string::String;
use std::type_name::{Self, TypeName};
use sui::clock::Clock;

// === Errors ===

const EOUNotActive: u64 = 0;
const ETypeNotEnabled: u64 = 1;
const EOUIdMismatch: u64 = 2;
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
/// tracking writes the type's slot, so those types must use the `&mut OU` variant.
const ECooldownRequiresMutableOU: u64 = 9;

// === Constants ===

/// 80% approval floor for EnableProposalType proposals (basis points).
/// Matches ou::min_approval_threshold_for_type; enforced here at submission time.
const ENABLE_APPROVAL_FLOOR_BPS: u64 = 8_000;

// === Submit ===

/// Submit a new proposal for board governance.
/// Validates: OU is active, type `P` is enabled, proposer is a board member.
/// The proposal type is identified by `P` itself: its slot on the OU supplies
/// the ProposalConfig and the display key recorded on the proposal, so a
/// payload of one type can never be submitted under another type's config.
#[allow(lint(share_owned, custom_state_change))]
public fun submit_proposal<P: store>(
    ou: &OU,
    metadata_ipfs: Option<String>,
    payload: P,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let name = type_name::with_defining_ids<P>();
    assert_submittable(ou, &name);

    let proposer = ctx.sender();
    ou.governance().assert_board_member(proposer);

    let config = ou.type_config_by_name(&name);
    assert_enable_floor(&name, &config);
    assert_propose_threshold(ou, &config, proposer);

    // Status validated above: active or migration-allowed
    proposal::create<P>(
        ou.id(),
        ou.type_display_key_by_name(&name),
        proposer,
        metadata_ipfs,
        payload,
        config,
        ou.governance(),
        true,
        clock,
        ctx,
    );
}

// === Vote ===

/// Cast the caller's vote on a proposal of `ou`. The caller must have been a
/// board member at the roster version the proposal was created at: members
/// added since cannot vote, and members removed since still can. Takes the OU
/// by immutable reference to read its roster, so votes do not contend on it.
public fun vote<P: store>(
    proposal: &mut Proposal<P>,
    ou: &OU,
    approve: bool,
    clock: &Clock,
    ctx: &TxContext,
) {
    assert!(proposal.ou_id() == ou.id(), EOUIdMismatch);
    proposal.record_vote(ou.governance(), approve, clock, ctx);
}

// === Submit + Vote + Execute (atomic) ===

/// Submit a proposal, cast the caller's YES vote, and execute — all in one PTB.
///
/// No Proposal object is created: nobody else votes on it, so the proposal's
/// events (ProposalCreated, ProposalPayloadCreated, VoteCast, ProposalPassed,
/// ProposalExecuted) are the audit record, under a freshly minted proposal ID.
///
/// Requires:
/// - execution_delay_ms = 0 for this proposal type (EDelayForbidsAtomicExecution)
/// - The caller's single vote satisfies quorum and approval_threshold (EInsufficientVotingWeight)
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
/// the OU untouched.
public fun submit_vote_execute<P: store>(
    ou: &mut OU,
    metadata_ipfs: Option<String>,
    payload: P,
    freeze: &EmergencyFreeze,
    clock: &Clock,
    ctx: &mut TxContext,
): ExecutionTicket<P> {
    let ticket = submit_vote_execute_core(ou, metadata_ipfs, payload, freeze, clock, false, ctx);
    ou.record_execution(type_name::with_defining_ids<P>(), clock.timestamp_ms());
    ticket
}

/// `submit_vote_execute` for types with cooldown_ms = 0, taking the OU by
/// immutable reference. Nothing on the OU is written: the last-executed
/// timestamp only feeds cooldown checks, so it is not recorded. A PTB that uses
/// only read-only entry points can pass the OU as an immutable shared input,
/// which is neither versioned nor rewritten and takes no write lock, so
/// concurrent executions stop contending on the OU.
///
/// Aborts with ECooldownRequiresMutableOU if the type's cooldown_ms > 0.
public fun submit_vote_execute_readonly<P: store>(
    ou: &OU,
    metadata_ipfs: Option<String>,
    payload: P,
    freeze: &EmergencyFreeze,
    clock: &Clock,
    ctx: &mut TxContext,
): ExecutionTicket<P> {
    submit_vote_execute_core(ou, metadata_ipfs, payload, freeze, clock, true, ctx)
}

// === Execute ===

/// Mint an ExecutionTicket for a passed proposal and delete the proposal; the
/// storage rebate goes to the transaction's gas payer.
/// Validates: OU is active, proposal belongs to this OU, type still enabled,
/// type not frozen. Records the execution timestamp for cooldown tracking.
public fun ticket_from_vote<P: store>(
    ou: &mut OU,
    prop: Proposal<P>,
    freeze: &EmergencyFreeze,
    clock: &Clock,
    ctx: &TxContext,
): ExecutionTicket<P> {
    let ticket = ticket_from_vote_core(ou, prop, freeze, clock, false, ctx);
    ou.record_execution(type_name::with_defining_ids<P>(), clock.timestamp_ms());
    ticket
}

/// `ticket_from_vote` for types with cooldown_ms = 0, taking the OU by immutable
/// reference and recording nothing on it (see `submit_vote_execute_readonly`).
///
/// Aborts with ECooldownRequiresMutableOU if either the type's current config or
/// the config snapshotted on the proposal has cooldown_ms > 0.
public fun ticket_from_vote_readonly<P: store>(
    ou: &OU,
    prop: Proposal<P>,
    freeze: &EmergencyFreeze,
    clock: &Clock,
    ctx: &TxContext,
): ExecutionTicket<P> {
    ticket_from_vote_core(ou, prop, freeze, clock, true, ctx)
}

// === Internal ===

/// Shared body of `submit_vote_execute` and `submit_vote_execute_readonly`:
/// every check and effect except recording the execution timestamp.
fun submit_vote_execute_core<P: store>(
    ou: &OU,
    metadata_ipfs: Option<String>,
    payload: P,
    freeze: &EmergencyFreeze,
    clock: &Clock,
    readonly: bool,
    ctx: &mut TxContext,
): ExecutionTicket<P> {
    // --- Validation from submit_proposal ---

    let name = type_name::with_defining_ids<P>();
    assert_submittable(ou, &name);

    let proposer = ctx.sender();
    ou.governance().assert_board_member(proposer);

    let config = ou.type_config_by_name(&name);
    let display_key = ou.type_display_key_by_name(&name);
    assert_enable_floor(&name, &config);
    assert_propose_threshold(ou, &config, proposer);

    // Atomic execution is impossible when a delay is configured. Reject here
    // before any state mutation rather than letting execute() produce EDelayNotElapsed.
    assert!(config.execution_delay_ms() == 0, EDelayForbidsAtomicExecution);
    assert!(!readonly || config.cooldown_ms() == 0, ECooldownRequiresMutableOU);

    // --- Validation from ticket_from_vote ---

    assert!(!ou.is_controller_paused(), EControllerPaused);
    freeze.assert_not_frozen<P>(ou.id(), clock);

    // --- Vote: the proposer's YES must pass on its own ---

    let yes_weight = ou.governance().board_vote_weight(proposer);
    let total_snapshot_weight = ou.governance().board_vote_total_weight();
    assert!(config.passes(yes_weight, 0, total_snapshot_weight), EInsufficientVotingWeight);

    // --- Execute ---

    proposal::execute_single_vote(
        ou.id(),
        display_key,
        proposer,
        metadata_ipfs,
        payload,
        &config,
        yes_weight,
        total_snapshot_weight,
        ou.last_executed_ms_by_name(&name),
        ou.is_execution_paused(),
        clock,
        ctx,
    )
}

/// Shared body of `ticket_from_vote` and `ticket_from_vote_readonly`: every
/// check and effect except recording the execution timestamp.
fun ticket_from_vote_core<P: store>(
    ou: &OU,
    prop: Proposal<P>,
    freeze: &EmergencyFreeze,
    clock: &Clock,
    readonly: bool,
    ctx: &TxContext,
): ExecutionTicket<P> {
    let name = type_name::with_defining_ids<P>();
    let is_active = ou.status().is_active();
    let is_migration_ok =
        ou.status().is_migrating()
        && ou::is_migration_allowed_type(&name);
    assert!(is_active || is_migration_ok, EOUNotActive);
    assert!(prop.ou_id() == ou.id(), EOUIdMismatch);
    assert!(ou.is_type_name_enabled(&name), ETypeNotEnabled);
    assert!(!ou.is_controller_paused(), EControllerPaused);
    // Both configs matter: execute() enforces the proposal's snapshot, and the
    // slot's current config is what later executions of this type check against.
    assert!(
        !readonly || (ou.type_config_by_name(&name).cooldown_ms() == 0
            && prop.config().cooldown_ms() == 0),
        ECooldownRequiresMutableOU,
    );
    freeze.assert_not_frozen<P>(ou.id(), clock);

    let last_ms = ou.last_executed_ms_by_name(&name);

    // Read vote weights before execute() consumes the proposal.
    let yes_weight = prop.yes_weight();
    let total_snapshot_weight = prop.total_snapshot_weight();

    let (payload, req) = proposal::execute(
        prop,
        ou.governance(),
        last_ms,
        ou.is_execution_paused(),
        ou.type_config_by_name(&name).permissions(),
        ou.type_config_by_name(&name).borrow_scope(),
        clock,
        ctx,
    );

    proposal::new_ticket_standalone(req, payload, yes_weight, total_snapshot_weight)
}

/// OU must be Active, or Migrating with a migration-allowed type; the type
/// must have a slot.
fun assert_submittable(ou: &OU, name: &TypeName) {
    let is_active = ou.status().is_active();
    let is_migration_ok =
        ou.status().is_migrating()
        && ou::is_migration_allowed_type(name);
    assert!(is_active || is_migration_ok, EOUNotActive);
    assert!(ou.is_type_name_enabled(name), ETypeNotEnabled);
}

/// Submission-time floor enforcement for EnableProposalType.
/// The proposal's approval_threshold must be >= 80% so that the vote guarantee
/// (yes/total_voted >= threshold >= floor) is locked in at proposal creation time
/// rather than re-checked at execution (where only the ticket, not the proposal, is live).
fun assert_enable_floor(name: &TypeName, config: &ProposalConfig) {
    if (*name == type_name::with_defining_ids<EnableProposalType>()) {
        assert!((config.approval_threshold() as u64) >= ENABLE_APPROVAL_FLOOR_BPS, EFloorNotMet);
    };
}

fun assert_propose_threshold(ou: &OU, config: &ProposalConfig, proposer: address) {
    if (config.propose_threshold() > 0) {
        let weight = ou.governance().proposer_weight(proposer);
        assert!(weight >= config.propose_threshold(), EProposeThresholdNotMet);
    };
}

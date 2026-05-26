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
    // (yes/total_voted >= threshold >= floor) holds at execution time without
    // needing &Proposal<P> access in _step composite variants.
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

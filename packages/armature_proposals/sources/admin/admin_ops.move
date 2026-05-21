module armature_proposals::admin_ops;

use armature::board_voting;
use armature::charter::Charter;
use armature::dao::{Self, DAO};
use armature::proposal::{Self, Proposal, ExecutionRequest};
use armature_proposals::disable_proposal_type::DisableProposalType;
use armature_proposals::enable_proposal_type::EnableProposalType;
use armature_proposals::update_metadata::UpdateMetadata;
use armature_proposals::update_proposal_config::UpdateProposalConfig;
use std::string::String;
use sui::clock::Clock;
use sui::event;

// === Errors ===

const EDaoMismatch: u64 = 0;
const ECharterDaoMismatch: u64 = 1;
const EUndisableableType: u64 = 2;
const ESubDAOBlockedType: u64 = 4;
const EThresholdBelowFloor: u64 = 5;
/// Proposal's approval_threshold is below the hardcoded floor for this type.
/// Enforced at submission time by propose_update_proposal_config.
const EFloorNotMet: u64 = 6;

// === Constants ===

/// 66% approval floor for EnableProposalType (basis points).
const ENABLE_APPROVAL_FLOOR_BPS: u64 = 6_600;

/// 80% approval floor for self-referencing UpdateProposalConfig (basis points).
const SELF_UPDATE_APPROVAL_FLOOR_BPS: u64 = 8_000;

/// 80% approval floor for EnableBypassType (basis points). The handler that
/// enforces this floor at execute time lives in `armature::external_execution`;
/// the value is duplicated here so `UpdateProposalConfig` can keep
/// `EnableBypassType`'s on-DAO config above the floor.
const ENABLE_BYPASS_APPROVAL_FLOOR_BPS: u64 = 8_000;

// === Events ===

public struct ProposalTypeDisabled has copy, drop {
    dao_id: ID,
    type_key: std::ascii::String,
}

public struct ProposalTypeEnabled has copy, drop {
    dao_id: ID,
    type_key: std::ascii::String,
}

public struct ProposalConfigUpdated has copy, drop {
    dao_id: ID,
    target_type_key: std::ascii::String,
}

public struct MetadataUpdated has copy, drop {
    dao_id: ID,
    new_ipfs_cid: std::string::String,
}

// === Handlers ===

/// Execute a DisableProposalType proposal: remove a type from the enabled set.
/// Aborts if the type is undisableable (EnableProposalType, DisableProposalType,
/// TransferFreezeAdmin, UnfreezeProposalType).
public fun execute_disable_proposal_type(
    dao: &mut DAO,
    proposal: &Proposal<DisableProposalType>,
    request: ExecutionRequest<DisableProposalType>,
) {
    assert!(dao.id() == request.req_dao_id(), EDaoMismatch);

    let payload = proposal.payload();
    let type_key = payload.type_key();

    assert_disableable(&type_key);

    dao.disable_proposal_type(type_key, &request);

    event::emit(ProposalTypeDisabled {
        dao_id: dao.id(),
        type_key,
    });

    proposal::finalize(request, proposal);
}

/// Execute an EnableProposalType proposal: add a type to the enabled set and bind
/// the canonical Move type `NewType` to the type_key so future proposals cannot
/// substitute a different payload type under the same key.
/// The 66% approval floor is enforced at submission time in board_voting::submit_proposal;
/// no execution-time floor check is needed here.
public fun execute_enable_proposal_type<NewType: store>(
    dao: &mut DAO,
    proposal: &Proposal<EnableProposalType>,
    request: ExecutionRequest<EnableProposalType>,
) {
    enable_proposal_type_impl<NewType>(dao, proposal.payload(), &request);
    proposal::finalize(request, proposal);
}

/// Composite step variant: enable a proposal type from within a composite pipeline.
public fun execute_enable_proposal_type_step<NewType: store>(
    dao: &mut DAO,
    payload: EnableProposalType,
    request: ExecutionRequest<EnableProposalType>,
) {
    enable_proposal_type_impl<NewType>(dao, &payload, &request);
    proposal::consume_execution_request(request);
}

/// Execute an UpdateProposalConfig proposal: merge optional field overrides
/// into the existing config for the target type.
/// The 80% self-targeting floor is enforced at submission time by
/// propose_update_proposal_config; no execution-time floor check is needed here.
public fun execute_update_proposal_config(
    dao: &mut DAO,
    proposal: &Proposal<UpdateProposalConfig>,
    request: ExecutionRequest<UpdateProposalConfig>,
) {
    assert!(dao.id() == request.req_dao_id(), EDaoMismatch);

    let payload = proposal.payload();
    let target_key = payload.target_type_key();

    // Merge: use payload value if present, otherwise keep existing
    let existing = dao.proposal_configs().get(&target_key);
    let new_config = proposal::new_config(
        payload.quorum().destroy_with_default(existing.quorum()),
        payload.approval_threshold().destroy_with_default(existing.approval_threshold()),
        payload.propose_threshold().destroy_with_default(existing.propose_threshold()),
        payload.expiry_ms().destroy_with_default(existing.expiry_ms()),
        payload.execution_delay_ms().destroy_with_default(existing.execution_delay_ms()),
        payload.cooldown_ms().destroy_with_default(existing.cooldown_ms()),
    ).with_composable_allowed(payload
        .composable_allowed()
        .destroy_with_default(existing.composable_allowed()));

    // Enforce minimum approval_threshold for types with execution floors.
    // Prevents painting the DAO into a deadlock where proposals pass but cannot execute.
    assert_threshold_meets_floor(&target_key, &new_config);

    dao.update_proposal_config(target_key, new_config, &request);

    event::emit(ProposalConfigUpdated {
        dao_id: dao.id(),
        target_type_key: target_key,
    });

    proposal::finalize(request, proposal);
}

/// Execute an UpdateMetadata proposal: update the DAO charter's IPFS CID.
public fun execute_update_metadata(
    charter: &mut Charter,
    proposal: &Proposal<UpdateMetadata>,
    request: ExecutionRequest<UpdateMetadata>,
) {
    update_metadata_impl(charter, proposal.payload(), &request);
    proposal::finalize(request, proposal);
}

/// Composite step variant: execute an UpdateMetadata step extracted from a Pipeline.
public fun execute_update_metadata_step(
    charter: &mut Charter,
    payload: UpdateMetadata,
    request: ExecutionRequest<UpdateMetadata>,
) {
    update_metadata_impl(charter, &payload, &request);
    proposal::consume_execution_request(request);
}

// === Internal ===

fun enable_proposal_type_impl<NewType: store>(
    dao: &mut DAO,
    payload: &EnableProposalType,
    request: &ExecutionRequest<EnableProposalType>,
) {
    assert!(dao.id() == request.req_dao_id(), EDaoMismatch);

    let type_key = payload.type_key();
    let config = *payload.config();

    if (dao.controller_cap_id().is_some()) {
        assert!(!dao::is_subdao_blocked_type(&type_key), ESubDAOBlockedType);
    };

    assert_threshold_meets_floor(&type_key, &config);

    dao.enable_proposal_type(type_key, config, request);
    dao.bind_type_key<NewType, EnableProposalType>(type_key, request);

    event::emit(ProposalTypeEnabled {
        dao_id: dao.id(),
        type_key,
    });
}

fun update_metadata_impl(
    charter: &mut Charter,
    payload: &UpdateMetadata,
    request: &ExecutionRequest<UpdateMetadata>,
) {
    assert!(charter.dao_id() == request.req_dao_id(), ECharterDaoMismatch);
    charter.update_metadata(*payload.new_ipfs_cid(), request);
    event::emit(MetadataUpdated {
        dao_id: charter.dao_id(),
        new_ipfs_cid: *payload.new_ipfs_cid(),
    });
}

// === Submission wrapper ===

/// Submit an UpdateProposalConfig proposal with submission-time floor enforcement.
/// When the payload targets UpdateProposalConfig itself, asserts that the DAO's
/// current UpdateProposalConfig approval_threshold meets the 80% supermajority
/// floor before creating the proposal. This is strictly stronger than the old
/// execution-time check: a malicious downgrade proposal never enters the object
/// graph, cannot be voted on, and consumes no proposal slot.
///
/// Callers that need non-self-targeting UpdateProposalConfig submissions can use
/// board_voting::submit_proposal<UpdateProposalConfig> directly — no floor applies.
#[allow(lint(share_owned, custom_state_change))]
public fun propose_update_proposal_config(
    dao: &DAO,
    metadata_ipfs: Option<String>,
    payload: UpdateProposalConfig,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let type_key = b"UpdateProposalConfig".to_ascii_string();
    let config = *dao.proposal_configs().get(&type_key);

    if (payload.target_type_key() == b"UpdateProposalConfig".to_ascii_string()) {
        assert!(
            (config.approval_threshold() as u64) >= SELF_UPDATE_APPROVAL_FLOOR_BPS,
            EFloorNotMet,
        );
    };

    board_voting::submit_proposal<UpdateProposalConfig>(
        dao,
        type_key,
        metadata_ipfs,
        payload,
        clock,
        ctx,
    );
}

// === Internal ===

/// Abort if the type key is one of the core undisableable types.
fun assert_disableable(type_key: &std::ascii::String) {
    assert!(!dao::is_undisableable_type(type_key), EUndisableableType);
}

/// Assert that a config's approval_threshold is not below the execution floor
/// for the given type. Types without a floor are unconstrained.
fun assert_threshold_meets_floor(type_key: &std::ascii::String, config: &proposal::ProposalConfig) {
    let floor = execution_floor_for_type(type_key);
    if (floor > 0) {
        assert!((config.approval_threshold() as u64) >= floor, EThresholdBelowFloor);
    };
}

/// Return the execution floor (in basis points) for a given type key.
/// Returns 0 for types with no floor.
fun execution_floor_for_type(type_key: &std::ascii::String): u64 {
    if (*type_key == b"EnableProposalType".to_ascii_string()) {
        ENABLE_APPROVAL_FLOOR_BPS
    } else if (*type_key == b"UpdateProposalConfig".to_ascii_string()) {
        SELF_UPDATE_APPROVAL_FLOOR_BPS
    } else if (*type_key == b"EnableBypassType".to_ascii_string()) {
        ENABLE_BYPASS_APPROVAL_FLOOR_BPS
    } else {
        0
    }
}

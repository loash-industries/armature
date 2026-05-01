module armature_proposals::admin_ops;

use armature::charter::Charter;
use armature::dao::{Self, DAO};
use armature::proposal::{Self, Proposal, ExecutionRequest};
use armature::utils;
use armature_proposals::disable_proposal_type::DisableProposalType;
use armature_proposals::enable_proposal_type::EnableProposalType;
use armature_proposals::update_metadata::UpdateMetadata;
use armature_proposals::update_proposal_config::UpdateProposalConfig;
use sui::event;

// === Errors ===

const EDaoMismatch: u64 = 0;
const ECharterDaoMismatch: u64 = 1;
const EUndisableableType: u64 = 2;
const EApprovalFloorNotMet: u64 = 3;
const ESubDAOBlockedType: u64 = 4;
const EThresholdBelowFloor: u64 = 5;

// === Constants ===

/// 66% approval floor for EnableProposalType (basis points).
const ENABLE_APPROVAL_FLOOR_BPS: u64 = 6_600;

/// 80% approval floor for self-referencing UpdateProposalConfig (basis points).
const SELF_UPDATE_APPROVAL_FLOOR_BPS: u64 = 8_000;

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

/// Execute an EnableProposalType proposal: add a type to the enabled set.
/// Enforces a 66% approval floor regardless of the proposal's own config threshold.
public fun execute_enable_proposal_type(
    dao: &mut DAO,
    proposal: &Proposal<EnableProposalType>,
    request: ExecutionRequest<EnableProposalType>,
) {
    assert!(dao.id() == request.req_dao_id(), EDaoMismatch);

    assert_approval_floor(proposal, ENABLE_APPROVAL_FLOOR_BPS);

    let payload = proposal.payload();
    let type_key = payload.type_key();
    let config = *payload.config();

    // SubDAOs with a controller cannot enable hierarchy-altering types
    if (dao.controller_cap_id().is_some()) {
        assert!(!dao::is_subdao_blocked_type(&type_key), ESubDAOBlockedType);
    };

    // Enforce minimum threshold for the new type's config if it has an execution floor
    assert_threshold_meets_floor(&type_key, &config);

    dao.enable_proposal_type(type_key, config, &request);

    event::emit(ProposalTypeEnabled {
        dao_id: dao.id(),
        type_key,
    });

    proposal::finalize(request, proposal);
}

/// Execute an UpdateProposalConfig proposal: merge optional field overrides
/// into the existing config for the target type.
/// When targeting "UpdateProposalConfig" itself, enforces an 80% approval floor.
public fun execute_update_proposal_config(
    dao: &mut DAO,
    proposal: &Proposal<UpdateProposalConfig>,
    request: ExecutionRequest<UpdateProposalConfig>,
) {
    assert!(dao.id() == request.req_dao_id(), EDaoMismatch);

    let payload = proposal.payload();
    let target_key = payload.target_type_key();

    // Enforce 80% super-majority when modifying UpdateProposalConfig's own rules
    if (target_key == b"UpdateProposalConfig".to_ascii_string()) {
        assert_approval_floor(proposal, SELF_UPDATE_APPROVAL_FLOOR_BPS);
    };

    // Merge: use payload value if present, otherwise keep existing
    let existing = dao.proposal_configs().get(&target_key);
    let new_config = proposal::new_config(
        payload.quorum().destroy_with_default(existing.quorum()),
        payload.approval_threshold().destroy_with_default(existing.approval_threshold()),
        payload.propose_threshold().destroy_with_default(existing.propose_threshold()),
        payload.expiry_ms().destroy_with_default(existing.expiry_ms()),
        payload.execution_delay_ms().destroy_with_default(existing.execution_delay_ms()),
        payload.cooldown_ms().destroy_with_default(existing.cooldown_ms()),
    );

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
    assert!(charter.dao_id() == request.req_dao_id(), ECharterDaoMismatch);

    let payload = proposal.payload();

    charter.update_metadata(*payload.new_ipfs_cid(), &request);

    event::emit(MetadataUpdated {
        dao_id: charter.dao_id(),
        new_ipfs_cid: *payload.new_ipfs_cid(),
    });

    proposal::finalize(request, proposal);
}

// === Internal ===

/// Abort if the type key is one of the core undisableable types.
fun assert_disableable(type_key: &std::ascii::String) {
    assert!(!dao::is_undisableable_type(type_key), EUndisableableType);
}

/// Assert that a proposal's approval rate meets the specified floor (in basis points).
fun assert_approval_floor<P: store>(proposal: &Proposal<P>, floor_bps: u64) {
    let total = proposal.total_snapshot_weight();
    assert!(utils::gte_bps(proposal.yes_weight(), total, floor_bps), EApprovalFloorNotMet);
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
    } else {
        0
    }
}

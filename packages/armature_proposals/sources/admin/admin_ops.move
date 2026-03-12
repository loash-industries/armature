module armature_proposals::admin_ops;

use armature::charter::Charter;
use armature::dao::DAO;
use armature::proposal::{Self, Proposal, ExecutionRequest};
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

// === Constants ===

/// 66% approval floor for EnableProposalType (basis points).
const ENABLE_APPROVAL_FLOOR_BPS: u64 = 6_600;

/// 80% approval floor for self-referencing UpdateProposalConfig (basis points).
const SELF_UPDATE_APPROVAL_FLOOR_BPS: u64 = 8_000;

const BPS_SCALE: u64 = 10_000;

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
/// Aborts if the type is undisableable (SetBoard, EmergencyFreeze, EmergencyUnfreeze).
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
    assert!(*type_key != b"SetBoard".to_ascii_string(), EUndisableableType);
    assert!(*type_key != b"EmergencyFreeze".to_ascii_string(), EUndisableableType);
    assert!(*type_key != b"EmergencyUnfreeze".to_ascii_string(), EUndisableableType);
}

/// Assert that a proposal's approval rate meets the specified floor (in basis points).
fun assert_approval_floor<P: store>(proposal: &Proposal<P>, floor_bps: u64) {
    let total = proposal.total_snapshot_weight();
    assert!(proposal.yes_weight() * BPS_SCALE >= floor_bps * total, EApprovalFloorNotMet);
}

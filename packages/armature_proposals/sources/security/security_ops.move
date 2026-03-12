module armature_proposals::security_ops;

use armature::emergency::{Self, EmergencyFreeze, FreezeAdminCap};
use armature::proposal::{Self, Proposal, ExecutionRequest};
use armature_proposals::transfer_freeze_admin::TransferFreezeAdmin;
use armature_proposals::unfreeze_proposal_type::UnfreezeProposalType;
use armature_proposals::update_freeze_config::UpdateFreezeConfig;
use sui::event;

// === Errors ===

const EFreezeDaoMismatch: u64 = 0;
const ECapDaoMismatch: u64 = 1;

// === Events ===

public struct FreezeAdminTransferred has copy, drop {
    dao_id: ID,
    new_admin: address,
}

public struct FreezeConfigUpdated has copy, drop {
    dao_id: ID,
    new_max_freeze_duration_ms: u64,
}

// === Handlers ===

/// Execute a TransferFreezeAdmin proposal: unfreeze all frozen types
/// and transfer the FreezeAdminCap to the new admin.
/// The current cap holder must include their cap in the execution PTB.
public fun execute_transfer_freeze_admin(
    freeze: &mut EmergencyFreeze,
    cap: FreezeAdminCap,
    proposal: &Proposal<TransferFreezeAdmin>,
    request: ExecutionRequest<TransferFreezeAdmin>,
) {
    assert!(freeze.dao_id() == request.req_dao_id(), EFreezeDaoMismatch);
    assert!(cap.admin_cap_dao_id() == freeze.dao_id(), ECapDaoMismatch);

    let payload = proposal.payload();

    emergency::unfreeze_all(freeze, &request);

    event::emit(FreezeAdminTransferred {
        dao_id: freeze.dao_id(),
        new_admin: payload.new_admin(),
    });

    transfer::public_transfer(cap, payload.new_admin());

    proposal::consume(request);
}

/// Execute an UnfreezeProposalType proposal: unfreeze a single proposal type
/// via governance, without requiring the FreezeAdminCap.
public fun execute_unfreeze_proposal_type(
    freeze: &mut EmergencyFreeze,
    proposal: &Proposal<UnfreezeProposalType>,
    request: ExecutionRequest<UnfreezeProposalType>,
) {
    let payload = proposal.payload();

    emergency::governance_unfreeze_type(freeze, payload.type_key(), &request);

    proposal::consume(request);
}

/// Execute an UpdateFreezeConfig proposal: update the max freeze duration.
public fun execute_update_freeze_config(
    freeze: &mut EmergencyFreeze,
    proposal: &Proposal<UpdateFreezeConfig>,
    request: ExecutionRequest<UpdateFreezeConfig>,
) {
    let payload = proposal.payload();

    emergency::update_freeze_duration(
        freeze,
        payload.new_max_freeze_duration_ms(),
        &request,
    );

    event::emit(FreezeConfigUpdated {
        dao_id: freeze.dao_id(),
        new_max_freeze_duration_ms: payload.new_max_freeze_duration_ms(),
    });

    proposal::consume(request);
}

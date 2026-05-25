module armature_proposals::security_ops;

use armature::emergency::{Self, EmergencyFreeze, FreezeAdminCap};
use armature::proposal::{ExecutionTicket};
use armature_proposals::transfer_freeze_admin::TransferFreezeAdmin;
use armature_proposals::unfreeze_proposal_type::UnfreezeProposalType;
use armature_proposals::update_freeze_config::UpdateFreezeConfig;
use armature_proposals::update_freeze_exempt_types::UpdateFreezeExemptTypes;
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
public fun execute_transfer_freeze_admin(
    freeze: &mut EmergencyFreeze,
    cap: FreezeAdminCap,
    ticket: ExecutionTicket<TransferFreezeAdmin>,
) {
    assert!(freeze.dao_id() == ticket.ticket_dao_id(), EFreezeDaoMismatch);
    assert!(cap.admin_cap_dao_id() == freeze.dao_id(), ECapDaoMismatch);

    let payload = ticket.ticket_payload();

    emergency::unfreeze_all(freeze, ticket.ticket_request());

    event::emit(FreezeAdminTransferred {
        dao_id: freeze.dao_id(),
        new_admin: payload.new_admin(),
    });

    transfer::public_transfer(cap, payload.new_admin());

    ticket.discharge();
}

/// Execute an UnfreezeProposalType proposal: unfreeze a single proposal type
/// via governance, without requiring the FreezeAdminCap.
public fun execute_unfreeze_proposal_type(
    freeze: &mut EmergencyFreeze,
    ticket: ExecutionTicket<UnfreezeProposalType>,
) {
    let payload = ticket.ticket_payload();
    emergency::governance_unfreeze_type(freeze, payload.type_key(), ticket.ticket_request());
    ticket.discharge();
}

/// Execute an UpdateFreezeConfig proposal: update the max freeze duration.
public fun execute_update_freeze_config(
    freeze: &mut EmergencyFreeze,
    ticket: ExecutionTicket<UpdateFreezeConfig>,
) {
    let payload = ticket.ticket_payload();

    emergency::update_freeze_duration(
        freeze,
        payload.new_max_freeze_duration_ms(),
        ticket.ticket_request(),
    );

    event::emit(FreezeConfigUpdated {
        dao_id: freeze.dao_id(),
        new_max_freeze_duration_ms: payload.new_max_freeze_duration_ms(),
    });

    ticket.discharge();
}

/// Execute an UpdateFreezeExemptTypes proposal.
public fun execute_update_freeze_exempt_types(
    freeze: &mut EmergencyFreeze,
    ticket: ExecutionTicket<UpdateFreezeExemptTypes>,
) {
    assert!(freeze.dao_id() == ticket.ticket_dao_id(), EFreezeDaoMismatch);

    let payload = ticket.ticket_payload();
    let req = ticket.ticket_request();

    payload.types_to_add().do_ref!(|t| {
        emergency::add_freeze_exempt_type(freeze, *t, req);
    });

    payload.types_to_remove().do_ref!(|t| {
        emergency::remove_freeze_exempt_type(freeze, *t, req);
    });

    ticket.discharge();
}

/// Handlers for the framework's freeze-governance types: TransferFreezeAdmin,
/// UnfreezeProposalType, UpdateFreezeConfig and UpdateFreezeExemptTypes.
///
/// All four live in the framework, not an extension package. The emergency
/// freeze is the framework's own last line of defence, and the exempt set
/// decides which types keep executing while everything else is stopped; that
/// list must not be editable by a package whose handler might be the thing
/// being frozen. Only this package can mint the `Permit` for these types (see
/// `proposal::ticket_request`), so only this package can spend their tickets.
module armature::freeze_ops;

use armature::emergency::{Self, EmergencyFreeze, FreezeAdminCap};
use armature::proposal::ExecutionTicket;
use armature::transfer_freeze_admin::{Self, TransferFreezeAdmin};
use armature::unfreeze_proposal_type::{Self, UnfreezeProposalType};
use armature::update_freeze_config::{Self, UpdateFreezeConfig};
use armature::update_freeze_exempt_types::{Self, UpdateFreezeExemptTypes};
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

    emergency::unfreeze_all(freeze, ticket.ticket_request(transfer_freeze_admin::permit()));

    event::emit(FreezeAdminTransferred {
        dao_id: freeze.dao_id(),
        new_admin: payload.new_admin(),
    });

    transfer::public_transfer(cap, payload.new_admin());

    ticket.discharge(transfer_freeze_admin::permit());
}

/// Execute an UnfreezeProposalType proposal: unfreeze a single proposal type
/// via governance, without requiring the FreezeAdminCap.
public fun execute_unfreeze_proposal_type(
    freeze: &mut EmergencyFreeze,
    ticket: ExecutionTicket<UnfreezeProposalType>,
) {
    let payload = ticket.ticket_payload();
    emergency::governance_unfreeze_type(
        freeze,
        payload.type_name(),
        ticket.ticket_request(unfreeze_proposal_type::permit()),
    );
    ticket.discharge(unfreeze_proposal_type::permit());
}

/// Execute an UpdateFreezeConfig proposal: update the max freeze duration.
public fun execute_update_freeze_config(
    freeze: &mut EmergencyFreeze,
    ticket: ExecutionTicket<UpdateFreezeConfig>,
) {
    assert!(freeze.dao_id() == ticket.ticket_dao_id(), EFreezeDaoMismatch);

    let payload = ticket.ticket_payload();

    emergency::update_freeze_duration(
        freeze,
        payload.new_max_freeze_duration_ms(),
        ticket.ticket_request(update_freeze_config::permit()),
    );

    event::emit(FreezeConfigUpdated {
        dao_id: freeze.dao_id(),
        new_max_freeze_duration_ms: payload.new_max_freeze_duration_ms(),
    });

    ticket.discharge(update_freeze_config::permit());
}

/// Execute an UpdateFreezeExemptTypes proposal: add, then remove, the listed
/// types on the freeze-exempt set.
public fun execute_update_freeze_exempt_types(
    freeze: &mut EmergencyFreeze,
    ticket: ExecutionTicket<UpdateFreezeExemptTypes>,
) {
    assert!(freeze.dao_id() == ticket.ticket_dao_id(), EFreezeDaoMismatch);

    let payload = ticket.ticket_payload();
    let req = ticket.ticket_request(update_freeze_exempt_types::permit());

    payload.types_to_add().do_ref!(|t| {
        emergency::add_freeze_exempt_type(freeze, *t, req);
    });

    payload.types_to_remove().do_ref!(|t| {
        emergency::remove_freeze_exempt_type(freeze, *t, req);
    });

    ticket.discharge(update_freeze_exempt_types::permit());
}

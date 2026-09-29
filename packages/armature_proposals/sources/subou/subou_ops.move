module armature_proposals::subou_ops;

use armature::batch_add_members::{Self, BatchAddMembers};
use armature::batch_remove_members::{Self, BatchRemoveMembers};
use armature::capability_vault::{CapabilityVault, SubOUControl};
use armature::controller;
use armature::ou::OU;
use armature::proposal::ExecutionTicket;
use armature_proposals::controller_batch_add_members::{Self, ControllerBatchAddMembers};
use armature_proposals::controller_batch_remove_members::{Self, ControllerBatchRemoveMembers};
use armature_proposals::pause_execution::{Self, PauseSubOUExecution, UnpauseSubOUExecution};
use armature_proposals::reclaim_cap_from_subou::{Self, ReclaimCapFromSubOU};
use armature_proposals::transfer_cap_to_subou::{Self, TransferCapToSubOU};
use sui::event;

// === Errors ===

const EVaultOUMismatch: u64 = 0;
const ESubOUVaultMismatch: u64 = 1;
const EEmptyBatch: u64 = 3;
const EBatchTooLarge: u64 = 8;

// === Constants ===

/// Must match MAX_BATCH_SIZE — Move constants are module-private.
const MAX_BATCH_SIZE: u64 = 100;

// === Events ===

public struct CapTransferredToSubOU has copy, drop {
    ou_id: ID,
    cap_id: ID,
    target_vault: ID,
}

public struct CapReclaimedFromSubOU has copy, drop {
    ou_id: ID,
    cap_id: ID,
    subou_id: ID,
}

public struct SubOUExecutionPaused has copy, drop {
    ou_id: ID,
}

public struct SubOUExecutionUnpaused has copy, drop {
    ou_id: ID,
}

public struct ControllerMembersBatchAdded has copy, drop {
    controller_ou_id: ID,
    subou_id: ID,
    added: vector<address>,
    skipped: vector<address>,
}

public struct ControllerMembersBatchRemoved has copy, drop {
    controller_ou_id: ID,
    subou_id: ID,
    removed: vector<address>,
}

// === Handlers ===

/// Execute a TransferCapToSubOU proposal. `target_subou` must be a SubOU
/// whose registered SubOUControl sits in `source_vault`
/// (`controller::receive_cap_from_controller`).
public fun execute_transfer_cap<T: key + store>(
    source_vault: &mut CapabilityVault,
    target_vault: &mut CapabilityVault,
    target_subou: &OU,
    ticket: ExecutionTicket<TransferCapToSubOU>,
) {
    assert!(source_vault.ou_id() == ticket.ticket_ou_id(), EVaultOUMismatch);

    let payload = ticket.ticket_payload();
    assert!(target_vault.ou_id() == payload.target_subou(), ESubOUVaultMismatch);

    let cap_id = payload.cap_id();
    let req = ticket.ticket_request(transfer_cap_to_subou::permit());
    let cap: T = source_vault.extract_cap(cap_id, req);
    controller::receive_cap_from_controller(target_vault, cap, target_subou, source_vault, req);

    event::emit(CapTransferredToSubOU {
        ou_id: source_vault.ou_id(),
        cap_id,
        target_vault: object::id(target_vault),
    });

    ticket.discharge(transfer_cap_to_subou::permit());
}

/// Execute a ReclaimCapFromSubOU proposal. `control_id` must be `subou`'s
/// registered SubOUControl (`controller::privileged_extract`).
public fun execute_reclaim_cap<T: key + store>(
    controller_vault: &mut CapabilityVault,
    subou_vault: &mut CapabilityVault,
    subou: &OU,
    ticket: ExecutionTicket<ReclaimCapFromSubOU>,
) {
    assert!(controller_vault.ou_id() == ticket.ticket_ou_id(), EVaultOUMismatch);

    let payload = ticket.ticket_payload();
    assert!(subou_vault.ou_id() == payload.subou_id(), ESubOUVaultMismatch);

    let control_id = payload.control_id();
    let cap_id = payload.cap_id();
    let subou_id = payload.subou_id();
    let req = ticket.ticket_request(reclaim_cap_from_subou::permit());

    let (control, loan) = controller_vault.loan_cap<SubOUControl, ReclaimCapFromSubOU>(
        control_id,
        req,
    );

    let cap: T = controller::privileged_extract(subou_vault, cap_id, subou, &control);
    controller_vault.store_cap(cap, req);
    controller_vault.return_cap(control, loan);

    event::emit(CapReclaimedFromSubOU {
        ou_id: controller_vault.ou_id(),
        cap_id,
        subou_id,
    });

    ticket.discharge(reclaim_cap_from_subou::permit());
}

/// Execute a PauseSubOUExecution proposal.
public fun execute_pause_subou_execution(
    controller_vault: &mut CapabilityVault,
    subou: &mut OU,
    ticket: ExecutionTicket<PauseSubOUExecution>,
    ctx: &mut TxContext,
) {
    assert!(controller_vault.ou_id() == ticket.ticket_ou_id(), EVaultOUMismatch);

    let payload = ticket.ticket_payload();
    let req = ticket.ticket_request(pause_execution::pause_subou_permit());

    let (control, loan) = controller_vault.loan_cap<SubOUControl, PauseSubOUExecution>(
        payload.pause_control_id(),
        req,
    );

    let subou_req = controller::privileged_submit(
        &control,
        subou,
        b"PauseSubOUExecution".to_ascii_string(),
        option::some(std::string::utf8(b"Controller-initiated pause")),
        pause_execution::new_pause(payload.pause_control_id()),
        ctx,
    );

    subou.set_controller_paused(true, &subou_req);
    controller::privileged_consume(subou_req, &control);
    controller_vault.return_cap(control, loan);

    event::emit(SubOUExecutionPaused { ou_id: subou.id() });

    ticket.discharge(pause_execution::pause_subou_permit());
}

/// Execute an UnpauseSubOUExecution proposal.
public fun execute_unpause_subou_execution(
    controller_vault: &mut CapabilityVault,
    subou: &mut OU,
    ticket: ExecutionTicket<UnpauseSubOUExecution>,
    ctx: &mut TxContext,
) {
    assert!(controller_vault.ou_id() == ticket.ticket_ou_id(), EVaultOUMismatch);

    let payload = ticket.ticket_payload();
    let req = ticket.ticket_request(pause_execution::unpause_subou_permit());

    let (control, loan) = controller_vault.loan_cap<SubOUControl, UnpauseSubOUExecution>(
        payload.unpause_control_id(),
        req,
    );

    let subou_req = controller::privileged_submit(
        &control,
        subou,
        b"UnpauseSubOUExecution".to_ascii_string(),
        option::some(std::string::utf8(b"Controller-initiated unpause")),
        pause_execution::new_unpause(payload.unpause_control_id()),
        ctx,
    );

    subou.set_controller_paused(false, &subou_req);
    controller::privileged_consume(subou_req, &control);
    controller_vault.return_cap(control, loan);

    event::emit(SubOUExecutionUnpaused { ou_id: subou.id() });

    ticket.discharge(pause_execution::unpause_subou_permit());
}

/// Execute a ControllerBatchAddMembers proposal.
public fun execute_controller_batch_add_members(
    controller_vault: &mut CapabilityVault,
    members_ou: &mut OU,
    ticket: ExecutionTicket<ControllerBatchAddMembers>,
    ctx: &mut TxContext,
) {
    assert!(controller_vault.ou_id() == ticket.ticket_ou_id(), EVaultOUMismatch);

    let payload = ticket.ticket_payload();
    let req = ticket.ticket_request(controller_batch_add_members::permit());

    let len = payload.members().length();
    assert!(len > 0, EEmptyBatch);
    assert!(len <= MAX_BATCH_SIZE, EBatchTooLarge);

    let (control, loan) = controller_vault.loan_cap<SubOUControl, ControllerBatchAddMembers>(
        payload.control_id(),
        req,
    );

    let members_req = controller::privileged_submit<BatchAddMembers>(
        &control,
        members_ou,
        b"BatchAddMembers".to_ascii_string(),
        option::none(),
        batch_add_members::new(*payload.members()),
        ctx,
    );

    let (added, skipped) = members_ou.add_board_members_governance(
        *payload.members(),
        &members_req,
    );
    controller::privileged_consume(members_req, &control);
    controller_vault.return_cap(control, loan);

    event::emit(ControllerMembersBatchAdded {
        controller_ou_id: controller_vault.ou_id(),
        subou_id: members_ou.id(),
        added,
        skipped,
    });

    ticket.discharge(controller_batch_add_members::permit());
}

/// Execute a ControllerBatchRemoveMembers proposal.
public fun execute_controller_batch_remove_members(
    controller_vault: &mut CapabilityVault,
    members_ou: &mut OU,
    ticket: ExecutionTicket<ControllerBatchRemoveMembers>,
    ctx: &mut TxContext,
) {
    assert!(controller_vault.ou_id() == ticket.ticket_ou_id(), EVaultOUMismatch);

    let payload = ticket.ticket_payload();
    let req = ticket.ticket_request(controller_batch_remove_members::permit());

    let len = payload.members().length();
    assert!(len > 0, EEmptyBatch);
    assert!(len <= MAX_BATCH_SIZE, EBatchTooLarge);

    let (control, loan) = controller_vault.loan_cap<SubOUControl, ControllerBatchRemoveMembers>(
        payload.control_id(),
        req,
    );

    let members_req = controller::privileged_submit<BatchRemoveMembers>(
        &control,
        members_ou,
        b"BatchRemoveMembers".to_ascii_string(),
        option::none(),
        batch_remove_members::new(*payload.members()),
        ctx,
    );

    let removed = members_ou.remove_board_members_governance(*payload.members(), &members_req);
    controller::privileged_consume(members_req, &control);
    controller_vault.return_cap(control, loan);

    event::emit(ControllerMembersBatchRemoved {
        controller_ou_id: controller_vault.ou_id(),
        subou_id: members_ou.id(),
        removed,
    });

    ticket.discharge(controller_batch_remove_members::permit());
}

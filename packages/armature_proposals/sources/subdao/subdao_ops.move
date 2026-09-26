module armature_proposals::subdao_ops;

use armature::batch_add_members::{Self, BatchAddMembers};
use armature::batch_remove_members::{Self, BatchRemoveMembers};
use armature::capability_vault::{CapabilityVault, SubDAOControl};
use armature::controller;
use armature::dao::DAO;
use armature::proposal::ExecutionTicket;
use armature_proposals::controller_batch_add_members::{Self, ControllerBatchAddMembers};
use armature_proposals::controller_batch_remove_members::{Self, ControllerBatchRemoveMembers};
use armature_proposals::pause_execution::{Self, PauseSubDAOExecution, UnpauseSubDAOExecution};
use armature_proposals::reclaim_cap_from_subdao::{Self, ReclaimCapFromSubDAO};
use armature_proposals::transfer_cap_to_subdao::{Self, TransferCapToSubDAO};
use sui::event;

// === Errors ===

const EVaultDAOMismatch: u64 = 0;
const ESubDAOVaultMismatch: u64 = 1;
const EEmptyBatch: u64 = 3;
const EBatchTooLarge: u64 = 8;

// === Constants ===

/// Must match MAX_BATCH_SIZE — Move constants are module-private.
const MAX_BATCH_SIZE: u64 = 100;

// === Events ===

public struct CapTransferredToSubDAO has copy, drop {
    dao_id: ID,
    cap_id: ID,
    target_vault: ID,
}

public struct CapReclaimedFromSubDAO has copy, drop {
    dao_id: ID,
    cap_id: ID,
    subdao_id: ID,
}

public struct SubDAOExecutionPaused has copy, drop {
    dao_id: ID,
}

public struct SubDAOExecutionUnpaused has copy, drop {
    dao_id: ID,
}

public struct ControllerMembersBatchAdded has copy, drop {
    controller_dao_id: ID,
    subdao_id: ID,
    added: vector<address>,
    skipped: vector<address>,
}

public struct ControllerMembersBatchRemoved has copy, drop {
    controller_dao_id: ID,
    subdao_id: ID,
    removed: vector<address>,
}

// === Handlers ===

/// Execute a TransferCapToSubDAO proposal.
public fun execute_transfer_cap<T: key + store>(
    source_vault: &mut CapabilityVault,
    target_vault: &mut CapabilityVault,
    ticket: ExecutionTicket<TransferCapToSubDAO>,
) {
    assert!(source_vault.dao_id() == ticket.ticket_dao_id(), EVaultDAOMismatch);

    let payload = ticket.ticket_payload();
    assert!(target_vault.dao_id() == payload.target_subdao(), ESubDAOVaultMismatch);

    let cap_id = payload.cap_id();
    let req = ticket.ticket_request(transfer_cap_to_subdao::permit());
    let cap: T = source_vault.extract_cap(cap_id, req);
    target_vault.receive_cap(cap, req);

    event::emit(CapTransferredToSubDAO {
        dao_id: source_vault.dao_id(),
        cap_id,
        target_vault: object::id(target_vault),
    });

    ticket.discharge(transfer_cap_to_subdao::permit());
}

/// Execute a ReclaimCapFromSubDAO proposal.
public fun execute_reclaim_cap<T: key + store>(
    controller_vault: &mut CapabilityVault,
    subdao_vault: &mut CapabilityVault,
    ticket: ExecutionTicket<ReclaimCapFromSubDAO>,
) {
    assert!(controller_vault.dao_id() == ticket.ticket_dao_id(), EVaultDAOMismatch);

    let payload = ticket.ticket_payload();
    assert!(subdao_vault.dao_id() == payload.subdao_id(), ESubDAOVaultMismatch);

    let control_id = payload.control_id();
    let cap_id = payload.cap_id();
    let subdao_id = payload.subdao_id();
    let req = ticket.ticket_request(reclaim_cap_from_subdao::permit());

    let (control, loan) = controller_vault.loan_cap<SubDAOControl, ReclaimCapFromSubDAO>(
        control_id,
        req,
    );

    let cap: T = subdao_vault.privileged_extract(cap_id, &control);
    controller_vault.store_cap(cap, req);
    controller_vault.return_cap(control, loan);

    event::emit(CapReclaimedFromSubDAO {
        dao_id: controller_vault.dao_id(),
        cap_id,
        subdao_id,
    });

    ticket.discharge(reclaim_cap_from_subdao::permit());
}

/// Execute a PauseSubDAOExecution proposal.
public fun execute_pause_subdao_execution(
    controller_vault: &mut CapabilityVault,
    subdao: &mut DAO,
    ticket: ExecutionTicket<PauseSubDAOExecution>,
    ctx: &mut TxContext,
) {
    assert!(controller_vault.dao_id() == ticket.ticket_dao_id(), EVaultDAOMismatch);

    let payload = ticket.ticket_payload();
    let req = ticket.ticket_request(pause_execution::pause_subdao_permit());

    let (control, loan) = controller_vault.loan_cap<SubDAOControl, PauseSubDAOExecution>(
        payload.pause_control_id(),
        req,
    );

    let subdao_req = controller::privileged_submit(
        &control,
        subdao,
        b"PauseSubDAOExecution".to_ascii_string(),
        option::some(std::string::utf8(b"Controller-initiated pause")),
        pause_execution::new_pause(payload.pause_control_id()),
        ctx,
    );

    subdao.set_controller_paused(true, &subdao_req);
    controller::privileged_consume(subdao_req, &control);
    controller_vault.return_cap(control, loan);

    event::emit(SubDAOExecutionPaused { dao_id: subdao.id() });

    ticket.discharge(pause_execution::pause_subdao_permit());
}

/// Execute an UnpauseSubDAOExecution proposal.
public fun execute_unpause_subdao_execution(
    controller_vault: &mut CapabilityVault,
    subdao: &mut DAO,
    ticket: ExecutionTicket<UnpauseSubDAOExecution>,
    ctx: &mut TxContext,
) {
    assert!(controller_vault.dao_id() == ticket.ticket_dao_id(), EVaultDAOMismatch);

    let payload = ticket.ticket_payload();
    let req = ticket.ticket_request(pause_execution::unpause_subdao_permit());

    let (control, loan) = controller_vault.loan_cap<SubDAOControl, UnpauseSubDAOExecution>(
        payload.unpause_control_id(),
        req,
    );

    let subdao_req = controller::privileged_submit(
        &control,
        subdao,
        b"UnpauseSubDAOExecution".to_ascii_string(),
        option::some(std::string::utf8(b"Controller-initiated unpause")),
        pause_execution::new_unpause(payload.unpause_control_id()),
        ctx,
    );

    subdao.set_controller_paused(false, &subdao_req);
    controller::privileged_consume(subdao_req, &control);
    controller_vault.return_cap(control, loan);

    event::emit(SubDAOExecutionUnpaused { dao_id: subdao.id() });

    ticket.discharge(pause_execution::unpause_subdao_permit());
}

/// Execute a ControllerBatchAddMembers proposal.
public fun execute_controller_batch_add_members(
    controller_vault: &mut CapabilityVault,
    members_dao: &mut DAO,
    ticket: ExecutionTicket<ControllerBatchAddMembers>,
    ctx: &mut TxContext,
) {
    assert!(controller_vault.dao_id() == ticket.ticket_dao_id(), EVaultDAOMismatch);

    let payload = ticket.ticket_payload();
    let req = ticket.ticket_request(controller_batch_add_members::permit());

    let len = payload.members().length();
    assert!(len > 0, EEmptyBatch);
    assert!(len <= MAX_BATCH_SIZE, EBatchTooLarge);

    let (control, loan) = controller_vault.loan_cap<SubDAOControl, ControllerBatchAddMembers>(
        payload.control_id(),
        req,
    );

    let members_req = controller::privileged_submit<BatchAddMembers>(
        &control,
        members_dao,
        b"BatchAddMembers".to_ascii_string(),
        option::none(),
        batch_add_members::new(*payload.members()),
        ctx,
    );

    let (added, skipped) = members_dao.add_board_members_governance(
        *payload.members(),
        &members_req,
    );
    controller::privileged_consume(members_req, &control);
    controller_vault.return_cap(control, loan);

    event::emit(ControllerMembersBatchAdded {
        controller_dao_id: controller_vault.dao_id(),
        subdao_id: members_dao.id(),
        added,
        skipped,
    });

    ticket.discharge(controller_batch_add_members::permit());
}

/// Execute a ControllerBatchRemoveMembers proposal.
public fun execute_controller_batch_remove_members(
    controller_vault: &mut CapabilityVault,
    members_dao: &mut DAO,
    ticket: ExecutionTicket<ControllerBatchRemoveMembers>,
    ctx: &mut TxContext,
) {
    assert!(controller_vault.dao_id() == ticket.ticket_dao_id(), EVaultDAOMismatch);

    let payload = ticket.ticket_payload();
    let req = ticket.ticket_request(controller_batch_remove_members::permit());

    let len = payload.members().length();
    assert!(len > 0, EEmptyBatch);
    assert!(len <= MAX_BATCH_SIZE, EBatchTooLarge);

    let (control, loan) = controller_vault.loan_cap<SubDAOControl, ControllerBatchRemoveMembers>(
        payload.control_id(),
        req,
    );

    let members_req = controller::privileged_submit<BatchRemoveMembers>(
        &control,
        members_dao,
        b"BatchRemoveMembers".to_ascii_string(),
        option::none(),
        batch_remove_members::new(*payload.members()),
        ctx,
    );

    let removed = members_dao.remove_board_members_governance(*payload.members(), &members_req);
    controller::privileged_consume(members_req, &control);
    controller_vault.return_cap(control, loan);

    event::emit(ControllerMembersBatchRemoved {
        controller_dao_id: controller_vault.dao_id(),
        subdao_id: members_dao.id(),
        removed,
    });

    ticket.discharge(controller_batch_remove_members::permit());
}

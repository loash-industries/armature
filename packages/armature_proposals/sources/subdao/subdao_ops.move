module armature_proposals::subdao_ops;

use armature::capability_vault::{CapabilityVault, SubDAOControl};
use armature::controller;
use armature::dao::{Self, DAO};
use armature::emergency;
use armature::governance;
use armature::proposal::{ExecutionTicket};
use armature::treasury_vault::TreasuryVault;
use armature_proposals::create_subdao::CreateSubDAO;
use armature_proposals::pause_execution::{Self, PauseSubDAOExecution, UnpauseSubDAOExecution};
use armature_proposals::reclaim_cap_from_subdao::ReclaimCapFromSubDAO;
use armature_proposals::spawn_dao::SpawnDAO;
use armature_proposals::spin_out_subdao::{Self, SpinOutSubDAO};
use armature_proposals::transfer_assets::TransferAssets;
use armature_proposals::transfer_cap_to_subdao::TransferCapToSubDAO;
use sui::clock::Clock;
use sui::event;

// === Errors ===

const EVaultDAOMismatch: u64 = 0;
const ESubDAOVaultMismatch: u64 = 1;
const EDAOMismatch: u64 = 2;
const EAssetLimitExceeded: u64 = 4;
const ETargetTreasuryMismatch: u64 = 5;
const ETargetVaultMismatch: u64 = 6;
const ETargetDAOMismatch: u64 = 7;

// === Constants ===

const MAX_TRANSFER_ASSETS: u64 = 50;

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

public struct SubDAOCreated has copy, drop {
    controller_dao_id: ID,
    subdao_id: ID,
    control_cap_id: ID,
}

public struct SubDAOExecutionPaused has copy, drop {
    dao_id: ID,
}

public struct SubDAOExecutionUnpaused has copy, drop {
    dao_id: ID,
}

public struct SuccessorDAOSpawned has copy, drop {
    origin_dao_id: ID,
    successor_dao_id: ID,
}

public struct SubDAOSpunOut has copy, drop {
    controller_dao_id: ID,
    subdao_id: ID,
}

public struct AssetsTransferInitiated has copy, drop {
    dao_id: ID,
    target_dao_id: ID,
    coin_count: u64,
    cap_count: u64,
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
    let req = ticket.ticket_request();
    let cap: T = source_vault.extract_cap(cap_id, req);
    target_vault.receive_cap(cap, req);

    event::emit(CapTransferredToSubDAO {
        dao_id: source_vault.dao_id(),
        cap_id,
        target_vault: object::id(target_vault),
    });

    ticket.discharge();
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
    let req = ticket.ticket_request();

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

    ticket.discharge();
}

/// Execute a CreateSubDAO proposal.
public fun execute_create_subdao(
    vault: &mut CapabilityVault,
    ticket: ExecutionTicket<CreateSubDAO>,
    ctx: &mut TxContext,
) {
    assert!(vault.dao_id() == ticket.ticket_dao_id(), EVaultDAOMismatch);

    let payload = ticket.ticket_payload();
    let gov_init = governance::init_board(*payload.initial_board());

    let (subdao, freeze_admin_cap) = dao::create_subdao(
        &gov_init,
        *payload.name(),
        *payload.description(),
        *payload.metadata_ipfs(),
        ctx,
    );

    let subdao_id = object::id(&subdao);
    let req = ticket.ticket_request();

    let control_cap_id = vault.create_subdao_control(subdao_id, req, ctx);
    vault.store_cap(freeze_admin_cap, req);
    dao::share_subdao(subdao, control_cap_id);

    event::emit(SubDAOCreated {
        controller_dao_id: vault.dao_id(),
        subdao_id,
        control_cap_id,
    });

    ticket.discharge();
}

/// Execute a PauseSubDAOExecution proposal.
public fun execute_pause_subdao_execution(
    controller_vault: &mut CapabilityVault,
    subdao: &mut DAO,
    ticket: ExecutionTicket<PauseSubDAOExecution>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(controller_vault.dao_id() == ticket.ticket_dao_id(), EVaultDAOMismatch);

    let payload = ticket.ticket_payload();
    let req = ticket.ticket_request();

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
        clock,
        ctx,
    );

    subdao.set_controller_paused(true, &subdao_req);
    controller::privileged_consume(subdao_req, &control);
    controller_vault.return_cap(control, loan);

    event::emit(SubDAOExecutionPaused { dao_id: subdao.id() });

    ticket.discharge();
}

/// Execute an UnpauseSubDAOExecution proposal.
public fun execute_unpause_subdao_execution(
    controller_vault: &mut CapabilityVault,
    subdao: &mut DAO,
    ticket: ExecutionTicket<UnpauseSubDAOExecution>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(controller_vault.dao_id() == ticket.ticket_dao_id(), EVaultDAOMismatch);

    let payload = ticket.ticket_payload();
    let req = ticket.ticket_request();

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
        clock,
        ctx,
    );

    subdao.set_controller_paused(false, &subdao_req);
    controller::privileged_consume(subdao_req, &control);
    controller_vault.return_cap(control, loan);

    event::emit(SubDAOExecutionUnpaused { dao_id: subdao.id() });

    ticket.discharge();
}

/// Execute a SpawnDAO proposal.
public fun execute_spawn_dao(
    dao: &mut DAO,
    ticket: ExecutionTicket<SpawnDAO>,
    ctx: &mut TxContext,
) {
    assert!(dao.id() == ticket.ticket_dao_id(), EDAOMismatch);

    let payload = ticket.ticket_payload();

    let successor_id = dao::create(
        payload.governance_init(),
        *payload.name(),
        *payload.description(),
        *payload.metadata_ipfs(),
        ctx,
    );

    dao.set_migrating(successor_id, ticket.ticket_request());

    event::emit(SuccessorDAOSpawned {
        origin_dao_id: dao.id(),
        successor_dao_id: successor_id,
    });

    ticket.discharge();
}

/// Execute a SpinOutSubDAO proposal.
public fun execute_spin_out_subdao(
    vault: &mut CapabilityVault,
    subdao_vault: &mut CapabilityVault,
    subdao: &mut DAO,
    ticket: ExecutionTicket<SpinOutSubDAO>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(vault.dao_id() == ticket.ticket_dao_id(), EVaultDAOMismatch);

    let payload = ticket.ticket_payload();
    assert!(subdao_vault.dao_id() == payload.subdao_id(), ESubDAOVaultMismatch);

    let req = ticket.ticket_request();

    let (control, loan) = vault.loan_cap<SubDAOControl, SpinOutSubDAO>(
        payload.control_cap_id(),
        req,
    );

    let subdao_req = controller::privileged_submit(
        &control,
        subdao,
        b"SpinOutSubDAO".to_ascii_string(),
        option::some(std::string::utf8(b"Controller-initiated spin-out")),
        spin_out_subdao::new(
            payload.subdao_id(),
            payload.control_cap_id(),
            payload.freeze_admin_cap_id(),
            *payload.spawn_dao_config(),
            *payload.spin_out_subdao_config(),
            *payload.create_subdao_config(),
        ),
        clock,
        ctx,
    );

    subdao.clear_controller(&subdao_req);
    subdao.enable_proposal_type(
        b"SpawnDAO".to_ascii_string(),
        *payload.spawn_dao_config(),
        &subdao_req,
    );
    subdao.enable_proposal_type(
        b"SpinOutSubDAO".to_ascii_string(),
        *payload.spin_out_subdao_config(),
        &subdao_req,
    );
    subdao.enable_proposal_type(
        b"CreateSubDAO".to_ascii_string(),
        *payload.create_subdao_config(),
        &subdao_req,
    );

    controller::privileged_consume(subdao_req, &control);
    vault.return_cap(control, loan);

    let freeze_cap = vault.extract_cap<emergency::FreezeAdminCap, SpinOutSubDAO>(
        payload.freeze_admin_cap_id(),
        req,
    );
    subdao_vault.receive_cap(freeze_cap, req);

    vault.destroy_subdao_control(payload.control_cap_id(), req);

    event::emit(SubDAOSpunOut {
        controller_dao_id: vault.dao_id(),
        subdao_id: payload.subdao_id(),
    });

    ticket.discharge();
}

/// Validate a TransferAssets proposal and emit the transfer event.
/// Borrows the ticket so the caller can compose typed withdraw/extract calls
/// before calling finalize_transfer_assets.
///
/// PTB flow:
///   1. ticket_from_vote(...) → ExecutionTicket<TransferAssets>
///   2. validate_transfer_assets(..., &ticket)
///   3. N × source_treasury.withdraw<T>(amount, ticket.ticket_request(), ctx)
///   4. N × source_vault.extract_cap<T>(cap_id, ticket.ticket_request())
///   5. finalize_transfer_assets(ticket)
public fun validate_transfer_assets(
    source_treasury: &TreasuryVault,
    source_cap_vault: &CapabilityVault,
    target_treasury: &TreasuryVault,
    target_cap_vault: &CapabilityVault,
    ticket: &ExecutionTicket<TransferAssets>,
) {
    let request = ticket.ticket_request();
    let payload = ticket.ticket_payload();

    assert!(source_treasury.dao_id() == request.req_dao_id(), EVaultDAOMismatch);
    assert!(source_cap_vault.dao_id() == request.req_dao_id(), EVaultDAOMismatch);
    assert!(object::id(target_treasury) == payload.target_treasury_id(), ETargetTreasuryMismatch);
    assert!(object::id(target_cap_vault) == payload.target_vault_id(), ETargetVaultMismatch);
    assert!(target_treasury.dao_id() == payload.target_dao_id(), ETargetDAOMismatch);
    assert!(target_cap_vault.dao_id() == payload.target_dao_id(), ETargetDAOMismatch);
    assert!(
        payload.coin_types().length() + payload.cap_ids().length() <= MAX_TRANSFER_ASSETS,
        EAssetLimitExceeded,
    );

    event::emit(AssetsTransferInitiated {
        dao_id: source_treasury.dao_id(),
        target_dao_id: payload.target_dao_id(),
        coin_count: payload.coin_types().length(),
        cap_count: payload.cap_ids().length(),
    });
}

/// Consume the ticket after all typed transfers are complete.
public fun finalize_transfer_assets(ticket: ExecutionTicket<TransferAssets>) {
    ticket.discharge();
}

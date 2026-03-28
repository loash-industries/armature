module armature_proposals::subdao_ops;

use armature::capability_vault::{CapabilityVault, SubDAOControl};
use armature::controller;
use armature::dao::{Self, DAO};
use armature::emergency;
use armature::governance;
use armature::proposal::{Self, Proposal, ExecutionRequest};
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

/// Execute a TransferCapToSubDAO proposal: extract a capability from the DAO's
/// vault and store it in the target SubDAO's vault.
public fun execute_transfer_cap<T: key + store>(
    source_vault: &mut CapabilityVault,
    target_vault: &mut CapabilityVault,
    proposal: &Proposal<TransferCapToSubDAO>,
    request: ExecutionRequest<TransferCapToSubDAO>,
) {
    assert!(source_vault.dao_id() == request.req_dao_id(), EVaultDAOMismatch);

    let payload = proposal.payload();
    assert!(target_vault.dao_id() == payload.target_subdao(), ESubDAOVaultMismatch);

    let cap: T = source_vault.extract_cap(payload.cap_id(), &request);
    target_vault.receive_cap(cap, &request);

    event::emit(CapTransferredToSubDAO {
        dao_id: source_vault.dao_id(),
        cap_id: payload.cap_id(),
        target_vault: object::id(target_vault),
    });

    proposal::finalize(request, proposal);
}

/// Execute a ReclaimCapFromSubDAO proposal: loan the SubDAOControl from the
/// controller's vault, use it to extract a capability from the SubDAO's vault,
/// store the reclaimed capability in the controller's vault, and return the loan.
public fun execute_reclaim_cap<T: key + store>(
    controller_vault: &mut CapabilityVault,
    subdao_vault: &mut CapabilityVault,
    proposal: &Proposal<ReclaimCapFromSubDAO>,
    request: ExecutionRequest<ReclaimCapFromSubDAO>,
) {
    assert!(controller_vault.dao_id() == request.req_dao_id(), EVaultDAOMismatch);

    let payload = proposal.payload();
    assert!(subdao_vault.dao_id() == payload.subdao_id(), ESubDAOVaultMismatch);

    // Loan SubDAOControl from controller's vault
    let (control, loan) = controller_vault.loan_cap<SubDAOControl, ReclaimCapFromSubDAO>(
        payload.control_id(),
        &request,
    );

    // Extract target cap from subdao vault using SubDAOControl authority
    let cap: T = subdao_vault.privileged_extract(payload.cap_id(), &control);

    // Store reclaimed cap in controller's vault
    controller_vault.store_cap(cap, &request);

    // Return SubDAOControl loan
    controller_vault.return_cap(control, loan);

    event::emit(CapReclaimedFromSubDAO {
        dao_id: controller_vault.dao_id(),
        cap_id: payload.cap_id(),
        subdao_id: payload.subdao_id(),
    });

    proposal::finalize(request, proposal);
}

/// Execute a CreateSubDAO proposal: spawn a new Board-governance child DAO and
/// store a SubDAOControl token and the child's FreezeAdminCap in the
/// controller's capability vault.
public fun execute_create_subdao(
    vault: &mut CapabilityVault,
    proposal: &Proposal<CreateSubDAO>,
    request: ExecutionRequest<CreateSubDAO>,
    ctx: &mut TxContext,
) {
    assert!(vault.dao_id() == request.req_dao_id(), EVaultDAOMismatch);

    let payload = proposal.payload();
    let gov_init = governance::init_board(*payload.initial_board());

    let (subdao, freeze_admin_cap) = dao::create_subdao(
        &gov_init,
        *payload.name(),
        *payload.description(),
        *payload.metadata_ipfs(),
        ctx,
    );

    let subdao_id = object::id(&subdao);

    let control_cap_id = vault.create_subdao_control(subdao_id, &request, ctx);

    // Store the child DAO's FreezeAdminCap in the controller's vault
    vault.store_cap(freeze_admin_cap, &request);

    // Set controller_cap_id on SubDAO and share it
    dao::share_subdao(subdao, control_cap_id);

    event::emit(SubDAOCreated {
        controller_dao_id: vault.dao_id(),
        subdao_id,
        control_cap_id,
    });

    proposal::finalize(request, proposal);
}

/// Execute a PauseSubDAOExecution proposal: loan SubDAOControl from the
/// controller's vault, create a privileged proposal on the SubDAO, and set
/// `controller_paused = true` on the SubDAO.
public fun execute_pause_subdao_execution(
    controller_vault: &mut CapabilityVault,
    subdao: &mut DAO,
    proposal: &Proposal<PauseSubDAOExecution>,
    request: ExecutionRequest<PauseSubDAOExecution>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(controller_vault.dao_id() == request.req_dao_id(), EVaultDAOMismatch);

    let payload = proposal.payload();

    let (control, loan) = controller_vault.loan_cap<SubDAOControl, PauseSubDAOExecution>(
        payload.pause_control_id(),
        &request,
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

    proposal::finalize(request, proposal);
}

/// Execute an UnpauseSubDAOExecution proposal: loan SubDAOControl from the
/// controller's vault, create a privileged proposal on the SubDAO, and set
/// `controller_paused = false` on the SubDAO.
public fun execute_unpause_subdao_execution(
    controller_vault: &mut CapabilityVault,
    subdao: &mut DAO,
    proposal: &Proposal<UnpauseSubDAOExecution>,
    request: ExecutionRequest<UnpauseSubDAOExecution>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(controller_vault.dao_id() == request.req_dao_id(), EVaultDAOMismatch);

    let payload = proposal.payload();

    let (control, loan) = controller_vault.loan_cap<SubDAOControl, UnpauseSubDAOExecution>(
        payload.unpause_control_id(),
        &request,
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

    proposal::finalize(request, proposal);
}

/// Execute a SpawnDAO proposal: create a successor DAO and transition
/// the current DAO to Migrating status.
public fun execute_spawn_dao(
    dao: &mut DAO,
    proposal: &Proposal<SpawnDAO>,
    request: ExecutionRequest<SpawnDAO>,
    ctx: &mut TxContext,
) {
    assert!(dao.id() == request.req_dao_id(), EDAOMismatch);

    let payload = proposal.payload();

    let successor_id = dao::create(
        payload.governance_init(),
        *payload.name(),
        *payload.description(),
        *payload.metadata_ipfs(),
        ctx,
    );

    dao.set_migrating(successor_id, &request);

    event::emit(SuccessorDAOSpawned {
        origin_dao_id: dao.id(),
        successor_dao_id: successor_id,
    });

    proposal::finalize(request, proposal);
}

/// Execute a SpinOutSubDAO proposal: clear the controller relationship on the
/// SubDAO, re-enable previously blocked proposal types, transfer the SubDAO's
/// FreezeAdminCap back to it, then destroy the SubDAOControl token —
/// permanently granting the SubDAO full independence.
public fun execute_spin_out_subdao(
    vault: &mut CapabilityVault,
    subdao_vault: &mut CapabilityVault,
    subdao: &mut DAO,
    proposal: &Proposal<SpinOutSubDAO>,
    request: ExecutionRequest<SpinOutSubDAO>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(vault.dao_id() == request.req_dao_id(), EVaultDAOMismatch);

    let payload = proposal.payload();
    assert!(subdao_vault.dao_id() == payload.subdao_id(), ESubDAOVaultMismatch);

    // Loan SubDAOControl to perform privileged ops on the SubDAO
    let (control, loan) = vault.loan_cap<SubDAOControl, SpinOutSubDAO>(
        payload.control_cap_id(),
        &request,
    );

    // Create a privileged request on the SubDAO via controller bypass
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

    // Clear controller relationship (resets controller_cap_id and controller_paused)
    subdao.clear_controller(&subdao_req);

    // Re-enable hierarchy-altering types with governance-specified configs
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

    // Consume the privileged request and return the loan
    controller::privileged_consume(subdao_req, &control);
    vault.return_cap(control, loan);

    // Transfer SubDAO's FreezeAdminCap from parent vault to SubDAO vault
    let freeze_cap = vault.extract_cap<emergency::FreezeAdminCap, SpinOutSubDAO>(
        payload.freeze_admin_cap_id(),
        &request,
    );
    subdao_vault.receive_cap(freeze_cap, &request);

    // Now destroy the SubDAOControl permanently
    vault.destroy_subdao_control(payload.control_cap_id(), &request);

    event::emit(SubDAOSpunOut {
        controller_dao_id: vault.dao_id(),
        subdao_id: payload.subdao_id(),
    });

    proposal::finalize(request, proposal);
}

/// Validate a TransferAssets proposal: check ownership and asset count limits,
/// verify target objects match the proposal payload, and emit the transfer event.
/// Borrows the ExecutionRequest so the caller can compose typed
/// `withdraw<T>` / `extract_cap<T>` calls in the same PTB
/// before calling `finalize_transfer_assets` to consume the request.
///
/// PTB flow:
///   1. `board_voting::authorize_execution` → `ExecutionRequest<TransferAssets>`
///   2. `validate_transfer_assets(..., &request)` — validates limits + targets, emits event
///   3. N × `source_treasury.withdraw<T>(amount, &request, ctx)` →
/// `target_treasury.deposit<T>(coin)`
///   4. N × `source_vault.extract_cap<T>(cap_id, &request)` →
/// `target_vault.receive_cap<T>(cap, &request)`
///   5. `finalize_transfer_assets(request, &proposal)` — consumes the request
public fun validate_transfer_assets(
    source_treasury: &TreasuryVault,
    source_cap_vault: &CapabilityVault,
    target_treasury: &TreasuryVault,
    target_cap_vault: &CapabilityVault,
    proposal: &Proposal<TransferAssets>,
    request: &ExecutionRequest<TransferAssets>,
) {
    assert!(source_treasury.dao_id() == request.req_dao_id(), EVaultDAOMismatch);
    assert!(source_cap_vault.dao_id() == request.req_dao_id(), EVaultDAOMismatch);

    let payload = proposal.payload();

    // Validate target objects match proposal payload
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

/// Consume the ExecutionRequest after all typed transfers are complete.
public fun finalize_transfer_assets(
    request: ExecutionRequest<TransferAssets>,
    proposal: &Proposal<TransferAssets>,
) {
    proposal::finalize(request, proposal);
}

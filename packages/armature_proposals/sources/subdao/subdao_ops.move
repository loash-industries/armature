module armature_proposals::subdao_ops;

use armature::capability_vault::{CapabilityVault, SubDAOControl};
use armature::dao::{Self, DAO};
use armature::governance;
use armature::proposal::{Self, Proposal, ExecutionRequest};
use armature::treasury_vault::TreasuryVault;
use armature_proposals::create_subdao::CreateSubDAO;
use armature_proposals::pause_execution::{PauseSubDAOExecution, UnpauseSubDAOExecution};
use armature_proposals::reclaim_cap_from_subdao::ReclaimCapFromSubDAO;
use armature_proposals::spawn_dao::SpawnDAO;
use armature_proposals::spin_out_subdao::SpinOutSubDAO;
use armature_proposals::transfer_assets::TransferAssets;
use armature_proposals::transfer_cap_to_subdao::TransferCapToSubDAO;
use sui::event;

// === Errors ===

const EVaultDAOMismatch: u64 = 0;
const ESubDAOVaultMismatch: u64 = 1;
const EDAOMismatch: u64 = 2;
const EAssetLimitExceeded: u64 = 4;

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
    target_vault.store_cap(cap, &request);

    event::emit(CapTransferredToSubDAO {
        dao_id: source_vault.dao_id(),
        cap_id: payload.cap_id(),
        target_vault: object::id(target_vault),
    });

    proposal::consume(request);
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

    proposal::consume(request);
}

/// Execute a CreateSubDAO proposal: spawn a new Board-governance child DAO and
/// store a SubDAOControl token in the controller's capability vault.
public fun execute_create_subdao(
    vault: &mut CapabilityVault,
    proposal: &Proposal<CreateSubDAO>,
    request: ExecutionRequest<CreateSubDAO>,
    ctx: &mut TxContext,
) {
    assert!(vault.dao_id() == request.req_dao_id(), EVaultDAOMismatch);

    let payload = proposal.payload();
    let gov_init = governance::init_board(*payload.initial_board());

    let subdao_id = dao::create(
        &gov_init,
        *payload.name(),
        *payload.description(),
        *payload.metadata_ipfs(),
        ctx,
    );

    let control_cap_id = vault.create_subdao_control(subdao_id, &request, ctx);

    event::emit(SubDAOCreated {
        controller_dao_id: vault.dao_id(),
        subdao_id,
        control_cap_id,
    });

    proposal::consume(request);
}

/// Execute a PauseSubDAOExecution proposal: pause all proposal execution on the DAO.
/// Must be submitted by the parent DAO (privileged_submit) and executed against
/// the SubDAO's DAO object.
public fun execute_pause_subdao_execution(
    dao: &mut DAO,
    proposal: &Proposal<PauseSubDAOExecution>,
    request: ExecutionRequest<PauseSubDAOExecution>,
) {
    assert!(dao.id() == request.req_dao_id(), EDAOMismatch);
    let _ = proposal.payload();

    dao.set_execution_paused(true, &request);

    event::emit(SubDAOExecutionPaused { dao_id: dao.id() });

    proposal::consume(request);
}

/// Execute an UnpauseSubDAOExecution proposal: resume proposal execution on the DAO.
public fun execute_unpause_subdao_execution(
    dao: &mut DAO,
    proposal: &Proposal<UnpauseSubDAOExecution>,
    request: ExecutionRequest<UnpauseSubDAOExecution>,
) {
    assert!(dao.id() == request.req_dao_id(), EDAOMismatch);
    let _ = proposal.payload();

    dao.set_execution_paused(false, &request);

    event::emit(SubDAOExecutionUnpaused { dao_id: dao.id() });

    proposal::consume(request);
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

    dao.set_migrating(&request);

    event::emit(SuccessorDAOSpawned {
        origin_dao_id: dao.id(),
        successor_dao_id: successor_id,
    });

    proposal::consume(request);
}

/// Execute a SpinOutSubDAO proposal: destroy the SubDAOControl token,
/// permanently relinquishing the parent's authority over the sub-DAO.
public fun execute_spin_out_subdao(
    vault: &mut CapabilityVault,
    proposal: &Proposal<SpinOutSubDAO>,
    request: ExecutionRequest<SpinOutSubDAO>,
) {
    assert!(vault.dao_id() == request.req_dao_id(), EVaultDAOMismatch);

    let payload = proposal.payload();

    vault.destroy_subdao_control(payload.control_cap_id(), &request);

    event::emit(SubDAOSpunOut {
        controller_dao_id: vault.dao_id(),
        subdao_id: payload.subdao_id(),
    });

    proposal::consume(request);
}

/// Execute a TransferAssets proposal: validate limits and authorize the PTB to
/// perform the actual typed asset transfers via `withdraw<T>` / `extract_cap<T>`.
/// The caller must include the individual typed transfer commands in the same PTB
/// using `&request` before this handler is invoked.
public fun execute_transfer_assets(
    source_treasury: &TreasuryVault,
    source_cap_vault: &CapabilityVault,
    proposal: &Proposal<TransferAssets>,
    request: ExecutionRequest<TransferAssets>,
) {
    assert!(source_treasury.dao_id() == request.req_dao_id(), EVaultDAOMismatch);
    assert!(source_cap_vault.dao_id() == request.req_dao_id(), EVaultDAOMismatch);

    let payload = proposal.payload();
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

    proposal::consume(request);
}

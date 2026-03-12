module armature_proposals::subdao_ops;

use armature::capability_vault::{CapabilityVault, SubDAOControl};
use armature::proposal::{Self, Proposal, ExecutionRequest};
use armature_proposals::reclaim_cap_from_subdao::ReclaimCapFromSubDAO;
use armature_proposals::transfer_cap_to_subdao::TransferCapToSubDAO;
use sui::event;

// === Errors ===

const EVaultDAOMismatch: u64 = 0;
const ESubDAOVaultMismatch: u64 = 1;

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

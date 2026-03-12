module armature::controller;

use armature::capability_vault::SubDAOControl;
use armature::dao::DAO;
use armature::proposal::{Self, ExecutionRequest};
use std::string::String;
use sui::clock::Clock;

// === Errors ===

const EControlMismatch: u64 = 0;
const EDAONotActive: u64 = 1;

// === Public Functions ===

/// Create a privileged proposal on a SubDAO, bypassing normal voting.
/// Authorization: caller must possess `&SubDAOControl` bound to the SubDAO.
/// Creates a Proposal<P> directly in Executed status and shares it for audit.
/// Returns an ExecutionRequest<P> for the SubDAO, which can authorize SubDAO
/// mutations (e.g., `set_controller_paused`) in the same PTB.
public fun privileged_submit<P: store>(
    control: &SubDAOControl,
    subdao: &DAO,
    type_key: std::ascii::String,
    metadata_ipfs: String,
    payload: P,
    clock: &Clock,
    ctx: &mut TxContext,
): ExecutionRequest<P> {
    assert!(control.subdao_id() == subdao.id(), EControlMismatch);
    assert!(subdao.status().is_active(), EDAONotActive);

    proposal::privileged_create(
        subdao.id(),
        type_key,
        ctx.sender(),
        metadata_ipfs,
        payload,
        clock,
        ctx,
    )
}

/// Consume the ExecutionRequest from a privileged operation.
/// Validates the request's DAO ID matches the SubDAOControl's target.
public fun privileged_consume<P>(req: ExecutionRequest<P>, control: &SubDAOControl) {
    assert!(req.req_dao_id() == control.subdao_id(), EControlMismatch);
    proposal::consume(req);
}

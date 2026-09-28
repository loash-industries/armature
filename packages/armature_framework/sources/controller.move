module armature::controller;

use armature::capability_vault::{Self, CapabilityVault, SubDAOControl};
use armature::dao::DAO;
use armature::permissions;
use armature::proposal::{Self, ExecutionRequest};
use std::string::String;

// === Errors ===

const EControlMismatch: u64 = 0;
const EDAONotActive: u64 = 1;
/// The SubDAOControl is bound to this SubDAO but is not its registered
/// controller (`DAO::controller_cap_id`), or the SubDAO has none.
const ENotController: u64 = 2;

// === Public Functions ===

/// Create a privileged proposal on a SubDAO, bypassing normal voting.
/// Authorization: caller must possess the SubDAO's registered `&SubDAOControl`
/// (`assert_registered_control`).
/// No Proposal object is created: ProposalCreated, ProposalPayloadCreated and
/// ProposalExecuted are the audit record, and the payload is dropped once
/// serialised into ProposalPayloadCreated. Returns an ExecutionRequest<P> for
/// the SubDAO, which can authorize SubDAO mutations (e.g.,
/// `set_controller_paused`) in the same PTB.
public fun privileged_submit<P: store + drop>(
    control: &SubDAOControl,
    subdao: &DAO,
    type_key: std::ascii::String,
    metadata_ipfs: Option<String>,
    payload: P,
    ctx: &mut TxContext,
): ExecutionRequest<P> {
    assert_registered_control(control, subdao);
    assert!(subdao.status().is_active(), EDAONotActive);

    proposal::privileged_execute(
        subdao.id(),
        type_key,
        ctx.sender(),
        metadata_ipfs,
        &payload,
        0,
        vector[],
        true,
        ctx,
    )
}

/// Consume the ExecutionRequest from a privileged operation.
/// Validates the request's DAO ID matches the SubDAOControl's target.
public fun privileged_consume<P>(req: ExecutionRequest<P>, control: &SubDAOControl) {
    assert!(req.req_dao_id() == control.subdao_id(), EControlMismatch);
    proposal::consume(req);
}

/// Extract capability `cap_id` from a SubDAO's vault on its controller's
/// authority (controller reclaim). `control` must be the SubDAO's registered
/// controller (`assert_registered_control`) and `subdao_vault` its vault.
public fun privileged_extract<T: key + store>(
    subdao_vault: &mut CapabilityVault,
    cap_id: ID,
    subdao: &DAO,
    control: &SubDAOControl,
): T {
    assert!(subdao_vault.dao_id() == subdao.id(), EControlMismatch);
    assert_registered_control(control, subdao);
    subdao_vault.privileged_extract(cap_id, control)
}

/// Receive `cap` into a SubDAO's vault from its controller DAO. `req` must
/// come from the DAO whose `controller_vault` holds the SubDAO's registered
/// SubDAOControl, which is what ties the sender to this SubDAO.
/// Requires VAULT_EXTRACT on `req` (`proposal::assert_permitted`).
public fun receive_cap_from_controller<T: key + store, P>(
    subdao_vault: &mut CapabilityVault,
    cap: T,
    subdao: &DAO,
    controller_vault: &CapabilityVault,
    req: &ExecutionRequest<P>,
) {
    req.assert_permitted(permissions::vault_extract());
    assert!(subdao_vault.dao_id() == subdao.id(), EControlMismatch);
    assert!(controller_vault.dao_id() == req.req_dao_id(), EControlMismatch);
    let control_id = subdao.controller_cap_id();
    assert!(
        control_id.is_some() && controller_vault.contains(*control_id.borrow()),
        ENotController,
    );
    capability_vault::receive_cap(subdao_vault, cap, req);
}

/// Abort unless `control` is bound to `subdao` (EControlMismatch) and is the
/// SubDAO's registered controller (ENotController). The second check is what
/// stops a SubDAOControl minted elsewhere from acting on a DAO it does not
/// control: only the object recorded by `dao::share_subdao` passes.
public fun assert_registered_control(control: &SubDAOControl, subdao: &DAO) {
    assert!(control.subdao_id() == subdao.id(), EControlMismatch);
    assert!(
        subdao.controller_cap_id() == &option::some(object::id(control)),
        ENotController,
    );
}

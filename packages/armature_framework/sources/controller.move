module armature::controller;

use armature::capability_vault::{Self, CapabilityVault, SubOUControl};
use armature::ou::OU;
use armature::permissions;
use armature::proposal::{Self, ExecutionRequest};
use std::string::String;

// === Errors ===

const EControlMismatch: u64 = 0;
const EOUNotActive: u64 = 1;
/// The SubOUControl is bound to this SubOU but is not its registered
/// controller (`OU::controller_cap_id`), or the SubOU has none.
const ENotController: u64 = 2;

// === Public Functions ===

/// Create a privileged proposal on a SubOU, bypassing normal voting.
/// Authorization: caller must possess the SubOU's registered `&SubOUControl`
/// (`assert_registered_control`).
/// No Proposal object is created: ProposalCreated, ProposalPayloadCreated and
/// ProposalExecuted are the audit record, and the payload is dropped once
/// serialised into ProposalPayloadCreated. Returns an ExecutionRequest<P> for
/// the SubOU, which can authorize SubOU mutations (e.g.,
/// `set_controller_paused`) in the same PTB.
public fun privileged_submit<P: store + drop>(
    control: &SubOUControl,
    subou: &OU,
    type_key: std::ascii::String,
    metadata_ipfs: Option<String>,
    payload: P,
    ctx: &mut TxContext,
): ExecutionRequest<P> {
    assert_registered_control(control, subou);
    assert!(subou.status().is_active(), EOUNotActive);

    proposal::privileged_execute(
        subou.id(),
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
/// Validates the request's OU ID matches the SubOUControl's target.
public fun privileged_consume<P>(req: ExecutionRequest<P>, control: &SubOUControl) {
    assert!(req.req_ou_id() == control.subou_id(), EControlMismatch);
    proposal::consume(req);
}

/// Extract capability `cap_id` from a SubOU's vault on its controller's
/// authority (controller reclaim). `control` must be the SubOU's registered
/// controller (`assert_registered_control`) and `subou_vault` its vault.
public fun privileged_extract<T: key + store>(
    subou_vault: &mut CapabilityVault,
    cap_id: ID,
    subou: &OU,
    control: &SubOUControl,
): T {
    assert!(subou_vault.ou_id() == subou.id(), EControlMismatch);
    assert_registered_control(control, subou);
    subou_vault.privileged_extract(cap_id, control)
}

/// Receive `cap` into a SubOU's vault from its controller OU. `req` must
/// come from the OU whose `controller_vault` holds the SubOU's registered
/// SubOUControl, which is what ties the sender to this SubOU.
/// Requires VAULT_EXTRACT on `req` (`proposal::assert_permitted`).
public fun receive_cap_from_controller<T: key + store, P>(
    subou_vault: &mut CapabilityVault,
    cap: T,
    subou: &OU,
    controller_vault: &CapabilityVault,
    req: &ExecutionRequest<P>,
) {
    req.assert_permitted(permissions::vault_extract());
    assert!(subou_vault.ou_id() == subou.id(), EControlMismatch);
    assert!(controller_vault.ou_id() == req.req_ou_id(), EControlMismatch);
    let control_id = subou.controller_cap_id();
    assert!(
        control_id.is_some() && controller_vault.contains(*control_id.borrow()),
        ENotController,
    );
    capability_vault::receive_cap(subou_vault, cap, req);
}

/// Abort unless `control` is bound to `subou` (EControlMismatch) and is the
/// SubOU's registered controller (ENotController). The second check is what
/// stops a SubOUControl minted elsewhere from acting on an OU it does not
/// control: only the object recorded by `ou::share_subou` passes.
public fun assert_registered_control(control: &SubOUControl, subou: &OU) {
    assert!(control.subou_id() == subou.id(), EControlMismatch);
    assert!(
        subou.controller_cap_id() == &option::some(object::id(control)),
        ENotController,
    );
}

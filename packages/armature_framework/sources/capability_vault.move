module armature::capability_vault;

use armature::permissions;
use armature::proposal::ExecutionRequest;
use armature::version;
use std::type_name;
use sui::dynamic_object_field as dof;
use sui::vec_map::{Self, VecMap};
use sui::vec_set::{Self, VecSet};

// === Errors ===

const ENotController: u64 = 0;
const ECapIdMismatch: u64 = 1;
const EVaultIdMismatch: u64 = 2;
const EOUIdMismatch: u64 = 3;

// === Structs ===

/// Stores arbitrary capabilities as dynamic object fields.
/// Created as a shared object during OU creation.
public struct CapabilityVault has key, store {
    id: UID,
    ou_id: ID,
    cap_types: VecSet<std::ascii::String>,
    cap_ids: VecSet<ID>,
    ids_by_type: VecMap<std::ascii::String, vector<ID>>,
    /// Version floor (see `version`): its OU's floor at creation.
    min_version: u64,
}

/// Hot-potato receipt for a loaned capability. Must be consumed by `return_cap`.
public struct CapLoan {
    cap_id: ID,
    vault_id: ID,
    /// The lending vault's version floor (see `version`).
    min_version: u64,
}

/// Controller token for a sub-OU relationship.
/// Used by parent OUs to reclaim capabilities from child OUs.
public struct SubOUControl has key, store {
    id: UID,
    subou_id: ID,
}

// === Constructor ===

/// Create a new empty CapabilityVault. Only callable within the framework package.
public(package) fun new(ou_id: ID, min_version: u64, ctx: &mut TxContext): CapabilityVault {
    CapabilityVault {
        id: object::new(ctx),
        ou_id,
        cap_types: vec_set::empty(),
        cap_ids: vec_set::empty(),
        ids_by_type: vec_map::empty(),
        min_version,
    }
}

/// Share the vault as a shared object.
#[allow(lint(share_owned, custom_state_change))]
public(package) fun share(vault: CapabilityVault) {
    transfer::share_object(vault);
}

// === Accessors ===

/// Returns the OU ID this vault belongs to.
public fun ou_id(self: &CapabilityVault): ID { self.ou_id }

/// Returns the set of capability type names stored.
public fun cap_types(self: &CapabilityVault): &VecSet<std::ascii::String> { &self.cap_types }

/// Returns the set of capability object IDs stored.
public fun cap_ids(self: &CapabilityVault): &VecSet<ID> { &self.cap_ids }

/// Returns true if a capability with the given ID is registered in the vault.
public fun contains(self: &CapabilityVault, cap_id: ID): bool {
    self.cap_ids.contains(&cap_id)
}

/// Returns the IDs of stored capabilities for a given type.
public fun ids_for_type<T: key + store>(self: &CapabilityVault): vector<ID> {
    let type_name = std::type_name::with_defining_ids<T>().into_string();
    if (self.ids_by_type.contains(&type_name)) {
        *self.ids_by_type.get(&type_name)
    } else {
        vector[]
    }
}

// === Store ===

/// Store a capability during OU creation. No ExecutionRequest required.
/// Only callable within the framework package.
public(package) fun store_cap_init<T: key + store>(self: &mut CapabilityVault, cap: T) {
    let cap_id = object::id(&cap);
    register_cap<T>(self, cap_id);
    dof::add(&mut self.id, cap_id, cap);
}

/// Store a capability into the vault. Requires an active ExecutionRequest.
/// Requires VAULT_STORE (`proposal::assert_permitted`).
public fun store_cap<T: key + store, P>(
    self: &mut CapabilityVault,
    cap: T,
    req: &ExecutionRequest<P>,
) {
    self.check_version_mut();
    req.check_request_version();
    assert!(self.ou_id == req.req_ou_id(), EOUIdMismatch);
    req.assert_permitted(permissions::vault_store());
    let cap_id = object::id(&cap);
    register_cap<T>(self, cap_id);
    dof::add(&mut self.id, cap_id, cap);
}

/// Receive a capability into the vault for cross-OU transfers.
/// Requires an ExecutionRequest for governance authorization but does NOT
/// check ou_id match, since the request originates from the source OU.
/// Package-only: nothing here ties the request's OU to this vault, so each
/// framework caller establishes that link itself (SpinOutSubOU's own SubOU,
/// TransferAssets' voted target, `controller::receive_cap_from_controller`).
/// Other packages use `controller::receive_cap_from_controller` for
/// parent→child transfers, or `receive_cap_authorized` for anything else.
/// Requires VAULT_EXTRACT on the sending OU's request (`proposal::assert_permitted`).
public(package) fun receive_cap<T: key + store, P>(
    self: &mut CapabilityVault,
    cap: T,
    req: &ExecutionRequest<P>,
) {
    self.check_version_mut();
    req.check_request_version();
    req.assert_permitted(permissions::vault_extract());
    let cap_id = object::id(&cap);
    register_cap<T>(self, cap_id);
    dof::add(&mut self.id, cap_id, cap);
}

/// Receive a capability with dual authorization: both the sending OU's governance
/// (via `send_req`) and the receiving OU's governance (via `recv_req`) must approve.
/// Unlike `receive_cap`, this asserts the receiving vault belongs to the OU that
/// issued `recv_req`. Third-party cross-OU handlers should prefer this over
/// `receive_cap` so the destination OU has an explicit vote to accept the capability.
/// Requires VAULT_EXTRACT on the sending request and VAULT_STORE on the receiving one.
public fun receive_cap_authorized<T: key + store, Send, Recv>(
    self: &mut CapabilityVault,
    cap: T,
    sendreq: &ExecutionRequest<Send>,
    recvreq: &ExecutionRequest<Recv>,
) {
    self.check_version_mut();
    sendreq.check_request_version();
    recvreq.check_request_version();
    assert!(self.ou_id == recvreq.req_ou_id(), EOUIdMismatch);
    sendreq.assert_permitted(permissions::vault_extract());
    recvreq.assert_permitted(permissions::vault_store());
    let cap_id = object::id(&cap);
    register_cap<T>(self, cap_id);
    dof::add(&mut self.id, cap_id, cap);
}

// === Borrow ===

/// Borrow an immutable reference to a stored capability.
/// Requires VAULT_BORROW (`proposal::assert_permitted`) and `T` in the
/// request's borrow scope (`proposal::assert_may_borrow`).
public fun borrow_cap<T: key + store, P>(
    self: &CapabilityVault,
    cap_id: ID,
    req: &ExecutionRequest<P>,
): &T {
    self.check_version();
    req.check_request_version();
    assert!(self.ou_id == req.req_ou_id(), EOUIdMismatch);
    req.assert_permitted(permissions::vault_borrow());
    req.assert_may_borrow(&type_name::with_defining_ids<T>());
    dof::borrow(&self.id, cap_id)
}

/// Borrow an `ExternalExecutionCap<P>` from the vault without an
/// `ExecutionRequest`. The cap is bearer auth: its presence in this vault
/// is the OU's on-chain opt-in for bypass execution under type `P`.
///
/// The caller MUST pass the `ou_id` of the OU it intends to act on, and
/// this function asserts the vault belongs to that OU. Combined with the
/// cap's own `ou_id` (re-checked at the use site by
/// `external_execution::ticket_from_cap`), this is two independent
/// boundaries between a borrowed cap and an OU mutation. Don't rely on the
/// use-site check alone — a future consumer that forgets it would otherwise
/// have an authority leak.
public fun borrow_external_cap<P>(
    self: &CapabilityVault,
    ou_id: ID,
    cap_id: ID,
): &armature::proposal::ExternalExecutionCap<P> {
    self.check_version();
    assert!(self.ou_id == ou_id, EOUIdMismatch);
    dof::borrow(&self.id, cap_id)
}

/// Borrow a mutable reference to a stored capability.
/// Requires VAULT_BORROW (`proposal::assert_permitted`) and `T` in the
/// request's borrow scope (`proposal::assert_may_borrow`).
public fun borrow_cap_mut<T: key + store, P>(
    self: &mut CapabilityVault,
    cap_id: ID,
    req: &ExecutionRequest<P>,
): &mut T {
    self.check_version_mut();
    req.check_request_version();
    assert!(self.ou_id == req.req_ou_id(), EOUIdMismatch);
    req.assert_permitted(permissions::vault_borrow());
    req.assert_may_borrow(&type_name::with_defining_ids<T>());
    dof::borrow_mut(&mut self.id, cap_id)
}

// === Loan ===

/// Loan a capability out of the vault. Returns the capability and a hot-potato CapLoan.
/// Registries are NOT updated — the capability is considered "held" during the loan.
/// Requires VAULT_BORROW (`proposal::assert_permitted`) and `T` in the
/// request's borrow scope (`proposal::assert_may_borrow`).
public fun loan_cap<T: key + store, P>(
    self: &mut CapabilityVault,
    cap_id: ID,
    req: &ExecutionRequest<P>,
): (T, CapLoan) {
    self.check_version_mut();
    req.check_request_version();
    assert!(self.ou_id == req.req_ou_id(), EOUIdMismatch);
    req.assert_permitted(permissions::vault_borrow());
    req.assert_may_borrow(&type_name::with_defining_ids<T>());
    let cap: T = dof::remove(&mut self.id, cap_id);
    let loan = CapLoan {
        cap_id,
        vault_id: object::id(self),
        min_version: version::raised(self.min_version),
    };
    (cap, loan)
}

/// Return a loaned capability to the vault. Consumes the CapLoan hot potato.
public fun return_cap<T: key + store>(self: &mut CapabilityVault, cap: T, loan: CapLoan) {
    self.check_version_mut();
    let CapLoan { cap_id, vault_id, min_version } = loan;
    version::assert_stamp_supported(min_version);
    assert!(object::id(&cap) == cap_id, ECapIdMismatch);
    assert!(object::id(self) == vault_id, EVaultIdMismatch);
    dof::add(&mut self.id, cap_id, cap);
}

// === Extract ===

/// Extract a capability from the vault permanently. Requires an active ExecutionRequest.
/// Updates registries to reflect removal.
/// Requires VAULT_EXTRACT (`proposal::assert_permitted`).
public fun extract_cap<T: key + store, P>(
    self: &mut CapabilityVault,
    cap_id: ID,
    req: &ExecutionRequest<P>,
): T {
    self.check_version_mut();
    req.check_request_version();
    assert!(self.ou_id == req.req_ou_id(), EOUIdMismatch);
    req.assert_permitted(permissions::vault_extract());
    deregister_cap<T>(self, cap_id);
    dof::remove(&mut self.id, cap_id)
}

/// Extract a capability using SubOUControl (controller reclaim).
/// Asserts that `control.subou_id == vault.ou_id`. Package-only: whether
/// `control` is the SubOU's registered controller can only be checked against
/// the OU, so callers go through `controller::privileged_extract`.
public(package) fun privileged_extract<T: key + store>(
    self: &mut CapabilityVault,
    cap_id: ID,
    control: &SubOUControl,
): T {
    self.check_version_mut();
    assert!(control.subou_id == self.ou_id, ENotController);
    deregister_cap<T>(self, cap_id);
    dof::remove(&mut self.id, cap_id)
}

/// Create a SubOUControl for `subou_id` and store it in this vault.
/// Returns the ID of the newly created control token.
/// Authorized by ExecutionRequest — only callable within a governance-approved PTB.
/// Package-only: `subou_id` is not checked, so the only caller is CreateSubOU,
/// which passes the SubOU it has just created.
/// Requires VAULT_EXTRACT (`proposal::assert_permitted`).
public(package) fun create_subou_control<P>(
    self: &mut CapabilityVault,
    subou_id: ID,
    req: &ExecutionRequest<P>,
    ctx: &mut TxContext,
): ID {
    self.check_version_mut();
    req.check_request_version();
    assert!(self.ou_id == req.req_ou_id(), EOUIdMismatch);
    req.assert_permitted(permissions::vault_extract());
    let control = SubOUControl {
        id: object::new(ctx),
        subou_id,
    };
    let cap_id = object::id(&control);
    register_cap<SubOUControl>(self, cap_id);
    dof::add(&mut self.id, cap_id, control);
    cap_id
}

/// Extract and permanently destroy a SubOUControl from this vault.
/// Used by SpinOutSubOU to relinquish parent authority over a sub-OU.
/// Authorized by ExecutionRequest — only callable within a governance-approved PTB.
/// Requires VAULT_EXTRACT (`proposal::assert_permitted`).
public fun destroy_subou_control<P>(
    self: &mut CapabilityVault,
    cap_id: ID,
    req: &ExecutionRequest<P>,
) {
    self.check_version_mut();
    req.check_request_version();
    assert!(self.ou_id == req.req_ou_id(), EOUIdMismatch);
    req.assert_permitted(permissions::vault_extract());
    deregister_cap<SubOUControl>(self, cap_id);
    let control: SubOUControl = dof::remove(&mut self.id, cap_id);
    let SubOUControl { id, subou_id: _ } = control;
    id.delete();
}

// === SubOUControl Accessors ===

/// Returns the sub-OU ID this control token is bound to.
public fun subou_id(self: &SubOUControl): ID { self.subou_id }

/// Create a SubOUControl. Only callable within the framework package.
public(package) fun new_subou_control(subou_id: ID, ctx: &mut TxContext): SubOUControl {
    SubOUControl {
        id: object::new(ctx),
        subou_id,
    }
}

/// The version floor this loan carries.
public fun loan_min_version(loan: &CapLoan): u64 { loan.min_version }

// === Test Helpers ===

#[test_only]
public fun set_min_version_for_testing(self: &mut CapabilityVault, min_version: u64) {
    self.min_version = min_version;
}

#[test_only]
/// Create a SubOUControl for testing.
public fun new_subou_control_for_testing(subou_id: ID, ctx: &mut TxContext): SubOUControl {
    SubOUControl {
        id: object::new(ctx),
        subou_id,
    }
}

#[test_only]
/// Store a capability in the vault without an ExecutionRequest. Test-only.
public fun store_cap_for_testing<T: key + store>(self: &mut CapabilityVault, cap: T) {
    store_cap_init(self, cap);
}

#[test_only]
/// Return `loan` stamped with `min_version`, e.g. `version::retired_floor_for_testing()`.
public fun cap_loan_with_min_version_for_testing(mut loan: CapLoan, min_version: u64): CapLoan {
    loan.min_version = min_version;
    loan
}

/// Returns true if the vault contains no capabilities.
public fun is_empty(self: &CapabilityVault): bool {
    self.cap_ids.is_empty()
}

/// Destroy an empty CapabilityVault. Aborts if capabilities are still stored.
public(package) fun destroy_empty(vault: CapabilityVault) {
    let CapabilityVault { id, ou_id: _, cap_types, cap_ids, ids_by_type, min_version: _ } = vault;
    assert!(cap_ids.is_empty());
    assert!(cap_types.is_empty());
    assert!(ids_by_type.is_empty());
    id.delete();
}

// === Internal ===

/// Register a capability in the type and ID tracking sets.
fun register_cap<T: key + store>(self: &mut CapabilityVault, cap_id: ID) {
    let type_name = std::type_name::with_defining_ids<T>().into_string();
    self.cap_ids.insert(cap_id);
    if (!self.cap_types.contains(&type_name)) {
        self.cap_types.insert(type_name);
        self.ids_by_type.insert(type_name, vector[cap_id]);
    } else {
        self.ids_by_type.get_mut(&type_name).push_back(cap_id);
    };
}

/// Deregister a capability from the type and ID tracking sets.
fun deregister_cap<T: key + store>(self: &mut CapabilityVault, cap_id: ID) {
    let type_name = std::type_name::with_defining_ids<T>().into_string();
    self.cap_ids.remove(&cap_id);
    let ids = self.ids_by_type.get_mut(&type_name);
    let (found, idx) = ids.index_of(&cap_id);
    assert!(found);
    ids.swap_remove(idx);
    let is_empty = ids.is_empty();
    if (is_empty) {
        self.cap_types.remove(&type_name);
        let (_, _) = self.ids_by_type.remove(&type_name);
    };
}

// === Version gate (ARMATURE-45, see `version`) ===

/// The oldest framework version allowed to act on this CapabilityVault.
public fun min_version(self: &CapabilityVault): u64 { self.min_version }

/// Raise this CapabilityVault's floor to the running release's `MIN_SUPPORTED`. Anyone
/// may call it; it never lowers the floor. Run by the sweep after a security
/// upgrade.
public fun enforce_version(self: &mut CapabilityVault) { self.check_version_mut() }

/// Abort `version::EVersionRetired` if this release is retired for `self`.
public(package) fun check_version(self: &CapabilityVault) {
    version::assert_supported(self.min_version)
}

/// `check_version`, then raise the floor to `MIN_SUPPORTED`.
public(package) fun check_version_mut(self: &mut CapabilityVault) {
    self.min_version = version::check_and_raise(object::id(self), self.min_version);
}

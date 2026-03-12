module armature::capability_vault;

use armature::proposal::ExecutionRequest;
use sui::dynamic_object_field as dof;
use sui::vec_map::{Self, VecMap};
use sui::vec_set::{Self, VecSet};

// === Errors ===

const ENotController: u64 = 0;
const ECapIdMismatch: u64 = 1;
const EVaultIdMismatch: u64 = 2;

// === Structs ===

/// Stores arbitrary capabilities as dynamic object fields.
/// Created as a shared object during DAO creation.
public struct CapabilityVault has key, store {
    id: UID,
    dao_id: ID,
    cap_types: VecSet<std::ascii::String>,
    cap_ids: VecSet<ID>,
    ids_by_type: VecMap<std::ascii::String, vector<ID>>,
}

/// Hot-potato receipt for a loaned capability. Must be consumed by `return_cap`.
public struct CapLoan {
    cap_id: ID,
    vault_id: ID,
}

/// Controller token for a sub-DAO relationship.
/// Used by parent DAOs to reclaim capabilities from child DAOs.
public struct SubDAOControl has key, store {
    id: UID,
    subdao_id: ID,
}

// === Constructor ===

/// Create a new empty CapabilityVault. Only callable within the framework package.
public(package) fun new(dao_id: ID, ctx: &mut TxContext): CapabilityVault {
    CapabilityVault {
        id: object::new(ctx),
        dao_id,
        cap_types: vec_set::empty(),
        cap_ids: vec_set::empty(),
        ids_by_type: vec_map::empty(),
    }
}

/// Share the vault as a shared object.
#[allow(lint(share_owned, custom_state_change))]
public(package) fun share(vault: CapabilityVault) {
    transfer::share_object(vault);
}

// === Accessors ===

/// Returns the DAO ID this vault belongs to.
public fun dao_id(self: &CapabilityVault): ID { self.dao_id }

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

/// Store a capability during DAO creation. No ExecutionRequest required.
/// Only callable within the framework package.
public(package) fun store_cap_init<T: key + store>(self: &mut CapabilityVault, cap: T) {
    let cap_id = object::id(&cap);
    register_cap<T>(self, cap_id);
    dof::add(&mut self.id, cap_id, cap);
}

/// Store a capability into the vault. Requires an active ExecutionRequest.
public fun store_cap<T: key + store, P>(
    self: &mut CapabilityVault,
    cap: T,
    _req: &ExecutionRequest<P>,
) {
    let cap_id = object::id(&cap);
    register_cap<T>(self, cap_id);
    dof::add(&mut self.id, cap_id, cap);
}

// === Borrow ===

/// Borrow an immutable reference to a stored capability.
public fun borrow_cap<T: key + store, P>(
    self: &CapabilityVault,
    cap_id: ID,
    _req: &ExecutionRequest<P>,
): &T {
    dof::borrow(&self.id, cap_id)
}

/// Borrow a mutable reference to a stored capability.
public fun borrow_cap_mut<T: key + store, P>(
    self: &mut CapabilityVault,
    cap_id: ID,
    _req: &ExecutionRequest<P>,
): &mut T {
    dof::borrow_mut(&mut self.id, cap_id)
}

// === Loan ===

/// Loan a capability out of the vault. Returns the capability and a hot-potato CapLoan.
/// Registries are NOT updated — the capability is considered "held" during the loan.
public fun loan_cap<T: key + store, P>(
    self: &mut CapabilityVault,
    cap_id: ID,
    _req: &ExecutionRequest<P>,
): (T, CapLoan) {
    let cap: T = dof::remove(&mut self.id, cap_id);
    let loan = CapLoan {
        cap_id,
        vault_id: object::id(self),
    };
    (cap, loan)
}

/// Return a loaned capability to the vault. Consumes the CapLoan hot potato.
public fun return_cap<T: key + store>(self: &mut CapabilityVault, cap: T, loan: CapLoan) {
    let CapLoan { cap_id, vault_id } = loan;
    assert!(object::id(&cap) == cap_id, ECapIdMismatch);
    assert!(object::id(self) == vault_id, EVaultIdMismatch);
    dof::add(&mut self.id, cap_id, cap);
}

// === Extract ===

/// Extract a capability from the vault permanently. Requires an active ExecutionRequest.
/// Updates registries to reflect removal.
public fun extract_cap<T: key + store, P>(
    self: &mut CapabilityVault,
    cap_id: ID,
    _req: &ExecutionRequest<P>,
): T {
    deregister_cap<T>(self, cap_id);
    dof::remove(&mut self.id, cap_id)
}

/// Extract a capability using SubDAOControl (controller reclaim).
/// Asserts that `control.subdao_id == vault.dao_id`.
public fun privileged_extract<T: key + store>(
    self: &mut CapabilityVault,
    cap_id: ID,
    control: &SubDAOControl,
): T {
    assert!(control.subdao_id == self.dao_id, ENotController);
    deregister_cap<T>(self, cap_id);
    dof::remove(&mut self.id, cap_id)
}

/// Create a SubDAOControl for `subdao_id` and store it in this vault.
/// Returns the ID of the newly created control token.
/// Authorized by ExecutionRequest — only callable within a governance-approved PTB.
public fun create_subdao_control<P>(
    self: &mut CapabilityVault,
    subdao_id: ID,
    _req: &ExecutionRequest<P>,
    ctx: &mut TxContext,
): ID {
    let control = SubDAOControl {
        id: object::new(ctx),
        subdao_id,
    };
    let cap_id = object::id(&control);
    register_cap<SubDAOControl>(self, cap_id);
    dof::add(&mut self.id, cap_id, control);
    cap_id
}

/// Extract and permanently destroy a SubDAOControl from this vault.
/// Used by SpinOutSubDAO to relinquish parent authority over a sub-DAO.
/// Authorized by ExecutionRequest — only callable within a governance-approved PTB.
public fun destroy_subdao_control<P>(
    self: &mut CapabilityVault,
    cap_id: ID,
    _req: &ExecutionRequest<P>,
) {
    deregister_cap<SubDAOControl>(self, cap_id);
    let control: SubDAOControl = dof::remove(&mut self.id, cap_id);
    let SubDAOControl { id, subdao_id: _ } = control;
    id.delete();
}

// === SubDAOControl Accessors ===

/// Returns the sub-DAO ID this control token is bound to.
public fun subdao_id(self: &SubDAOControl): ID { self.subdao_id }

/// Create a SubDAOControl. Only callable within the framework package.
public(package) fun new_subdao_control(subdao_id: ID, ctx: &mut TxContext): SubDAOControl {
    SubDAOControl {
        id: object::new(ctx),
        subdao_id,
    }
}

// === Test Helpers ===

#[test_only]
/// Create a SubDAOControl for testing.
public fun new_subdao_control_for_testing(subdao_id: ID, ctx: &mut TxContext): SubDAOControl {
    SubDAOControl {
        id: object::new(ctx),
        subdao_id,
    }
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

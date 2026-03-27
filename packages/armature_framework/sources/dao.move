module armature::dao;

use armature::capability_vault;
use armature::charter;
use armature::emergency;
use armature::governance::{Self, GovernanceConfig, GovernanceTypeInit};
use armature::proposal::{Self, ExecutionRequest, ProposalConfig};
use armature::treasury_vault;
use std::option::{Self, Option};
use std::string::String;
use std::type_name;
use sui::dynamic_field as df;
use sui::event;
use sui::vec_map::{Self, VecMap};
use sui::vec_set::{Self, VecSet};

// === Errors ===

const EInvalidName: u64 = 0;
const EInvalidDescription: u64 = 1;
const EDAOIdMismatch: u64 = 2;
const ENotMigrating: u64 = 3;
const ETreasuryIdMismatch: u64 = 4;
const EVaultIdMismatch: u64 = 5;
const ECharterIdMismatch: u64 = 6;
const EFreezeIdMismatch: u64 = 7;

// === Constants ===

/// Default proposal type keys that every DAO starts with.
const DEFAULT_PROPOSAL_TYPES: vector<vector<u8>> = vector[
    b"SetBoard",
    b"CharterUpdate",
    b"EnableProposalType",
    b"DisableProposalType",
    b"UpdateProposalConfig",
    b"TransferFreezeAdmin",
    b"UnfreezeProposalType",
];

/// Proposal types blocked for SubDAOs — hierarchy-altering operations
/// reserved for independent DAOs.
const SUBDAO_BLOCKED_TYPES: vector<vector<u8>> = vector[
    b"SpawnDAO",
    b"SpinOutSubDAO",
    b"CreateSubDAO",
];

/// Proposal types that can never be disabled via DisableProposalType.
/// These are governance meta-operations and security invariants.
const UNDISABLEABLE_TYPES: vector<vector<u8>> = vector[
    b"EnableProposalType",
    b"DisableProposalType",
    b"TransferFreezeAdmin",
    b"UnfreezeProposalType",
];

/// Proposal types that may be created and executed during Migrating status.
const MIGRATION_ALLOWED_TYPES: vector<vector<u8>> = vector[b"TransferAssets"];

// Default config values: quorum=5000 (50%), threshold=5000 (50%), propose_threshold=0,
// expiry=7 days, execution_delay=0, cooldown=0
const DEFAULT_QUORUM: u16 = 5_000;
const DEFAULT_APPROVAL_THRESHOLD: u16 = 5_000;
const DEFAULT_PROPOSE_THRESHOLD: u64 = 0;
const DEFAULT_EXPIRY_MS: u64 = 604_800_000; // 7 days
const DEFAULT_EXECUTION_DELAY_MS: u64 = 0;
const DEFAULT_COOLDOWN_MS: u64 = 0;

/// Minimum approval_threshold for EnableProposalType — must be >= the 66% execution floor
/// enforced by admin_ops::execute_enable_proposal_type.
const ENABLE_PROPOSAL_TYPE_MIN_THRESHOLD: u16 = 6_600;

/// Minimum approval_threshold for UpdateProposalConfig — must be >= the 80% self-update
/// execution floor enforced by admin_ops::execute_update_proposal_config.
const UPDATE_PROPOSAL_CONFIG_MIN_THRESHOLD: u16 = 8_000;

// === Enums ===

/// DAO lifecycle status.
public enum DAOStatus has copy, drop, store {
    Active,
    Migrating { successor_dao_id: ID },
}

/// Returns true if the status is Active.
public fun is_active(self: &DAOStatus): bool {
    match (self) {
        DAOStatus::Active => true,
        _ => false,
    }
}

/// Returns true if the status is Migrating.
public fun is_migrating(self: &DAOStatus): bool {
    match (self) {
        DAOStatus::Migrating { .. } => true,
        _ => false,
    }
}

/// Returns the successor DAO ID if the status is Migrating.
public fun successor_dao_id(self: &DAOStatus): ID {
    match (self) {
        DAOStatus::Migrating { successor_dao_id } => *successor_dao_id,
        _ => abort 0,
    }
}

// === Structs ===

/// The core DAO shared object. Holds governance configuration, proposal configs,
/// enabled proposal types, and references to companion objects.
public struct DAO has key, store {
    id: UID,
    status: DAOStatus,
    governance: GovernanceConfig,
    proposal_configs: VecMap<std::ascii::String, ProposalConfig>,
    enabled_proposal_types: VecSet<std::ascii::String>,
    last_executed_at: VecMap<std::ascii::String, u64>,
    treasury_id: ID,
    capability_vault_id: ID,
    charter_id: ID,
    emergency_freeze_id: ID,
    execution_paused: bool,
    controller_cap_id: Option<ID>,
    controller_paused: bool,
}

// === Events ===

/// Emitted when a new DAO is created.
public struct DAOCreated has copy, drop {
    dao_id: ID,
    treasury_id: ID,
    capability_vault_id: ID,
    charter_id: ID,
    emergency_freeze_id: ID,
    creator: address,
}

/// Emitted when a Migrating DAO is permanently destroyed.
public struct DAODestroyed has copy, drop {
    dao_id: ID,
    successor_dao_id: ID,
}

// === Constructor ===

/// Create a new DAO with all companion objects.
/// The governance type is determined by `gov_init` and is immutable after creation.
/// All companion objects are shared. The FreezeAdminCap is transferred to the creator.
public fun create(
    gov_init: &GovernanceTypeInit,
    name: String,
    description: String,
    image_url: String,
    ctx: &mut TxContext,
): ID {
    assert!(name.length() > 0, EInvalidName);
    assert!(description.length() > 0, EInvalidDescription);

    let creator = ctx.sender();

    // Build governance config from init payload (Board only for now)
    let governance = governance::new_board(gov_init);

    // Create a placeholder DAO ID so companion objects can reference it
    let dao_uid = object::new(ctx);
    let dao_id = dao_uid.to_inner();

    // Create companion objects
    let treasury_vault = treasury_vault::new(dao_id, ctx);
    let treasury_id = object::id(&treasury_vault);

    let cap_vault = capability_vault::new(dao_id, ctx);
    let capability_vault_id = object::id(&cap_vault);

    let dao_charter = charter::new(dao_id, name, description, image_url, ctx);
    let charter_id = object::id(&dao_charter);

    let emergency_freeze = emergency::new(dao_id, ctx);
    let emergency_freeze_id = object::id(&emergency_freeze);

    let freeze_admin_cap = emergency::new_admin_cap(dao_id, ctx);

    // Build default proposal configs
    let (proposal_configs, enabled_proposal_types) = default_proposal_configs();

    // Create DAO
    let dao = DAO {
        id: dao_uid,
        status: DAOStatus::Active,
        governance,
        proposal_configs,
        enabled_proposal_types,
        last_executed_at: vec_map::empty(),
        treasury_id,
        capability_vault_id,
        charter_id,
        emergency_freeze_id,
        execution_paused: false,
        controller_cap_id: option::none(),
        controller_paused: false,
    };

    // Emit creation event
    event::emit(DAOCreated {
        dao_id,
        treasury_id,
        capability_vault_id,
        charter_id,
        emergency_freeze_id,
        creator,
    });

    // Share all objects
    transfer::share_object(dao);
    treasury_vault::share(treasury_vault);
    capability_vault::share(cap_vault);
    charter::share(dao_charter);
    emergency::share(emergency_freeze);

    // Transfer admin cap to creator
    emergency::transfer_admin_cap(freeze_admin_cap, creator);

    dao_id
}

// === Accessors ===

/// Returns the DAO's current status.
public fun status(self: &DAO): &DAOStatus { &self.status }

/// Returns the DAO's governance configuration.
public fun governance(self: &DAO): &GovernanceConfig { &self.governance }

/// Returns a mutable reference to the governance config. Package-internal only.
public(package) fun governance_mut(self: &mut DAO): &mut GovernanceConfig { &mut self.governance }

/// Returns the proposal configs map.
public fun proposal_configs(self: &DAO): &VecMap<std::ascii::String, ProposalConfig> {
    &self.proposal_configs
}

/// Returns the set of enabled proposal types.
public fun enabled_proposal_types(self: &DAO): &VecSet<std::ascii::String> {
    &self.enabled_proposal_types
}

/// Returns the treasury vault ID.
public fun treasury_id(self: &DAO): ID { self.treasury_id }

/// Returns the capability vault ID.
public fun capability_vault_id(self: &DAO): ID { self.capability_vault_id }

/// Returns the charter ID.
public fun charter_id(self: &DAO): ID { self.charter_id }

/// Returns the emergency freeze ID.
public fun emergency_freeze_id(self: &DAO): ID { self.emergency_freeze_id }

/// Returns whether proposal execution is paused on this DAO.
public fun is_execution_paused(self: &DAO): bool { self.execution_paused }

/// Returns the controller capability ID if this DAO is a SubDAO.
public fun controller_cap_id(self: &DAO): &Option<ID> { &self.controller_cap_id }

/// Returns whether the controller has paused this SubDAO's execution.
public fun is_controller_paused(self: &DAO): bool { self.controller_paused }

/// Returns the last-executed-at map (type_key → timestamp_ms).
public fun last_executed_at(self: &DAO): &VecMap<std::ascii::String, u64> {
    &self.last_executed_at
}

/// Returns the DAO's object ID.
public fun id(self: &DAO): ID { object::id(self) }

// === Public Mutators (ExecutionRequest-gated) ===

/// Replace the DAO's board members and seat count.
/// Authorized by ExecutionRequest — only callable within a governance-approved PTB.
public fun set_board_governance<P>(
    self: &mut DAO,
    new_members: vector<address>,
    req: &ExecutionRequest<P>,
) {
    assert!(self.id() == req.req_dao_id(), EDAOIdMismatch);
    self.governance.set_board(new_members);
}

/// Remove a proposal type from the enabled set and its config.
/// Authorized by ExecutionRequest — only callable within a governance-approved PTB.
public fun disable_proposal_type<P>(
    self: &mut DAO,
    type_key: std::ascii::String,
    req: &ExecutionRequest<P>,
) {
    assert!(self.id() == req.req_dao_id(), EDAOIdMismatch);
    self.enabled_proposal_types.remove(&type_key);
    self.proposal_configs.remove(&type_key);
}

/// Add a proposal type to the enabled set with a mandatory config.
/// Authorized by ExecutionRequest — only callable within a governance-approved PTB.
public fun enable_proposal_type<P>(
    self: &mut DAO,
    type_key: std::ascii::String,
    config: ProposalConfig,
    req: &ExecutionRequest<P>,
) {
    assert!(self.id() == req.req_dao_id(), EDAOIdMismatch);
    self.enabled_proposal_types.insert(type_key);
    self.proposal_configs.insert(type_key, config);
}

/// Replace the ProposalConfig for an existing proposal type.
/// Authorized by ExecutionRequest — only callable within a governance-approved PTB.
public fun update_proposal_config<P>(
    self: &mut DAO,
    type_key: std::ascii::String,
    new_config: ProposalConfig,
    req: &ExecutionRequest<P>,
) {
    assert!(self.id() == req.req_dao_id(), EDAOIdMismatch);
    let entry = self.proposal_configs.get_mut(&type_key);
    *entry = new_config;
}

/// Pause or resume proposal execution on this DAO.
/// Authorized by ExecutionRequest — only callable within a governance-approved PTB.
public fun set_execution_paused<P>(self: &mut DAO, paused: bool, req: &ExecutionRequest<P>) {
    assert!(self.id() == req.req_dao_id(), EDAOIdMismatch);
    self.execution_paused = paused;
}

/// Set or clear controller-initiated pause on this SubDAO.
/// Authorized by ExecutionRequest — only callable within a governance-approved PTB.
public fun set_controller_paused<P>(self: &mut DAO, paused: bool, req: &ExecutionRequest<P>) {
    assert!(self.id() == req.req_dao_id(), EDAOIdMismatch);
    self.controller_paused = paused;
}

/// Clear the controller relationship (for SpinOutSubDAO).
/// Resets controller_cap_id to none and controller_paused to false.
/// Authorized by ExecutionRequest — only callable within a governance-approved PTB.
public fun clear_controller<P>(self: &mut DAO, req: &ExecutionRequest<P>) {
    assert!(self.id() == req.req_dao_id(), EDAOIdMismatch);
    self.controller_cap_id = option::none();
    self.controller_paused = false;
}

/// Transition the DAO to Migrating status (irreversible).
/// Authorized by ExecutionRequest — only callable within a governance-approved PTB.
public fun set_migrating<P>(self: &mut DAO, successor_dao_id: ID, req: &ExecutionRequest<P>) {
    assert!(self.id() == req.req_dao_id(), EDAOIdMismatch);
    self.status = DAOStatus::Migrating { successor_dao_id };
}

// === ProposalTypeState ===

/// Check if type state exists for proposal type P.
public fun has_type_state<P>(self: &DAO): bool {
    df::exists_(&self.id, type_name::with_defining_ids<P>())
}

/// Borrow immutable reference to type state for proposal type P.
public fun borrow_type_state<P, S: store>(self: &DAO): &S {
    df::borrow(&self.id, type_name::with_defining_ids<P>())
}

/// Borrow mutable reference to type state. Requires ExecutionRequest for authorization.
public fun borrow_type_state_mut<P, S: store>(self: &mut DAO, req: &ExecutionRequest<P>): &mut S {
    assert!(self.id() == req.req_dao_id(), EDAOIdMismatch);
    df::borrow_mut(&mut self.id, type_name::with_defining_ids<P>())
}

/// Initialize type state for proposal type P (lazy-init on first execution).
/// Requires ExecutionRequest for authorization.
public fun init_type_state<P, S: store>(self: &mut DAO, state: S, req: &ExecutionRequest<P>) {
    assert!(self.id() == req.req_dao_id(), EDAOIdMismatch);
    df::add(&mut self.id, type_name::with_defining_ids<P>(), state);
}

/// Remove type state for proposal type P. Requires ExecutionRequest for authorization.
public fun remove_type_state<P, S: store>(self: &mut DAO, req: &ExecutionRequest<P>): S {
    assert!(self.id() == req.req_dao_id(), EDAOIdMismatch);
    df::remove(&mut self.id, type_name::with_defining_ids<P>())
}

/// Record the execution timestamp for a proposal type.
/// Called after a successful execute() to update cooldown tracking.
public(package) fun record_execution(
    self: &mut DAO,
    type_key: std::ascii::String,
    timestamp_ms: u64,
) {
    if (self.last_executed_at.contains(&type_key)) {
        let entry = self.last_executed_at.get_mut(&type_key);
        *entry = timestamp_ms;
    } else {
        self.last_executed_at.insert(type_key, timestamp_ms);
    };
}

/// Create a new SubDAO with Board governance and filtered proposal types.
/// Returns the un-shared DAO and FreezeAdminCap. The caller must set
/// controller_cap_id via `share_subdao()` before sharing.
/// Companion objects (treasury, vault, charter, emergency) are shared internally.
/// Hierarchy-altering proposal types (SpawnDAO, SpinOutSubDAO, CreateSubDAO)
/// are excluded from the SubDAO's enabled types.
public fun create_subdao(
    gov_init: &GovernanceTypeInit,
    name: String,
    description: String,
    image_url: String,
    ctx: &mut TxContext,
): (DAO, emergency::FreezeAdminCap) {
    assert!(name.length() > 0, EInvalidName);
    assert!(description.length() > 0, EInvalidDescription);

    let governance = governance::new_board(gov_init);

    let dao_uid = object::new(ctx);
    let dao_id = dao_uid.to_inner();

    let treasury_vault = treasury_vault::new(dao_id, ctx);
    let treasury_id = object::id(&treasury_vault);

    let cap_vault = capability_vault::new(dao_id, ctx);
    let capability_vault_id = object::id(&cap_vault);

    let dao_charter = charter::new(dao_id, name, description, image_url, ctx);
    let charter_id = object::id(&dao_charter);

    let emergency_freeze = emergency::new(dao_id, ctx);
    let emergency_freeze_id = object::id(&emergency_freeze);

    let freeze_admin_cap = emergency::new_admin_cap(dao_id, ctx);

    let (proposal_configs, enabled_proposal_types) = subdao_proposal_configs();

    let dao = DAO {
        id: dao_uid,
        status: DAOStatus::Active,
        governance,
        proposal_configs,
        enabled_proposal_types,
        last_executed_at: vec_map::empty(),
        treasury_id,
        capability_vault_id,
        charter_id,
        emergency_freeze_id,
        execution_paused: false,
        controller_cap_id: option::none(),
        controller_paused: false,
    };

    event::emit(DAOCreated {
        dao_id,
        treasury_id,
        capability_vault_id,
        charter_id,
        emergency_freeze_id,
        creator: ctx.sender(),
    });

    treasury_vault::share(treasury_vault);
    capability_vault::share(cap_vault);
    charter::share(dao_charter);
    emergency::share(emergency_freeze);

    (dao, freeze_admin_cap)
}

/// Share a SubDAO after setting its controller_cap_id.
/// Consumes the DAO by value — can only be called on an un-shared DAO.
public fun share_subdao(mut dao: DAO, controller_cap_id: ID) {
    dao.controller_cap_id = option::some(controller_cap_id);
    transfer::share_object(dao);
}

/// Permissionless cleanup of a Migrating DAO.
/// Destroys the DAO and all companion objects. Aborts if the DAO is not
/// in Migrating status or if the treasury/vault still hold assets.
/// The caller must pass the exact companion objects referenced by the DAO.
public fun destroy(
    dao: DAO,
    treasury: treasury_vault::TreasuryVault,
    vault: capability_vault::CapabilityVault,
    charter: charter::Charter,
    freeze: emergency::EmergencyFreeze,
) {
    assert!(dao.status.is_migrating(), ENotMigrating);
    assert!(object::id(&treasury) == dao.treasury_id, ETreasuryIdMismatch);
    assert!(object::id(&vault) == dao.capability_vault_id, EVaultIdMismatch);
    assert!(object::id(&charter) == dao.charter_id, ECharterIdMismatch);
    assert!(object::id(&freeze) == dao.emergency_freeze_id, EFreezeIdMismatch);

    let successor_dao_id = dao.status.successor_dao_id();
    let dao_id = object::id(&dao);

    // Destroy companion objects (asserts vaults are empty internally)
    treasury_vault::destroy_empty(treasury);
    capability_vault::destroy_empty(vault);
    charter::destroy(charter);
    emergency::destroy(freeze);

    // Destroy the DAO itself
    let DAO {
        id,
        status: _,
        governance: _,
        proposal_configs: _,
        enabled_proposal_types: _,
        last_executed_at: _,
        treasury_id: _,
        capability_vault_id: _,
        charter_id: _,
        emergency_freeze_id: _,
        execution_paused: _,
        controller_cap_id: _,
        controller_paused: _,
    } = dao;
    id.delete();

    event::emit(DAODestroyed { dao_id, successor_dao_id });
}

// === Type Classification Queries ===

/// Returns true if the type key is undisableable (cannot be removed via DisableProposalType).
public fun is_undisableable_type(type_key: &std::ascii::String): bool {
    let types = UNDISABLEABLE_TYPES;
    vec_contains_key(&types, type_key)
}

/// Returns true if the type key is blocked for controlled SubDAOs.
/// SubDAOs with `controller_cap_id.is_some()` cannot enable these types.
public fun is_subdao_blocked_type(type_key: &std::ascii::String): bool {
    let types = SUBDAO_BLOCKED_TYPES;
    vec_contains_key(&types, type_key)
}

/// Returns true if the type key is allowed during Migrating status.
public fun is_migration_allowed_type(type_key: &std::ascii::String): bool {
    let types = MIGRATION_ALLOWED_TYPES;
    vec_contains_key(&types, type_key)
}

/// Helper: check if a vector of byte-string constants contains the given ascii key.
fun vec_contains_key(keys: &vector<vector<u8>>, target: &std::ascii::String): bool {
    let mut i = 0;
    while (i < keys.length()) {
        if (keys[i].to_ascii_string() == *target) return true;
        i = i + 1;
    };
    false
}

// === Internal ===

/// Build the default proposal config map and enabled types set.
fun default_proposal_configs(): (
    VecMap<std::ascii::String, ProposalConfig>,
    VecSet<std::ascii::String>,
) {
    build_proposal_configs(DEFAULT_PROPOSAL_TYPES, vector[])
}

/// Build proposal configs for SubDAOs — defaults minus blocked hierarchy types.
fun subdao_proposal_configs(): (
    VecMap<std::ascii::String, ProposalConfig>,
    VecSet<std::ascii::String>,
) {
    build_proposal_configs(DEFAULT_PROPOSAL_TYPES, SUBDAO_BLOCKED_TYPES)
}

/// Return the per-type default ProposalConfig for a given type key.
/// Types with hardcoded execution floors in admin_ops use a threshold that
/// matches the floor so the config threshold is never misleadingly low.
fun config_for_type(type_key: &std::ascii::String): ProposalConfig {
    let approval_threshold = if (*type_key == b"EnableProposalType".to_ascii_string()) {
        ENABLE_PROPOSAL_TYPE_MIN_THRESHOLD
    } else if (*type_key == b"UpdateProposalConfig".to_ascii_string()) {
        UPDATE_PROPOSAL_CONFIG_MIN_THRESHOLD
    } else {
        DEFAULT_APPROVAL_THRESHOLD
    };
    proposal::new_config(
        DEFAULT_QUORUM,
        approval_threshold,
        DEFAULT_PROPOSE_THRESHOLD,
        DEFAULT_EXPIRY_MS,
        DEFAULT_EXECUTION_DELAY_MS,
        DEFAULT_COOLDOWN_MS,
    )
}

/// Build proposal config map and enabled set from a types list, excluding blocked types.
fun build_proposal_configs(
    types: vector<vector<u8>>,
    blocked: vector<vector<u8>>,
): (VecMap<std::ascii::String, ProposalConfig>, VecSet<std::ascii::String>) {
    let mut configs = vec_map::empty<std::ascii::String, ProposalConfig>();
    let mut enabled = vec_set::empty<std::ascii::String>();

    let blocked_set = {
        let mut s = vec_set::empty<std::ascii::String>();
        let mut j = 0;
        while (j < blocked.length()) {
            s.insert(blocked[j].to_ascii_string());
            j = j + 1;
        };
        s
    };

    let mut i = 0;
    while (i < types.length()) {
        let type_name = types[i].to_ascii_string();
        if (!blocked_set.contains(&type_name)) {
            configs.insert(type_name, config_for_type(&type_name));
            enabled.insert(type_name);
        };
        i = i + 1;
    };

    (configs, enabled)
}

// === Test Helpers ===

#[test_only]
/// Enable a proposal type on the DAO without an ExecutionRequest.
public fun test_enable_type(self: &mut DAO, type_key: std::ascii::String, config: ProposalConfig) {
    self.enabled_proposal_types.insert(type_key);
    self.proposal_configs.insert(type_key, config);
}

#[test_only]
/// Update the config for an already-enabled proposal type.
public fun test_update_config(
    self: &mut DAO,
    type_key: std::ascii::String,
    config: ProposalConfig,
) {
    let (_, _existing) = self.proposal_configs.remove(&type_key);
    self.proposal_configs.insert(type_key, config);
}

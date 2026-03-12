module armature::dao;

use armature::capability_vault;
use armature::charter;
use armature::emergency;
use armature::governance::{Self, GovernanceConfig, GovernanceTypeInit};
use armature::proposal::{Self, ExecutionRequest, Proposal, ProposalConfig};
use armature::treasury_vault;
use std::string::String;
use sui::clock::Clock;
use sui::event;
use sui::vec_map::{Self, VecMap};
use sui::vec_set::{Self, VecSet};

// === Errors ===

const EInvalidName: u64 = 0;
const EInvalidDescription: u64 = 1;
const EDAONotActive: u64 = 2;
const ETypeNotEnabled: u64 = 3;
const EDAOMismatch: u64 = 4;

// === Constants ===

/// Default proposal type keys that every DAO starts with.
const DEFAULT_PROPOSAL_TYPES: vector<vector<u8>> = vector[
    b"SetBoard",
    b"TreasuryWithdraw",
    b"CapabilityExtract",
    b"EmergencyFreeze",
    b"EmergencyUnfreeze",
    b"CharterUpdate",
];

// Default config values: quorum=5000 (50%), threshold=5000 (50%), propose_threshold=0,
// expiry=7 days, execution_delay=0, cooldown=0
const DEFAULT_QUORUM: u16 = 5_000;
const DEFAULT_APPROVAL_THRESHOLD: u16 = 5_000;
const DEFAULT_PROPOSE_THRESHOLD: u64 = 0;
const DEFAULT_EXPIRY_MS: u64 = 604_800_000; // 7 days
const DEFAULT_EXECUTION_DELAY_MS: u64 = 0;
const DEFAULT_COOLDOWN_MS: u64 = 0;

// === Enums ===

/// DAO lifecycle status.
public enum DAOStatus has copy, drop, store {
    Active,
    Migrating,
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
        DAOStatus::Migrating => true,
        _ => false,
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
    _req: &ExecutionRequest<P>,
) {
    self.governance.set_board(new_members);
}

/// Submit a new proposal on this DAO. Validates DAO status, type enablement,
/// and proposer eligibility before delegating to proposal::create.
#[allow(lint(share_owned, custom_state_change))]
public fun submit_proposal<P: store>(
    self: &DAO,
    type_key: std::ascii::String,
    payload: P,
    metadata_ipfs: String,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(self.status.is_active(), EDAONotActive);
    assert!(self.enabled_proposal_types.contains(&type_key), ETypeNotEnabled);
    self.governance.assert_board_member(ctx.sender());

    let config_idx = self.proposal_configs.get_idx(&type_key);
    let (_, config) = self.proposal_configs.get_entry_by_idx(config_idx);

    proposal::create(
        object::id(self),
        type_key,
        ctx.sender(),
        metadata_ipfs,
        payload,
        *config,
        &self.governance,
        clock,
        ctx,
    )
}

/// Authorize execution of a Passed proposal. Validates DAO status, dao_id match,
/// and executor eligibility, then transitions the proposal to Executed and returns
/// an ExecutionRequest hot potato for the handler to consume.
public fun authorize_execution<P: store>(
    self: &DAO,
    proposal: &mut Proposal<P>,
    clock: &Clock,
    ctx: &TxContext,
): ExecutionRequest<P> {
    assert!(self.status.is_active(), EDAONotActive);
    assert!(proposal.dao_id() == object::id(self), EDAOMismatch);
    self.governance.assert_board_member(ctx.sender());

    let type_key = proposal.type_key();
    let last_executed_at_ms = if (self.last_executed_at.contains(&type_key)) {
        option::some(*self.last_executed_at.get(&type_key))
    } else {
        option::none()
    };

    proposal::execute(proposal, &self.governance, last_executed_at_ms, clock, ctx)
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

// === Internal ===

/// Build the default proposal config map and enabled types set.
fun default_proposal_configs(): (
    VecMap<std::ascii::String, ProposalConfig>,
    VecSet<std::ascii::String>,
) {
    let default_config = proposal::new_config(
        DEFAULT_QUORUM,
        DEFAULT_APPROVAL_THRESHOLD,
        DEFAULT_PROPOSE_THRESHOLD,
        DEFAULT_EXPIRY_MS,
        DEFAULT_EXECUTION_DELAY_MS,
        DEFAULT_COOLDOWN_MS,
    );

    let mut configs = vec_map::empty<std::ascii::String, ProposalConfig>();
    let mut enabled = vec_set::empty<std::ascii::String>();

    let types = DEFAULT_PROPOSAL_TYPES;
    let mut i = 0;
    while (i < types.length()) {
        let type_name = types[i].to_ascii_string();
        configs.insert(type_name, default_config);
        enabled.insert(type_name);
        i = i + 1;
    };

    (configs, enabled)
}

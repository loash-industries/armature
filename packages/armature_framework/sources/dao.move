module armature::dao;

use armature::add_member::AddMember;
use armature::batch_add_members::BatchAddMembers;
use armature::batch_remove_members::BatchRemoveMembers;
use armature::capability_vault;
use armature::charter;
use armature::composite_payload::CompositePayload;
use armature::create_subdao::CreateSubDAO;
use armature::disable_bypass_type::DisableBypassType;
use armature::disable_proposal_type::DisableProposalType;
use armature::emergency;
use armature::enable_bypass_type::EnableBypassType;
use armature::enable_proposal_type::EnableProposalType;
use armature::governance::{Self, GovernanceConfig, GovernanceTypeInit};
use armature::proposal::{Self, ExecutionRequest, ProposalConfig};
use armature::remove_member::RemoveMember;
use armature::set_board::SetBoard;
use armature::spawn_dao::SpawnDAO;
use armature::spin_out_subdao::SpinOutSubDAO;
use armature::transfer_assets::TransferAssets;
use armature::transfer_freeze_admin::TransferFreezeAdmin;
use armature::treasury_vault;
use armature::unfreeze_proposal_type::UnfreezeProposalType;
use armature::update_metadata::UpdateMetadata;
use armature::update_proposal_config::UpdateProposalConfig;
use std::string::String;
use std::type_name::{Self, TypeName};
use sui::dynamic_field as df;
use sui::event;

// === Errors ===

const EInvalidName: u64 = 0;
const EDAOIdMismatch: u64 = 2;
const ENotMigrating: u64 = 3;
const ETreasuryIdMismatch: u64 = 4;
const EVaultIdMismatch: u64 = 5;
const ECharterIdMismatch: u64 = 6;
const EFreezeIdMismatch: u64 = 7;
const EEntriesNotEmpty: u64 = 8;
const EEntryIdNotFound: u64 = 9;
/// Attempted to add or override a blocked proposal type (hierarchy-altering or bypass-meta).
const EBlockedProposalType: u64 = 11;
/// Override sets approval_threshold below the hardcoded minimum for the type.
const EThresholdBelowMinimum: u64 = 12;
/// The proposal type has no slot on this DAO (not enabled).
const ETypeNotEnabled: u64 = 13;
/// The proposal type already has a slot on this DAO.
const ETypeAlreadyEnabled: u64 = 14;
/// Another enabled type already uses this display key.
const EDisplayKeyTaken: u64 = 15;
/// Display keys must be non-empty.
const EEmptyDisplayKey: u64 = 16;
/// Override for an already-enabled type names a display key other than the slot's.
const EDisplayKeyMismatch: u64 = 17;

// === Constants ===

// Default config values: quorum=5000 (50%), threshold=5000 (50%), propose_threshold=0,
// expiry=7 days, execution_delay=0, cooldown=0
const DEFAULT_QUORUM: u16 = 5_000;
const DEFAULT_APPROVAL_THRESHOLD: u16 = 5_000;
const DEFAULT_PROPOSE_THRESHOLD: u64 = 0;
const DEFAULT_EXPIRY_MS: u64 = 604_800_000; // 7 days
const DEFAULT_EXECUTION_DELAY_MS: u64 = 0;
const DEFAULT_COOLDOWN_MS: u64 = 0;

/// Minimum approval_threshold for EnableProposalType — matches the 66% submission-time
/// floor enforced by board_voting::submit_proposal and the config-level floor in
/// admin_ops::execute_update_proposal_config (assert_threshold_meets_floor).
const ENABLE_PROPOSAL_TYPE_MIN_THRESHOLD: u16 = 6_600;

/// Minimum approval_threshold for UpdateProposalConfig — matches the 80% submission-time
/// floor enforced by admin_ops::propose_update_proposal_config (self-targeting) and the
/// config-level floor in admin_ops::execute_update_proposal_config.
const UPDATE_PROPOSAL_CONFIG_MIN_THRESHOLD: u16 = 8_000;

/// Minimum approval_threshold for EnableBypassType — must be >= the 80% execution
/// floor enforced by external_execution::execute_enable_bypass_type.
const ENABLE_BYPASS_TYPE_MIN_THRESHOLD: u16 = 8_000;

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

/// The core DAO shared object. Holds governance configuration, lifecycle
/// flags and references to companion objects.
///
/// The proposal-type registry is NOT stored inline. Each enabled proposal
/// type is one dynamic field on `id`, keyed by `TypeSlot { name }` where
/// `name` is the canonical `TypeName` of the payload type (see `ProposalType`).
/// A second dynamic field per type, keyed by `DisplayKey`, maps the
/// human-readable display key back to the `TypeName` so cold admin paths
/// (config updates, disables, freezes) can address a type by name.
///
/// Keeping the registry out of the root keeps the root a few hundred bytes
/// regardless of how many types are enabled. Sui charges the non-refundable
/// storage fee and per-byte computation on the whole object written, so the
/// hot path (submit, execute) only ever touches the root plus one slot.
public struct DAO has key, store {
    id: UID,
    status: DAOStatus,
    governance: GovernanceConfig,
    treasury_id: ID,
    capability_vault_id: ID,
    charter_id: ID,
    emergency_freeze_id: ID,
    execution_paused: bool,
    controller_cap_id: Option<ID>,
    controller_paused: bool,
    encrypt_epoch: u64,
    entries: vector<ID>,
}

/// Dynamic-field key of a proposal-type slot. Wraps the canonical `TypeName`
/// of the payload type so slots never collide with type-state fields, which
/// are keyed by the bare `TypeName` (see `init_type_state`).
public struct TypeSlot has copy, drop, store {
    name: TypeName,
}

/// Dynamic-field key of the display-key reverse index (display key -> TypeName).
public struct DisplayKey has copy, drop, store {
    key: std::ascii::String,
}

/// Registry entry for one enabled proposal type. One dynamic field per type.
///
/// `display_key` is the human-readable label carried in events and
/// `Proposal.type_key`; it is unique per DAO but carries no authority. The
/// slot key (the Move type) is the only thing submission and execution consult,
/// so a payload of type `Q` can never be submitted under `P`'s slot.
public struct ProposalType has store {
    display_key: std::ascii::String,
    config: ProposalConfig,
    /// Timestamp of the last execution of this type, for cooldown tracking.
    last_executed_ms: Option<u64>,
}

/// Construction-time initializer for a proposal-type slot: the type to enable,
/// its display key and its config. Build one per type with `new_type_init<T>`
/// and pass a vector of them as `config_overrides` to the `*_configured`
/// constructors and `tribe::create_wired_subdao`.
public struct ProposalTypeInit has copy, drop, store {
    type_name: TypeName,
    display_key: std::ascii::String,
    config: ProposalConfig,
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

/// Emitted immediately after DAOCreated to record the initial board members.
/// Kept as a separate event so DAOCreated's layout remains stable across upgrades.
public struct DAOBoardInitialized has copy, drop {
    dao_id: ID,
    initial_members: vector<address>,
}

/// Emitted whenever a proposal-type slot is added to a DAO: at construction
/// for the default types, and on every EnableProposalType / EnableBypassType /
/// spin-out enable afterwards. `type_name` is the canonical Move type.
public struct TypeSlotAdded has copy, drop {
    dao_id: ID,
    type_name: std::ascii::String,
    display_key: std::ascii::String,
    config: ProposalConfig,
}

/// Emitted whenever a proposal-type slot is removed from a DAO.
public struct TypeSlotRemoved has copy, drop {
    dao_id: ID,
    type_name: std::ascii::String,
    display_key: std::ascii::String,
}

/// Emitted whenever a slot's config is replaced (UpdateProposalConfig or a
/// construction-time override of a default type).
public struct TypeSlotConfigUpdated has copy, drop {
    dao_id: ID,
    type_name: std::ascii::String,
    display_key: std::ascii::String,
    config: ProposalConfig,
}

/// Emitted when the encryption epoch is incremented, either automatically on
/// member removal via SetBoard or explicitly via rotate_encryption_epoch.
public struct EncryptionEpochRotated has copy, drop {
    dao_id: ID,
    old_epoch: u64,
    new_epoch: u64,
}

/// Emitted when a Migrating DAO is permanently destroyed.
public struct DAODestroyed has copy, drop {
    dao_id: ID,
    successor_dao_id: ID,
}

// === Constructors ===

/// Create a new DAO with all companion objects.
/// The governance type is determined by `gov_init` and is immutable after creation.
/// All companion objects are shared. The FreezeAdminCap is transferred to the creator.
public fun create(
    gov_init: &GovernanceTypeInit,
    name: String,
    metadata_uri: String,
    ctx: &mut TxContext,
): ID {
    let (dao, treasury, cap_vault, dao_charter, freeze, freeze_admin_cap) = build(
        gov_init,
        name,
        metadata_uri,
        false,
        vector[],
        ctx,
    );
    let dao_id = object::id(&dao);

    transfer::share_object(dao);
    treasury_vault::share(treasury);
    capability_vault::share(cap_vault);
    charter::share(dao_charter);
    emergency::share(freeze);

    emergency::transfer_admin_cap(freeze_admin_cap, ctx.sender());

    dao_id
}

/// Create a parent DAO without sharing the CapabilityVault.
/// All other companion objects are shared; the freeze admin cap is transferred
/// to the creator. Returns the dao_id and the un-shared vault so the caller
/// can populate it with SubDAOControls before sharing.
/// Only callable within the framework package.
public(package) fun create_returning_vault(
    gov_init: &GovernanceTypeInit,
    name: String,
    metadata_uri: String,
    ctx: &mut TxContext,
): (ID, capability_vault::CapabilityVault) {
    create_returning_vault_configured(gov_init, name, metadata_uri, vector[], ctx)
}

/// Like `create_returning_vault` but applies `config_overrides` over the default
/// proposal-type slots before sharing. Existing types have their config replaced;
/// types not yet enabled are inserted and enabled. No types are blocked for parent
/// DAOs — hierarchy-altering types (CreateSubDAO, SpawnDAO, etc.) are legitimately
/// part of a parent's config. Only callable within the framework package.
public(package) fun create_returning_vault_configured(
    gov_init: &GovernanceTypeInit,
    name: String,
    metadata_uri: String,
    config_overrides: vector<ProposalTypeInit>,
    ctx: &mut TxContext,
): (ID, capability_vault::CapabilityVault) {
    let (dao, treasury, cap_vault, dao_charter, freeze, freeze_admin_cap) = build(
        gov_init,
        name,
        metadata_uri,
        false,
        config_overrides,
        ctx,
    );
    let dao_id = object::id(&dao);

    transfer::share_object(dao);
    treasury_vault::share(treasury);
    charter::share(dao_charter);
    emergency::share(freeze);

    emergency::transfer_admin_cap(freeze_admin_cap, ctx.sender());

    (dao_id, cap_vault)
}

/// Like `create_subdao_returning_vault` but applies `config_overrides` over the
/// subdao default slots before construction completes. Existing types have their
/// config replaced; non-blocked types not yet enabled are inserted and enabled.
/// Blocked types abort with EBlockedProposalType. Only callable within the framework package.
public(package) fun create_subdao_returning_vault_configured(
    gov_init: &GovernanceTypeInit,
    name: String,
    metadata_uri: String,
    config_overrides: vector<ProposalTypeInit>,
    ctx: &mut TxContext,
): (DAO, emergency::FreezeAdminCap, capability_vault::CapabilityVault) {
    let (dao, treasury, cap_vault, dao_charter, freeze, freeze_admin_cap) = build(
        gov_init,
        name,
        metadata_uri,
        true,
        config_overrides,
        ctx,
    );

    treasury_vault::share(treasury);
    charter::share(dao_charter);
    emergency::share(freeze);

    (dao, freeze_admin_cap, cap_vault)
}

/// Like `create_subdao` but returns the CapabilityVault un-shared so the caller
/// can store capabilities in it before sharing. Treasury, charter, and emergency
/// freeze are shared internally; the FreezeAdminCap is returned to the caller.
/// Only callable within the framework package.
public(package) fun create_subdao_returning_vault(
    gov_init: &GovernanceTypeInit,
    name: String,
    metadata_uri: String,
    ctx: &mut TxContext,
): (DAO, emergency::FreezeAdminCap, capability_vault::CapabilityVault) {
    create_subdao_returning_vault_configured(gov_init, name, metadata_uri, vector[], ctx)
}

/// Create a new SubDAO with Board governance and filtered proposal types.
/// Returns the un-shared DAO and FreezeAdminCap. The caller must set
/// controller_cap_id via `share_subdao()` before sharing.
/// Companion objects (treasury, vault, charter, emergency) are shared internally.
/// Hierarchy-altering proposal types (SpawnDAO, SpinOutSubDAO, CreateSubDAO)
/// and the bypass meta-types are excluded from the SubDAO's default slots.
public fun create_subdao(
    gov_init: &GovernanceTypeInit,
    name: String,
    metadata_uri: String,
    ctx: &mut TxContext,
): (DAO, emergency::FreezeAdminCap) {
    create_subdao_configured(gov_init, name, metadata_uri, vector[], ctx)
}

/// Like `create_subdao` but applies `config_overrides` over the subdao default
/// slots. Existing types have their config replaced; non-blocked types not yet
/// enabled are inserted and enabled. Blocked types abort with EBlockedProposalType.
public fun create_subdao_configured(
    gov_init: &GovernanceTypeInit,
    name: String,
    metadata_uri: String,
    config_overrides: vector<ProposalTypeInit>,
    ctx: &mut TxContext,
): (DAO, emergency::FreezeAdminCap) {
    let (dao, treasury, cap_vault, dao_charter, freeze, freeze_admin_cap) = build(
        gov_init,
        name,
        metadata_uri,
        true,
        config_overrides,
        ctx,
    );

    treasury_vault::share(treasury);
    capability_vault::share(cap_vault);
    charter::share(dao_charter);
    emergency::share(freeze);

    (dao, freeze_admin_cap)
}

/// Share a SubDAO after setting its controller_cap_id.
/// Consumes the DAO by value — can only be called on an un-shared DAO.
#[allow(lint(custom_state_change, share_owned))]
public fun share_subdao(mut dao: DAO, controller_cap_id: ID) {
    dao.controller_cap_id = option::some(controller_cap_id);
    transfer::share_object(dao);
}

/// Permissionless cleanup of a Migrating DAO.
/// Destroys the DAO and all companion objects. Aborts if the DAO is not
/// in Migrating status or if the treasury/vault still hold assets.
/// The caller must pass the exact companion objects referenced by the DAO.
///
/// Proposal-type slots are dynamic fields and cannot be enumerated from Move;
/// they are left attached to the deleted UID (a few hundred bytes per type).
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
    assert!(dao.entries.is_empty(), EEntriesNotEmpty);

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
        treasury_id: _,
        capability_vault_id: _,
        charter_id: _,
        emergency_freeze_id: _,
        execution_paused: _,
        controller_cap_id: _,
        controller_paused: _,
        encrypt_epoch: _,
        entries: _,
    } = dao;
    id.delete();

    event::emit(DAODestroyed { dao_id, successor_dao_id });
}

// === Accessors ===

/// Returns the DAO's current status.
public fun status(self: &DAO): &DAOStatus { &self.status }

/// Returns the DAO's governance configuration.
public fun governance(self: &DAO): &GovernanceConfig { &self.governance }

/// Returns a mutable reference to the governance config. Package-internal only.
public(package) fun governance_mut(self: &mut DAO): &mut GovernanceConfig { &mut self.governance }

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

/// Returns the DAO's object ID.
public fun id(self: &DAO): ID { object::id(self) }

/// Returns the current encryption epoch. Increments on any board-member removal.
public fun encrypt_epoch(self: &DAO): u64 { self.encrypt_epoch }

/// Returns the on-chain index of published EncryptedEntry IDs (at most 32).
public fun entries(self: &DAO): &vector<ID> { &self.entries }

/// Returns true if addr is a current board member (encryption grantee).
/// Only valid for Board governance; aborts for Direct/Weighted.
public fun is_governance_member(self: &DAO, addr: address): bool {
    self.governance.is_board_member(addr)
}

/// Increment the encryption epoch and emit EncryptionEpochRotated.
/// Called by set_board_governance (on member removal) and by
/// encrypted_entry::rotate_encryption_epoch (explicit out-of-band rotation).
/// Emitting the event here keeps it tied to the module that defines the type.
public(package) fun increment_encrypt_epoch(self: &mut DAO) {
    let old = self.encrypt_epoch;
    self.encrypt_epoch = old + 1;
    event::emit(EncryptionEpochRotated {
        dao_id: self.id(),
        old_epoch: old,
        new_epoch: self.encrypt_epoch,
    });
}

/// Append an entry ID to the on-chain index.
/// Called by encrypted_entry::publish_entry after creating the EncryptedEntry.
public(package) fun push_entry(self: &mut DAO, entry_id: ID) {
    self.entries.push_back(entry_id);
}

/// Remove an entry ID from the on-chain index by value.
/// Called by encrypted_entry::remove_entry before deleting the EncryptedEntry.
/// Aborts if the ID is absent — index divergence would corrupt the cap count
/// and break the migration entries.is_empty() guard.
public(package) fun remove_entry_id(self: &mut DAO, target: ID) {
    let (found, idx) = self.entries.index_of(&target);
    assert!(found, EEntryIdNotFound);
    self.entries.remove(idx);
}

// === Proposal-type registry: reads ===

/// Canonical registry identity of payload type `P` (defining-package ids, so it
/// is stable across upgrades of the package that defines `P`).
public fun type_name_of<P>(): TypeName { type_name::with_defining_ids<P>() }

/// Returns true if proposal type `P` has a slot on this DAO.
public fun is_type_enabled<P>(self: &DAO): bool {
    self.is_type_name_enabled(&type_name_of<P>())
}

/// Returns true if the proposal type named `name` has a slot on this DAO.
public fun is_type_name_enabled(self: &DAO, name: &TypeName): bool {
    df::exists(&self.id, TypeSlot { name: *name })
}

/// Returns the ProposalConfig of type `P`. Aborts with ETypeNotEnabled if absent.
public fun type_config<P>(self: &DAO): ProposalConfig {
    self.type_config_by_name(&type_name_of<P>())
}

/// Returns the ProposalConfig of the type named `name`. Aborts with ETypeNotEnabled if absent.
public fun type_config_by_name(self: &DAO, name: &TypeName): ProposalConfig {
    self.slot(name).config
}

/// Returns the display key of type `P`. Aborts with ETypeNotEnabled if absent.
public fun type_display_key<P>(self: &DAO): std::ascii::String {
    self.type_display_key_by_name(&type_name_of<P>())
}

/// Returns the display key of the type named `name`. Aborts with ETypeNotEnabled if absent.
public fun type_display_key_by_name(self: &DAO, name: &TypeName): std::ascii::String {
    self.slot(name).display_key
}

/// Returns the last execution timestamp of type `P`, if it has ever executed.
/// Aborts with ETypeNotEnabled if the type has no slot.
public fun last_executed_ms<P>(self: &DAO): Option<u64> {
    self.last_executed_ms_by_name(&type_name_of<P>())
}

/// Returns the last execution timestamp of the type named `name`, if any.
/// Aborts with ETypeNotEnabled if the type has no slot.
public fun last_executed_ms_by_name(self: &DAO, name: &TypeName): Option<u64> {
    self.slot(name).last_executed_ms
}

/// Resolve a display key to the enabled type that carries it, if any.
/// This is the only string-addressed lookup in the registry and is meant for
/// cold admin paths (config updates, disables) where a human names the type.
public fun type_for_display_key(self: &DAO, key: &std::ascii::String): Option<TypeName> {
    if (df::exists(&self.id, DisplayKey { key: *key })) {
        option::some(*df::borrow(&self.id, DisplayKey { key: *key }))
    } else {
        option::none()
    }
}

// === Proposal-type registry: ProposalTypeInit ===

/// Build a slot initializer for type `T`.
public fun new_type_init<T>(
    display_key: std::ascii::String,
    config: ProposalConfig,
): ProposalTypeInit {
    ProposalTypeInit { type_name: type_name_of<T>(), display_key, config }
}

public fun init_type_name(self: &ProposalTypeInit): TypeName { self.type_name }

public fun init_display_key(self: &ProposalTypeInit): std::ascii::String { self.display_key }

public fun init_config(self: &ProposalTypeInit): &ProposalConfig { &self.config }

// === Public Mutators (ExecutionRequest-gated) ===

/// Replace the DAO's board members and seat count.
/// Authorized by ExecutionRequest — only callable within a governance-approved PTB.
/// Auto-increments encrypt_epoch if any member was removed, providing forward security.
public fun set_board_governance<P>(
    self: &mut DAO,
    new_members: vector<address>,
    req: &ExecutionRequest<P>,
) {
    assert!(self.id() == req.req_dao_id(), EDAOIdMismatch);
    let old_members = *self.governance.board_members().keys();
    self.governance.set_board(new_members);
    if (any_member_removed(&old_members, &new_members)) {
        self.increment_encrypt_epoch();
    };
}

/// Add a single member to the DAO's board.
/// Authorized by ExecutionRequest — only callable within a governance-approved PTB.
public fun add_board_member_governance<P>(
    self: &mut DAO,
    member: address,
    req: &ExecutionRequest<P>,
) {
    assert!(self.id() == req.req_dao_id(), EDAOIdMismatch);
    self.governance.add_board_member(member);
}

/// Add multiple members to the DAO's board, skipping any address already
/// present. Returns (added, skipped) in input order.
///
/// IMPORTANT: This diverges from `add_board_member_governance`, which aborts
/// on duplicates. The batch variant prefers ergonomics over symmetry because
/// its primary use case (bulk migration / large rosters) routinely contains
/// addresses the officer board did not realize were already on the board —
/// aborting the entire batch would force re-curation and re-vote for a
/// benign condition. Internal duplicates within `new_members` (the same
/// address listed twice in the input) still abort: that is proposer error
/// with no plausible benign reading.
///
/// Callers MUST surface `skipped` in any event they emit so the on-chain
/// audit trail reflects actual state changes, not just proposer intent.
///
/// Authorized by ExecutionRequest — only callable within a governance-approved PTB.
public fun add_board_members_governance<P>(
    self: &mut DAO,
    new_members: vector<address>,
    req: &ExecutionRequest<P>,
): (vector<address>, vector<address>) {
    assert!(self.id() == req.req_dao_id(), EDAOIdMismatch);
    self.governance.add_board_members(new_members)
}

/// Remove a single member from the DAO's board.
/// Authorized by ExecutionRequest — only callable within a governance-approved PTB.
/// Auto-increments encrypt_epoch for forward security.
public fun remove_board_member_governance<P>(
    self: &mut DAO,
    member: address,
    req: &ExecutionRequest<P>,
) {
    assert!(self.id() == req.req_dao_id(), EDAOIdMismatch);
    self.governance.remove_board_member(member);
    self.increment_encrypt_epoch();
}

/// Remove multiple members from the DAO's board atomically.
/// Authorized by ExecutionRequest — only callable within a governance-approved PTB.
/// Auto-increments encrypt_epoch once for the batch.
public fun remove_board_members_governance<P>(
    self: &mut DAO,
    members: vector<address>,
    req: &ExecutionRequest<P>,
): vector<address> {
    assert!(self.id() == req.req_dao_id(), EDAOIdMismatch);
    let removed = self.governance.remove_board_members(members);
    self.increment_encrypt_epoch();
    removed
}

/// Enable proposal type `NewType` with a display key and config.
/// Aborts if `NewType` already has a slot or the display key is taken.
/// Authorized by ExecutionRequest — only callable within a governance-approved PTB.
public fun enable_proposal_type<NewType, P>(
    self: &mut DAO,
    display_key: std::ascii::String,
    config: ProposalConfig,
    req: &ExecutionRequest<P>,
) {
    assert!(self.id() == req.req_dao_id(), EDAOIdMismatch);
    let dao_id = self.id();
    add_slot(&mut self.id, dao_id, new_type_init<NewType>(display_key, config));
}

/// Remove the slot (config, display key, cooldown state) of the type named `name`.
/// Aborts with ETypeNotEnabled if absent. Nothing is left behind.
///
/// Cooldown state is not preserved: if the type is re-enabled later, its first
/// execution is not subject to the cooldown. Re-enabling requires an
/// EnableProposalType (66% floor) or EnableBypassType (80% floor) vote.
/// Authorized by ExecutionRequest — only callable within a governance-approved PTB.
public fun disable_proposal_type<P>(self: &mut DAO, name: TypeName, req: &ExecutionRequest<P>) {
    assert!(self.id() == req.req_dao_id(), EDAOIdMismatch);
    let dao_id = self.id();
    remove_slot(&mut self.id, dao_id, name);
}

/// Replace the ProposalConfig of the type named `name`.
/// Aborts with ETypeNotEnabled if absent.
/// Authorized by ExecutionRequest — only callable within a governance-approved PTB.
public fun update_proposal_config<P>(
    self: &mut DAO,
    name: TypeName,
    new_config: ProposalConfig,
    req: &ExecutionRequest<P>,
) {
    assert!(self.id() == req.req_dao_id(), EDAOIdMismatch);
    let dao_id = self.id();
    let entry = self.slot_mut(&name);
    entry.config = new_config;
    event::emit(TypeSlotConfigUpdated {
        dao_id,
        type_name: name.into_string(),
        display_key: entry.display_key,
        config: new_config,
    });
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
    df::exists(&self.id, type_name::with_defining_ids<P>())
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

/// Record the execution timestamp for the type named `name`.
/// Called after a successful execute() to update cooldown tracking.
/// Aborts with ETypeNotEnabled if the type has no slot.
public(package) fun record_execution(self: &mut DAO, name: TypeName, timestamp_ms: u64) {
    self.slot_mut(&name).last_executed_ms = option::some(timestamp_ms);
}

// === Type Classification Queries ===

/// Returns true if the type is undisableable (cannot be removed via DisableProposalType).
/// These are governance meta-operations and security invariants.
public fun is_undisableable_type(name: &TypeName): bool {
    let n = *name;
    n == type_name_of<EnableProposalType>()
        || n == type_name_of<EnableBypassType>()
        || n == type_name_of<DisableBypassType>()
        || n == type_name_of<DisableProposalType>()
        || n == type_name_of<TransferFreezeAdmin>()
        || n == type_name_of<UnfreezeProposalType>()
}

/// Returns true if the type is blocked for controlled SubDAOs: hierarchy-altering
/// operations reserved for independent DAOs, plus bypass-meta types that would let
/// a SubDAO autonomously escalate its own execution privileges.
/// SubDAOs with `controller_cap_id.is_some()` cannot enable these types.
public fun is_subdao_blocked_type(name: &TypeName): bool {
    let n = *name;
    n == type_name_of<SpawnDAO>()
        || n == type_name_of<SpinOutSubDAO>()
        || n == type_name_of<CreateSubDAO>()
        || n == type_name_of<EnableBypassType>()
        || n == type_name_of<DisableBypassType>()
}

/// Returns true if the type may be created and executed during Migrating status.
public fun is_migration_allowed_type(name: &TypeName): bool {
    *name == type_name_of<TransferAssets>()
}

/// Return the hardcoded minimum approval_threshold for a type, or 0 if no floor applies.
/// This is the single source of truth consumed by both config_for_type and
/// apply_type_overrides so the two cannot drift apart.
public fun min_approval_threshold_for_type(name: &TypeName): u16 {
    let n = *name;
    if (n == type_name_of<EnableProposalType>()) {
        ENABLE_PROPOSAL_TYPE_MIN_THRESHOLD
    } else if (n == type_name_of<UpdateProposalConfig>()) {
        UPDATE_PROPOSAL_CONFIG_MIN_THRESHOLD
    } else if (n == type_name_of<EnableBypassType>()) {
        ENABLE_BYPASS_TYPE_MIN_THRESHOLD
    } else {
        0u16
    }
}

/// Returns true if any address in old_members is absent from new_members.
/// Used by set_board_governance to detect member removals for epoch auto-rotation.
fun any_member_removed(old_members: &vector<address>, new_members: &vector<address>): bool {
    let mut i = 0;
    while (i < old_members.length()) {
        let old = old_members[i];
        let mut found = false;
        let mut j = 0;
        while (j < new_members.length()) {
            if (new_members[j] == old) { found = true };
            j = j + 1;
        };
        if (!found) return true;
        i = i + 1;
    };
    false
}

// === Internal: construction ===

/// Build a DAO and its companion objects, seed the default proposal-type slots
/// and apply `overrides`. Nothing is shared here; each public constructor
/// decides what to share and what to return.
fun build(
    gov_init: &GovernanceTypeInit,
    name: String,
    metadata_uri: String,
    is_subdao: bool,
    overrides: vector<ProposalTypeInit>,
    ctx: &mut TxContext,
): (
    DAO,
    treasury_vault::TreasuryVault,
    capability_vault::CapabilityVault,
    charter::Charter,
    emergency::EmergencyFreeze,
    emergency::FreezeAdminCap,
) {
    assert!(name.length() > 0, EInvalidName);

    let creator = ctx.sender();

    // Build governance config from init payload (Board only for now)
    let governance = governance::new_board(gov_init);
    let initial_members = governance.board_member_vec();

    // Create a placeholder DAO ID so companion objects can reference it
    let dao_uid = object::new(ctx);
    let dao_id = dao_uid.to_inner();

    // Create companion objects
    let treasury = treasury_vault::new(dao_id, ctx);
    let treasury_id = object::id(&treasury);

    let cap_vault = capability_vault::new(dao_id, ctx);
    let capability_vault_id = object::id(&cap_vault);

    let dao_charter = charter::new(dao_id, name, metadata_uri, ctx);
    let charter_id = object::id(&dao_charter);

    let freeze = emergency::new(dao_id, ctx);
    let emergency_freeze_id = object::id(&freeze);

    let freeze_admin_cap = emergency::new_admin_cap(dao_id, ctx);

    let mut dao = DAO {
        id: dao_uid,
        status: DAOStatus::Active,
        governance,
        treasury_id,
        capability_vault_id,
        charter_id,
        emergency_freeze_id,
        execution_paused: false,
        controller_cap_id: option::none(),
        controller_paused: false,
        encrypt_epoch: 0,
        entries: vector[],
    };

    event::emit(DAOCreated {
        dao_id,
        treasury_id,
        capability_vault_id,
        charter_id,
        emergency_freeze_id,
        creator,
    });
    event::emit(DAOBoardInitialized { dao_id, initial_members });

    // Seed the registry: defaults first, then construction-time overrides.
    let defaults = default_type_inits(is_subdao);
    let mut i = 0;
    while (i < defaults.length()) {
        add_slot(&mut dao.id, dao_id, defaults[i]);
        i = i + 1;
    };
    apply_type_overrides(&mut dao.id, dao_id, overrides, is_subdao);

    (dao, treasury, cap_vault, dao_charter, freeze, freeze_admin_cap)
}

/// Default proposal-type slots every DAO starts with. SubDAOs omit the bypass
/// meta-types (they are SubDAO-blocked).
fun default_type_inits(is_subdao: bool): vector<ProposalTypeInit> {
    let mut v = vector[
        default_init<SetBoard>(b"SetBoard"),
        default_init<AddMember>(b"AddMember"),
        default_init<RemoveMember>(b"RemoveMember"),
        default_init<BatchAddMembers>(b"BatchAddMembers"),
        default_init<BatchRemoveMembers>(b"BatchRemoveMembers"),
        default_init<UpdateMetadata>(b"CharterUpdate"),
        default_init<EnableProposalType>(b"EnableProposalType"),
    ];
    if (!is_subdao) {
        v.push_back(default_init<EnableBypassType>(b"EnableBypassType"));
        v.push_back(default_init<DisableBypassType>(b"DisableBypassType"));
    };
    v.push_back(default_init<DisableProposalType>(b"DisableProposalType"));
    v.push_back(default_init<UpdateProposalConfig>(b"UpdateProposalConfig"));
    v.push_back(default_init<TransferFreezeAdmin>(b"TransferFreezeAdmin"));
    v.push_back(default_init<UnfreezeProposalType>(b"UnfreezeProposalType"));
    v.push_back(default_init<CompositePayload>(b"Composite"));
    v
}

fun default_init<T>(display_key: vector<u8>): ProposalTypeInit {
    let name = type_name_of<T>();
    ProposalTypeInit {
        type_name: name,
        display_key: display_key.to_ascii_string(),
        config: config_for_type(&name),
    }
}

/// Return the per-type default ProposalConfig for a given type.
/// Types with hardcoded execution floors in admin_ops use a threshold that
/// matches the floor so the config threshold is never misleadingly low.
/// composable_allowed is true for single-operation types that make sense as steps
/// inside a CompositeFrame. Batch types (BatchAddMembers, BatchRemoveMembers) are
/// excluded: they have no _step handler variant and BatchAddMembers carries an
/// explicit regression test guarding its deny-by-default status.
fun config_for_type(name: &TypeName): ProposalConfig {
    let min = min_approval_threshold_for_type(name);
    let approval_threshold = if (min > 0) { min } else { DEFAULT_APPROVAL_THRESHOLD };
    let n = *name;
    let composable =
        n == type_name_of<AddMember>()
        || n == type_name_of<RemoveMember>()
        || n == type_name_of<SetBoard>()
        || n == type_name_of<UpdateMetadata>()
        || n == type_name_of<EnableProposalType>();
    proposal::new_config(
        DEFAULT_QUORUM,
        approval_threshold,
        DEFAULT_PROPOSE_THRESHOLD,
        DEFAULT_EXPIRY_MS,
        DEFAULT_EXECUTION_DELAY_MS,
        DEFAULT_COOLDOWN_MS,
    ).with_composable_allowed(composable)
}

/// Apply `overrides` to an already-seeded registry.
/// - Type already enabled: replace its ProposalConfig, preserving composable_allowed.
///   The override's display key must equal the slot's (EDisplayKeyMismatch otherwise);
///   default display keys cannot be renamed at construction time.
/// - Type not yet enabled: add its slot (enables the type at construction time).
/// - Type is a SubDAO-blocked type AND `check_subdao_blocked` is true: abort with
///   EBlockedProposalType. Pass false for parent DAOs, which legitimately have these
///   types (e.g. CreateSubDAO).
/// - Config sets approval_threshold below the hardcoded minimum: abort with EThresholdBelowMinimum.
fun apply_type_overrides(
    id: &mut UID,
    dao_id: ID,
    overrides: vector<ProposalTypeInit>,
    check_subdao_blocked: bool,
) {
    let mut i = 0;
    while (i < overrides.length()) {
        let init = overrides[i];
        assert!(
            !check_subdao_blocked || !is_subdao_blocked_type(&init.type_name),
            EBlockedProposalType,
        );
        let floor = min_approval_threshold_for_type(&init.type_name);
        assert!(init.config.approval_threshold() >= floor, EThresholdBelowMinimum);
        if (df::exists(id, TypeSlot { name: init.type_name })) {
            let entry: &mut ProposalType = df::borrow_mut(id, TypeSlot { name: init.type_name });
            assert!(entry.display_key == init.display_key, EDisplayKeyMismatch);
            let composable = entry.config.composable_allowed();
            entry.config = init.config.with_composable_allowed(composable);
            event::emit(TypeSlotConfigUpdated {
                dao_id,
                type_name: init.type_name.into_string(),
                display_key: entry.display_key,
                config: entry.config,
            });
        } else {
            add_slot(id, dao_id, init);
        };
        i = i + 1;
    };
}

// === Internal: registry ===

fun add_slot(id: &mut UID, dao_id: ID, init: ProposalTypeInit) {
    let ProposalTypeInit { type_name, display_key, config } = init;
    assert!(display_key.length() > 0, EEmptyDisplayKey);
    assert!(!df::exists(id, TypeSlot { name: type_name }), ETypeAlreadyEnabled);
    assert!(!df::exists(id, DisplayKey { key: display_key }), EDisplayKeyTaken);
    df::add(
        id,
        TypeSlot { name: type_name },
        ProposalType { display_key, config, last_executed_ms: option::none() },
    );
    df::add(id, DisplayKey { key: display_key }, type_name);
    event::emit(TypeSlotAdded {
        dao_id,
        type_name: type_name.into_string(),
        display_key,
        config,
    });
}

fun remove_slot(id: &mut UID, dao_id: ID, name: TypeName) {
    assert!(df::exists(id, TypeSlot { name }), ETypeNotEnabled);
    let ProposalType { display_key, config: _, last_executed_ms: _ } = df::remove(
        id,
        TypeSlot { name },
    );
    let _: TypeName = df::remove(id, DisplayKey { key: display_key });
    event::emit(TypeSlotRemoved { dao_id, type_name: name.into_string(), display_key });
}

fun slot(self: &DAO, name: &TypeName): &ProposalType {
    assert!(df::exists(&self.id, TypeSlot { name: *name }), ETypeNotEnabled);
    df::borrow(&self.id, TypeSlot { name: *name })
}

fun slot_mut(self: &mut DAO, name: &TypeName): &mut ProposalType {
    assert!(df::exists(&self.id, TypeSlot { name: *name }), ETypeNotEnabled);
    df::borrow_mut(&mut self.id, TypeSlot { name: *name })
}

// === Test Helpers ===

#[test_only]
/// Enable proposal type `T` on the DAO without an ExecutionRequest.
public fun test_enable_type<T>(
    self: &mut DAO,
    display_key: std::ascii::String,
    config: ProposalConfig,
) {
    let dao_id = self.id();
    add_slot(&mut self.id, dao_id, new_type_init<T>(display_key, config));
}

#[test_only]
/// Replace the config of an already-enabled proposal type `T`.
public fun test_update_config<T>(self: &mut DAO, config: ProposalConfig) {
    let name = type_name_of<T>();
    self.slot_mut(&name).config = config;
}

#[test_only]
/// Disable proposal type `T` on the DAO without an ExecutionRequest.
public fun test_disable_type<T>(self: &mut DAO) {
    let dao_id = self.id();
    remove_slot(&mut self.id, dao_id, type_name_of<T>());
}

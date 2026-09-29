module armature::ou;

use armature::add_member::AddMember;
use armature::batch_add_members::BatchAddMembers;
use armature::batch_remove_members::BatchRemoveMembers;
use armature::capability_vault;
use armature::charter;
use armature::composite_payload::CompositePayload;
use armature::create_subou::CreateSubOU;
use armature::disable_bypass_type::DisableBypassType;
use armature::disable_proposal_type::DisableProposalType;
use armature::emergency;
use armature::enable_bypass_type::EnableBypassType;
use armature::enable_proposal_type::EnableProposalType;
use armature::governance::{Self, GovernanceConfig, GovernanceTypeInit};
use armature::permissions;
use armature::proposal::{Self, ExecutionRequest, ProposalConfig};
use armature::remove_member::RemoveMember;
use armature::set_board::SetBoard;
use armature::spawn_ou::SpawnOU;
use armature::spin_out_subou::SpinOutSubOU;
use armature::transfer_assets::TransferAssets;
use armature::transfer_freeze_admin::TransferFreezeAdmin;
use armature::treasury_vault;
use armature::unfreeze_proposal_type::UnfreezeProposalType;
use armature::update_freeze_config::UpdateFreezeConfig;
use armature::update_freeze_exempt_types::UpdateFreezeExemptTypes;
use armature::update_metadata::UpdateMetadata;
use armature::update_proposal_config::UpdateProposalConfig;
use std::string::String;
use std::type_name::{Self, TypeName};
use sui::dynamic_field as df;
use sui::event;

// === Errors ===

const EInvalidName: u64 = 0;
const EOUIdMismatch: u64 = 2;
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
/// The proposal type has no slot on this OU (not enabled).
const ETypeNotEnabled: u64 = 13;
/// The proposal type already has a slot on this OU.
const ETypeAlreadyEnabled: u64 = 14;
/// Another enabled type already uses this display key.
const EDisplayKeyTaken: u64 = 15;
/// Display keys must be non-empty.
const EEmptyDisplayKey: u64 = 16;
/// Override for an already-enabled type names a display key other than the slot's.
const EDisplayKeyMismatch: u64 = 17;
// 18 is unused: permission denials abort with proposal::EPermissionDenied.
/// A config change would alter a type's permission bits, but the request is
/// not EnableProposalType, EnableBypassType or UpdateProposalConfig.
const EPermissionChangeNotAllowed: u64 = 19;
// 20 is unused: a meta-type changing its own bits is ruled out by
// EFixedPermissions, since every meta-type is a framework type.
/// The bits being granted need a higher approval floor than the granting
/// meta-type's vote is held to.
const EGrantFloorNotMet: u64 = 21;
// 22 is unused: CompositePayload's fixed bits are 0 (EFixedPermissions).
/// A config for a framework type names bits other than its fixed set
/// (`framework_permissions`).
const EFixedPermissions: u64 = 23;
/// A controller-only mutator was called with an unprivileged request.
const ENotPrivileged: u64 = 24;
/// An EnableBypassType config whose quorum × approval_threshold is below
/// ENABLE_BYPASS_TYPE_MIN_THRESHOLD × 100%: a vote could pass on it yet fail
/// the execution-time floor on the whole board's weight.
const EBypassQuorumTooLow: u64 = 25;
/// An EnableProposalType config whose quorum × approval_threshold is below
/// ENABLE_PROPOSAL_TYPE_MIN_THRESHOLD × 100%: a minority of the board could
/// pass it and enable a type with high-impact bits.
const EEnableQuorumTooLow: u64 = 26;
/// An UpdateProposalConfig config whose quorum × approval_threshold is below
/// UPDATE_PROPOSAL_CONFIG_MIN_THRESHOLD × 100%: a minority of the board could
/// pass it and make any enabled type single-vote.
const EUpdateConfigQuorumTooLow: u64 = 27;

// === Constants ===

// Default config values: quorum=5000 (50%), threshold=5000 (50%), propose_threshold=0,
// expiry=7 days, execution_delay=0, cooldown=0
const DEFAULT_QUORUM: u16 = 5_000;
const DEFAULT_APPROVAL_THRESHOLD: u16 = 5_000;
const DEFAULT_PROPOSE_THRESHOLD: u64 = 0;
const DEFAULT_EXPIRY_MS: u64 = 604_800_000; // 7 days
const DEFAULT_EXECUTION_DELAY_MS: u64 = 0;
const DEFAULT_COOLDOWN_MS: u64 = 0;

/// Minimum approval_threshold for EnableProposalType — matches the 80% submission-time
/// floor enforced by board_voting::submit_proposal. EnableProposalType holds
/// TYPE_ADMIN and may grant high-impact bits, so it sits at the 80% floor.
const ENABLE_PROPOSAL_TYPE_MIN_THRESHOLD: u16 = 8_000;

/// Minimum approval_threshold for UpdateProposalConfig — enforced on every stored
/// config by `assert_config_floors`, and at submission by
/// admin_ops::propose_update_proposal_config (self-targeting).
const UPDATE_PROPOSAL_CONFIG_MIN_THRESHOLD: u16 = 8_000;

/// Minimum approval_threshold for EnableBypassType — must be >= the 80% execution
/// floor enforced by external_execution::execute_enable_bypass_type.
const ENABLE_BYPASS_TYPE_MIN_THRESHOLD: u16 = 8_000;

/// Default quorum and approval_threshold for the whole-board types
/// (EnableBypassType, EnableProposalType, UpdateProposalConfig). quorum ×
/// threshold = 80% of the board, the least `assert_config_floors` accepts:
/// the proposal passes once 80% of the board has voted, all YES, without
/// waiting on the rest. Trade-off: with a 100% threshold, a single NO vote
/// means the proposal can never pass; it expires and must be resubmitted.
const WHOLE_BOARD_DEFAULT_QUORUM: u16 = 8_000;
const WHOLE_BOARD_DEFAULT_APPROVAL_THRESHOLD: u16 = 10_000;

/// Minimum approval_threshold for a config holding any high-impact bit
/// (TYPE_ADMIN, MIGRATE, TREASURY_WITHDRAW, VAULT_BORROW, VAULT_EXTRACT).
/// Same as the EnableBypassType floor.
const HIGH_PERMISSION_MIN_THRESHOLD: u16 = 8_000;

// === Enums ===

/// OU lifecycle status.
public enum OUStatus has copy, drop, store {
    Active,
    Migrating { successor_ou_id: ID },
}

/// Returns true if the status is Active.
public fun is_active(self: &OUStatus): bool {
    match (self) {
        OUStatus::Active => true,
        _ => false,
    }
}

/// Returns true if the status is Migrating.
public fun is_migrating(self: &OUStatus): bool {
    match (self) {
        OUStatus::Migrating { .. } => true,
        _ => false,
    }
}

/// Returns the successor OU ID if the status is Migrating.
public fun successor_ou_id(self: &OUStatus): ID {
    match (self) {
        OUStatus::Migrating { successor_ou_id } => *successor_ou_id,
        _ => abort 0,
    }
}

// === Structs ===

/// The core OU shared object. Holds governance configuration, lifecycle
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
public struct OU has key, store {
    id: UID,
    status: OUStatus,
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
/// `Proposal.type_key`; it is unique per OU but carries no authority. The
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
/// constructors and `tribe::create_wired_subou`.
public struct ProposalTypeInit has copy, drop, store {
    type_name: TypeName,
    display_key: std::ascii::String,
    config: ProposalConfig,
}

// === Events ===

/// Emitted when a new OU is created.
public struct OUCreated has copy, drop {
    ou_id: ID,
    treasury_id: ID,
    capability_vault_id: ID,
    charter_id: ID,
    emergency_freeze_id: ID,
    creator: address,
}

/// Emitted immediately after OUCreated to record the initial board members.
/// Kept as a separate event so OUCreated's layout remains stable across upgrades.
public struct OUBoardInitialized has copy, drop {
    ou_id: ID,
    initial_members: vector<address>,
}

/// Emitted whenever a proposal-type slot is added to an OU: at construction
/// for the default types, and on every EnableProposalType / EnableBypassType /
/// spin-out enable afterwards. `type_name` is the canonical Move type.
public struct TypeSlotAdded has copy, drop {
    ou_id: ID,
    type_name: std::ascii::String,
    display_key: std::ascii::String,
    config: ProposalConfig,
}

/// Emitted whenever a proposal-type slot is removed from an OU.
public struct TypeSlotRemoved has copy, drop {
    ou_id: ID,
    type_name: std::ascii::String,
    display_key: std::ascii::String,
}

/// Emitted whenever a slot's config is replaced (UpdateProposalConfig or a
/// construction-time override of a default type).
public struct TypeSlotConfigUpdated has copy, drop {
    ou_id: ID,
    type_name: std::ascii::String,
    display_key: std::ascii::String,
    config: ProposalConfig,
}

/// Emitted when the encryption epoch is incremented, either automatically on
/// member removal via SetBoard or explicitly via rotate_encryption_epoch.
public struct EncryptionEpochRotated has copy, drop {
    ou_id: ID,
    old_epoch: u64,
    new_epoch: u64,
}

/// Emitted when a Migrating OU is permanently destroyed.
public struct OUDestroyed has copy, drop {
    ou_id: ID,
    successor_ou_id: ID,
}

// === Constructors ===

/// Create a new OU with all companion objects.
/// The governance type is determined by `gov_init` and is immutable after creation.
/// All companion objects are shared. The FreezeAdminCap is transferred to the creator.
public fun create(
    gov_init: &GovernanceTypeInit,
    name: String,
    metadata_uri: String,
    ctx: &mut TxContext,
): ID {
    let (ou, treasury, cap_vault, ou_charter, freeze, freeze_admin_cap) = build(
        gov_init,
        name,
        metadata_uri,
        false,
        vector[],
        ctx,
    );
    let ou_id = object::id(&ou);

    transfer::share_object(ou);
    treasury_vault::share(treasury);
    capability_vault::share(cap_vault);
    charter::share(ou_charter);
    emergency::share(freeze);

    emergency::transfer_admin_cap(freeze_admin_cap, ctx.sender());

    ou_id
}

/// Create a parent OU without sharing the CapabilityVault.
/// All other companion objects are shared; the freeze admin cap is transferred
/// to the creator. Returns the ou_id and the un-shared vault so the caller
/// can populate it with SubOUControls before sharing.
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
/// OUs — hierarchy-altering types (CreateSubOU, SpawnOU, etc.) are legitimately
/// part of a parent's config. Only callable within the framework package.
public(package) fun create_returning_vault_configured(
    gov_init: &GovernanceTypeInit,
    name: String,
    metadata_uri: String,
    config_overrides: vector<ProposalTypeInit>,
    ctx: &mut TxContext,
): (ID, capability_vault::CapabilityVault) {
    let (ou, treasury, cap_vault, ou_charter, freeze, freeze_admin_cap) = build(
        gov_init,
        name,
        metadata_uri,
        false,
        config_overrides,
        ctx,
    );
    let ou_id = object::id(&ou);

    transfer::share_object(ou);
    treasury_vault::share(treasury);
    charter::share(ou_charter);
    emergency::share(freeze);

    emergency::transfer_admin_cap(freeze_admin_cap, ctx.sender());

    (ou_id, cap_vault)
}

/// Like `create_subou_returning_vault` but applies `config_overrides` over the
/// subou default slots before construction completes. Existing types have their
/// config replaced; non-blocked types not yet enabled are inserted and enabled.
/// Blocked types abort with EBlockedProposalType. Only callable within the framework package.
public(package) fun create_subou_returning_vault_configured(
    gov_init: &GovernanceTypeInit,
    name: String,
    metadata_uri: String,
    config_overrides: vector<ProposalTypeInit>,
    ctx: &mut TxContext,
): (OU, emergency::FreezeAdminCap, capability_vault::CapabilityVault) {
    let (ou, treasury, cap_vault, ou_charter, freeze, freeze_admin_cap) = build(
        gov_init,
        name,
        metadata_uri,
        true,
        config_overrides,
        ctx,
    );

    treasury_vault::share(treasury);
    charter::share(ou_charter);
    emergency::share(freeze);

    (ou, freeze_admin_cap, cap_vault)
}

/// Like `create_subou` but returns the CapabilityVault un-shared so the caller
/// can store capabilities in it before sharing. Treasury, charter, and emergency
/// freeze are shared internally; the FreezeAdminCap is returned to the caller.
/// Only callable within the framework package.
public(package) fun create_subou_returning_vault(
    gov_init: &GovernanceTypeInit,
    name: String,
    metadata_uri: String,
    ctx: &mut TxContext,
): (OU, emergency::FreezeAdminCap, capability_vault::CapabilityVault) {
    create_subou_returning_vault_configured(gov_init, name, metadata_uri, vector[], ctx)
}

/// Create a new SubOU with Board governance and filtered proposal types.
/// Returns the un-shared OU and FreezeAdminCap. The caller must set
/// controller_cap_id via `share_subou()` before sharing.
/// Companion objects (treasury, vault, charter, emergency) are shared internally.
/// Hierarchy-altering proposal types (SpawnOU, SpinOutSubOU, CreateSubOU)
/// and the bypass meta-types are excluded from the SubOU's default slots.
public fun create_subou(
    gov_init: &GovernanceTypeInit,
    name: String,
    metadata_uri: String,
    ctx: &mut TxContext,
): (OU, emergency::FreezeAdminCap) {
    create_subou_configured(gov_init, name, metadata_uri, vector[], ctx)
}

/// Like `create_subou` but applies `config_overrides` over the subou default
/// slots. Existing types have their config replaced; non-blocked types not yet
/// enabled are inserted and enabled. Blocked types abort with EBlockedProposalType.
public fun create_subou_configured(
    gov_init: &GovernanceTypeInit,
    name: String,
    metadata_uri: String,
    config_overrides: vector<ProposalTypeInit>,
    ctx: &mut TxContext,
): (OU, emergency::FreezeAdminCap) {
    let (ou, treasury, cap_vault, ou_charter, freeze, freeze_admin_cap) = build(
        gov_init,
        name,
        metadata_uri,
        true,
        config_overrides,
        ctx,
    );

    treasury_vault::share(treasury);
    capability_vault::share(cap_vault);
    charter::share(ou_charter);
    emergency::share(freeze);

    (ou, freeze_admin_cap)
}

/// Share a SubOU after setting its controller_cap_id.
/// Consumes the OU by value — can only be called on an un-shared OU.
#[allow(lint(custom_state_change, share_owned))]
public fun share_subou(mut ou: OU, controller_cap_id: ID) {
    ou.controller_cap_id = option::some(controller_cap_id);
    transfer::share_object(ou);
}

/// Permissionless cleanup of a Migrating OU.
/// Destroys the OU and all companion objects. Aborts if the OU is not
/// in Migrating status or if the treasury/vault still hold assets.
/// The caller must pass the exact companion objects referenced by the OU.
///
/// Proposal-type slots are dynamic fields and cannot be enumerated from Move;
/// they are left attached to the deleted UID (a few hundred bytes per type).
public fun destroy(
    ou: OU,
    treasury: treasury_vault::TreasuryVault,
    vault: capability_vault::CapabilityVault,
    charter: charter::Charter,
    freeze: emergency::EmergencyFreeze,
) {
    assert!(ou.status.is_migrating(), ENotMigrating);
    assert!(object::id(&treasury) == ou.treasury_id, ETreasuryIdMismatch);
    assert!(object::id(&vault) == ou.capability_vault_id, EVaultIdMismatch);
    assert!(object::id(&charter) == ou.charter_id, ECharterIdMismatch);
    assert!(object::id(&freeze) == ou.emergency_freeze_id, EFreezeIdMismatch);
    assert!(ou.entries.is_empty(), EEntriesNotEmpty);

    let successor_ou_id = ou.status.successor_ou_id();
    let ou_id = object::id(&ou);

    // Destroy companion objects (asserts vaults are empty internally)
    treasury_vault::destroy_empty(treasury);
    capability_vault::destroy_empty(vault);
    charter::destroy(charter);
    emergency::destroy(freeze);

    // Destroy the OU itself
    let OU {
        id,
        status: _,
        governance,
        treasury_id: _,
        capability_vault_id: _,
        charter_id: _,
        emergency_freeze_id: _,
        execution_paused: _,
        controller_cap_id: _,
        controller_paused: _,
        encrypt_epoch: _,
        entries: _,
    } = ou;
    governance.destroy();
    id.delete();

    event::emit(OUDestroyed { ou_id, successor_ou_id });
}

// === Accessors ===

/// Returns the OU's current status.
public fun status(self: &OU): &OUStatus { &self.status }

/// Returns the OU's governance configuration.
public fun governance(self: &OU): &GovernanceConfig { &self.governance }

/// Returns a mutable reference to the governance config. Package-internal only.
public(package) fun governance_mut(self: &mut OU): &mut GovernanceConfig { &mut self.governance }

/// Returns the treasury vault ID.
public fun treasury_id(self: &OU): ID { self.treasury_id }

/// Returns the capability vault ID.
public fun capability_vault_id(self: &OU): ID { self.capability_vault_id }

/// Returns the charter ID.
public fun charter_id(self: &OU): ID { self.charter_id }

/// Returns the emergency freeze ID.
public fun emergency_freeze_id(self: &OU): ID { self.emergency_freeze_id }

/// Returns whether proposal execution is paused on this OU.
public fun is_execution_paused(self: &OU): bool { self.execution_paused }

/// Returns the controller capability ID if this OU is a SubOU.
public fun controller_cap_id(self: &OU): &Option<ID> { &self.controller_cap_id }

/// Returns whether the controller has paused this SubOU's execution.
public fun is_controller_paused(self: &OU): bool { self.controller_paused }

/// Returns the OU's object ID.
public fun id(self: &OU): ID { object::id(self) }

/// Returns the current encryption epoch. Increments on any board-member removal.
public fun encrypt_epoch(self: &OU): u64 { self.encrypt_epoch }

/// Returns the on-chain index of published EncryptedEntry IDs (at most 32).
public fun entries(self: &OU): &vector<ID> { &self.entries }

/// Returns true if addr is a current board member (encryption grantee).
/// Former members are not: their roster entry is kept, but closed.
public fun is_governance_member(self: &OU, addr: address): bool {
    self.governance.is_board_member(addr)
}

/// Increment the encryption epoch and emit EncryptionEpochRotated.
/// Called by set_board_governance (on member removal) and by
/// encrypted_entry::rotate_encryption_epoch (explicit out-of-band rotation).
/// Emitting the event here keeps it tied to the module that defines the type.
public(package) fun increment_encrypt_epoch(self: &mut OU) {
    let old = self.encrypt_epoch;
    self.encrypt_epoch = old + 1;
    event::emit(EncryptionEpochRotated {
        ou_id: self.id(),
        old_epoch: old,
        new_epoch: self.encrypt_epoch,
    });
}

/// Append an entry ID to the on-chain index.
/// Called by encrypted_entry::publish_entry after creating the EncryptedEntry.
public(package) fun push_entry(self: &mut OU, entry_id: ID) {
    self.entries.push_back(entry_id);
}

/// Remove an entry ID from the on-chain index by value.
/// Called by encrypted_entry::remove_entry before deleting the EncryptedEntry.
/// Aborts if the ID is absent — index divergence would corrupt the cap count
/// and break the migration entries.is_empty() guard.
public(package) fun remove_entry_id(self: &mut OU, target: ID) {
    let (found, idx) = self.entries.index_of(&target);
    assert!(found, EEntryIdNotFound);
    self.entries.remove(idx);
}

// === Proposal-type registry: reads ===

/// Canonical registry identity of payload type `P` (defining-package ids, so it
/// is stable across upgrades of the package that defines `P`).
public fun type_name_of<P>(): TypeName { type_name::with_defining_ids<P>() }

/// Returns true if proposal type `P` has a slot on this OU.
public fun is_type_enabled<P>(self: &OU): bool {
    self.is_type_name_enabled(&type_name_of<P>())
}

/// Returns true if the proposal type named `name` has a slot on this OU.
public fun is_type_name_enabled(self: &OU, name: &TypeName): bool {
    df::exists(&self.id, TypeSlot { name: *name })
}

/// Returns the ProposalConfig of type `P`. Aborts with ETypeNotEnabled if absent.
public fun type_config<P>(self: &OU): ProposalConfig {
    self.type_config_by_name(&type_name_of<P>())
}

/// Returns the ProposalConfig of the type named `name`. Aborts with ETypeNotEnabled if absent.
public fun type_config_by_name(self: &OU, name: &TypeName): ProposalConfig {
    self.slot(name).config
}

/// Returns the display key of type `P`. Aborts with ETypeNotEnabled if absent.
public fun type_display_key<P>(self: &OU): std::ascii::String {
    self.type_display_key_by_name(&type_name_of<P>())
}

/// Returns the display key of the type named `name`. Aborts with ETypeNotEnabled if absent.
public fun type_display_key_by_name(self: &OU, name: &TypeName): std::ascii::String {
    self.slot(name).display_key
}

/// Returns the last execution timestamp of type `P`, if it has ever executed.
/// Aborts with ETypeNotEnabled if the type has no slot.
public fun last_executed_ms<P>(self: &OU): Option<u64> {
    self.last_executed_ms_by_name(&type_name_of<P>())
}

/// Returns the last execution timestamp of the type named `name`, if any.
/// Aborts with ETypeNotEnabled if the type has no slot.
public fun last_executed_ms_by_name(self: &OU, name: &TypeName): Option<u64> {
    self.slot(name).last_executed_ms
}

/// Resolve a display key to the enabled type that carries it, if any.
/// This is the only string-addressed lookup in the registry and is meant for
/// cold admin paths (config updates, disables) where a human names the type.
public fun type_for_display_key(self: &OU, key: &std::ascii::String): Option<TypeName> {
    if (df::exists(&self.id, DisplayKey { key: *key })) {
        option::some(*df::borrow(&self.id, DisplayKey { key: *key }))
    } else {
        option::none()
    }
}

// === Permissions ===

/// Whether a request may perform mutations requiring `bits` on this OU: it
/// belongs to this OU and is privileged or carries every bit (the bits its
/// type's slot held when the request was minted).
public fun is_permitted<P>(self: &OU, bits: u64, req: &ExecutionRequest<P>): bool {
    self.id() == req.req_ou_id() && req.req_has_permission(bits)
}

/// The authorization check every OU mutator runs before acting on a request.
/// Aborts with EOUIdMismatch if `req` belongs to another OU and with
/// proposal::EPermissionDenied unless it is privileged or carries `bits`.
///
/// Holding a ticket for one type must not authorize mutations that type was
/// never granted: without this check, any request for the OU would do.
/// Modules `ou` depends on (treasury_vault, capability_vault, charter,
/// emergency) cannot take `&OU`; they call `proposal::assert_permitted` on
/// the request directly after their own OU check.
public fun assert_permitted<P>(self: &OU, bits: u64, req: &ExecutionRequest<P>) {
    assert!(self.id() == req.req_ou_id(), EOUIdMismatch);
    req.assert_permitted(bits);
}

/// Minimum approval_threshold for a config holding `bits`: 80% if any of
/// TYPE_ADMIN, MIGRATE, TREASURY_WITHDRAW, VAULT_BORROW or VAULT_EXTRACT is
/// set, else 0.
public fun permission_floor(bits: u64): u16 {
    let high =
        permissions::type_admin()
        | permissions::migrate()
        | permissions::treasury_withdraw()
        | permissions::vault_borrow()
        | permissions::vault_extract();
    if (bits & high != 0) HIGH_PERMISSION_MIN_THRESHOLD else 0
}

/// Returns true if `name` is one of the framework's own payload types
/// (`armature::types`). Their permission bits are fixed; see
/// `framework_permissions`.
public fun is_framework_type(name: &TypeName): bool {
    let n = *name;
    n == type_name_of<SetBoard>()
        || n == type_name_of<AddMember>()
        || n == type_name_of<RemoveMember>()
        || n == type_name_of<BatchAddMembers>()
        || n == type_name_of<BatchRemoveMembers>()
        || n == type_name_of<UpdateMetadata>()
        || n == type_name_of<EnableProposalType>()
        || n == type_name_of<DisableProposalType>()
        || n == type_name_of<UpdateProposalConfig>()
        || n == type_name_of<EnableBypassType>()
        || n == type_name_of<DisableBypassType>()
        || n == type_name_of<TransferFreezeAdmin>()
        || n == type_name_of<UnfreezeProposalType>()
        || n == type_name_of<UpdateFreezeConfig>()
        || n == type_name_of<UpdateFreezeExemptTypes>()
        || n == type_name_of<CompositePayload>()
        || n == type_name_of<SpawnOU>()
        || n == type_name_of<SpinOutSubOU>()
        || n == type_name_of<CreateSubOU>()
        || n == type_name_of<TransferAssets>()
}

/// The fixed permission bits of a framework type: exactly what its handler
/// needs, and nothing else. A framework type's slot always holds these bits,
/// whatever config enabled it, and no config update can change them. Returns
/// 0 for any other type.
///
/// Why each type holds its bits:
/// - SetBoard: BOARD_SET (applies an add/remove diff).
/// - AddMember, BatchAddMembers: BOARD_ADD. RemoveMember, BatchRemoveMembers: BOARD_REMOVE.
/// - UpdateMetadata: METADATA (charter::update_metadata).
/// - EnableProposalType, DisableProposalType, UpdateProposalConfig: TYPE_ADMIN.
/// - EnableBypassType: TYPE_ADMIN + VAULT_STORE (stores the new ExternalExecutionCap).
/// - DisableBypassType: TYPE_ADMIN + VAULT_EXTRACT (extracts the cap to destroy it).
/// - TransferFreezeAdmin (unfreeze_all), UnfreezeProposalType, UpdateFreezeConfig,
/// UpdateFreezeExemptTypes: FREEZE (governance changes to the EmergencyFreeze).
/// - SpawnOU: MIGRATE (set_migrating).
/// - CreateSubOU: VAULT_STORE + VAULT_EXTRACT (creates and stores a SubOUControl,
/// stores the SubOU's FreezeAdminCap).
/// - SpinOutSubOU: VAULT_BORROW + VAULT_EXTRACT (loans the SubOUControl, then
/// extracts the FreezeAdminCap and destroys the control).
/// - TransferAssets: TREASURY_WITHDRAW + VAULT_EXTRACT (moves coins and caps out).
/// - CompositePayload: none; its ticket is consumed by begin_pipeline.
public fun framework_permissions(name: &TypeName): u64 {
    let n = *name;
    if (n == type_name_of<SetBoard>()) {
        permissions::board_set()
    } else if (n == type_name_of<AddMember>() || n == type_name_of<BatchAddMembers>()) {
        permissions::board_add()
    } else if (n == type_name_of<RemoveMember>() || n == type_name_of<BatchRemoveMembers>()) {
        permissions::board_remove()
    } else if (n == type_name_of<UpdateMetadata>()) {
        permissions::metadata()
    } else if (
        n == type_name_of<EnableProposalType>()
            || n == type_name_of<DisableProposalType>()
            || n == type_name_of<UpdateProposalConfig>()
    ) {
        permissions::type_admin()
    } else if (n == type_name_of<EnableBypassType>()) {
        permissions::type_admin() | permissions::vault_store()
    } else if (n == type_name_of<DisableBypassType>()) {
        permissions::type_admin() | permissions::vault_extract()
    } else if (
        n == type_name_of<TransferFreezeAdmin>()
            || n == type_name_of<UnfreezeProposalType>()
            || n == type_name_of<UpdateFreezeConfig>()
            || n == type_name_of<UpdateFreezeExemptTypes>()
    ) {
        permissions::emergency_freeze()
    } else if (n == type_name_of<SpawnOU>()) {
        permissions::migrate()
    } else if (n == type_name_of<CreateSubOU>()) {
        permissions::vault_store() | permissions::vault_extract()
    } else if (n == type_name_of<SpinOutSubOU>()) {
        permissions::vault_borrow() | permissions::vault_extract()
    } else if (n == type_name_of<TransferAssets>()) {
        permissions::treasury_withdraw() | permissions::vault_extract()
    } else {
        0
    }
}

/// The fixed borrow scope of a framework type: the capability types its
/// handler borrows or loans. SpinOutSubOU loans the SubOUControl; no other
/// framework type borrows. Returns empty for any other type.
public fun framework_borrow_scope(name: &TypeName): vector<TypeName> {
    if (*name == type_name_of<SpinOutSubOU>()) {
        vector[type_name_of<capability_vault::SubOUControl>()]
    } else {
        vector[]
    }
}

/// For a framework type, return `config` carrying its fixed bits and borrow
/// scope; aborts with EFixedPermissions if `config` names any other non-empty
/// set of either. Other types' configs are returned unchanged.
fun with_fixed_permissions(name: &TypeName, config: ProposalConfig): ProposalConfig {
    if (!is_framework_type(name)) return config;
    let fixed = framework_permissions(name);
    let bits = config.permissions();
    assert!(bits == 0 || bits == fixed, EFixedPermissions);
    let fixed_scope = framework_borrow_scope(name);
    let scope = config.borrow_scope();
    assert!(scope.is_empty() || scope == fixed_scope, EFixedPermissions);
    config.with_permissions(fixed).with_borrow_scope(fixed_scope)
}

/// Abort with EThresholdBelowMinimum unless a config's approval_threshold
/// meets both the type's own floor (`min_approval_threshold_for_type`) and the
/// floor of the bits it holds (`permission_floor`). Every path that stores a
/// config runs this, so no caller can skip it.
///
/// EnableBypassType's execution floor counts YES against the whole board, not
/// votes cast, and a proposal stops taking votes once it passes. Its config
/// must therefore make passing imply the floor: YES ≥ quorum × threshold of the
/// board, so quorum × threshold must be at least 80% (EBypassQuorumTooLow).
///
/// EnableProposalType is held to the same whole-board rule (EEnableQuorumTooLow):
/// it can grant any bit, including TREASURY_WITHDRAW and VAULT_EXTRACT, so a
/// type must not be enabled by less than 80% of the board's weight. The 80%
/// threshold alone counts votes cast, which one YES meets on any board.
///
/// UpdateProposalConfig is held to it too (EUpdateConfigQuorumTooLow): it can
/// rewrite any enabled type's quorum and threshold, e.g. make a
/// treasury-withdrawing type single-vote, which is a grant of power as real as
/// enabling a type.
fun assert_config_floors(name: &TypeName, config: &ProposalConfig) {
    let threshold = config.approval_threshold();
    assert!(threshold >= min_approval_threshold_for_type(name), EThresholdBelowMinimum);
    assert!(threshold >= permission_floor(config.permissions()), EThresholdBelowMinimum);
    if (*name == type_name_of<EnableBypassType>()) {
        assert!(
            (config.quorum() as u64) * (threshold as u64)
                >= (ENABLE_BYPASS_TYPE_MIN_THRESHOLD as u64) * 10_000,
            EBypassQuorumTooLow,
        );
    };
    if (*name == type_name_of<EnableProposalType>()) {
        assert!(
            (config.quorum() as u64) * (threshold as u64)
                >= (ENABLE_PROPOSAL_TYPE_MIN_THRESHOLD as u64) * 10_000,
            EEnableQuorumTooLow,
        );
    };
    if (*name == type_name_of<UpdateProposalConfig>()) {
        assert!(
            (config.quorum() as u64) * (threshold as u64)
                >= (UPDATE_PROPOSAL_CONFIG_MIN_THRESHOLD as u64) * 10_000,
            EUpdateConfigQuorumTooLow,
        );
    };
}

/// Abort unless a request of type `P` may change a type's grant from
/// (`old`, `old_scope`) to (`new`, `new_scope`): its permission bits and its
/// borrow scope. No change passes. A privileged (controller) request passes.
/// Otherwise `P` must be EnableProposalType, EnableBypassType or
/// UpdateProposalConfig (EPermissionChangeNotAllowed), and the floor of the
/// bits being added must not exceed `P`'s own approval floor
/// (EGrantFloorNotMet): the vote that grants a power is held to at least that
/// power's floor. A scope change counts as a VAULT_BORROW grant for the floor.
/// All three meta-types sit at the 80% floor today, so this holds by
/// construction; the check keeps it true if a floor is ever lowered.
///
/// Grants are standalone-only: composite::add_step refuses grant steps.
fun assert_may_change_permissions<P>(
    old: u64,
    new: u64,
    old_scope: &vector<TypeName>,
    new_scope: &vector<TypeName>,
    req: &ExecutionRequest<P>,
) {
    let scope_changed = old_scope != new_scope;
    if ((old == new && !scope_changed) || req.req_is_privileged()) return;
    let granter = type_name_of<P>();
    assert!(
        granter == type_name_of<EnableProposalType>()
            || granter == type_name_of<EnableBypassType>()
            || granter == type_name_of<UpdateProposalConfig>(),
        EPermissionChangeNotAllowed,
    );
    let mut added = new ^ (new & old);
    if (scope_changed) added = added | permissions::vault_borrow();
    assert!(
        permission_floor(added) <= min_approval_threshold_for_type(&granter),
        EGrantFloorNotMet,
    );
}

/// Abort unless `req` is a controller override (privileged) for this OU:
/// EOUIdMismatch for another OU, ENotPrivileged otherwise. Guards the
/// mutators only a parent OU's controller may call (set_controller_paused,
/// clear_controller); no permission bit grants them.
public fun assert_controller<P>(self: &OU, req: &ExecutionRequest<P>) {
    assert!(self.id() == req.req_ou_id(), EOUIdMismatch);
    assert!(req.req_is_privileged(), ENotPrivileged);
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

/// Add `to_add` to and remove `to_remove` from the OU's board as one change.
/// Requires BOARD_SET (`assert_permitted`).
/// Auto-increments encrypt_epoch if any member was removed, providing forward security.
public fun set_board_governance<P>(
    self: &mut OU,
    to_add: vector<address>,
    to_remove: vector<address>,
    req: &ExecutionRequest<P>,
) {
    self.assert_permitted(permissions::board_set(), req);
    let any_removed = !to_remove.is_empty();
    self.governance.set_board(to_add, to_remove);
    if (any_removed) {
        self.increment_encrypt_epoch();
    };
}

/// Add a single member to the OU's board.
/// Requires BOARD_ADD (`assert_permitted`).
public fun add_board_member_governance<P>(
    self: &mut OU,
    member: address,
    req: &ExecutionRequest<P>,
) {
    self.assert_permitted(permissions::board_add(), req);
    self.governance.add_board_member(member);
}

/// Add multiple members to the OU's board, skipping any address already
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
/// Requires BOARD_ADD (`assert_permitted`).
public fun add_board_members_governance<P>(
    self: &mut OU,
    new_members: vector<address>,
    req: &ExecutionRequest<P>,
): (vector<address>, vector<address>) {
    self.assert_permitted(permissions::board_add(), req);
    self.governance.add_board_members(new_members)
}

/// Remove a single member from the OU's board.
/// Requires BOARD_REMOVE (`assert_permitted`).
/// Auto-increments encrypt_epoch for forward security.
public fun remove_board_member_governance<P>(
    self: &mut OU,
    member: address,
    req: &ExecutionRequest<P>,
) {
    self.assert_permitted(permissions::board_remove(), req);
    self.governance.remove_board_member(member);
    self.increment_encrypt_epoch();
}

/// Remove multiple members from the OU's board atomically.
/// Requires BOARD_REMOVE (`assert_permitted`).
/// Auto-increments encrypt_epoch once for the batch.
public fun remove_board_members_governance<P>(
    self: &mut OU,
    members: vector<address>,
    req: &ExecutionRequest<P>,
): vector<address> {
    self.assert_permitted(permissions::board_remove(), req);
    let removed = self.governance.remove_board_members(members);
    self.increment_encrypt_epoch();
    removed
}

/// Enable proposal type `NewType` with a display key and config.
/// Aborts if `NewType` already has a slot or the display key is taken, if the
/// config misses a floor (`assert_config_floors`), or if it holds permission
/// bits that `P` may not grant (`assert_may_change_permissions`).
/// Requires TYPE_ADMIN (`assert_permitted`).
public fun enable_proposal_type<NewType, P>(
    self: &mut OU,
    display_key: std::ascii::String,
    config: ProposalConfig,
    req: &ExecutionRequest<P>,
) {
    self.assert_permitted(permissions::type_admin(), req);
    let name = type_name_of<NewType>();
    let config = with_fixed_permissions(&name, config);
    assert_config_floors(&name, &config);
    assert_may_change_permissions(0, config.permissions(), &vector[], &config.borrow_scope(), req);
    let ou_id = self.id();
    add_slot(&mut self.id, ou_id, new_type_init<NewType>(display_key, config));
}

/// Remove the slot (config, display key, cooldown state) of the type named `name`.
/// Aborts with ETypeNotEnabled if absent. Nothing is left behind.
///
/// Cooldown state is not preserved: if the type is re-enabled later, its first
/// execution is not subject to the cooldown. Re-enabling requires an
/// EnableProposalType or EnableBypassType vote (both 80% floor).
/// Requires TYPE_ADMIN (`assert_permitted`).
public fun disable_proposal_type<P>(self: &mut OU, name: TypeName, req: &ExecutionRequest<P>) {
    self.assert_permitted(permissions::type_admin(), req);
    let ou_id = self.id();
    remove_slot(&mut self.id, ou_id, name);
}

/// Replace the ProposalConfig of the type named `name`.
/// Aborts with ETypeNotEnabled if absent, if the new config misses a floor
/// (`assert_config_floors`), or if it changes the type's permission bits in a
/// way `P` may not (`assert_may_change_permissions`).
/// Requires TYPE_ADMIN (`assert_permitted`).
public fun update_proposal_config<P>(
    self: &mut OU,
    name: TypeName,
    new_config: ProposalConfig,
    req: &ExecutionRequest<P>,
) {
    self.assert_permitted(permissions::type_admin(), req);
    assert!(
        !is_framework_type(&name)
            || (new_config.permissions() == framework_permissions(&name)
                && new_config.borrow_scope() == framework_borrow_scope(&name)),
        EFixedPermissions,
    );
    assert_config_floors(&name, &new_config);
    let old = self.slot(&name).config;
    assert_may_change_permissions(
        old.permissions(),
        new_config.permissions(),
        &old.borrow_scope(),
        &new_config.borrow_scope(),
        req,
    );
    let ou_id = self.id();
    let entry = self.slot_mut(&name);
    entry.config = new_config;
    event::emit(TypeSlotConfigUpdated {
        ou_id,
        type_name: name.into_string(),
        display_key: entry.display_key,
        config: new_config,
    });
}

/// Pause or resume proposal execution on this OU.
/// Requires PAUSE (`assert_permitted`).
public fun set_execution_paused<P>(self: &mut OU, paused: bool, req: &ExecutionRequest<P>) {
    self.assert_permitted(permissions::pause(), req);
    self.execution_paused = paused;
}

/// Set or clear controller-initiated pause on this SubOU.
/// Controller override only: requires a privileged request (`assert_controller`).
public fun set_controller_paused<P>(self: &mut OU, paused: bool, req: &ExecutionRequest<P>) {
    self.assert_controller(req);
    self.controller_paused = paused;
}

/// Clear the controller relationship (for SpinOutSubOU).
/// Resets controller_cap_id to none and controller_paused to false.
/// Controller override only: requires a privileged request (`assert_controller`).
public fun clear_controller<P>(self: &mut OU, req: &ExecutionRequest<P>) {
    self.assert_controller(req);
    self.controller_cap_id = option::none();
    self.controller_paused = false;
}

/// Transition the OU to Migrating status (irreversible).
/// Requires MIGRATE (`assert_permitted`).
public fun set_migrating<P>(self: &mut OU, successor_ou_id: ID, req: &ExecutionRequest<P>) {
    self.assert_permitted(permissions::migrate(), req);
    self.status = OUStatus::Migrating { successor_ou_id };
}

// === ProposalTypeState ===

/// Check if type state exists for proposal type P.
public fun has_type_state<P>(self: &OU): bool {
    df::exists(&self.id, type_name::with_defining_ids<P>())
}

/// Borrow immutable reference to type state for proposal type P.
public fun borrow_type_state<P, S: store>(self: &OU): &S {
    df::borrow(&self.id, type_name::with_defining_ids<P>())
}

/// Borrow mutable reference to type state. Requires ExecutionRequest for authorization.
public fun borrow_type_state_mut<P, S: store>(self: &mut OU, req: &ExecutionRequest<P>): &mut S {
    assert!(self.id() == req.req_ou_id(), EOUIdMismatch);
    df::borrow_mut(&mut self.id, type_name::with_defining_ids<P>())
}

/// Initialize type state for proposal type P (lazy-init on first execution).
/// Requires ExecutionRequest for authorization.
public fun init_type_state<P, S: store>(self: &mut OU, state: S, req: &ExecutionRequest<P>) {
    assert!(self.id() == req.req_ou_id(), EOUIdMismatch);
    df::add(&mut self.id, type_name::with_defining_ids<P>(), state);
}

/// Remove type state for proposal type P. Requires ExecutionRequest for authorization.
public fun remove_type_state<P, S: store>(self: &mut OU, req: &ExecutionRequest<P>): S {
    assert!(self.id() == req.req_ou_id(), EOUIdMismatch);
    df::remove(&mut self.id, type_name::with_defining_ids<P>())
}

/// Record the execution timestamp for the type named `name`.
/// Called after a successful execute() to update cooldown tracking.
/// Aborts with ETypeNotEnabled if the type has no slot.
public(package) fun record_execution(self: &mut OU, name: TypeName, timestamp_ms: u64) {
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

/// Returns true if the type is blocked for controlled SubOUs: hierarchy-altering
/// operations reserved for independent OUs, plus bypass-meta types that would let
/// a SubOU autonomously escalate its own execution privileges.
/// SubOUs with `controller_cap_id.is_some()` cannot enable these types.
public fun is_subou_blocked_type(name: &TypeName): bool {
    let n = *name;
    n == type_name_of<SpawnOU>()
        || n == type_name_of<SpinOutSubOU>()
        || n == type_name_of<CreateSubOU>()
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

// === Internal: construction ===

/// Build an OU and its companion objects, seed the default proposal-type slots
/// and apply `overrides`. Nothing is shared here; each public constructor
/// decides what to share and what to return.
fun build(
    gov_init: &GovernanceTypeInit,
    name: String,
    metadata_uri: String,
    is_subou: bool,
    overrides: vector<ProposalTypeInit>,
    ctx: &mut TxContext,
): (
    OU,
    treasury_vault::TreasuryVault,
    capability_vault::CapabilityVault,
    charter::Charter,
    emergency::EmergencyFreeze,
    emergency::FreezeAdminCap,
) {
    assert!(name.length() > 0, EInvalidName);

    let creator = ctx.sender();

    // Build governance config from init payload (Board only for now)
    let governance = governance::new_board(gov_init, ctx);
    let initial_members = gov_init.init_members();

    // Create a placeholder OU ID so companion objects can reference it
    let ou_uid = object::new(ctx);
    let ou_id = ou_uid.to_inner();

    // Create companion objects
    let treasury = treasury_vault::new(ou_id, ctx);
    let treasury_id = object::id(&treasury);

    let cap_vault = capability_vault::new(ou_id, ctx);
    let capability_vault_id = object::id(&cap_vault);

    let ou_charter = charter::new(ou_id, name, metadata_uri, ctx);
    let charter_id = object::id(&ou_charter);

    let freeze = emergency::new(ou_id, ctx);
    let emergency_freeze_id = object::id(&freeze);

    let freeze_admin_cap = emergency::new_admin_cap(ou_id, ctx);

    let mut ou = OU {
        id: ou_uid,
        status: OUStatus::Active,
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

    event::emit(OUCreated {
        ou_id,
        treasury_id,
        capability_vault_id,
        charter_id,
        emergency_freeze_id,
        creator,
    });
    event::emit(OUBoardInitialized { ou_id, initial_members });

    // Seed the registry: defaults first, then construction-time overrides.
    let defaults = default_type_inits(is_subou);
    let mut i = 0;
    while (i < defaults.length()) {
        add_slot(&mut ou.id, ou_id, defaults[i]);
        i = i + 1;
    };
    apply_type_overrides(&mut ou.id, ou_id, overrides, is_subou);

    (ou, treasury, cap_vault, ou_charter, freeze, freeze_admin_cap)
}

/// Default proposal-type slots every OU starts with. SubOUs omit the bypass
/// meta-types (they are SubOU-blocked).
fun default_type_inits(is_subou: bool): vector<ProposalTypeInit> {
    let mut v = vector[
        default_init<SetBoard>(b"SetBoard"),
        default_init<AddMember>(b"AddMember"),
        default_init<RemoveMember>(b"RemoveMember"),
        default_init<BatchAddMembers>(b"BatchAddMembers"),
        default_init<BatchRemoveMembers>(b"BatchRemoveMembers"),
        default_init<UpdateMetadata>(b"CharterUpdate"),
        default_init<EnableProposalType>(b"EnableProposalType"),
    ];
    if (!is_subou) {
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
/// It carries the type's fixed bits (`framework_permissions`), and its
/// threshold is the default raised to the type's own floor and the floor of
/// its bits, so the config threshold is never misleadingly low. EnableBypassType,
/// EnableProposalType and UpdateProposalConfig instead get an 80% quorum and a
/// 100% threshold, so their defaults pass `assert_config_floors`.
/// composable_allowed is true for single-operation types that make sense as steps
/// inside a CompositeFrame. Batch types (BatchAddMembers, BatchRemoveMembers) are
/// excluded: they have no _step handler variant and BatchAddMembers carries an
/// explicit regression test guarding its deny-by-default status.
fun config_for_type(name: &TypeName): ProposalConfig {
    let bits = framework_permissions(name);
    let n = *name;
    let whole_board =
        n == type_name_of<EnableBypassType>()
        || n == type_name_of<EnableProposalType>()
        || n == type_name_of<UpdateProposalConfig>();
    let (quorum, approval_threshold) = if (whole_board) {
        (WHOLE_BOARD_DEFAULT_QUORUM, WHOLE_BOARD_DEFAULT_APPROVAL_THRESHOLD)
    } else {
        (
            DEFAULT_QUORUM,
            DEFAULT_APPROVAL_THRESHOLD
                .max(min_approval_threshold_for_type(name))
                .max(permission_floor(bits)),
        )
    };
    let composable =
        n == type_name_of<AddMember>()
        || n == type_name_of<RemoveMember>()
        || n == type_name_of<SetBoard>()
        || n == type_name_of<UpdateMetadata>()
        || n == type_name_of<EnableProposalType>();
    proposal::new_config(
        quorum,
        approval_threshold,
        DEFAULT_PROPOSE_THRESHOLD,
        DEFAULT_EXPIRY_MS,
        DEFAULT_EXECUTION_DELAY_MS,
        DEFAULT_COOLDOWN_MS,
    )
        .with_composable_allowed(composable)
        .with_permissions(bits)
        .with_borrow_scope(framework_borrow_scope(name))
}

/// Apply `overrides` to an already-seeded registry.
/// - Type already enabled: replace its ProposalConfig, preserving composable_allowed,
/// permissions and borrow_scope.
/// The override's display key must equal the slot's (EDisplayKeyMismatch otherwise);
/// default display keys cannot be renamed at construction time.
/// - Type not yet enabled: add its slot (enables the type at construction time).
/// - Type is a SubOU-blocked type AND `check_subou_blocked` is true: abort with
/// EBlockedProposalType. Pass false for parent OUs, which legitimately have these
/// types (e.g. CreateSubOU).
/// - The resulting config misses a floor (`assert_config_floors`): abort.
fun apply_type_overrides(
    id: &mut UID,
    ou_id: ID,
    overrides: vector<ProposalTypeInit>,
    check_subou_blocked: bool,
) {
    let mut i = 0;
    while (i < overrides.length()) {
        let init = overrides[i];
        assert!(
            !check_subou_blocked || !is_subou_blocked_type(&init.type_name),
            EBlockedProposalType,
        );
        if (df::exists(id, TypeSlot { name: init.type_name })) {
            let entry: &mut ProposalType = df::borrow_mut(id, TypeSlot { name: init.type_name });
            assert!(entry.display_key == init.display_key, EDisplayKeyMismatch);
            let composable = entry.config.composable_allowed();
            let permissions = entry.config.permissions();
            let borrow_scope = entry.config.borrow_scope();
            let config = init
                .config
                .with_composable_allowed(composable)
                .with_permissions(permissions)
                .with_borrow_scope(borrow_scope);
            assert_config_floors(&init.type_name, &config);
            entry.config = config;
            event::emit(TypeSlotConfigUpdated {
                ou_id,
                type_name: init.type_name.into_string(),
                display_key: entry.display_key,
                config: entry.config,
            });
        } else {
            let init = ProposalTypeInit {
                type_name: init.type_name,
                display_key: init.display_key,
                config: with_fixed_permissions(&init.type_name, init.config),
            };
            assert_config_floors(&init.type_name, &init.config);
            add_slot(id, ou_id, init);
        };
        i = i + 1;
    };
}

// === Internal: registry ===

fun add_slot(id: &mut UID, ou_id: ID, init: ProposalTypeInit) {
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
        ou_id,
        type_name: type_name.into_string(),
        display_key,
        config,
    });
}

fun remove_slot(id: &mut UID, ou_id: ID, name: TypeName) {
    assert!(df::exists(id, TypeSlot { name }), ETypeNotEnabled);
    let ProposalType { display_key, config: _, last_executed_ms: _ } = df::remove(
        id,
        TypeSlot { name },
    );
    let _: TypeName = df::remove(id, DisplayKey { key: display_key });
    event::emit(TypeSlotRemoved { ou_id, type_name: name.into_string(), display_key });
}

fun slot(self: &OU, name: &TypeName): &ProposalType {
    assert!(df::exists(&self.id, TypeSlot { name: *name }), ETypeNotEnabled);
    df::borrow(&self.id, TypeSlot { name: *name })
}

fun slot_mut(self: &mut OU, name: &TypeName): &mut ProposalType {
    assert!(df::exists(&self.id, TypeSlot { name: *name }), ETypeNotEnabled);
    df::borrow_mut(&mut self.id, TypeSlot { name: *name })
}

// === Test Helpers ===

#[test_only]
/// Enable proposal type `T` on the OU without an ExecutionRequest or floor
/// checks. A framework type gets its fixed bits, as on every real path.
public fun test_enable_type<T>(
    self: &mut OU,
    display_key: std::ascii::String,
    config: ProposalConfig,
) {
    let ou_id = self.id();
    let config = with_fixed_permissions(&type_name_of<T>(), config);
    add_slot(&mut self.id, ou_id, new_type_init<T>(display_key, config));
}

#[test_only]
/// Replace the config of an already-enabled proposal type `T`, without floor
/// checks. A framework type keeps its fixed bits, as on every real path.
public fun test_update_config<T>(self: &mut OU, config: ProposalConfig) {
    let name = type_name_of<T>();
    self.slot_mut(&name).config = with_fixed_permissions(&name, config);
}

#[test_only]
/// Register `control_id` as this SubOU's controller without sharing it, for
/// tests that call `controller::privileged_submit` on an unshared SubOU.
public fun set_controller_for_testing(self: &mut OU, control_id: ID) {
    self.controller_cap_id = option::some(control_id);
}

#[test_only]
/// Disable proposal type `T` on the OU without an ExecutionRequest.
public fun test_disable_type<T>(self: &mut OU) {
    let ou_id = self.id();
    remove_slot(&mut self.id, ou_id, type_name_of<T>());
}

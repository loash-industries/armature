/// External-authorization bypass execution.
///
/// This module is the single sanctioned third path to mint an `ExecutionTicket<P>`,
/// alongside `board_voting::ticket_from_vote` (vote-then-execute) and
/// `controller::privileged_submit` (parent-board override via `SubOUControl`).
///
/// Extension packages that gate execution on *external state* — Character
/// ownership, token balance, soulbound attestation, oracle assertion, ZK proof —
/// implement their own authorization check, then present the OU's
/// `ExternalExecutionCap<P>` (which the OU received via `EnableBypassType<P>`,
/// or, for a controlled SubOU, via a controller's `ControllerEnableBypassType<P>`)
/// to `ticket_from_cap` to mint the `ExecutionTicket<P>`.
///
/// All the safety machinery a vote-then-execute path runs through
/// (slot lookup by type, freeze, execution pause, controller pause,
/// cooldown, record_execution) lives behind the cap-gated function so every
/// bypass mechanism inherits it for free. The cap is the only on-chain
/// opt-in: an OU without a cap for `P` cannot have one of its proposals
/// of type `P` execute via this path, regardless of the extension package.
module armature::external_execution;

use armature::capability_vault::CapabilityVault;
use armature::controller_disable_bypass_type::{Self, ControllerDisableBypassType};
use armature::controller_enable_bypass_type::{Self, ControllerEnableBypassType};
use armature::disable_bypass_type::{Self, DisableBypassType};
use armature::emergency::EmergencyFreeze;
use armature::enable_bypass_type::{Self, EnableBypassType};
use armature::ou::{Self, OU};
use armature::permissions;
use armature::proposal::{Self, ExecutionTicket, ExternalExecutionCap, ProposalConfig};
use armature::utils;
use std::internal::Permit;
use std::string::String;
use std::type_name::{Self, TypeName};
use sui::clock::Clock;
use sui::event;

// === Errors ===

const EOUNotActive: u64 = 0;
const ETypeNotEnabled: u64 = 1;
const EExecutionPaused: u64 = 2;
const EControllerPaused: u64 = 3;
/// The handler's `NewType` does not match the type pinned in the payload, or
/// the display key in the payload does not match the slot's display key.
const ETypeMismatch: u64 = 4;
const ECooldownActive: u64 = 5;
const EOUIdMismatch: u64 = 6;
const EVaultOUMismatch: u64 = 7;
const EApprovalFloorNotMet: u64 = 8;
const ESubOUBlockedType: u64 = 9;
const ECapNotFound: u64 = 10;
const ESelfBootstrapDenied: u64 = 11;
/// Config sets cooldown_ms > 0 and composable_allowed = true simultaneously.
const EComposableCooldownConflict: u64 = 13;
/// `ticket_from_cap_readonly` called for a type with cooldown_ms > 0. Cooldown
/// tracking writes the type's slot, so those types must use `ticket_from_cap`.
const ECooldownRequiresMutableOU: u64 = 14;
/// The type's slot holds a bit in `bypass_forbidden_bits`: a no-vote path may
/// not change the authority graph (type registry, lifecycle, cap custody,
/// freeze). Checked when the bypass is enabled and again at every mint, so a
/// later UpdateProposalConfig grant cannot open it either.
const EBypassForbiddenBits: u64 = 15;
/// The SubOU (or its vault, or its registered control) is not the one named in
/// a controller bypass payload.
const ESubOUMismatch: u64 = 16;
/// A controller chain step does not connect: the vault is not the current
/// tip's, or it does not hold the next OU's registered SubOUControl bound to
/// that OU. Also raised when a chain is finished on an OU that is not its tip.
const EChainBroken: u64 = 17;
/// A controller chain is longer than MAX_CHAIN_DEPTH levels.
const EChainTooDeep: u64 = 18;

// === Constants ===

/// 80% approval floor for EnableBypassType and ControllerEnableBypassType (basis
/// points), enforced at execute time against the whole board's weight. Mirrored by
/// `ou::ENABLE_BYPASS_TYPE_MIN_THRESHOLD`; the two MUST stay in sync. `ou`
/// holds every stored EnableBypassType config to quorum × threshold ≥ this
/// floor, so a proposal that passes its vote always clears this check.
const ENABLE_BYPASS_APPROVAL_FLOOR_BPS: u64 = 8_000;

/// Most levels a controller chain may span (`extend_controller_chain`).
const MAX_CHAIN_DEPTH: u64 = 16;

// Self-bootstrap forbidden types — see `assert_not_bypass_forbidden` below.

// === Public Functions ===

/// Permission bits a bypass-enabled type may never hold: TYPE_ADMIN, MIGRATE,
/// VAULT_EXTRACT and FREEZE. Each changes who may do what (the type registry,
/// the OU's lifecycle, capability custody, the emergency freeze), and a path
/// that executes without a vote must not be able to change that. Mirrors
/// `assert_not_bypass_forbidden`, which refuses the bypass meta-types themselves.
public fun bypass_forbidden_bits(): u64 {
    permissions::type_admin()
        | permissions::migrate()
        | permissions::vault_extract()
        | permissions::emergency_freeze()
}

// === Events ===

/// Emitted when a proposal is created and executed atomically through the
/// external-authorization bypass path. Indexers can use this to distinguish
/// bypass executions from vote-then-execute and controller bypass.
public struct ExternalExecutionCreated has copy, drop {
    ou_id: ID,
    type_key: std::ascii::String,
    submitter: address,
}

/// Emitted when an OU opts into bypass execution for a proposal type.
public struct BypassEnabled has copy, drop {
    ou_id: ID,
    type_key: std::ascii::String,
    cap_id: ID,
}

/// Emitted when an OU opts out of bypass execution for a proposal type.
public struct BypassDisabled has copy, drop {
    ou_id: ID,
    type_key: std::ascii::String,
    cap_id: ID,
}

/// Mint an ExecutionTicket authorized by an `ExternalExecutionCap<P>`,
/// bypassing the vote, and records the execution timestamp for cooldown
/// tracking. No Proposal object is created; ProposalCreated,
/// ProposalPayloadCreated and ProposalExecuted are the audit record.
///
/// The proposal type is `P` itself: its slot on the OU supplies the config
/// and display key, so no separate type key or binding check is needed.
///
/// Asserts (in order):
/// 1. Cap is scoped to this OU
/// 2. OU is Active (not Migrating)
/// 3. `P` has a slot (is enabled)
/// 4. OU execution is not paused
/// 5. SubOU is not controller-paused
/// 6. `P` is not frozen
/// 7. Cooldown for `P` has elapsed
///
/// Requires `Permit<P>`, so only `P`'s own module can mint a bypass ticket.
/// The cap sits in the shared vault and anyone can borrow it; the external
/// authorization check (Character ownership, token balance, ...) must live
/// next to `P` and run before the mint. A type whose payload constructor is
/// public cannot be minted from outside its module with a payload of the
/// caller's choosing.
///
/// For types with cooldown_ms = 0 prefer `ticket_from_cap_readonly`, which
/// leaves the OU untouched.
public fun ticket_from_cap<P: store>(
    cap: &ExternalExecutionCap<P>,
    ou: &mut OU,
    freeze: &EmergencyFreeze,
    metadata_ipfs: Option<String>,
    payload: P,
    _: Permit<P>,
    clock: &Clock,
    ctx: &mut TxContext,
): ExecutionTicket<P> {
    let ticket = ticket_from_cap_core(cap, ou, freeze, metadata_ipfs, payload, clock, false, ctx);
    ou.record_execution(type_name::with_defining_ids<P>(), clock.timestamp_ms());
    ticket
}

/// `ticket_from_cap` for types with cooldown_ms = 0, taking the OU by immutable
/// reference. The last-executed timestamp only feeds cooldown checks, so it is
/// not recorded and nothing on the OU is written; the OU can be an immutable
/// shared input that takes no write lock.
///
/// Requires `Permit<P>` (see `ticket_from_cap`).
/// Aborts with ECooldownRequiresMutableOU if the type's cooldown_ms > 0.
public fun ticket_from_cap_readonly<P: store>(
    cap: &ExternalExecutionCap<P>,
    ou: &OU,
    freeze: &EmergencyFreeze,
    metadata_ipfs: Option<String>,
    payload: P,
    _: Permit<P>,
    clock: &Clock,
    ctx: &mut TxContext,
): ExecutionTicket<P> {
    ticket_from_cap_core(cap, ou, freeze, metadata_ipfs, payload, clock, true, ctx)
}

// === EnableBypassType / DisableBypassType ===
//
// The payload types live in the leaf modules `enable_bypass_type` and
// `disable_bypass_type` so `ou` can name them when seeding default slots.
// The handlers live here (not in armature_proposals) because they mint
// `ExternalExecutionCap<NewType>` via a `public(package)` constructor.
// Keeping the handler in the same Move package as the constructor prevents
// the privilege-escalation path that arises when any caller holding any
// `ExecutionRequest<Auth>` could mint a cap for an unrelated proposal type.

// === Constructors ===

/// Build an `EnableBypassType` payload. `type_name` must be
/// `std::type_name::with_defining_ids<NewType>()` for the type the board is
/// approving; the handler asserts the executor's `NewType` matches it.
public fun new_enable_bypass_type(
    type_key: std::ascii::String,
    type_name: TypeName,
    config: ProposalConfig,
): EnableBypassType {
    enable_bypass_type::new(type_key, type_name, config)
}

public fun new_disable_bypass_type(type_key: std::ascii::String, cap_id: ID): DisableBypassType {
    disable_bypass_type::new(type_key, cap_id)
}

// === Accessors ===

public fun enable_type_key(self: &EnableBypassType): std::ascii::String { self.type_key() }

public fun enable_type_name(self: &EnableBypassType): TypeName { self.type_name() }

public fun enable_config(self: &EnableBypassType): &ProposalConfig { self.config() }

public fun disable_type_key(self: &DisableBypassType): std::ascii::String { self.type_key() }

public fun disable_cap_id(self: &DisableBypassType): ID { self.cap_id() }

// === Handlers ===

/// Execute an `EnableBypassType` proposal: enable a proposal type AND mint
/// an `ExternalExecutionCap<NewType>` into the OU's `CapabilityVault`.
/// Subsequent submissions of type `NewType` can skip the vote by going
/// through `ticket_from_cap` with the cap.
///
/// `NewType` must be the type pinned in the payload (ETypeMismatch otherwise),
/// so the executor cannot register a different type than the board approved.
///
/// Enforces an 80% approval floor on the actual vote weights, because every
/// future submission under this type will execute without a vote.
public fun execute_enable_bypass_type<NewType: store>(
    ou: &mut OU,
    vault: &mut CapabilityVault,
    ticket: ExecutionTicket<EnableBypassType>,
    ctx: &mut TxContext,
) {
    assert!(ou.id() == ticket.ticket_ou_id(), EOUIdMismatch);
    assert!(vault.ou_id() == ou.id(), EVaultOUMismatch);

    assert_not_bypass_forbidden<NewType>();
    assert_approval_floor_ticket(&ticket, ENABLE_BYPASS_APPROVAL_FLOOR_BPS);

    let payload = ticket.ticket_payload();
    let new_type = type_name::with_defining_ids<NewType>();
    assert!(new_type == payload.type_name(), ETypeMismatch);
    let display_key = payload.type_key();
    let config = *payload.config();

    // Enforce the composability–cooldown mutual exclusion before the config is
    // committed. A bypass type with cooldown_ms > 0 must not be composable.
    assert!(config.cooldown_ms() == 0 || !config.composable_allowed(), EComposableCooldownConflict);
    assert_bypass_safe_bits(config.permissions());

    if (ou.controller_cap_id().is_some()) {
        assert!(!ou::is_subou_blocked_type(&new_type), ESubOUBlockedType);
    };

    let req = ticket.ticket_request(enable_bypass_type::permit());
    ou.enable_proposal_type<NewType, EnableBypassType>(display_key, config, req);

    let cap = proposal::new_external_execution_cap<EnableBypassType, NewType>(req, ctx);
    let cap_id = object::id(&cap);
    vault.store_cap(cap, req);

    event::emit(BypassEnabled { ou_id: ou.id(), type_key: display_key, cap_id });

    ticket.discharge(enable_bypass_type::permit());
}

/// Execute a `DisableBypassType` proposal: extract the specified
/// `ExternalExecutionCap<NewType>` from the vault, destroy it, and remove
/// the proposal type's slot in one atomic step.
///
/// The payload's display key must match `NewType`'s slot (ETypeMismatch),
/// so the executor cannot disable a different type than the board approved.
public fun execute_disable_bypass_type<NewType: store>(
    ou: &mut OU,
    vault: &mut CapabilityVault,
    ticket: ExecutionTicket<DisableBypassType>,
) {
    assert!(ou.id() == ticket.ticket_ou_id(), EOUIdMismatch);
    assert!(vault.ou_id() == ou.id(), EVaultOUMismatch);

    let payload = ticket.ticket_payload();
    let display_key = payload.type_key();
    let cap_id = payload.cap_id();

    let name = type_name::with_defining_ids<NewType>();
    assert!(ou.is_type_name_enabled(&name), ETypeNotEnabled);
    assert!(ou.type_display_key_by_name(&name) == display_key, ETypeMismatch);

    let cap_ids = vault.ids_for_type<ExternalExecutionCap<NewType>>();
    assert!(cap_ids.contains(&cap_id), ECapNotFound);

    let req = ticket.ticket_request(disable_bypass_type::permit());
    let cap: ExternalExecutionCap<NewType> = vault.extract_cap(cap_id, req);
    proposal::destroy_external_execution_cap(cap, req);

    ou.disable_proposal_type<DisableBypassType>(name, req);

    event::emit(BypassDisabled { ou_id: ou.id(), type_key: display_key, cap_id });

    ticket.discharge(disable_bypass_type::permit());
}

// === Controller chain: ControllerEnableBypassType / ControllerDisableBypassType ===
//
// A controlled SubOU cannot pass EnableBypassType or DisableBypassType itself
// (SubOU-blocked), so the grant and the revoke come from an OU that controls
// it: its direct controller, or any OU further up the controller hierarchy.
// The voting OU's board passes the proposal; the executor then proves, one
// level per PTB command, that the voting OU controls the SubOU:
//
//   start_controller_chain(ticket)
//   -> extend_controller_chain(&tip_vault, &next) once per level
//   -> finish_controller_enable_bypass_type<NewType> (or _disable_)
//
// Each step checks that the current tip's vault holds the next OU's registered
// SubOUControl and that the control is bound to that OU, the two checks
// `controller::assert_registered_control` makes. Custody of an object with the
// registered ID is not enough: v1 `ou::share_subou` stays callable and lets
// anyone point an OU's controller_cap_id at any ID. If a level's pointer has
// been moved off its bound control, the chain stops there until
// `ou::restore_controller` points it back; the executor can call that first in
// the same PTB. Nothing is loaned or moved, and intermediate OUs and vaults are
// read only. Each OU has one bound
// control, held in one vault, so the chain from the voting OU to the payload's
// SubOU is unique: the executor cannot route through anyone else. `finish`
// then acts on the SubOU on a privileged request, as a direct controller's
// override would.

/// Hot potato: the OU that passed `ticket` controls `tip_ou_id` through `hops`
/// verified levels. Only the `finish_controller_*` functions consume it.
public struct ControllerChain<P> {
    ticket: ExecutionTicket<P>,
    tip_ou_id: ID,
    hops: u64,
}

/// Build a `ControllerEnableBypassType` payload. `type_name` must be
/// `std::type_name::with_defining_ids<NewType>()` for the type the board is
/// approving, and `control_cap_id` the SubOU's registered SubOUControl.
public fun new_controller_enable_bypass_type(
    subou_id: ID,
    control_cap_id: ID,
    type_key: std::ascii::String,
    type_name: TypeName,
    config: ProposalConfig,
): ControllerEnableBypassType {
    controller_enable_bypass_type::new(subou_id, control_cap_id, type_key, type_name, config)
}

/// Build a `ControllerDisableBypassType` payload. `type_name` must be
/// `std::type_name::with_defining_ids<NewType>()` for the type being revoked.
public fun new_controller_disable_bypass_type(
    subou_id: ID,
    control_cap_id: ID,
    type_name: TypeName,
): ControllerDisableBypassType {
    controller_disable_bypass_type::new(subou_id, control_cap_id, type_name)
}

/// Start a chain at the OU that passed `ticket`. Only a
/// `ControllerEnableBypassType` or `ControllerDisableBypassType` chain can be
/// finished; the checks that need the payload run at `finish`.
public fun start_controller_chain<P>(ticket: ExecutionTicket<P>): ControllerChain<P> {
    let tip_ou_id = ticket.ticket_ou_id();
    ControllerChain { ticket, tip_ou_id, hops: 0 }
}

/// Extend the chain one level: `tip_vault` must be the current tip's vault and
/// hold `next`'s registered SubOUControl, bound to `next`, so the tip controls
/// `next`, which becomes the tip. `next` must be Active. Aborts with
/// EChainTooDeep past MAX_CHAIN_DEPTH levels. Aborts with EChainBroken if
/// `next`'s controller_cap_id was moved off its bound control; call
/// `ou::restore_controller` first.
public fun extend_controller_chain<P>(
    chain: &mut ControllerChain<P>,
    tip_vault: &CapabilityVault,
    next: &OU,
) {
    assert!(tip_vault.ou_id() == chain.tip_ou_id, EChainBroken);
    let control_id = next.controller_cap_id();
    assert!(
        control_id.is_some()
            && tip_vault.holds_subou_control_for(*control_id.borrow(), next.id()),
        EChainBroken,
    );
    assert!(next.status().is_active(), EOUNotActive);
    assert!(chain.hops < MAX_CHAIN_DEPTH, EChainTooDeep);
    chain.hops = chain.hops + 1;
    chain.tip_ou_id = next.id();
}

/// Finish a `ControllerEnableBypassType` chain whose tip is the payload's
/// SubOU: enable `NewType` on the SubOU and mint an
/// `ExternalExecutionCap<NewType>` scoped to it into its vault.
///
/// Runs the same checks as `execute_enable_bypass_type`: self-bootstrap
/// denylist, 80% of the voting OU's whole board on the actual vote weights,
/// type pin, composability vs cooldown, bypass-safe bits, SubOU-blocked types.
/// Plus: the SubOU, its vault and its registered control are the payload's.
public fun finish_controller_enable_bypass_type<NewType: store>(
    chain: ControllerChain<ControllerEnableBypassType>,
    subou: &mut OU,
    subou_vault: &mut CapabilityVault,
    ctx: &mut TxContext,
) {
    let ControllerChain { ticket, tip_ou_id, hops } = chain;
    assert!(hops > 0 && tip_ou_id == subou.id(), EChainBroken);

    assert_not_bypass_forbidden<NewType>();
    assert_approval_floor_ticket(&ticket, ENABLE_BYPASS_APPROVAL_FLOOR_BPS);

    let payload = ticket.ticket_payload();
    assert_controller_target(subou, subou_vault, payload.subou_id(), payload.control_cap_id());
    let new_type = type_name::with_defining_ids<NewType>();
    assert!(new_type == payload.type_name(), ETypeMismatch);
    let display_key = payload.type_key();
    let config = *payload.config();

    assert!(config.cooldown_ms() == 0 || !config.composable_allowed(), EComposableCooldownConflict);
    assert_bypass_safe_bits(config.permissions());
    assert!(!ou::is_subou_blocked_type(&new_type), ESubOUBlockedType);

    let subou_req = proposal::privileged_execute(
        subou.id(),
        b"ControllerEnableBypassType".to_ascii_string(),
        ctx.sender(),
        option::none(),
        payload,
        0,
        vector[],
        true,
        ctx,
    );

    subou.enable_proposal_type<NewType, ControllerEnableBypassType>(
        display_key,
        config,
        &subou_req,
    );
    let cap = proposal::new_external_execution_cap<ControllerEnableBypassType, NewType>(
        &subou_req,
        ctx,
    );
    let cap_id = object::id(&cap);
    subou_vault.store_cap(cap, &subou_req);
    subou.add_controller_grants(new_type, vector[cap_id]);
    proposal::consume(subou_req);

    event::emit(BypassEnabled { ou_id: subou.id(), type_key: display_key, cap_id });

    ticket.discharge(controller_enable_bypass_type::permit());
}

/// Finish a `ControllerDisableBypassType` chain whose tip is the payload's
/// SubOU: destroy every `ExternalExecutionCap<NewType>` a controller chain
/// granted the SubOU that is in the SubOU's vault, and remove `NewType`'s slot
/// on the SubOU.
///
/// Each half runs on whatever is there. The SubOU controls its slots, so
/// requiring the slot (or its display key) would let it block the revoke by
/// removing or renaming the slot first and later re-enable it to revive the
/// cap. Destroying every recorded grant means a duplicate or orphaned grant
/// cannot survive a revoke. The revoke reads the SubOU's grant record
/// (`ou::take_controller_grants`), never every cap of the type in the vault:
/// anyone can push caps scoped to other OUs into a vault (TransferAssets), and
/// loading each one would let them push the revoke past the per-transaction
/// object limit. A recorded cap that is not in the vault stays recorded, so a
/// later revoke destroys it if it comes back. Emits one BypassDisabled per
/// destroyed cap. Aborts with ECapNotFound only when there is neither a cap
/// nor a slot. `NewType` must be the payload's type.
public fun finish_controller_disable_bypass_type<NewType: store>(
    chain: ControllerChain<ControllerDisableBypassType>,
    subou: &mut OU,
    subou_vault: &mut CapabilityVault,
    ctx: &mut TxContext,
) {
    let ControllerChain { ticket, tip_ou_id, hops } = chain;
    assert!(hops > 0 && tip_ou_id == subou.id(), EChainBroken);

    let payload = ticket.ticket_payload();
    assert_controller_target(subou, subou_vault, payload.subou_id(), payload.control_cap_id());
    let name = type_name::with_defining_ids<NewType>();
    assert!(name == payload.type_name(), ETypeMismatch);

    let subou_id = subou.id();
    // `contains` reads the vault's ID set and loads no objects.
    let recorded = subou.take_controller_grants(name);
    let cap_ids = recorded.filter!(|id| subou_vault.contains(*id));
    subou.add_controller_grants(name, recorded.filter!(|id| !subou_vault.contains(*id)));
    let has_slot = subou.is_type_name_enabled(&name);
    assert!(!cap_ids.is_empty() || has_slot, ECapNotFound);
    let type_key = if (has_slot) subou.type_display_key_by_name(&name) else name.into_string();

    let subou_req = proposal::privileged_execute(
        subou_id,
        b"ControllerDisableBypassType".to_ascii_string(),
        ctx.sender(),
        option::none(),
        payload,
        0,
        vector[],
        true,
        ctx,
    );

    cap_ids.do!(|cap_id| {
        let cap: ExternalExecutionCap<NewType> = subou_vault.extract_cap(cap_id, &subou_req);
        proposal::destroy_external_execution_cap(cap, &subou_req);
        event::emit(BypassDisabled { ou_id: subou_id, type_key, cap_id });
    });
    if (has_slot) {
        subou.disable_proposal_type<ControllerDisableBypassType>(name, &subou_req);
    };
    proposal::consume(subou_req);

    ticket.discharge(controller_disable_bypass_type::permit());
}

// === Internal ===

/// Shared body of `ticket_from_cap` and `ticket_from_cap_readonly`: every check
/// and effect except recording the execution timestamp.
fun ticket_from_cap_core<P: store>(
    cap: &ExternalExecutionCap<P>,
    ou: &OU,
    freeze: &EmergencyFreeze,
    metadata_ipfs: Option<String>,
    payload: P,
    clock: &Clock,
    readonly: bool,
    ctx: &mut TxContext,
): ExecutionTicket<P> {
    proposal::assert_cap_for_ou(cap, ou.id());
    assert!(ou.status().is_active(), EOUNotActive);
    let name = type_name::with_defining_ids<P>();
    assert!(ou.is_type_name_enabled(&name), ETypeNotEnabled);
    assert!(!ou.is_execution_paused(), EExecutionPaused);
    assert!(!ou.is_controller_paused(), EControllerPaused);

    let display_key = ou.type_display_key_by_name(&name);
    assert_bypass_safe_bits(ou.type_config_by_name(&name).permissions());
    freeze.assert_not_frozen<P>(ou.id(), clock);

    let now = clock.timestamp_ms();
    let cooldown_ms = ou.type_config_by_name(&name).cooldown_ms();
    assert!(!readonly || cooldown_ms == 0, ECooldownRequiresMutableOU);
    if (cooldown_ms > 0) {
        let last_executed = ou.last_executed_ms_by_name(&name);
        if (last_executed.is_some()) {
            let last = last_executed.destroy_some();
            assert!(now >= last + cooldown_ms, ECooldownActive);
        };
    };

    event::emit(ExternalExecutionCreated {
        ou_id: ou.id(),
        type_key: display_key,
        submitter: ctx.sender(),
    });

    let req = proposal::privileged_execute(
        ou.id(),
        display_key,
        ctx.sender(),
        metadata_ipfs,
        &payload,
        ou.type_config_by_name(&name).permissions(),
        ou.type_config_by_name(&name).borrow_scope(),
        false,
        ctx,
    );

    proposal::new_ticket_external(req, payload)
}

/// Abort with ESubOUMismatch unless `subou` is the payload's SubOU, `subou_vault`
/// is its vault, and `control_cap_id` is its registered SubOUControl.
fun assert_controller_target(
    subou: &OU,
    subou_vault: &CapabilityVault,
    subou_id: ID,
    control_cap_id: ID,
) {
    assert!(subou.id() == subou_id, ESubOUMismatch);
    assert!(subou_vault.ou_id() == subou.id(), ESubOUMismatch);
    assert!(subou.controller_cap_id() == &option::some(control_cap_id), ESubOUMismatch);
}

/// Abort with EBypassForbiddenBits if `bits` holds any of `bypass_forbidden_bits`.
fun assert_bypass_safe_bits(bits: u64) {
    assert!(bits & bypass_forbidden_bits() == 0, EBypassForbiddenBits);
}

/// Refuse to bypass-enable the bypass meta-types themselves.
fun assert_not_bypass_forbidden<NewType>() {
    let new_type = type_name::with_defining_ids<NewType>();
    assert!(new_type != type_name::with_defining_ids<EnableBypassType>(), ESelfBootstrapDenied);
    assert!(new_type != type_name::with_defining_ids<DisableBypassType>(), ESelfBootstrapDenied);
    assert!(
        new_type != type_name::with_defining_ids<ControllerEnableBypassType>(),
        ESelfBootstrapDenied,
    );
    assert!(
        new_type != type_name::with_defining_ids<ControllerDisableBypassType>(),
        ESelfBootstrapDenied,
    );
}

/// Approval floor check for Standalone (vote-path) tickets.
/// Requires a Standalone ticket — path check comes first with a clear error.
fun assert_approval_floor_ticket<P>(ticket: &ExecutionTicket<P>, floor_bps: u64) {
    assert!(ticket.ticket_is_standalone(), EApprovalFloorNotMet);
    let total = ticket.ticket_total_snapshot_weight();
    // Reject zero-weight proposals (vacuous floor pass).
    assert!(total > 0, EApprovalFloorNotMet);
    assert!(utils::gte_bps(ticket.ticket_yes_weight(), total, floor_bps), EApprovalFloorNotMet);
}

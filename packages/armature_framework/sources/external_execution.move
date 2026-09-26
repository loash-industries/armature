/// External-authorization bypass execution.
///
/// This module is the single sanctioned third path to mint an `ExecutionTicket<P>`,
/// alongside `board_voting::ticket_from_vote` (vote-then-execute) and
/// `controller::privileged_submit` (parent-board override via `SubDAOControl`).
///
/// Extension packages that gate execution on *external state* — Character
/// ownership, token balance, soulbound attestation, oracle assertion, ZK proof —
/// implement their own authorization check, then present the DAO's
/// `ExternalExecutionCap<P>` (which the DAO received via `EnableBypassType<P>`)
/// to `ticket_from_cap` to mint the `ExecutionTicket<P>`.
///
/// All the safety machinery a vote-then-execute path runs through
/// (slot lookup by type, freeze, execution pause, controller pause,
/// cooldown, record_execution) lives behind the cap-gated function so every
/// bypass mechanism inherits it for free. The cap is the only on-chain
/// opt-in: a DAO without a cap for `P` cannot have one of its proposals
/// of type `P` execute via this path, regardless of the extension package.
module armature::external_execution;

use armature::capability_vault::CapabilityVault;
use armature::dao::{Self, DAO};
use armature::disable_bypass_type::{Self, DisableBypassType};
use armature::emergency::EmergencyFreeze;
use armature::enable_bypass_type::{Self, EnableBypassType};
use armature::proposal::{Self, ExecutionTicket, ExternalExecutionCap, ProposalConfig};
use armature::utils;
use std::string::String;
use std::type_name::{Self, TypeName};
use sui::clock::Clock;
use sui::event;

// === Errors ===

const EDAONotActive: u64 = 0;
const ETypeNotEnabled: u64 = 1;
const EExecutionPaused: u64 = 2;
const EControllerPaused: u64 = 3;
/// The handler's `NewType` does not match the type pinned in the payload, or
/// the display key in the payload does not match the slot's display key.
const ETypeMismatch: u64 = 4;
const ECooldownActive: u64 = 5;
const EDAOIdMismatch: u64 = 6;
const EVaultDAOMismatch: u64 = 7;
const EApprovalFloorNotMet: u64 = 8;
const ESubDAOBlockedType: u64 = 9;
const ECapNotFound: u64 = 10;
const ESelfBootstrapDenied: u64 = 11;
/// Config sets cooldown_ms > 0 and composable_allowed = true simultaneously.
const EComposableCooldownConflict: u64 = 13;
/// `ticket_from_cap_readonly` called for a type with cooldown_ms > 0. Cooldown
/// tracking writes the type's slot, so those types must use `ticket_from_cap`.
const ECooldownRequiresMutableDAO: u64 = 14;

// === Constants ===

/// 80% approval floor for EnableBypassType (basis points).
/// Approval floor enforced at execute time. Mirrored by
/// `admin_ops::ENABLE_BYPASS_APPROVAL_FLOOR_BPS` for the `UpdateProposalConfig`
/// path; the two MUST stay in sync. The handler's check (this constant) is
/// authoritative — the duplicate guards the on-DAO config from being relaxed
/// below the handler floor via `UpdateProposalConfig`.
const ENABLE_BYPASS_APPROVAL_FLOOR_BPS: u64 = 8_000;

// Self-bootstrap forbidden types — see `assert_not_bypass_forbidden` below.

// === Events ===

/// Emitted when a proposal is created and executed atomically through the
/// external-authorization bypass path. Indexers can use this to distinguish
/// bypass executions from vote-then-execute and controller bypass.
public struct ExternalExecutionCreated has copy, drop {
    dao_id: ID,
    type_key: std::ascii::String,
    submitter: address,
}

/// Emitted when a DAO opts into bypass execution for a proposal type.
public struct BypassEnabled has copy, drop {
    dao_id: ID,
    type_key: std::ascii::String,
    cap_id: ID,
}

/// Emitted when a DAO opts out of bypass execution for a proposal type.
public struct BypassDisabled has copy, drop {
    dao_id: ID,
    type_key: std::ascii::String,
    cap_id: ID,
}

// === Public Functions ===

/// Mint an ExecutionTicket authorized by an `ExternalExecutionCap<P>`,
/// bypassing the vote, and records the execution timestamp for cooldown
/// tracking. No Proposal object is created; ProposalCreated,
/// ProposalPayloadCreated and ProposalExecuted are the audit record.
///
/// The proposal type is `P` itself: its slot on the DAO supplies the config
/// and display key, so no separate type key or binding check is needed.
///
/// Asserts (in order):
///   1. Cap is scoped to this DAO
///   2. DAO is Active (not Migrating)
///   3. `P` has a slot (is enabled)
///   4. DAO execution is not paused
///   5. SubDAO is not controller-paused
///   6. `P` is not frozen
///   7. Cooldown for `P` has elapsed
///
/// For types with cooldown_ms = 0 prefer `ticket_from_cap_readonly`, which
/// leaves the DAO untouched.
public fun ticket_from_cap<P: store>(
    cap: &ExternalExecutionCap<P>,
    dao: &mut DAO,
    freeze: &EmergencyFreeze,
    metadata_ipfs: Option<String>,
    payload: P,
    clock: &Clock,
    ctx: &mut TxContext,
): ExecutionTicket<P> {
    let ticket = ticket_from_cap_core(cap, dao, freeze, metadata_ipfs, payload, clock, false, ctx);
    dao.record_execution(type_name::with_defining_ids<P>(), clock.timestamp_ms());
    ticket
}

/// `ticket_from_cap` for types with cooldown_ms = 0, taking the DAO by immutable
/// reference. The last-executed timestamp only feeds cooldown checks, so it is
/// not recorded and nothing on the DAO is written; the DAO can be an immutable
/// shared input that takes no write lock.
///
/// Aborts with ECooldownRequiresMutableDAO if the type's cooldown_ms > 0.
public fun ticket_from_cap_readonly<P: store>(
    cap: &ExternalExecutionCap<P>,
    dao: &DAO,
    freeze: &EmergencyFreeze,
    metadata_ipfs: Option<String>,
    payload: P,
    clock: &Clock,
    ctx: &mut TxContext,
): ExecutionTicket<P> {
    ticket_from_cap_core(cap, dao, freeze, metadata_ipfs, payload, clock, true, ctx)
}

// === EnableBypassType / DisableBypassType ===
//
// The payload types live in the leaf modules `enable_bypass_type` and
// `disable_bypass_type` so `dao` can name them when seeding default slots.
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
/// an `ExternalExecutionCap<NewType>` into the DAO's `CapabilityVault`.
/// Subsequent submissions of type `NewType` can skip the vote by going
/// through `ticket_from_cap` with the cap.
///
/// `NewType` must be the type pinned in the payload (ETypeMismatch otherwise),
/// so the executor cannot register a different type than the board approved.
///
/// Enforces an 80% approval floor on the actual vote weights, because every
/// future submission under this type will execute without a vote.
public fun execute_enable_bypass_type<NewType: store>(
    dao: &mut DAO,
    vault: &mut CapabilityVault,
    ticket: ExecutionTicket<EnableBypassType>,
    ctx: &mut TxContext,
) {
    assert!(dao.id() == ticket.ticket_dao_id(), EDAOIdMismatch);
    assert!(vault.dao_id() == dao.id(), EVaultDAOMismatch);

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

    if (dao.controller_cap_id().is_some()) {
        assert!(!dao::is_subdao_blocked_type(&new_type), ESubDAOBlockedType);
    };

    let req = ticket.ticket_request();
    dao.enable_proposal_type<NewType, EnableBypassType>(display_key, config, req);

    let cap = proposal::new_external_execution_cap<EnableBypassType, NewType>(req, ctx);
    let cap_id = object::id(&cap);
    vault.store_cap(cap, req);

    event::emit(BypassEnabled { dao_id: dao.id(), type_key: display_key, cap_id });

    ticket.discharge();
}

/// Execute a `DisableBypassType` proposal: extract the specified
/// `ExternalExecutionCap<NewType>` from the vault, destroy it, and remove
/// the proposal type's slot in one atomic step.
///
/// The payload's display key must match `NewType`'s slot (ETypeMismatch),
/// so the executor cannot disable a different type than the board approved.
public fun execute_disable_bypass_type<NewType: store>(
    dao: &mut DAO,
    vault: &mut CapabilityVault,
    ticket: ExecutionTicket<DisableBypassType>,
) {
    assert!(dao.id() == ticket.ticket_dao_id(), EDAOIdMismatch);
    assert!(vault.dao_id() == dao.id(), EVaultDAOMismatch);

    let payload = ticket.ticket_payload();
    let display_key = payload.type_key();
    let cap_id = payload.cap_id();

    let name = type_name::with_defining_ids<NewType>();
    assert!(dao.is_type_name_enabled(&name), ETypeNotEnabled);
    assert!(dao.type_display_key_by_name(&name) == display_key, ETypeMismatch);

    let cap_ids = vault.ids_for_type<ExternalExecutionCap<NewType>>();
    assert!(cap_ids.contains(&cap_id), ECapNotFound);

    let req = ticket.ticket_request();
    let cap: ExternalExecutionCap<NewType> = vault.extract_cap(cap_id, req);
    proposal::destroy_external_execution_cap(cap, req);

    dao.disable_proposal_type<DisableBypassType>(name, req);

    event::emit(BypassDisabled { dao_id: dao.id(), type_key: display_key, cap_id });

    ticket.discharge();
}

// === Internal ===

/// Shared body of `ticket_from_cap` and `ticket_from_cap_readonly`: every check
/// and effect except recording the execution timestamp.
fun ticket_from_cap_core<P: store>(
    cap: &ExternalExecutionCap<P>,
    dao: &DAO,
    freeze: &EmergencyFreeze,
    metadata_ipfs: Option<String>,
    payload: P,
    clock: &Clock,
    readonly: bool,
    ctx: &mut TxContext,
): ExecutionTicket<P> {
    proposal::assert_cap_for_dao(cap, dao.id());
    assert!(dao.status().is_active(), EDAONotActive);
    let name = type_name::with_defining_ids<P>();
    assert!(dao.is_type_name_enabled(&name), ETypeNotEnabled);
    assert!(!dao.is_execution_paused(), EExecutionPaused);
    assert!(!dao.is_controller_paused(), EControllerPaused);

    let display_key = dao.type_display_key_by_name(&name);
    freeze.assert_not_frozen<P>(clock);

    let now = clock.timestamp_ms();
    let cooldown_ms = dao.type_config_by_name(&name).cooldown_ms();
    assert!(!readonly || cooldown_ms == 0, ECooldownRequiresMutableDAO);
    if (cooldown_ms > 0) {
        let last_executed = dao.last_executed_ms_by_name(&name);
        if (last_executed.is_some()) {
            let last = last_executed.destroy_some();
            assert!(now >= last + cooldown_ms, ECooldownActive);
        };
    };

    event::emit(ExternalExecutionCreated {
        dao_id: dao.id(),
        type_key: display_key,
        submitter: ctx.sender(),
    });

    let req = proposal::privileged_execute(
        dao.id(),
        display_key,
        ctx.sender(),
        metadata_ipfs,
        &payload,
        false,
        ctx,
    );

    proposal::new_ticket_external(req, payload)
}

/// Refuse to bypass-enable the bypass meta-types themselves.
fun assert_not_bypass_forbidden<NewType>() {
    let new_type = type_name::with_defining_ids<NewType>();
    assert!(new_type != type_name::with_defining_ids<EnableBypassType>(), ESelfBootstrapDenied);
    assert!(new_type != type_name::with_defining_ids<DisableBypassType>(), ESelfBootstrapDenied);
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

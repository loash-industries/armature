/// External-authorization bypass execution.
///
/// This module is the single sanctioned third path to mint an `ExecutionRequest<P>`,
/// alongside `board_voting::authorize_execution` (vote-then-execute) and
/// `controller::privileged_submit` (parent-board override via `SubDAOControl`).
///
/// Extension packages that gate execution on *external state* — Character
/// ownership, token balance, soulbound attestation, oracle assertion, ZK proof —
/// implement their own authorization check, then present the DAO's
/// `ExternalExecutionCap<P>` (which the DAO received via `EnableBypassType<P>`)
/// to `external_executed_create` to mint the `ExecutionRequest<P>`.
///
/// All the safety machinery a vote-then-execute path runs through
/// (type-binding anti-spoof, freeze, execution pause, controller pause,
/// cooldown, record_execution) lives behind the cap-gated function so every
/// bypass mechanism inherits it for free. The cap is the only on-chain
/// opt-in: a DAO without a cap for `P` cannot have one of its proposals
/// of type `P` execute via this path, regardless of the extension package.
module armature::external_execution;

use armature::capability_vault::CapabilityVault;
use armature::dao::{Self, DAO};
use armature::emergency::EmergencyFreeze;
use armature::proposal::{Self, ExecutionRequest, ExternalExecutionCap, Proposal, ProposalConfig};
use armature::utils;
use std::string::String;
use std::type_name;
use sui::clock::Clock;
use sui::event;

// === Errors ===

const EDAONotActive: u64 = 0;
const ETypeNotEnabled: u64 = 1;
const EExecutionPaused: u64 = 2;
const EControllerPaused: u64 = 3;
const ETypeMismatch: u64 = 4;
const ECooldownActive: u64 = 5;
const EDAOIdMismatch: u64 = 6;
const EVaultDAOMismatch: u64 = 7;
const EApprovalFloorNotMet: u64 = 8;
const ESubDAOBlockedType: u64 = 9;
const ECapNotFound: u64 = 10;
const ESelfBootstrapDenied: u64 = 11;

// === Constants ===

/// 80% approval floor for EnableBypassType (basis points).
/// Approval floor enforced at execute time. Mirrored by
/// `admin_ops::ENABLE_BYPASS_APPROVAL_FLOOR_BPS` for the `UpdateProposalConfig`
/// path; the two MUST stay in sync. The handler's check (this constant) is
/// authoritative — the duplicate guards the on-DAO config from being relaxed
/// below the handler floor via `UpdateProposalConfig`.
const ENABLE_BYPASS_APPROVAL_FLOOR_BPS: u64 = 8_000;

// Self-bootstrap forbidden types — see `bypass_forbidden_type_names` below.

// === Events ===

/// Emitted when a proposal is created and executed atomically through the
/// external-authorization bypass path. Indexers can use this to distinguish
/// bypass executions from vote-then-execute and controller bypass.
public struct ExternalExecutionCreated has copy, drop {
    dao_id: ID,
    type_key: std::ascii::String,
    submitter: address,
}

// === Public Functions ===

/// Create a privileged proposal authorized by an `ExternalExecutionCap<P>`,
/// bypassing the vote. Mints an in-Executed-status `Proposal<P>` (shared
/// for audit), returns an `ExecutionRequest<P>` for the same DAO, and
/// records the execution timestamp for cooldown tracking.
///
/// Asserts (in order):
///   1. Cap is scoped to this DAO
///   2. DAO is Active (not Migrating)
///   3. `type_key` is in the enabled set
///   4. DAO execution is not paused
///   5. SubDAO is not controller-paused
///   6. `type_key` is not frozen for this DAO
///   7. If `type_key` has a type-binding, `P`'s canonical name matches it
///   8. Cooldown for `type_key` has elapsed
///
/// Then mints the request via `proposal::privileged_create` and calls
/// `dao::record_execution(type_key, now)` for cooldown bookkeeping.
///
/// The cap is the sole authorization — the framework does not look at
/// `ctx.sender()` for permissioning. Extension packages are responsible
/// for the auth check that gates access to the cap.
public fun external_executed_create<P: store>(
    cap: &ExternalExecutionCap<P>,
    dao: &mut DAO,
    freeze: &EmergencyFreeze,
    type_key: std::ascii::String,
    metadata_ipfs: Option<String>,
    payload: P,
    clock: &Clock,
    ctx: &mut TxContext,
): ExecutionRequest<P> {
    proposal::assert_cap_for_dao(cap, dao.id());
    assert!(dao.status().is_active(), EDAONotActive);
    assert!(dao.enabled_proposal_types().contains(&type_key), ETypeNotEnabled);
    assert!(!dao.is_execution_paused(), EExecutionPaused);
    assert!(!dao.is_controller_paused(), EControllerPaused);
    freeze.assert_not_frozen(&type_key, clock);

    if (dao.has_type_binding(&type_key)) {
        let actual = type_name::with_defining_ids<P>().into_string();
        assert!(dao.type_binding_for(&type_key) == actual, ETypeMismatch);
    };

    let now = clock.timestamp_ms();
    let cooldown_ms = dao.proposal_configs().get(&type_key).cooldown_ms();
    if (cooldown_ms > 0) {
        let last_executed_at = dao.last_executed_at();
        if (last_executed_at.contains(&type_key)) {
            let last = *last_executed_at.get(&type_key);
            assert!(now >= last + cooldown_ms, ECooldownActive);
        };
    };

    dao.record_execution(type_key, now);

    event::emit(ExternalExecutionCreated {
        dao_id: dao.id(),
        type_key,
        submitter: ctx.sender(),
    });

    proposal::privileged_create<P>(
        dao.id(),
        type_key,
        ctx.sender(),
        metadata_ipfs,
        payload,
        clock,
        ctx,
    )
}

// === EnableBypassType / DisableBypassType ===
//
// Lives in the framework (not in armature_proposals) because the handler
// mints `ExternalExecutionCap<NewType>` via a `public(package)` constructor.
// Keeping the proposal type and its handler in the same Move package as the
// constructor prevents the privilege-escalation path that arises when any
// caller holding any `ExecutionRequest<Auth>` can mint a cap for an
// unrelated proposal type.

/// Enable a new proposal type on the DAO with bypass-execution authorization.
/// In addition to the standard `EnableProposalType` effects (register the type,
/// bind the canonical Move type for anti-spoofing), this mints an
/// `ExternalExecutionCap<NewType>` into the DAO's `CapabilityVault`.
public struct EnableBypassType has drop, store {
    type_key: std::ascii::String,
    config: ProposalConfig,
}

/// Disable a bypass-enabled proposal type and destroy its
/// `ExternalExecutionCap<NewType>` in one atomic step.
public struct DisableBypassType has drop, store {
    type_key: std::ascii::String,
    cap_id: ID,
}

// === Events ===

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

// === Constructors ===

public fun new_enable_bypass_type(
    type_key: std::ascii::String,
    config: ProposalConfig,
): EnableBypassType {
    EnableBypassType { type_key, config }
}

public fun new_disable_bypass_type(type_key: std::ascii::String, cap_id: ID): DisableBypassType {
    DisableBypassType { type_key, cap_id }
}

// === Accessors ===

public fun enable_type_key(self: &EnableBypassType): std::ascii::String { self.type_key }

public fun enable_config(self: &EnableBypassType): &ProposalConfig { &self.config }

public fun disable_type_key(self: &DisableBypassType): std::ascii::String { self.type_key }

public fun disable_cap_id(self: &DisableBypassType): ID { self.cap_id }

// === Handlers ===

/// Execute an `EnableBypassType` proposal: enable a proposal type AND mint
/// an `ExternalExecutionCap<NewType>` into the DAO's `CapabilityVault`.
/// Subsequent submissions of type `NewType` can skip the vote by going
/// through `external_executed_create` with the cap.
///
/// Enforces an 80% approval floor — strictly more consequential than
/// `EnableProposalType` (66%) because every future submission under this
/// type will execute without a vote.
public fun execute_enable_bypass_type<NewType: store>(
    dao: &mut DAO,
    vault: &mut CapabilityVault,
    proposal: &Proposal<EnableBypassType>,
    request: ExecutionRequest<EnableBypassType>,
    ctx: &mut TxContext,
) {
    assert!(dao.id() == request.req_dao_id(), EDAOIdMismatch);
    assert!(vault.dao_id() == dao.id(), EVaultDAOMismatch);

    // Deny bypass-enabling the framework's own bypass-meta types. Letting
    // NewType = EnableBypassType (or DisableBypassType) creates a self-
    // bootstrap loop: a single cap could mint caps for arbitrary types
    // via privileged_create-zero-weight proposals.
    assert_not_bypass_forbidden<NewType>();

    assert_approval_floor(proposal, ENABLE_BYPASS_APPROVAL_FLOOR_BPS);

    let payload = proposal.payload();
    let type_key = payload.type_key;
    let config = payload.config;

    if (dao.controller_cap_id().is_some()) {
        assert!(!dao::is_subdao_blocked_type(&type_key), ESubDAOBlockedType);
    };

    dao.enable_proposal_type(type_key, config, &request);
    dao.bind_type_key<NewType, EnableBypassType>(type_key, &request);

    let cap = proposal::new_external_execution_cap<EnableBypassType, NewType>(&request, ctx);
    let cap_id = object::id(&cap);
    vault.store_cap(cap, &request);

    event::emit(BypassEnabled { dao_id: dao.id(), type_key, cap_id });

    proposal::finalize(request, proposal);
}

/// Execute a `DisableBypassType` proposal: extract the specified
/// `ExternalExecutionCap<NewType>` from the vault, destroy it, and remove
/// the proposal type from the enabled set in one atomic step.
///
/// The caller specifies which cap to destroy by ID; the handler verifies
/// the cap belongs to the type being disabled by checking `type_binding_for`
/// matches `NewType`. This prevents griefing a different bypass-enabled
/// type by passing an unrelated cap_id.
public fun execute_disable_bypass_type<NewType: store>(
    dao: &mut DAO,
    vault: &mut CapabilityVault,
    proposal: &Proposal<DisableBypassType>,
    request: ExecutionRequest<DisableBypassType>,
) {
    assert!(dao.id() == request.req_dao_id(), EDAOIdMismatch);
    assert!(vault.dao_id() == dao.id(), EVaultDAOMismatch);

    let payload = proposal.payload();
    let type_key = payload.type_key;
    let cap_id = payload.cap_id;

    // Verify the type is bound to NewType — guards against destroying a cap
    // for a different type by ID confusion.
    assert!(dao.has_type_binding(&type_key), ETypeNotEnabled);
    let expected = type_name::with_defining_ids<NewType>().into_string();
    assert!(dao.type_binding_for(&type_key) == expected, ETypeMismatch);

    // Verify the cap_id is actually registered in the vault as an EEC<NewType>.
    let cap_ids = vault.ids_for_type<ExternalExecutionCap<NewType>>();
    assert!(cap_ids.contains(&cap_id), ECapNotFound);

    let cap: ExternalExecutionCap<NewType> = vault.extract_cap(cap_id, &request);
    proposal::destroy_external_execution_cap(cap, &request);

    dao.disable_proposal_type(type_key, &request);

    event::emit(BypassDisabled { dao_id: dao.id(), type_key, cap_id });

    proposal::finalize(request, proposal);
}

// === Internal ===

/// Refuse to bypass-enable any Move type whose canonical name is in
/// the framework's self-bootstrap denylist. Centralising this guard
/// means future framework-meta types only need to be added in one place
/// to stay safe. Aborts with `ESelfBootstrapDenied` on match.
fun assert_not_bypass_forbidden<NewType>() {
    let new_type_name = type_name::with_defining_ids<NewType>().into_string();
    let forbidden = bypass_forbidden_type_names();
    let mut i = 0;
    while (i < forbidden.length()) {
        assert!(new_type_name != forbidden[i], ESelfBootstrapDenied);
        i = i + 1;
    };
}

/// Canonical Move type names that cannot be bypass-enabled. Extend this
/// list whenever a new framework-meta type is added whose handler runs
/// inside the bypass path. Centralised so a single edit covers the
/// invariant rather than scattered assertions.
fun bypass_forbidden_type_names(): vector<std::ascii::String> {
    vector[
        type_name::with_defining_ids<EnableBypassType>().into_string(),
        type_name::with_defining_ids<DisableBypassType>().into_string(),
    ]
}

fun assert_approval_floor<P: store>(proposal: &Proposal<P>, floor_bps: u64) {
    let total = proposal.total_snapshot_weight();
    // Reject zero-weight proposals. gte_bps(0, 0, _) returns true (0 >= 0),
    // which would let a privileged_create / external_executed_create proposal
    // (snapshot weight 0) pass any floor vacuously. The floor only has meaning
    // when there is real voting power behind the proposal.
    assert!(total > 0, EApprovalFloorNotMet);
    assert!(utils::gte_bps(proposal.yes_weight(), total, floor_bps), EApprovalFloorNotMet);
}

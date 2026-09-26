module armature_proposals::admin_ops;

use armature::board_voting;
use armature::charter::Charter;
use armature::dao::{Self, DAO};
use armature::disable_proposal_type::DisableProposalType;
use armature::enable_proposal_type::EnableProposalType;
use armature::proposal::{Self, ExecutionRequest, ExecutionTicket};
use armature::update_metadata::UpdateMetadata;
use armature::update_proposal_config::UpdateProposalConfig;
use std::string::String;
use std::type_name::{Self, TypeName};
use sui::clock::Clock;
use sui::event;

// === Errors ===

const EDaoMismatch: u64 = 0;
const ECharterDaoMismatch: u64 = 1;
const EUndisableableType: u64 = 2;
const ESubDAOBlockedType: u64 = 4;
// 5 was EThresholdBelowFloor: config floors are now enforced by
// dao::enable_proposal_type / update_proposal_config (dao::EThresholdBelowMinimum).
/// Proposal's approval_threshold is below the hardcoded floor for this type.
/// Enforced at submission time by propose_update_proposal_config.
const EFloorNotMet: u64 = 6;
/// Config sets cooldown_ms > 0 and composable_allowed = true simultaneously.
const EComposableCooldownConflict: u64 = 7;
/// The executor's `NewType` does not match the type pinned in the EnableProposalType payload.
const ETypeMismatch: u64 = 8;
/// The payload names a display key that no enabled type carries.
const ETypeNotEnabled: u64 = 9;

// === Events ===

public struct ProposalTypeDisabled has copy, drop {
    dao_id: ID,
    type_key: std::ascii::String,
}

public struct ProposalTypeEnabled has copy, drop {
    dao_id: ID,
    type_key: std::ascii::String,
}

public struct ProposalConfigUpdated has copy, drop {
    dao_id: ID,
    target_type_key: std::ascii::String,
}

public struct MetadataUpdated has copy, drop {
    dao_id: ID,
    new_ipfs_cid: std::string::String,
}

// === Handlers ===

/// Execute a DisableProposalType proposal: remove the slot of the type whose
/// display key the payload names. Aborts if the type is undisableable
/// (EnableProposalType, EnableBypassType, DisableBypassType, DisableProposalType,
/// TransferFreezeAdmin, UnfreezeProposalType) or not enabled.
public fun execute_disable_proposal_type(
    dao: &mut DAO,
    ticket: ExecutionTicket<DisableProposalType>,
) {
    assert!(dao.id() == ticket.ticket_dao_id(), EDaoMismatch);
    let type_key = ticket.ticket_payload().type_key();
    let name = resolve_display_key(dao, &type_key);
    assert_disableable(&name);
    dao.disable_proposal_type<DisableProposalType>(name, ticket.ticket_request());
    event::emit(ProposalTypeDisabled { dao_id: dao.id(), type_key });
    ticket.discharge();
}

/// Execute an EnableProposalType proposal: add a slot for `NewType` under the
/// payload's display key. `NewType` must equal the type pinned in the payload,
/// so the executor cannot register a different payload type than the board voted on.
public fun execute_enable_proposal_type<NewType: store>(
    dao: &mut DAO,
    ticket: ExecutionTicket<EnableProposalType>,
) {
    enable_proposal_type_impl<NewType>(dao, ticket.ticket_payload(), ticket.ticket_request());
    ticket.discharge();
}

/// Execute an UpdateProposalConfig proposal: merge optional field overrides
/// into the existing config of the type whose display key the payload names.
public fun execute_update_proposal_config(
    dao: &mut DAO,
    ticket: ExecutionTicket<UpdateProposalConfig>,
) {
    assert!(dao.id() == ticket.ticket_dao_id(), EDaoMismatch);

    let payload = ticket.ticket_payload();
    let target_key = payload.target_type_key();
    let name = resolve_display_key(dao, &target_key);

    let existing = dao.type_config_by_name(&name);
    let new_config = proposal::new_config(
        payload.quorum().destroy_with_default(existing.quorum()),
        payload.approval_threshold().destroy_with_default(existing.approval_threshold()),
        payload.propose_threshold().destroy_with_default(existing.propose_threshold()),
        payload.expiry_ms().destroy_with_default(existing.expiry_ms()),
        payload.execution_delay_ms().destroy_with_default(existing.execution_delay_ms()),
        payload.cooldown_ms().destroy_with_default(existing.cooldown_ms()),
    )
        .with_composable_allowed(payload
            .composable_allowed()
            .destroy_with_default(existing.composable_allowed()))
        .with_permissions(payload.permissions().destroy_with_default(existing.permissions()));

    assert_config_composability(&new_config);

    dao.update_proposal_config<UpdateProposalConfig>(name, new_config, ticket.ticket_request());

    event::emit(ProposalConfigUpdated {
        dao_id: dao.id(),
        target_type_key: target_key,
    });

    ticket.discharge();
}

/// Execute an UpdateMetadata proposal: update the DAO charter's IPFS CID.
public fun execute_update_metadata(charter: &mut Charter, ticket: ExecutionTicket<UpdateMetadata>) {
    update_metadata_impl(charter, ticket.ticket_payload(), ticket.ticket_request());
    ticket.discharge();
}

// === Internal ===

fun enable_proposal_type_impl<NewType: store>(
    dao: &mut DAO,
    payload: &EnableProposalType,
    request: &ExecutionRequest<EnableProposalType>,
) {
    assert!(dao.id() == request.req_dao_id(), EDaoMismatch);

    let name = type_name::with_defining_ids<NewType>();
    assert!(name == payload.type_name(), ETypeMismatch);

    let type_key = payload.type_key();
    let config = *payload.config();

    if (dao.controller_cap_id().is_some()) {
        assert!(!dao::is_subdao_blocked_type(&name), ESubDAOBlockedType);
    };

    assert_config_composability(&config);

    dao.enable_proposal_type<NewType, EnableProposalType>(type_key, config, request);

    event::emit(ProposalTypeEnabled {
        dao_id: dao.id(),
        type_key,
    });
}

fun update_metadata_impl(
    charter: &mut Charter,
    payload: &UpdateMetadata,
    request: &ExecutionRequest<UpdateMetadata>,
) {
    assert!(charter.dao_id() == request.req_dao_id(), ECharterDaoMismatch);
    charter.update_metadata(*payload.new_ipfs_cid(), request);
    event::emit(MetadataUpdated {
        dao_id: charter.dao_id(),
        new_ipfs_cid: *payload.new_ipfs_cid(),
    });
}

// === Submission wrapper ===

/// Submit an UpdateProposalConfig proposal with submission-time floor enforcement.
/// When the payload targets UpdateProposalConfig itself, asserts that the DAO's
/// current UpdateProposalConfig approval_threshold meets the 80% supermajority
/// floor before creating the proposal. This is strictly stronger than the old
/// execution-time check: a malicious downgrade proposal never enters the object
/// graph, cannot be voted on, and consumes no proposal slot.
///
/// The target display key must resolve to an enabled type (ETypeNotEnabled).
///
/// Callers that need non-self-targeting UpdateProposalConfig submissions can use
/// board_voting::submit_proposal<UpdateProposalConfig> directly. They are still
/// held to 80%: dao keeps UpdateProposalConfig's own config at or above its floor.
#[allow(lint(share_owned, custom_state_change))]
public fun propose_update_proposal_config(
    dao: &DAO,
    metadata_ipfs: Option<String>,
    payload: UpdateProposalConfig,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let self_type = type_name::with_defining_ids<UpdateProposalConfig>();
    let target = resolve_display_key(dao, &payload.target_type_key());

    if (target == self_type) {
        let config = dao.type_config_by_name(&self_type);
        let floor = dao::min_approval_threshold_for_type(&self_type);
        assert!(config.approval_threshold() >= floor, EFloorNotMet);
    };

    board_voting::submit_proposal<UpdateProposalConfig>(dao, metadata_ipfs, payload, clock, ctx);
}

// === Internal ===

/// Resolve a display key to the enabled type carrying it, aborting with
/// ETypeNotEnabled if no enabled type has that display key.
fun resolve_display_key(dao: &DAO, type_key: &std::ascii::String): TypeName {
    let name = dao.type_for_display_key(type_key);
    assert!(name.is_some(), ETypeNotEnabled);
    name.destroy_some()
}

/// Abort if the type is one of the core undisableable types.
fun assert_disableable(name: &TypeName) {
    assert!(!dao::is_undisableable_type(name), EUndisableableType);
}

/// Enforce the composability–cooldown mutual exclusion:
/// a config with cooldown_ms > 0 must not have composable_allowed = true.
/// Composite pipelines check cooldown against a frozen snapshot and cannot
/// enforce inter-step cooldown, so the combination is prohibited at config-write time.
fun assert_config_composability(config: &proposal::ProposalConfig) {
    assert!(config.cooldown_ms() == 0 || !config.composable_allowed(), EComposableCooldownConflict);
}

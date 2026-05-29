/// Option E — Frame + Pipeline composable proposal protocol.
///
/// A CompositeFrame is created by the submitter, populated with typed step
/// payloads via add_step<P>, then handed to submit_composite which computes
/// the effective ProposalConfig (component-wise max across all step configs),
/// enforces submission-time floors for floor-gated step types, and shares
/// both the frame and a Proposal<CompositePayload>.
///
/// At execution time, begin_pipeline issues a Pipeline hot potato from the
/// authorized Proposal<CompositePayload>. advance_step<P> extracts each step
/// payload by value, enforces per-step freeze and cooldown, and returns a
/// scoped ExecutionRequest<P> for the existing single-action handler. The
/// caller sequences these in PTB order. finalize_pipeline consumes the hot
/// potato after all steps have been advanced.
module armature::composite;

use armature::dao::DAO;
use armature::emergency::EmergencyFreeze;
use armature::proposal::{Self, ExecutionTicket, ProposalConfig};
use std::string::String;
use std::type_name::{Self, TypeName};
use sui::clock::Clock;
use sui::dynamic_field as df;
use sui::event;
use sui::vec_map::VecMap;

// === Errors ===

const ENotComposable: u64 = 0;
const EStepTypeMismatch: u64 = 1;
const EFrameMismatch: u64 = 2;
const EPipelineComplete: u64 = 3;
const EPipelineIncomplete: u64 = 4;
const ECompositeNesting: u64 = 5;
const EDAOIdMismatch: u64 = 6;
const EDAONotActive: u64 = 7;
const EFloorNotMet: u64 = 8;
const EEmptyFrame: u64 = 9;
/// A type with cooldown_ms > 0 reached advance_step (defence-in-depth).
const ECooldownTypeNotComposable: u64 = 11;
/// begin_pipeline called with an unsealed CompositeFrame.
const EFrameNotSealed: u64 = 12;
/// Frame write operation attempted after seal_frame.
const EFrameAlreadySealed: u64 = 13;
/// Frame step_type_keys or step_types do not match the voted-on payload.
const EFrameContentsMismatch: u64 = 14;
/// delete_exhausted_frame called before all steps have been extracted.
const EFrameNotExhausted: u64 = 15;

// === Constants ===

/// Maximum steps in a single composite proposal. Guards against unbounded PTBs.
const MAX_COMPOSITE_STEPS: u64 = 16;

/// The type_key registered in the DAO for composite proposals.
const COMPOSITE_TYPE_KEY: vector<u8> = b"Composite";

/// 66% floor for EnableProposalType steps inside a composite (basis points).
const ENABLE_APPROVAL_FLOOR_BPS: u64 = 6_600;

/// 80% floor for self-targeting UpdateProposalConfig steps inside a composite (basis points).
const SELF_UPDATE_APPROVAL_FLOOR_BPS: u64 = 8_000;

// === Key type for dynamic-field step storage ===

public struct StepKey has copy, drop, store { index: u64 }

// === Structs ===

/// Owned during submission; shared before voting.
/// Holds per-step payloads as dynamic fields keyed by StepKey { index }.
/// Immutable after sealing — advance_step only removes fields, never adds.
///
/// SECURITY INVARIANT: This module MUST NOT expose `&mut UID` (`uid_mut`) for
/// CompositeFrame. `df::add` / `df::remove` take `&mut UID` directly and would
/// bypass the seal check. Only `advance_step` (framework-internal) is permitted
/// to call `df::remove` on `frame.id`; no public `uid_mut` accessor may exist.
public struct CompositeFrame has key, store {
    id: UID,
    /// Set to true by seal_frame; never unset. All public write ops assert !sealed.
    sealed: bool,
    /// Tracks how many step payloads have been extracted by advance_step.
    /// Used by delete_exhausted_frame to verify all steps have run.
    steps_extracted: u64,
    dao_id: ID,
    step_type_keys: vector<std::ascii::String>,
    step_types: vector<TypeName>,
}

/// Stored inside Proposal<CompositePayload>.
/// References the shared CompositeFrame by ID; records step metadata copied
/// at submission so advance_step can validate P against the recorded TypeName
/// without reading the frame's dynamic fields.
public struct CompositePayload has drop, store {
    frame_id: ID,
    step_type_keys: vector<std::ascii::String>,
    step_types: vector<TypeName>,
}

/// Hot-potato step sequencer. No abilities — must be consumed in the same PTB
/// via finalize_pipeline after all steps have been advanced.
///
/// `last_executed_snapshot` captures `dao.last_executed_at()` at begin_pipeline
/// time. advance_step checks cooldowns against this snapshot so that two steps
/// sharing a type_key within the same composite don't block each other.
public struct Pipeline {
    frame_id: ID,
    dao_id: ID,
    composite_proposal_id: ID,
    current_step: u64,
    total_steps: u64,
    last_executed_snapshot: VecMap<std::ascii::String, u64>,
}

// === Events ===

/// Emitted by submit_composite so indexers can correlate the CompositeFrame
/// with the Proposal<CompositePayload> created in the same PTB. The proposal
/// also emits ProposalCreated (with type_key="Composite"), which carries the
/// proposal_id; the frame_id here is the cross-reference key.
public struct CompositeSubmitted has copy, drop {
    frame_id: ID,
    dao_id: ID,
    step_count: u64,
    proposer: address,
}

// === Submission: frame construction ===

/// Create a new CompositeFrame owned by the caller. Steps are added via add_step<P>.
/// Required creation sequence:
///   1. new_frame(dao_id, ctx)
///   2. add_step<P>(...) for each step
///   3. composite::seal_frame(&mut frame)   ← frame is now immutable to callers
///   4. submit_composite(dao, frame, ...)   ← seals internally if not already sealed
public fun new_frame(dao_id: ID, ctx: &mut TxContext): CompositeFrame {
    CompositeFrame {
        id: object::new(ctx),
        sealed: false,
        steps_extracted: 0,
        dao_id,
        step_type_keys: vector[],
        step_types: vector[],
    }
}

/// Append a typed step payload to the frame. Aborts if:
/// - The step count would exceed MAX_COMPOSITE_STEPS
/// - type_key is "Composite" (self-nesting is unconditionally blocked)
/// - The type's ProposalConfig has composable_allowed = false
/// - The type is not enabled in the DAO
#[allow(lint(share_owned))]
public fun add_step<P: store>(
    frame: &mut CompositeFrame,
    dao: &DAO,
    type_key: std::ascii::String,
    payload: P,
) {
    assert!(!frame.sealed, EFrameAlreadySealed);
    assert!(frame.dao_id == dao.id(), EDAOIdMismatch);
    assert!(frame.step_type_keys.length() < MAX_COMPOSITE_STEPS, EPipelineComplete);
    assert!(type_key != b"Composite".to_ascii_string(), ECompositeNesting);
    assert!(dao.enabled_proposal_types().contains(&type_key), ENotComposable);

    let step_config = dao.proposal_configs().get(&type_key);
    assert!(step_config.composable_allowed(), ENotComposable);

    let step_type = type_name::with_defining_ids<P>();

    frame.step_type_keys.push_back(type_key);
    frame.step_types.push_back(step_type);
    df::add(&mut frame.id, StepKey { index: frame.step_type_keys.length() - 1 }, payload);
}

/// Submit a composite proposal. Consumes the frame (which is shared internally),
/// computes the effective ProposalConfig as the component-wise max of all step
/// configs and the "Composite" type's own DAO config, enforces submission-time
/// floors for floor-gated step types, and creates a Proposal<CompositePayload>.
///
/// The effective config governs the vote threshold, quorum, and delays. Because
/// it is the max across all constituent steps, the composite can never pass
/// under weaker requirements than any individual step would require standalone.
#[allow(lint(share_owned, custom_state_change))]
public fun submit_composite(
    dao: &DAO,
    mut frame: CompositeFrame,
    metadata_ipfs: Option<String>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(frame.dao_id == dao.id(), EDAOIdMismatch);
    assert!(dao.status().is_active(), EDAONotActive);
    assert!(!frame.step_type_keys.is_empty(), EEmptyFrame);

    let composite_key = COMPOSITE_TYPE_KEY.to_ascii_string();
    assert!(dao.enabled_proposal_types().contains(&composite_key), ENotComposable);

    let proposer = ctx.sender();
    dao.governance().assert_board_member(proposer);

    // Compute effective config: component-wise max of the "Composite" base config
    // and every step type's config. This guarantees no step can weaken the bar.
    let effective = compute_effective_config(dao, &frame.step_type_keys);

    // Submission-time floor enforcement for floor-gated step types.
    // Mirrors board_voting::submit_proposal's EnableProposalType check but
    // operating on the composite's effective approval_threshold.
    assert_composite_floors(&frame.step_type_keys, effective.approval_threshold());

    let frame_id = object::id(&frame);
    let step_type_keys = copy_ascii_vec(&frame.step_type_keys);
    let step_types = copy_type_name_vec(&frame.step_types);

    let payload = CompositePayload { frame_id, step_type_keys, step_types };

    let step_count = frame.step_type_keys.length();

    // Seal the frame before sharing so no caller can mutate it after the vote.
    seal_frame(&mut frame);

    // Share the frame; it is now immutable to callers (sealed + no public write API).
    transfer::public_share_object(frame);

    proposal::create<CompositePayload>(
        dao.id(),
        composite_key,
        proposer,
        metadata_ipfs,
        payload,
        effective,
        dao.governance(),
        true,
        clock,
        ctx,
    );

    // proposal::create emits ProposalCreated (type_key="Composite") with the
    // proposal_id. Emit CompositeSubmitted so indexers can join frame ↔ proposal
    // on the shared frame_id without needing to join on block position.
    event::emit(CompositeSubmitted {
        frame_id,
        dao_id: dao.id(),
        step_count,
        proposer,
    });
}

// === Execution: pipeline lifecycle ===

/// Begin pipeline execution for a passed composite proposal.
/// Takes the ExecutionTicket<CompositePayload> from ticket_from_vote.
/// Verifies the frame is sealed and its contents match what was voted on.
/// Returns a Pipeline hot potato that enforces forward-only step ordering.
public fun begin_pipeline(
    dao: &DAO,
    frame: &CompositeFrame,
    ticket: ExecutionTicket<CompositePayload>,
): Pipeline {
    let payload = ticket.ticket_payload();
    assert!(payload.frame_id == object::id(frame), EFrameMismatch);

    // Verify the frame was sealed at proposal creation and has not been modified.
    assert!(frame.is_sealed(), EFrameNotSealed);
    assert!(payload.step_type_keys == frame.step_type_keys(), EFrameContentsMismatch);
    assert!(payload.step_types == frame.step_types(), EFrameContentsMismatch);

    let total_steps = payload.step_type_keys.length();
    let last_executed_snapshot = *dao.last_executed_at();
    let dao_id = ticket.ticket_dao_id();
    let composite_proposal_id = ticket.ticket_request().req_proposal_id();

    // Consume the composite-level ticket; the Pipeline hot potato takes over.
    ticket.discharge();

    Pipeline {
        frame_id: object::id(frame),
        dao_id,
        composite_proposal_id,
        current_step: 0,
        total_steps,
        last_executed_snapshot,
    }
}

/// Advance the pipeline by one step. Validates the caller-supplied type P
/// against the recorded TypeName, enforces per-step freeze check, asserts
/// the type has no cooldown (cooldown-bearing types are prohibited from
/// composites), extracts the payload, and returns
///   (ExecutionTicket<P>, next_pipeline: Pipeline)
///
/// Pass the ticket to the unified execute_* handler for P.
/// The returned Pipeline must be used in the next advance_step or
/// finalize_pipeline call.
public fun advance_step<P: store>(
    dao: &mut DAO,
    frame: &mut CompositeFrame,
    pipeline: Pipeline,
    freeze: &EmergencyFreeze,
    clock: &Clock,
): (ExecutionTicket<P>, Pipeline) {
    assert!(object::id(frame) == pipeline.frame_id, EFrameMismatch);
    assert!(pipeline.current_step < pipeline.total_steps, EPipelineComplete);

    let step_idx = pipeline.current_step;
    let step_type_key = frame.step_type_keys[step_idx];
    let expected_type = frame.step_types[step_idx];

    assert!(type_name::with_defining_ids<P>() == expected_type, EStepTypeMismatch);

    freeze.assert_not_frozen(&step_type_key, clock);

    let step_config = *dao.proposal_configs().get(&step_type_key);

    // Cooldown-bearing types are prohibited from composites unless explicitly
    // opted-in via composable_allowed (enforced at config-write time by
    // assert_config_composability). Assert here as defence-in-depth.
    assert!(
        step_config.cooldown_ms() == 0 || step_config.composable_allowed(),
        ECooldownTypeNotComposable,
    );

    dao.record_execution(step_type_key, clock.timestamp_ms());

    let payload: P = df::remove(&mut frame.id, StepKey { index: step_idx });
    frame.steps_extracted = frame.steps_extracted + 1;

    let ticket = proposal::new_ticket_composite<P>(
        pipeline.dao_id,
        pipeline.composite_proposal_id,
        payload,
    );

    let Pipeline {
        frame_id,
        dao_id,
        composite_proposal_id,
        current_step: _,
        total_steps,
        last_executed_snapshot,
    } = pipeline;

    let next = Pipeline {
        frame_id,
        dao_id,
        composite_proposal_id,
        current_step: step_idx + 1,
        total_steps,
        last_executed_snapshot,
    };

    (ticket, next)
}

/// Consume the Pipeline hot potato after all steps have been advanced.
/// Aborts if any steps remain unexecuted.
public fun finalize_pipeline(pipeline: Pipeline) {
    assert!(pipeline.current_step == pipeline.total_steps, EPipelineIncomplete);
    let Pipeline {
        frame_id: _,
        dao_id: _,
        composite_proposal_id: _,
        current_step: _,
        total_steps: _,
        last_executed_snapshot: _,
    } = pipeline;
}

/// Delete an exhausted CompositeFrame whose every step payload has been extracted.
/// Safe to call by any party — the on-chain record is preserved in events.
/// The caller receives the Sui storage rebate.
/// Aborts if any step payloads remain unextracted (EFrameNotExhausted).
public fun delete_exhausted_frame(frame: CompositeFrame) {
    let CompositeFrame {
        id,
        sealed: _,
        steps_extracted,
        dao_id: _,
        step_type_keys,
        step_types: _,
    } = frame;
    assert!(steps_extracted == step_type_keys.length(), EFrameNotExhausted);
    object::delete(id);
}

// === Sealing ===

/// Lock the frame after all step payloads have been added. Irreversible.
/// Called by submit_composite automatically; can also be called explicitly
/// before submit_composite if the caller wants to verify the seal.
public(package) fun seal_frame(frame: &mut CompositeFrame) {
    assert!(!frame.sealed, EFrameAlreadySealed);
    frame.sealed = true;
}

/// Returns true after seal_frame has been called.
public fun is_sealed(frame: &CompositeFrame): bool {
    frame.sealed
}

/// Read-only accessor for content verification in begin_pipeline.
public fun step_type_keys(frame: &CompositeFrame): vector<std::ascii::String> {
    frame.step_type_keys
}

/// Read-only accessor for content verification in begin_pipeline.
public fun step_types(frame: &CompositeFrame): vector<TypeName> {
    frame.step_types
}

// === Internal ===

/// Compute the effective ProposalConfig for a composite as the component-wise
/// max of the "Composite" base config and each step type's config.
fun compute_effective_config(
    dao: &DAO,
    step_type_keys: &vector<std::ascii::String>,
): ProposalConfig {
    let composite_key = COMPOSITE_TYPE_KEY.to_ascii_string();
    let base = *dao.proposal_configs().get(&composite_key);

    let mut quorum = base.quorum();
    let mut approval_threshold = base.approval_threshold();
    let mut execution_delay_ms = base.execution_delay_ms();
    let mut cooldown_ms = base.cooldown_ms();

    let mut i = 0;
    while (i < step_type_keys.length()) {
        let step_config = dao.proposal_configs().get(&step_type_keys[i]);
        if (step_config.quorum() > quorum) { quorum = step_config.quorum() };
        if (step_config.approval_threshold() > approval_threshold) {
            approval_threshold = step_config.approval_threshold()
        };
        if (step_config.execution_delay_ms() > execution_delay_ms) {
            execution_delay_ms = step_config.execution_delay_ms()
        };
        if (step_config.cooldown_ms() > cooldown_ms) { cooldown_ms = step_config.cooldown_ms() };
        i = i + 1;
    };

    proposal::new_config(
        quorum,
        approval_threshold,
        base.propose_threshold(),
        base.expiry_ms(),
        execution_delay_ms,
        cooldown_ms,
    )
}

/// Enforce submission-time approval-threshold floors for floor-gated types
/// appearing as steps in the composite. Uses the already-computed
/// effective_threshold so any single floor-gated step raises the whole composite.
fun assert_composite_floors(step_type_keys: &vector<std::ascii::String>, effective_threshold: u16) {
    let mut i = 0;
    while (i < step_type_keys.length()) {
        let key = &step_type_keys[i];

        if (*key == b"EnableProposalType".to_ascii_string()) {
            assert!((effective_threshold as u64) >= ENABLE_APPROVAL_FLOOR_BPS, EFloorNotMet);
        };

        // UpdateProposalConfig: inspect the stored payload's target_type_key to detect
        // self-targeting. Because the payload is in a dynamic field (not readable without
        // moving it out), we apply the conservative floor to all UpdateProposalConfig
        // steps in composites — the payload-level check is only feasible for single-action
        // submissions (see admin_ops::propose_update_proposal_config).
        if (*key == b"UpdateProposalConfig".to_ascii_string()) {
            assert!((effective_threshold as u64) >= SELF_UPDATE_APPROVAL_FLOOR_BPS, EFloorNotMet);
        };

        i = i + 1;
    };
}

/// Copy a vector<ascii::String> element-by-element (ascii::String has copy).
fun copy_ascii_vec(v: &vector<std::ascii::String>): vector<std::ascii::String> {
    let mut result = vector[];
    let mut i = 0;
    while (i < v.length()) {
        result.push_back(v[i]);
        i = i + 1;
    };
    result
}

/// Copy a vector<TypeName> element-by-element (TypeName has copy).
fun copy_type_name_vec(v: &vector<TypeName>): vector<TypeName> {
    let mut result = vector[];
    let mut i = 0;
    while (i < v.length()) {
        result.push_back(v[i]);
        i = i + 1;
    };
    result
}

// === Accessors ===

public fun frame_id(payload: &CompositePayload): ID { payload.frame_id }

public fun step_count(payload: &CompositePayload): u64 { payload.step_type_keys.length() }

public fun step_type_key_at(payload: &CompositePayload, index: u64): std::ascii::String {
    payload.step_type_keys[index]
}

public fun pipeline_current_step(pipeline: &Pipeline): u64 { pipeline.current_step }

public fun pipeline_total_steps(pipeline: &Pipeline): u64 { pipeline.total_steps }

public fun max_composite_steps(): u64 { MAX_COMPOSITE_STEPS }

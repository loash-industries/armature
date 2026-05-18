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

use armature::dao::DAO;
use armature::emergency::EmergencyFreeze;
use armature::proposal::{Self, ExecutionRequest, ExternalExecutionCap};
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

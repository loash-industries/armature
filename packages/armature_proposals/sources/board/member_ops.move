module armature_proposals::member_ops;

use armature::dao::DAO;
use armature::proposal::{Self, Proposal, ExecutionRequest};
use armature_proposals::add_member::AddMember;
use armature_proposals::batch_add_members::BatchAddMembers;
use armature_proposals::remove_member::RemoveMember;
use sui::event;

// === Errors ===

const EDaoMismatch: u64 = 0;
const EEmptyBatch: u64 = 1;
const EBatchTooLarge: u64 = 2;

// === Constants ===

/// Maximum number of addresses accepted in a single BatchAddMembers proposal.
/// Bounds execution gas and keeps the proposal payload tractable for indexers.
const MAX_BATCH_SIZE: u64 = 100;

// === Events ===

/// Emitted when a single member is added to the board via governance.
public struct MemberAdded has copy, drop {
    dao_id: ID,
    member: address,
}

/// Emitted when a single member is removed from the board via governance.
public struct MemberRemoved has copy, drop {
    dao_id: ID,
    member: address,
}

/// Emitted when a batch of members is processed via governance.
/// `added` and `skipped` together reconstruct the full proposed batch:
/// `added` is the addresses actually inserted, `skipped` is the addresses
/// already on the board at execution time. Both are in input order.
public struct MembersBatchAdded has copy, drop {
    dao_id: ID,
    added: vector<address>,
    skipped: vector<address>,
}

// === Handlers ===

public fun execute_add_member(
    dao: &mut DAO,
    proposal: &Proposal<AddMember>,
    request: ExecutionRequest<AddMember>,
) {
    add_member_impl(dao, proposal.payload(), &request);
    proposal::finalize(request, proposal);
}

/// Execute a BatchAddMembers proposal: add many addresses to the DAO's board.
///
/// Aborts on:
///   - empty batch (`EEmptyBatch`)
///   - batch larger than `MAX_BATCH_SIZE` (`EBatchTooLarge`)
///   - the same address listed more than once within the batch
///     (`governance::EDuplicateBoardMember`)
///
/// Does NOT abort on addresses that are already on the board — those are
/// silently skipped. The emitted `MembersBatchAdded` event reports both
/// `added` and `skipped` so the on-chain audit trail reflects what
/// actually happened. See `dao::add_board_members_governance` for the
/// rationale.
public fun execute_batch_add_members(
    dao: &mut DAO,
    proposal: &Proposal<BatchAddMembers>,
    request: ExecutionRequest<BatchAddMembers>,
) {
    assert!(dao.id() == request.req_dao_id(), EDaoMismatch);
    let payload = proposal.payload();
    let members = payload.members();

    let len = members.length();
    assert!(len > 0, EEmptyBatch);
    assert!(len <= MAX_BATCH_SIZE, EBatchTooLarge);

    let (added, skipped) = dao.add_board_members_governance(*members, &request);

    event::emit(MembersBatchAdded {
        dao_id: dao.id(),
        added,
        skipped,
    });

    proposal::finalize(request, proposal);
}

public fun execute_add_member_step(
    dao: &mut DAO,
    payload: AddMember,
    request: ExecutionRequest<AddMember>,
) {
    add_member_impl(dao, &payload, &request);
    proposal::consume_execution_request(request);
}

public fun execute_remove_member(
    dao: &mut DAO,
    proposal: &Proposal<RemoveMember>,
    request: ExecutionRequest<RemoveMember>,
) {
    remove_member_impl(dao, proposal.payload(), &request);
    proposal::finalize(request, proposal);
}

public fun execute_remove_member_step(
    dao: &mut DAO,
    payload: RemoveMember,
    request: ExecutionRequest<RemoveMember>,
) {
    remove_member_impl(dao, &payload, &request);
    proposal::consume_execution_request(request);
}

// === Internal ===

fun add_member_impl(dao: &mut DAO, payload: &AddMember, request: &ExecutionRequest<AddMember>) {
    assert!(dao.id() == request.req_dao_id(), EDaoMismatch);
    dao.add_board_member_governance(payload.member(), request);
    event::emit(MemberAdded {
        dao_id: dao.id(),
        member: payload.member(),
    });
}

fun remove_member_impl(
    dao: &mut DAO,
    payload: &RemoveMember,
    request: &ExecutionRequest<RemoveMember>,
) {
    assert!(dao.id() == request.req_dao_id(), EDaoMismatch);
    dao.remove_board_member_governance(payload.member(), request);
    event::emit(MemberRemoved {
        dao_id: dao.id(),
        member: payload.member(),
    });
}

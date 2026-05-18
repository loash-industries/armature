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

/// Emitted when a batch of members is added to the board via governance.
public struct MembersBatchAdded has copy, drop {
    dao_id: ID,
    members: vector<address>,
}

// === Handlers ===

/// Execute an AddMember proposal: add a single address to the DAO's board.
public fun execute_add_member(
    dao: &mut DAO,
    proposal: &Proposal<AddMember>,
    request: ExecutionRequest<AddMember>,
) {
    assert!(dao.id() == request.req_dao_id(), EDaoMismatch);
    let payload = proposal.payload();

    dao.add_board_member_governance(
        payload.member(),
        &request,
    );

    event::emit(MemberAdded {
        dao_id: dao.id(),
        member: payload.member(),
    });

    proposal::finalize(request, proposal);
}

/// Execute a BatchAddMembers proposal: add many addresses to the DAO's board
/// in a single atomic operation. Aborts if the batch is empty, exceeds the
/// per-proposal cap, contains duplicates, or any address is already on the board.
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

    dao.add_board_members_governance(*members, &request);

    event::emit(MembersBatchAdded {
        dao_id: dao.id(),
        members: *members,
    });

    proposal::finalize(request, proposal);
}

/// Execute a RemoveMember proposal: remove a single address from the DAO's board.
public fun execute_remove_member(
    dao: &mut DAO,
    proposal: &Proposal<RemoveMember>,
    request: ExecutionRequest<RemoveMember>,
) {
    assert!(dao.id() == request.req_dao_id(), EDaoMismatch);
    let payload = proposal.payload();

    dao.remove_board_member_governance(
        payload.member(),
        &request,
    );

    event::emit(MemberRemoved {
        dao_id: dao.id(),
        member: payload.member(),
    });

    proposal::finalize(request, proposal);
}

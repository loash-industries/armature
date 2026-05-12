module armature_proposals::member_ops;

use armature::dao::DAO;
use armature::proposal::{Self, Proposal, ExecutionRequest};
use armature_proposals::add_member::AddMember;
use armature_proposals::remove_member::RemoveMember;
use sui::event;

// === Errors ===

const EDaoMismatch: u64 = 0;

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

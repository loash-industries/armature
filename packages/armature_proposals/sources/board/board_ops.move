module armature_proposals::board_ops;

use armature::dao::DAO;
use armature::proposal::{Self, Proposal, ExecutionRequest};
use armature_proposals::set_board::SetBoard;
use sui::event;

// === Errors ===

const EDaoMismatch: u64 = 0;

// === Events ===

/// Emitted when the board is updated via governance.
public struct BoardUpdated has copy, drop {
    dao_id: ID,
    new_members: vector<address>,
}

// === Handler ===

/// Execute a SetBoard proposal: replace the DAO's board members.
/// Validation (non-empty, no duplicates) is enforced
/// by governance::set_board inside the framework.
public fun execute_set_board(
    dao: &mut DAO,
    proposal: &Proposal<SetBoard>,
    request: ExecutionRequest<SetBoard>,
) {
    set_board_impl(dao, proposal.payload(), &request);
    proposal::finalize(request, proposal);
}

/// Composite step variant: execute a SetBoard step extracted from a Pipeline.
public fun execute_set_board_step(
    dao: &mut DAO,
    payload: SetBoard,
    request: ExecutionRequest<SetBoard>,
) {
    set_board_impl(dao, &payload, &request);
    proposal::consume_execution_request(request);
}

// === Internal ===

fun set_board_impl(dao: &mut DAO, payload: &SetBoard, request: &ExecutionRequest<SetBoard>) {
    assert!(dao.id() == request.req_dao_id(), EDaoMismatch);
    dao.set_board_governance(*payload.new_members(), request);
    event::emit(BoardUpdated {
        dao_id: dao.id(),
        new_members: *payload.new_members(),
    });
}

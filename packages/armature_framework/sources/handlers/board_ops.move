module armature::board_ops;

use armature::dao::DAO;
use armature::proposal::{ExecutionRequest, ExecutionTicket};
use armature::set_board::{Self, SetBoard};
use sui::event;

// === Errors ===

const EDaoMismatch: u64 = 0;

// === Events ===

/// Emitted when the board is updated via governance.
public struct BoardUpdated has copy, drop {
    dao_id: ID,
    added: vector<address>,
    removed: vector<address>,
}

// === Handler ===

/// Execute a SetBoard proposal: add and remove the listed board members.
/// Validation (non-empty result, no duplicates, adds not already members,
/// removals currently members) is enforced by governance::set_board.
public fun execute_set_board(dao: &mut DAO, ticket: ExecutionTicket<SetBoard>) {
    set_board_impl(dao, ticket.ticket_payload(), ticket.ticket_request(set_board::permit()));
    ticket.discharge(set_board::permit());
}

// === Internal ===

fun set_board_impl(dao: &mut DAO, payload: &SetBoard, request: &ExecutionRequest<SetBoard>) {
    assert!(dao.id() == request.req_dao_id(), EDaoMismatch);
    dao.set_board_governance(*payload.to_add(), *payload.to_remove(), request);
    event::emit(BoardUpdated {
        dao_id: dao.id(),
        added: *payload.to_add(),
        removed: *payload.to_remove(),
    });
}

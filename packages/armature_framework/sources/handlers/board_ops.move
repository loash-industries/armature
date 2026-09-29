module armature::board_ops;

use armature::ou::OU;
use armature::proposal::{ExecutionRequest, ExecutionTicket};
use armature::set_board::{Self, SetBoard};
use sui::event;

// === Errors ===

const EOuMismatch: u64 = 0;

// === Events ===

/// Emitted when the board is updated via governance.
public struct BoardUpdated has copy, drop {
    ou_id: ID,
    added: vector<address>,
    removed: vector<address>,
}

// === Handler ===

/// Execute a SetBoard proposal: add and remove the listed board members.
/// Validation (non-empty result, no duplicates, adds not already members,
/// removals currently members) is enforced by governance::set_board.
public fun execute_set_board(ou: &mut OU, ticket: ExecutionTicket<SetBoard>) {
    set_board_impl(ou, ticket.ticket_payload(), ticket.ticket_request(set_board::permit()));
    ticket.discharge(set_board::permit());
}

// === Internal ===

fun set_board_impl(ou: &mut OU, payload: &SetBoard, request: &ExecutionRequest<SetBoard>) {
    assert!(ou.id() == request.req_ou_id(), EOuMismatch);
    ou.set_board_governance(*payload.to_add(), *payload.to_remove(), request);
    event::emit(BoardUpdated {
        ou_id: ou.id(),
        added: *payload.to_add(),
        removed: *payload.to_remove(),
    });
}

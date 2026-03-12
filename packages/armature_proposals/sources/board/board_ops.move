module armature_proposals::board_ops;

use armature::dao::DAO;
use armature::proposal::{Self, Proposal, ExecutionRequest};
use armature_proposals::set_board::SetBoard;
use sui::event;

// === Events ===

/// Emitted when the board is updated via governance.
public struct BoardUpdated has copy, drop {
    dao_id: ID,
    new_members: vector<address>,
    new_seat_count: u8,
}

// === Handler ===

/// Execute a SetBoard proposal: replace the DAO's board members and seat count.
/// Validation (non-empty, no duplicates, members <= seat_count) is enforced
/// by governance::set_board inside the framework.
public fun execute_set_board(
    dao: &mut DAO,
    proposal: &Proposal<SetBoard>,
    request: ExecutionRequest<SetBoard>,
) {
    let payload = proposal.payload();

    dao.set_board_governance(
        *payload.new_members(),
        payload.new_seat_count(),
        &request,
    );

    event::emit(BoardUpdated {
        dao_id: dao.id(),
        new_members: *payload.new_members(),
        new_seat_count: payload.new_seat_count(),
    });

    proposal::consume(request);
}

module armature::member_ops;

use armature::add_member::{Self, AddMember};
use armature::batch_add_members::{Self, BatchAddMembers};
use armature::batch_remove_members::{Self, BatchRemoveMembers};
use armature::ou::OU;
use armature::proposal::{ExecutionRequest, ExecutionTicket};
use armature::remove_member::{Self, RemoveMember};
use sui::event;

// === Errors ===

const EOuMismatch: u64 = 0;
const EEmptyBatch: u64 = 1;
const EBatchTooLarge: u64 = 2;

// === Constants ===

/// Maximum number of addresses accepted in a single BatchAddMembers proposal.
/// Bounds execution gas and keeps the proposal payload tractable for indexers.
const MAX_BATCH_SIZE: u64 = 100;

// === Events ===

/// Emitted when a single member is added to the board via governance.
public struct MemberAdded has copy, drop {
    ou_id: ID,
    member: address,
}

/// Emitted when a single member is removed from the board via governance.
public struct MemberRemoved has copy, drop {
    ou_id: ID,
    member: address,
}

/// Emitted when a batch of members is processed via governance.
/// `added` and `skipped` together reconstruct the full proposed batch:
/// `added` is the addresses actually inserted, `skipped` is the addresses
/// already on the board at execution time. Both are in input order.
public struct MembersBatchAdded has copy, drop {
    ou_id: ID,
    added: vector<address>,
    skipped: vector<address>,
}

/// Emitted when a batch of members is removed from the board via governance.
public struct MembersBatchRemoved has copy, drop {
    ou_id: ID,
    removed: vector<address>,
}

// === Handlers ===

public fun execute_add_member(ou: &mut OU, ticket: ExecutionTicket<AddMember>) {
    add_member_impl(ou, ticket.ticket_payload(), ticket.ticket_request(add_member::permit()));
    ticket.discharge(add_member::permit());
}

/// Execute a BatchAddMembers proposal: add many addresses to the OU's board.
///
/// Aborts on:
/// - empty batch (`EEmptyBatch`)
/// - batch larger than `MAX_BATCH_SIZE` (`EBatchTooLarge`)
/// - the same address listed more than once within the batch
/// (`governance::EDuplicateBoardMember`)
///
/// Does NOT abort on addresses that are already on the board — those are
/// silently skipped. The emitted `MembersBatchAdded` event reports both
/// `added` and `skipped` so the on-chain audit trail reflects what
/// actually happened. See `ou::add_board_members_governance` for the
/// rationale.
public fun execute_batch_add_members(ou: &mut OU, ticket: ExecutionTicket<BatchAddMembers>) {
    assert!(ou.id() == ticket.ticket_ou_id(), EOuMismatch);
    let payload = ticket.ticket_payload();
    let members = payload.members();

    let len = members.length();
    assert!(len > 0, EEmptyBatch);
    assert!(len <= MAX_BATCH_SIZE, EBatchTooLarge);

    let (added, skipped) = ou.add_board_members_governance(
        *members,
        ticket.ticket_request(batch_add_members::permit()),
    );

    event::emit(MembersBatchAdded {
        ou_id: ou.id(),
        added,
        skipped,
    });

    ticket.discharge(batch_add_members::permit());
}

/// Execute a BatchRemoveMembers proposal: remove many addresses from the OU's board.
///
/// Aborts on:
/// - empty batch (`EEmptyBatch`)
/// - batch larger than `MAX_BATCH_SIZE` (`EBatchTooLarge`)
/// - any address not on the board (`governance::ENotBoardMember`)
/// - any duplicate address in the batch (`governance::EDuplicateBoardMember`)
/// - removal would leave the board empty (`governance::EEmptyBoard`)
public fun execute_batch_remove_members(ou: &mut OU, ticket: ExecutionTicket<BatchRemoveMembers>) {
    assert!(ou.id() == ticket.ticket_ou_id(), EOuMismatch);
    let payload = ticket.ticket_payload();
    let members = payload.members();
    let len = members.length();
    assert!(len > 0, EEmptyBatch);
    assert!(len <= MAX_BATCH_SIZE, EBatchTooLarge);
    let removed = ou.remove_board_members_governance(
        *members,
        ticket.ticket_request(batch_remove_members::permit()),
    );
    event::emit(MembersBatchRemoved { ou_id: ou.id(), removed });
    ticket.discharge(batch_remove_members::permit());
}

public fun execute_remove_member(ou: &mut OU, ticket: ExecutionTicket<RemoveMember>) {
    remove_member_impl(
        ou,
        ticket.ticket_payload(),
        ticket.ticket_request(remove_member::permit()),
    );
    ticket.discharge(remove_member::permit());
}

// === Internal ===

fun add_member_impl(ou: &mut OU, payload: &AddMember, request: &ExecutionRequest<AddMember>) {
    assert!(ou.id() == request.req_ou_id(), EOuMismatch);
    ou.add_board_member_governance(payload.member(), request);
    event::emit(MemberAdded {
        ou_id: ou.id(),
        member: payload.member(),
    });
}

fun remove_member_impl(
    ou: &mut OU,
    payload: &RemoveMember,
    request: &ExecutionRequest<RemoveMember>,
) {
    assert!(ou.id() == request.req_ou_id(), EOuMismatch);
    ou.remove_board_member_governance(payload.member(), request);
    event::emit(MemberRemoved {
        ou_id: ou.id(),
        member: payload.member(),
    });
}

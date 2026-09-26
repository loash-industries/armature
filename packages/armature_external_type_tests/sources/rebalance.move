/// A third-party proposal type, shaped like an integrator's: a generic payload
/// defined outside the armature packages and a handler that consumes its ticket.
module armature_external_type_tests::rebalance;

use armature::dao::DAO;
use armature::proposal::ExecutionTicket;
use sui::event;

// === Errors ===

const EDaoMismatch: u64 = 0;

// === Structs ===

public struct Rebalance<phantom T> has drop, store {
    amount: u64,
}

// === Events ===

public struct Rebalanced has copy, drop {
    dao_id: ID,
    amount: u64,
}

// === Constructor ===

public fun new<T>(amount: u64): Rebalance<T> {
    Rebalance { amount }
}

// === Accessors ===

public fun amount<T>(self: &Rebalance<T>): u64 { self.amount }

// === Handler ===

/// Execute a `Rebalance<T>` ticket for `dao`.
public fun execute_rebalance<T>(dao: &DAO, ticket: ExecutionTicket<Rebalance<T>>) {
    assert!(dao.id() == ticket.ticket_dao_id(), EDaoMismatch);
    event::emit(Rebalanced { dao_id: dao.id(), amount: ticket.ticket_payload().amount });
    ticket.discharge();
}

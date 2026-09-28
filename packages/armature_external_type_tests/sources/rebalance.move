/// A third-party proposal type, shaped like an integrator's: a generic payload
/// defined outside the armature packages and a handler that consumes its ticket.
module armature_external_type_tests::rebalance;

use armature::dao::DAO;
use armature::emergency::EmergencyFreeze;
use armature::external_execution;
use armature::proposal::{ExecutionTicket, ExternalExecutionCap};
use std::internal;
use sui::clock::Clock;
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

// === Bypass ===

/// Mint a bypass ticket for `Rebalance<T>`. `ticket_from_cap` requires
/// `Permit<Rebalance<T>>`, so this module is the only place a bypass ticket
/// for the type can be minted: a real integrator runs its external
/// authorization check (Character ownership, token balance, ...) here, before
/// the mint. This sample has none.
public fun submit_bypass<T>(
    cap: &ExternalExecutionCap<Rebalance<T>>,
    dao: &DAO,
    freeze: &EmergencyFreeze,
    amount: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): ExecutionTicket<Rebalance<T>> {
    external_execution::ticket_from_cap_readonly(
        cap,
        dao,
        freeze,
        option::none(),
        Rebalance { amount },
        internal::permit(),
        clock,
        ctx,
    )
}

// === Handler ===

/// Execute a `Rebalance<T>` ticket for `dao`.
public fun execute_rebalance<T>(dao: &DAO, ticket: ExecutionTicket<Rebalance<T>>) {
    assert!(dao.id() == ticket.ticket_dao_id(), EDaoMismatch);
    event::emit(Rebalanced { dao_id: dao.id(), amount: ticket.ticket_payload().amount });
    ticket.discharge(internal::permit());
}

// === Test Helpers ===

#[test_only]
/// The ticket's request, as a buggy handler in this module would see it. Lets
/// tests check that permission bits still bound what `Rebalance`'s own module
/// can do with its request.
public fun request_for_testing<T>(
    ticket: &ExecutionTicket<Rebalance<T>>,
): &armature::proposal::ExecutionRequest<Rebalance<T>> {
    ticket.ticket_request(internal::permit())
}

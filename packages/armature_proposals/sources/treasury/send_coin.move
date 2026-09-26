module armature_proposals::send_coin;

use std::internal::{Self, Permit};

/// Transfer amount of Coin<T> from treasury to an address.
public struct SendCoin<phantom T> has drop, store {
    recipient: address,
    amount: u64,
}

// === Constructor ===

public fun new<T>(recipient: address, amount: u64): SendCoin<T> {
    SendCoin { recipient, amount }
}

// === Accessors ===

public fun recipient<T>(self: &SendCoin<T>): address { self.recipient }

public fun amount<T>(self: &SendCoin<T>): u64 { self.amount }

// === Handler authority ===

/// `Permit<SendCoin>` for this package's handler: the only way to spend or close
/// an `ExecutionTicket<SendCoin>` (see `proposal::ticket_request`).
public(package) fun permit<T>(): Permit<SendCoin<T>> { internal::permit() }

module armature_proposals::send_coin;

/// Transfer amount of Coin<T> from treasury to an address.
public struct SendCoin<phantom T> has store {
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

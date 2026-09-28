module armature_proposals::send_batch_multicoin_to_player;

use armature_proposals::multicoin_item::MultiCoinItem;
use std::internal::{Self, Permit};

/// Transfer a batch of multicoin balances from treasury to a player address.
public struct SendBatchMulticoinToAddress has drop, store {
    recipient: address,
    items: vector<MultiCoinItem>,
}

// === Constructor ===

public fun new(recipient: address, items: vector<MultiCoinItem>): SendBatchMulticoinToAddress {
    SendBatchMulticoinToAddress { recipient, items }
}

// === Accessors ===

public fun recipient(self: &SendBatchMulticoinToAddress): address { self.recipient }

public fun items(self: &SendBatchMulticoinToAddress): &vector<MultiCoinItem> { &self.items }

// === Handler authority ===

/// `Permit<SendBatchMulticoinToAddress>` for this package's handler: the only way to spend or close
/// an `ExecutionTicket<SendBatchMulticoinToAddress>` (see `proposal::ticket_request`).
public(package) fun permit(): Permit<SendBatchMulticoinToAddress> { internal::permit() }

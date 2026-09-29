module armature_proposals::send_batch_multicoin_to_ou;

use armature_proposals::multicoin_item::MultiCoinItem;
use std::internal::{Self, Permit};

/// Transfer a batch of multicoin balances from treasury to another OU's TreasuryVault.
public struct SendBatchMulticoinToOU has drop, store {
    recipient_treasury: ID,
    items: vector<MultiCoinItem>,
}

// === Constructor ===

public fun new(recipient_treasury: ID, items: vector<MultiCoinItem>): SendBatchMulticoinToOU {
    SendBatchMulticoinToOU { recipient_treasury, items }
}

// === Accessors ===

public fun recipient_treasury(self: &SendBatchMulticoinToOU): ID { self.recipient_treasury }

public fun items(self: &SendBatchMulticoinToOU): &vector<MultiCoinItem> { &self.items }

// === Handler authority ===

/// `Permit<SendBatchMulticoinToOU>` for this package's handler: the only way to spend or close
/// an `ExecutionTicket<SendBatchMulticoinToOU>` (see `proposal::ticket_request`).
public(package) fun permit(): Permit<SendBatchMulticoinToOU> { internal::permit() }

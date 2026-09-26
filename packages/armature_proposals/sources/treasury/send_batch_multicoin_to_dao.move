module armature_proposals::send_batch_multicoin_to_dao;

use armature_proposals::multicoin_item::MultiCoinItem;
use std::internal::{Self, Permit};

/// Transfer a batch of multicoin balances from treasury to another DAO's TreasuryVault.
public struct SendBatchMulticoinToDAO has drop, store {
    recipient_treasury: ID,
    items: vector<MultiCoinItem>,
}

// === Constructor ===

public fun new(recipient_treasury: ID, items: vector<MultiCoinItem>): SendBatchMulticoinToDAO {
    SendBatchMulticoinToDAO { recipient_treasury, items }
}

// === Accessors ===

public fun recipient_treasury(self: &SendBatchMulticoinToDAO): ID { self.recipient_treasury }

public fun items(self: &SendBatchMulticoinToDAO): &vector<MultiCoinItem> { &self.items }

// === Handler authority ===

/// `Permit<SendBatchMulticoinToDAO>` for this package's handler: the only way to spend or close
/// an `ExecutionTicket<SendBatchMulticoinToDAO>` (see `proposal::ticket_request`).
public(package) fun permit(): Permit<SendBatchMulticoinToDAO> { internal::permit() }

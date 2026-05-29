module armature_proposals::send_batch_multicoin_to_dao;

use armature_proposals::multicoin_item::MultiCoinItem;

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

module armature::batch_remove_members;

use std::internal::{Self, Permit};

/// Remove multiple members from the board in a single proposal.
/// Aborts atomically if any address is not on the board, if the batch
/// contains duplicates, or if removal would leave the board empty.
public struct BatchRemoveMembers has drop, store {
    members: vector<address>,
}

// === Constructor ===

public fun new(members: vector<address>): BatchRemoveMembers {
    BatchRemoveMembers { members }
}

// === Accessors ===

public fun members(self: &BatchRemoveMembers): &vector<address> { &self.members }

// === Handler authority ===

/// `Permit<BatchRemoveMembers>` for this package's handler: the only way to spend or close
/// an `ExecutionTicket<BatchRemoveMembers>` (see `proposal::ticket_request`).
public(package) fun permit(): Permit<BatchRemoveMembers> { internal::permit() }

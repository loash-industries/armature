module armature::batch_add_members;

use std::internal::{Self, Permit};

/// Add multiple members to the board in a single proposal.
/// Aborts atomically if any address is already on the board or if the
/// batch exceeds the per-proposal cap (enforced in the handler).
public struct BatchAddMembers has drop, store {
    members: vector<address>,
}

// === Constructor ===

public fun new(members: vector<address>): BatchAddMembers {
    BatchAddMembers { members }
}

// === Accessors ===

public fun members(self: &BatchAddMembers): &vector<address> { &self.members }

// === Handler authority ===

/// `Permit<BatchAddMembers>` for this package's handler: the only way to spend or close
/// an `ExecutionTicket<BatchAddMembers>` (see `proposal::ticket_request`).
public(package) fun permit(): Permit<BatchAddMembers> { internal::permit() }

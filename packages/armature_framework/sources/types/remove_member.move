module armature::remove_member;

use std::internal::{Self, Permit};

/// Remove a single member from the board.
/// Lighter-weight alternative to SetBoard when only one address needs to be removed.
public struct RemoveMember has copy, drop, store {
    member: address,
}

// === Constructor ===

public fun new(member: address): RemoveMember {
    RemoveMember { member }
}

// === Accessors ===

public fun member(self: &RemoveMember): address { self.member }

// === Handler authority ===

/// `Permit<RemoveMember>` for this package's handler: the only way to spend or close
/// an `ExecutionTicket<RemoveMember>` (see `proposal::ticket_request`).
public(package) fun permit(): Permit<RemoveMember> { internal::permit() }

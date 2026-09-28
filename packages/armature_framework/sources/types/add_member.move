module armature::add_member;

use std::internal::{Self, Permit};

/// Add a single member to the board.
/// Lighter-weight alternative to SetBoard when only one address needs to be added.
public struct AddMember has copy, drop, store {
    member: address,
}

// === Constructor ===

public fun new(member: address): AddMember {
    AddMember { member }
}

// === Accessors ===

public fun member(self: &AddMember): address { self.member }

// === Handler authority ===

/// `Permit<AddMember>` for this package's handler: the only way to spend or close
/// an `ExecutionTicket<AddMember>` (see `proposal::ticket_request`).
public(package) fun permit(): Permit<AddMember> { internal::permit() }

module armature_proposals::batch_remove_members;

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

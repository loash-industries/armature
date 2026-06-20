module armature::charter;

use armature::proposal::ExecutionRequest;

// === Errors ===

const EDaoMismatch: u64 = 0;

// === Structs ===

/// On-chain charter / constitution for the DAO.
/// Stores the human-readable purpose and rules. Created as a shared object during DAO creation.
public struct Charter has key, store {
    id: UID,
    dao_id: ID,
    name: std::string::String,
    metadata_uri: std::string::String,
}

// === Constructor ===

/// Create a new Charter. Only callable within the framework package.
public(package) fun new(
    dao_id: ID,
    name: std::string::String,
    metadata_uri: std::string::String,
    ctx: &mut TxContext,
): Charter {
    Charter {
        id: object::new(ctx),
        dao_id,
        name,
        metadata_uri,
    }
}

/// Share the charter as a shared object.
#[allow(lint(share_owned, custom_state_change))]
public(package) fun share(charter: Charter) {
    transfer::share_object(charter);
}

// === Accessors ===

/// Returns the DAO ID this charter belongs to.
public fun dao_id(self: &Charter): ID { self.dao_id }

/// Returns the DAO name.
public fun name(self: &Charter): &std::string::String { &self.name }

/// Returns the DAO metadata URL.
public fun metadata_uri(self: &Charter): &std::string::String { &self.metadata_uri }

/// Destroy a Charter object.
public(package) fun destroy(charter: Charter) {
    let Charter { id, dao_id: _, name: _, metadata_uri: _ } = charter;
    id.delete();
}

// === Public Mutators (ExecutionRequest-gated) ===

/// Update the DAO's metadata URL.
/// Authorized by ExecutionRequest — only callable within a governance-approved PTB.
public fun update_metadata<P>(
    self: &mut Charter,
    new_metadata_uri: std::string::String,
    req: &ExecutionRequest<P>,
) {
    assert!(self.dao_id == req.req_dao_id(), EDaoMismatch);
    self.metadata_uri = new_metadata_uri;
}

module armature::charter;

use armature::permissions;
use armature::proposal::ExecutionRequest;

// === Errors ===

const EOuMismatch: u64 = 0;

// === Structs ===

/// On-chain charter / constitution for the OU.
/// Stores the human-readable purpose and rules. Created as a shared object during OU creation.
public struct Charter has key, store {
    id: UID,
    ou_id: ID,
    name: std::string::String,
    metadata_uri: std::string::String,
}

// === Constructor ===

/// Create a new Charter. Only callable within the framework package.
public(package) fun new(
    ou_id: ID,
    name: std::string::String,
    metadata_uri: std::string::String,
    ctx: &mut TxContext,
): Charter {
    Charter {
        id: object::new(ctx),
        ou_id,
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

/// Returns the OU ID this charter belongs to.
public fun ou_id(self: &Charter): ID { self.ou_id }

/// Returns the OU name.
public fun name(self: &Charter): &std::string::String { &self.name }

/// Returns the OU metadata URL.
public fun metadata_uri(self: &Charter): &std::string::String { &self.metadata_uri }

/// Destroy a Charter object.
public(package) fun destroy(charter: Charter) {
    let Charter { id, ou_id: _, name: _, metadata_uri: _ } = charter;
    id.delete();
}

// === Public Mutators (ExecutionRequest-gated) ===

/// Update the OU's metadata URL.
/// Authorized by ExecutionRequest — only callable within a governance-approved PTB.
/// Requires METADATA (`proposal::assert_permitted`).
public fun update_metadata<P>(
    self: &mut Charter,
    new_metadata_uri: std::string::String,
    req: &ExecutionRequest<P>,
) {
    assert!(self.ou_id == req.req_ou_id(), EOuMismatch);
    req.assert_permitted(permissions::metadata());
    self.metadata_uri = new_metadata_uri;
}

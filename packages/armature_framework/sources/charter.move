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
    description: std::string::String,
    image_url: std::string::String,
}

// === Constructor ===

/// Create a new Charter. Only callable within the framework package.
public(package) fun new(
    dao_id: ID,
    name: std::string::String,
    description: std::string::String,
    image_url: std::string::String,
    ctx: &mut TxContext,
): Charter {
    Charter {
        id: object::new(ctx),
        dao_id,
        name,
        description,
        image_url,
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

/// Returns the DAO description.
public fun description(self: &Charter): &std::string::String { &self.description }

/// Returns the DAO image URL.
public fun image_url(self: &Charter): &std::string::String { &self.image_url }

// === Public Mutators (ExecutionRequest-gated) ===

/// Update the DAO's metadata IPFS CID (stored as image_url).
/// Authorized by ExecutionRequest — only callable within a governance-approved PTB.
public fun update_metadata<P>(
    self: &mut Charter,
    new_ipfs_cid: std::string::String,
    req: &ExecutionRequest<P>,
) {
    assert!(self.dao_id == req.req_dao_id(), EDaoMismatch);
    self.image_url = new_ipfs_cid;
}

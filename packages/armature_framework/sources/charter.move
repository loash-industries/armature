module armature::charter;

use armature::permissions;
use armature::proposal::ExecutionRequest;
use armature::version;

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
    /// Version floor (see `version`): its OU's floor at creation.
    min_version: u64,
}

// === Constructor ===

/// Create a new Charter. Only callable within the framework package.
public(package) fun new(
    ou_id: ID,
    name: std::string::String,
    metadata_uri: std::string::String,
    min_version: u64,
    ctx: &mut TxContext,
): Charter {
    Charter {
        id: object::new(ctx),
        ou_id,
        name,
        metadata_uri,
        min_version,
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
    let Charter { id, ou_id: _, name: _, metadata_uri: _, min_version: _ } = charter;
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
    self.check_version_mut();
    req.check_request_version();
    assert!(self.ou_id == req.req_ou_id(), EOuMismatch);
    req.assert_permitted(permissions::metadata());
    self.metadata_uri = new_metadata_uri;
}

// === Version gate (ARMATURE-45, see `version`) ===

/// The oldest framework version allowed to act on this Charter.
public fun min_version(self: &Charter): u64 { self.min_version }

/// Raise this Charter's floor to the running release's `MIN_SUPPORTED`. Anyone
/// may call it; it never lowers the floor. Run by the sweep after a security
/// upgrade.
public fun enforce_version(self: &mut Charter) { self.check_version_mut() }

/// Abort `version::EVersionRetired` if this release is retired for `self`.
public(package) fun check_version(self: &Charter) { version::assert_supported(self.min_version) }

/// `check_version`, then raise the floor to `MIN_SUPPORTED`.
public(package) fun check_version_mut(self: &mut Charter) {
    self.min_version = version::check_and_raise(object::id(self), self.min_version);
}

#[test_only]
public fun set_min_version_for_testing(self: &mut Charter, min_version: u64) {
    self.min_version = min_version;
}

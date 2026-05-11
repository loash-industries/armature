module armature::encrypted_entry;

use armature::dao::DAO;
use std::string::String;
use sui::event;

// === Errors ===

const ENotMember: u64 = 0;
const EEntriesCapReached: u64 = 1;
const EDaoMismatch: u64 = 2;
const EEntryNotStale: u64 = 3;
const EDAONotActive: u64 = 4;
const EIdTooShort: u64 = 5;

// === Constants ===

const MAX_ENTRIES: u64 = 32;

// === Structs ===

public struct EncryptedEntry has key, store {
    id: UID,
    dao_id: ID,
    location: String,
    description: String,
    created_by: address,
    encrypt_epoch: u64,
}

// === Events ===

public struct EntryPublished has copy, drop {
    entry_id: ID,
    dao_id: ID,
    location: String,
    created_by: address,
    encrypt_epoch: u64,
}

public struct EntryUpdated has copy, drop {
    entry_id: ID,
    dao_id: ID,
    new_location: String,
    encrypt_epoch: u64,
}

public struct EntryRemoved has copy, drop {
    entry_id: ID,
    dao_id: ID,
}

// === Public Functions ===

/// Publish a new encrypted entry for this DAO.
/// The caller must encrypt the content off-chain with the current epoch key and
/// upload the ciphertext blob before calling this. Aborts if the 32-entry cap is reached.
#[allow(lint(share_owned))]
public fun publish_entry(
    dao: &mut DAO,
    location: String,
    description: String,
    ctx: &mut TxContext,
) {
    assert!(dao.status().is_active(), EDAONotActive);
    assert!(dao.is_governance_member(ctx.sender()), ENotMember);
    assert!(dao.entries().length() < MAX_ENTRIES, EEntriesCapReached);

    let entry = EncryptedEntry {
        id: object::new(ctx),
        dao_id: dao.id(),
        location,
        description,
        created_by: ctx.sender(),
        encrypt_epoch: dao.encrypt_epoch(),
    };

    let entry_id = object::id(&entry);
    dao.push_entry(entry_id);

    event::emit(EntryPublished {
        entry_id,
        dao_id: dao.id(),
        location: entry.location,
        created_by: ctx.sender(),
        encrypt_epoch: entry.encrypt_epoch,
    });

    transfer::share_object(entry);
}

/// Re-encrypt a stale entry after an epoch rotation.
/// The caller must have re-uploaded the ciphertext blob under the new epoch key.
/// Aborts if the entry is not stale (use edit_entry for same-epoch location updates).
public fun update_entry(
    dao: &DAO,
    entry: &mut EncryptedEntry,
    new_location: String,
    ctx: &TxContext,
) {
    assert!(dao.is_governance_member(ctx.sender()), ENotMember);
    assert!(entry.dao_id == dao.id(), EDaoMismatch);
    assert!(entry.encrypt_epoch != dao.encrypt_epoch(), EEntryNotStale);

    entry.location = new_location;
    entry.encrypt_epoch = dao.encrypt_epoch();

    event::emit(EntryUpdated {
        entry_id: object::id(entry),
        dao_id: dao.id(),
        new_location: entry.location,
        encrypt_epoch: entry.encrypt_epoch,
    });
}

/// Update the blob location within the same epoch (no re-keying required).
/// Use when re-pinning or migrating storage without a key rotation.
public fun edit_entry(
    dao: &DAO,
    entry: &mut EncryptedEntry,
    new_location: String,
    ctx: &TxContext,
) {
    assert!(dao.is_governance_member(ctx.sender()), ENotMember);
    assert!(entry.dao_id == dao.id(), EDaoMismatch);

    entry.location = new_location;

    event::emit(EntryUpdated {
        entry_id: object::id(entry),
        dao_id: dao.id(),
        new_location: entry.location,
        encrypt_epoch: entry.encrypt_epoch,
    });
}

/// Explicitly rotate the encryption epoch, marking all existing entries stale.
/// The primary rotation path is automatic (SetBoard member removal). Use this
/// for out-of-band rotations such as suspected key compromise or periodic hygiene.
/// The EncryptionEpochRotated event is emitted inside dao::increment_encrypt_epoch.
public fun rotate_encryption_epoch(dao: &mut DAO, ctx: &TxContext) {
    assert!(dao.status().is_active(), EDAONotActive);
    assert!(dao.is_governance_member(ctx.sender()), ENotMember);

    dao.increment_encrypt_epoch();
}

/// Remove an entry from the on-chain index and permanently delete the object.
/// The caller is responsible for ensuring the blob is no longer accessible
/// through any still-valid Seal key before calling this.
public fun remove_entry(dao: &mut DAO, entry: EncryptedEntry, ctx: &TxContext) {
    assert!(dao.is_governance_member(ctx.sender()), ENotMember);
    assert!(entry.dao_id == dao.id(), EDaoMismatch);

    let EncryptedEntry {
        id,
        dao_id,
        location: _,
        description: _,
        created_by: _,
        encrypt_epoch: _,
    } = entry;
    let entry_id = id.to_inner();
    dao.remove_entry_id(entry_id);

    event::emit(EntryRemoved { entry_id, dao_id });

    id.delete();
}

/// Walrus Seal approval gate. Called by the key server inside a PTB to authorise
/// decryption-key release for a board member.
/// `id` must be: dao_uid_bytes (32 bytes) || random nonce.
entry fun seal_approve(id: vector<u8>, dao: &DAO, ctx: &TxContext) {
    assert!(id.length() >= 32, EIdTooShort);
    let dao_id_bytes = object::id_to_bytes(&dao.id());
    let mut i = 0;
    while (i < 32) {
        assert!(id[i] == dao_id_bytes[i], EDaoMismatch);
        i = i + 1;
    };
    assert!(dao.is_governance_member(ctx.sender()), ENotMember);
}

// === Accessors ===

public fun entry_dao_id(self: &EncryptedEntry): ID { self.dao_id }

public fun entry_location(self: &EncryptedEntry): &String { &self.location }

public fun entry_description(self: &EncryptedEntry): &String { &self.description }

public fun entry_created_by(self: &EncryptedEntry): address { self.created_by }

public fun entry_encrypt_epoch(self: &EncryptedEntry): u64 { self.encrypt_epoch }

public fun max_entries(): u64 { MAX_ENTRIES }

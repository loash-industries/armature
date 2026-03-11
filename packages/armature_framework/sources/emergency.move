module armature::emergency;

use sui::vec_map::{Self, VecMap};

// === Structs ===

/// Tracks frozen proposal types and their expiry times.
/// Created as a shared object during DAO creation.
public struct EmergencyFreeze has key, store {
    id: UID,
    dao_id: ID,
    frozen_types: VecMap<std::ascii::String, u64>,
    max_freeze_duration_ms: u64,
}

/// Admin capability for triggering emergency freezes.
/// Transferred to the DAO creator at creation time.
public struct FreezeAdminCap has key, store {
    id: UID,
    dao_id: ID,
}

// === Constants ===

const DEFAULT_MAX_FREEZE_DURATION_MS: u64 = 604_800_000; // 7 days

// === Constructor ===

/// Create a new EmergencyFreeze. Only callable within the framework package.
public(package) fun new(dao_id: ID, ctx: &mut TxContext): EmergencyFreeze {
    EmergencyFreeze {
        id: object::new(ctx),
        dao_id,
        frozen_types: vec_map::empty(),
        max_freeze_duration_ms: DEFAULT_MAX_FREEZE_DURATION_MS,
    }
}

/// Create the FreezeAdminCap. Only callable within the framework package.
public(package) fun new_admin_cap(dao_id: ID, ctx: &mut TxContext): FreezeAdminCap {
    FreezeAdminCap {
        id: object::new(ctx),
        dao_id,
    }
}

/// Share the freeze object as a shared object.
#[allow(lint(share_owned, custom_state_change))]
public(package) fun share(freeze: EmergencyFreeze) {
    transfer::share_object(freeze);
}

/// Transfer the FreezeAdminCap to a recipient. Only callable within the framework package.
#[allow(lint(custom_state_change))]
public(package) fun transfer_admin_cap(cap: FreezeAdminCap, recipient: address) {
    transfer::transfer(cap, recipient);
}

// === Accessors ===

/// Returns the DAO ID this freeze tracker belongs to.
public fun dao_id(self: &EmergencyFreeze): ID { self.dao_id }

/// Returns the max freeze duration in milliseconds.
public fun max_freeze_duration_ms(self: &EmergencyFreeze): u64 { self.max_freeze_duration_ms }

/// Returns the DAO ID the admin cap is bound to.
public fun admin_cap_dao_id(self: &FreezeAdminCap): ID { self.dao_id }

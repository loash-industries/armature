module armature::update_freeze_config;

use std::internal::{Self, Permit};

/// Update the max_freeze_duration_ms on the EmergencyFreeze object.
public struct UpdateFreezeConfig has drop, store {
    new_max_freeze_duration_ms: u64,
}

// === Constructor ===

public fun new(new_max_freeze_duration_ms: u64): UpdateFreezeConfig {
    UpdateFreezeConfig { new_max_freeze_duration_ms }
}

// === Accessors ===

public fun new_max_freeze_duration_ms(self: &UpdateFreezeConfig): u64 {
    self.new_max_freeze_duration_ms
}

// === Handler authority ===

/// `Permit<UpdateFreezeConfig>` for this package's handler: the only way to spend or close
/// an `ExecutionTicket<UpdateFreezeConfig>` (see `proposal::ticket_request`).
public(package) fun permit(): Permit<UpdateFreezeConfig> { internal::permit() }

module armature_proposals::update_freeze_config;

/// Update the max_freeze_duration_ms on the EmergencyFreeze object.
public struct UpdateFreezeConfig has store {
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

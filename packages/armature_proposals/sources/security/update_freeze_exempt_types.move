module armature_proposals::update_freeze_exempt_types;

/// Add or remove types from the freeze-exempt set on EmergencyFreeze.
public struct UpdateFreezeExemptTypes has store {
    types_to_add: vector<std::ascii::String>,
    types_to_remove: vector<std::ascii::String>,
}

// === Constructor ===

public fun new(
    types_to_add: vector<std::ascii::String>,
    types_to_remove: vector<std::ascii::String>,
): UpdateFreezeExemptTypes {
    UpdateFreezeExemptTypes { types_to_add, types_to_remove }
}

// === Accessors ===

public fun types_to_add(self: &UpdateFreezeExemptTypes): &vector<std::ascii::String> {
    &self.types_to_add
}

public fun types_to_remove(self: &UpdateFreezeExemptTypes): &vector<std::ascii::String> {
    &self.types_to_remove
}

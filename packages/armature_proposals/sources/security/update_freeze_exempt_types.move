module armature_proposals::update_freeze_exempt_types;

use std::type_name::{Self, TypeName};

/// Add or remove types from the freeze-exempt set on EmergencyFreeze.
/// Built in a PTB with `new`, then `add_type<T>` / `remove_type<T>` per type.
public struct UpdateFreezeExemptTypes has drop, store {
    types_to_add: vector<TypeName>,
    types_to_remove: vector<TypeName>,
}

// === Constructor ===

public fun new(): UpdateFreezeExemptTypes {
    UpdateFreezeExemptTypes { types_to_add: vector[], types_to_remove: vector[] }
}

/// Mark proposal type `T` to be added to the exempt set.
public fun add_type<T>(self: &mut UpdateFreezeExemptTypes) {
    self.types_to_add.push_back(type_name::with_defining_ids<T>());
}

/// Mark proposal type `T` to be removed from the exempt set.
public fun remove_type<T>(self: &mut UpdateFreezeExemptTypes) {
    self.types_to_remove.push_back(type_name::with_defining_ids<T>());
}

// === Accessors ===

public fun types_to_add(self: &UpdateFreezeExemptTypes): &vector<TypeName> {
    &self.types_to_add
}

public fun types_to_remove(self: &UpdateFreezeExemptTypes): &vector<TypeName> {
    &self.types_to_remove
}

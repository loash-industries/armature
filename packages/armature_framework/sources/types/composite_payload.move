module armature::composite_payload;

use std::type_name::TypeName;

/// Stored inside `Proposal<CompositePayload>` (the "Composite" proposal type).
/// References the shared `CompositeFrame` by ID and records step metadata
/// copied at submission so `composite::advance_step` can validate each step's
/// payload type against the recorded `TypeName` without reading the frame's
/// dynamic fields.
///
/// Lives in its own leaf module so `dao` can seed the default "Composite"
/// slot by type without depending on `composite` (which depends on `dao`).
public struct CompositePayload has drop, store {
    frame_id: ID,
    step_type_keys: vector<std::ascii::String>,
    step_types: vector<TypeName>,
}

// === Constructor (framework-internal) ===

public(package) fun new(
    frame_id: ID,
    step_type_keys: vector<std::ascii::String>,
    step_types: vector<TypeName>,
): CompositePayload {
    CompositePayload { frame_id, step_type_keys, step_types }
}

// === Accessors ===

public fun frame_id(self: &CompositePayload): ID { self.frame_id }

public fun step_type_keys(self: &CompositePayload): &vector<std::ascii::String> {
    &self.step_type_keys
}

public fun step_types(self: &CompositePayload): &vector<TypeName> { &self.step_types }

public fun step_count(self: &CompositePayload): u64 { self.step_type_keys.length() }

public fun step_type_key_at(self: &CompositePayload, index: u64): std::ascii::String {
    self.step_type_keys[index]
}

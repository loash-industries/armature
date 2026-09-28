module armature::disable_bypass_type;

use std::internal::{Self, Permit};

/// Disable a bypass-enabled proposal type and destroy its
/// `ExternalExecutionCap<NewType>` in one atomic step.
///
/// The target type is named by the handler's type argument
/// (`external_execution::execute_disable_bypass_type<NewType>`); `type_key`
/// is the display key the voters saw and must match the slot's display key.
public struct DisableBypassType has drop, store {
    type_key: std::ascii::String,
    cap_id: ID,
}

// === Constructor ===

public fun new(type_key: std::ascii::String, cap_id: ID): DisableBypassType {
    DisableBypassType { type_key, cap_id }
}

// === Accessors ===

public fun type_key(self: &DisableBypassType): std::ascii::String { self.type_key }

public fun cap_id(self: &DisableBypassType): ID { self.cap_id }

// === Handler authority ===

/// `Permit<DisableBypassType>` for this package's handler: the only way to spend or close
/// an `ExecutionTicket<DisableBypassType>` (see `proposal::ticket_request`).
public(package) fun permit(): Permit<DisableBypassType> { internal::permit() }

module armature::controller_disable_bypass_type;

use std::internal::{Self, Permit};

/// Controller-side `DisableBypassType`: proposed on the controller OU, it
/// destroys a controlled SubOU's `ExternalExecutionCap<NewType>` and removes
/// `NewType`'s slot on the SubOU in one atomic step.
///
/// The counterpart of `ControllerEnableBypassType`. A SubOU cannot pass
/// `DisableBypassType` itself (SubOU-blocked), so without this type a
/// controller-granted bypass could only be paused or frozen, never revoked.
///
/// The target type is named by the handler's type argument
/// (`external_execution::execute_controller_disable_bypass_type<NewType>`);
/// `type_key` is the display key the voters saw and must match the slot's.
public struct ControllerDisableBypassType has drop, store {
    subou_id: ID,
    control_cap_id: ID,
    type_key: std::ascii::String,
    cap_id: ID,
}

// === Constructor ===

public fun new(
    subou_id: ID,
    control_cap_id: ID,
    type_key: std::ascii::String,
    cap_id: ID,
): ControllerDisableBypassType {
    ControllerDisableBypassType { subou_id, control_cap_id, type_key, cap_id }
}

// === Accessors ===

public fun subou_id(self: &ControllerDisableBypassType): ID { self.subou_id }

public fun control_cap_id(self: &ControllerDisableBypassType): ID { self.control_cap_id }

public fun type_key(self: &ControllerDisableBypassType): std::ascii::String { self.type_key }

public fun cap_id(self: &ControllerDisableBypassType): ID { self.cap_id }

// === Handler authority ===

/// `Permit<ControllerDisableBypassType>` for this package's handler: the only way to spend or
/// close an `ExecutionTicket<ControllerDisableBypassType>` (see `proposal::ticket_request`).
public(package) fun permit(): Permit<ControllerDisableBypassType> { internal::permit() }

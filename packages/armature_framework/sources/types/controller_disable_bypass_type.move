module armature::controller_disable_bypass_type;

use std::internal::{Self, Permit};
use std::type_name::TypeName;

/// Controller-side `DisableBypassType`: proposed on an OU that controls a
/// SubOU (directly or further down a controller chain), it destroys every
/// `ExternalExecutionCap<NewType>` a controller chain granted the SubOU that is
/// in the SubOU's vault and removes `NewType`'s slot on the SubOU in one
/// atomic step.
///
/// The counterpart of `ControllerEnableBypassType`. A SubOU cannot pass
/// `DisableBypassType` itself (SubOU-blocked), so without this type a
/// controller-granted bypass could only be paused or frozen, never revoked.
///
/// `type_name` pins the Move type the voters approved, not the slot's display
/// key: the SubOU controls its slots and could rename or remove one. The
/// handler (`external_execution::finish_controller_disable_bypass_type`)
/// destroys whichever of the SubOU's recorded grants are in its vault and
/// removes the slot if it exists, so neither one being gone blocks the other,
/// and no cap ID has to be named: a duplicate or orphaned grant is destroyed
/// with the rest.
public struct ControllerDisableBypassType has drop, store {
    subou_id: ID,
    control_cap_id: ID,
    /// Canonical Move type (`std::type_name::with_defining_ids<T>()`) being revoked.
    type_name: TypeName,
}

// === Constructor ===

public fun new(subou_id: ID, control_cap_id: ID, type_name: TypeName): ControllerDisableBypassType {
    ControllerDisableBypassType { subou_id, control_cap_id, type_name }
}

// === Accessors ===

public fun subou_id(self: &ControllerDisableBypassType): ID { self.subou_id }

public fun control_cap_id(self: &ControllerDisableBypassType): ID { self.control_cap_id }

public fun type_name(self: &ControllerDisableBypassType): TypeName { self.type_name }

// === Handler authority ===

/// `Permit<ControllerDisableBypassType>` for this package's handler: the only way to spend or
/// close an `ExecutionTicket<ControllerDisableBypassType>` (see `proposal::ticket_request`).
public(package) fun permit(): Permit<ControllerDisableBypassType> { internal::permit() }

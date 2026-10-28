module armature::controller_enable_bypass_type;

use armature::proposal::ProposalConfig;
use std::internal::{Self, Permit};
use std::type_name::TypeName;

/// Controller-side `EnableBypassType`: proposed on the controller OU, it
/// enables `NewType` on a controlled SubOU and mints an
/// `ExternalExecutionCap<NewType>` scoped to the SubOU into the SubOU's vault.
///
/// A SubOU cannot pass `EnableBypassType` itself (SubOU-blocked), which stops
/// it from escalating its own execution privileges. This type lets the
/// controller's board make that grant instead, at the same 80% whole-board
/// floor, through the SubOUControl it already holds.
///
/// `type_name` pins the exact Move type the voters approved; the handler
/// (`external_execution::execute_controller_enable_bypass_type<NewType>`)
/// asserts that `NewType` matches it.
public struct ControllerEnableBypassType has drop, store {
    subou_id: ID,
    control_cap_id: ID,
    /// Human-readable label for the new type on the SubOU. Unique per OU.
    type_key: std::ascii::String,
    /// Canonical Move type (`std::type_name::with_defining_ids<T>()`) being enabled.
    type_name: TypeName,
    config: ProposalConfig,
}

// === Constructor ===

public fun new(
    subou_id: ID,
    control_cap_id: ID,
    type_key: std::ascii::String,
    type_name: TypeName,
    config: ProposalConfig,
): ControllerEnableBypassType {
    ControllerEnableBypassType { subou_id, control_cap_id, type_key, type_name, config }
}

// === Accessors ===

public fun subou_id(self: &ControllerEnableBypassType): ID { self.subou_id }

public fun control_cap_id(self: &ControllerEnableBypassType): ID { self.control_cap_id }

public fun type_key(self: &ControllerEnableBypassType): std::ascii::String { self.type_key }

public fun type_name(self: &ControllerEnableBypassType): TypeName { self.type_name }

public fun config(self: &ControllerEnableBypassType): &ProposalConfig { &self.config }

// === Handler authority ===

/// `Permit<ControllerEnableBypassType>` for this package's handler: the only way to spend or
/// close an `ExecutionTicket<ControllerEnableBypassType>` (see `proposal::ticket_request`).
public(package) fun permit(): Permit<ControllerEnableBypassType> { internal::permit() }

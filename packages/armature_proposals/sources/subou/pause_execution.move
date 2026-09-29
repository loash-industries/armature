module armature_proposals::pause_execution;

use std::internal::{Self, Permit};

/// Pause all proposal execution on a SubOU. privileged_submit only.
public struct PauseSubOUExecution has drop, store {
    control_id: ID,
}

/// Resume proposal execution on a paused SubOU. privileged_submit only.
public struct UnpauseSubOUExecution has drop, store {
    control_id: ID,
}

// === Constructors ===

public fun new_pause(control_id: ID): PauseSubOUExecution {
    PauseSubOUExecution { control_id }
}

public fun new_unpause(control_id: ID): UnpauseSubOUExecution {
    UnpauseSubOUExecution { control_id }
}

// === Accessors ===

public fun pause_control_id(self: &PauseSubOUExecution): ID { self.control_id }

public fun unpause_control_id(self: &UnpauseSubOUExecution): ID { self.control_id }

// === Handler authority ===

/// `Permit<PauseSubOUExecution>` for this package's handler: the only way to spend or close
/// an `ExecutionTicket<PauseSubOUExecution>` (see `proposal::ticket_request`).
public(package) fun pause_subou_permit(): Permit<PauseSubOUExecution> { internal::permit() }

/// `Permit<UnpauseSubOUExecution>` for this package's handler: the only way to spend or close
/// an `ExecutionTicket<UnpauseSubOUExecution>` (see `proposal::ticket_request`).
public(package) fun unpause_subou_permit(): Permit<UnpauseSubOUExecution> { internal::permit() }

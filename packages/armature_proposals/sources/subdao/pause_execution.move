module armature_proposals::pause_execution;

use std::internal::{Self, Permit};

/// Pause all proposal execution on a SubDAO. privileged_submit only.
public struct PauseSubDAOExecution has drop, store {
    control_id: ID,
}

/// Resume proposal execution on a paused SubDAO. privileged_submit only.
public struct UnpauseSubDAOExecution has drop, store {
    control_id: ID,
}

// === Constructors ===

public fun new_pause(control_id: ID): PauseSubDAOExecution {
    PauseSubDAOExecution { control_id }
}

public fun new_unpause(control_id: ID): UnpauseSubDAOExecution {
    UnpauseSubDAOExecution { control_id }
}

// === Accessors ===

public fun pause_control_id(self: &PauseSubDAOExecution): ID { self.control_id }

public fun unpause_control_id(self: &UnpauseSubDAOExecution): ID { self.control_id }

// === Handler authority ===

/// `Permit<PauseSubDAOExecution>` for this package's handler: the only way to spend or close
/// an `ExecutionTicket<PauseSubDAOExecution>` (see `proposal::ticket_request`).
public(package) fun pause_subdao_permit(): Permit<PauseSubDAOExecution> { internal::permit() }

/// `Permit<UnpauseSubDAOExecution>` for this package's handler: the only way to spend or close
/// an `ExecutionTicket<UnpauseSubDAOExecution>` (see `proposal::ticket_request`).
public(package) fun unpause_subdao_permit(): Permit<UnpauseSubDAOExecution> { internal::permit() }

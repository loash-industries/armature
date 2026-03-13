module armature_proposals::pause_execution;

/// Pause all proposal execution on a SubDAO. privileged_submit only.
public struct PauseSubDAOExecution has store {
    control_id: ID,
}

/// Resume proposal execution on a paused SubDAO. privileged_submit only.
public struct UnpauseSubDAOExecution has store {
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

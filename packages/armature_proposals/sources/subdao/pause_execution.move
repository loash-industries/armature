module armature_proposals::pause_execution;

/// Pause all proposal execution on a SubDAO. privileged_submit only.
public struct PauseSubDAOExecution has store {}

/// Resume proposal execution on a paused SubDAO. privileged_submit only.
public struct UnpauseSubDAOExecution has store {}

// === Constructors ===

public fun new_pause(): PauseSubDAOExecution {
    PauseSubDAOExecution {}
}

public fun new_unpause(): UnpauseSubDAOExecution {
    UnpauseSubDAOExecution {}
}

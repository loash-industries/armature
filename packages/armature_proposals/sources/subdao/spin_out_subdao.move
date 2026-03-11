module armature_proposals::spin_out_subdao;

/// Destroy SubDAOControl and grant a SubDAO full independence.
public struct SpinOutSubDAO has store {
    subdao_id: ID,
    control_cap_id: ID,
}

// === Constructor ===

public fun new(subdao_id: ID, control_cap_id: ID): SpinOutSubDAO {
    SpinOutSubDAO { subdao_id, control_cap_id }
}

// === Accessors ===

public fun subdao_id(self: &SpinOutSubDAO): ID { self.subdao_id }
public fun control_cap_id(self: &SpinOutSubDAO): ID { self.control_cap_id }

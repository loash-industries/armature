module armature_proposals::spin_out_subdao;

use armature::proposal::ProposalConfig;

/// Destroy SubDAOControl and grant a SubDAO full independence.
public struct SpinOutSubDAO has store {
    subdao_id: ID,
    control_cap_id: ID,
    freeze_admin_cap_id: ID,
    spawn_dao_config: ProposalConfig,
    spin_out_subdao_config: ProposalConfig,
    create_subdao_config: ProposalConfig,
}

// === Constructor ===

public fun new(
    subdao_id: ID,
    control_cap_id: ID,
    freeze_admin_cap_id: ID,
    spawn_dao_config: ProposalConfig,
    spin_out_subdao_config: ProposalConfig,
    create_subdao_config: ProposalConfig,
): SpinOutSubDAO {
    SpinOutSubDAO {
        subdao_id,
        control_cap_id,
        freeze_admin_cap_id,
        spawn_dao_config,
        spin_out_subdao_config,
        create_subdao_config,
    }
}

// === Accessors ===

public fun subdao_id(self: &SpinOutSubDAO): ID { self.subdao_id }

public fun control_cap_id(self: &SpinOutSubDAO): ID { self.control_cap_id }

public fun freeze_admin_cap_id(self: &SpinOutSubDAO): ID { self.freeze_admin_cap_id }

public fun spawn_dao_config(self: &SpinOutSubDAO): &ProposalConfig { &self.spawn_dao_config }

public fun spin_out_subdao_config(self: &SpinOutSubDAO): &ProposalConfig {
    &self.spin_out_subdao_config
}

public fun create_subdao_config(self: &SpinOutSubDAO): &ProposalConfig {
    &self.create_subdao_config
}

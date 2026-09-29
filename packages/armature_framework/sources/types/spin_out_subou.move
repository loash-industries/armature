module armature::spin_out_subou;

use armature::proposal::ProposalConfig;
use std::internal::{Self, Permit};

/// Destroy SubOUControl and grant a SubOU full independence.
public struct SpinOutSubOU has drop, store {
    subou_id: ID,
    control_cap_id: ID,
    freeze_admin_cap_id: ID,
    spawn_ou_config: ProposalConfig,
    spin_out_subou_config: ProposalConfig,
    create_subou_config: ProposalConfig,
}

// === Constructor ===

public fun new(
    subou_id: ID,
    control_cap_id: ID,
    freeze_admin_cap_id: ID,
    spawn_ou_config: ProposalConfig,
    spin_out_subou_config: ProposalConfig,
    create_subou_config: ProposalConfig,
): SpinOutSubOU {
    SpinOutSubOU {
        subou_id,
        control_cap_id,
        freeze_admin_cap_id,
        spawn_ou_config,
        spin_out_subou_config,
        create_subou_config,
    }
}

// === Accessors ===

public fun subou_id(self: &SpinOutSubOU): ID { self.subou_id }

public fun control_cap_id(self: &SpinOutSubOU): ID { self.control_cap_id }

public fun freeze_admin_cap_id(self: &SpinOutSubOU): ID { self.freeze_admin_cap_id }

public fun spawn_ou_config(self: &SpinOutSubOU): &ProposalConfig { &self.spawn_ou_config }

public fun spin_out_subou_config(self: &SpinOutSubOU): &ProposalConfig {
    &self.spin_out_subou_config
}

public fun create_subou_config(self: &SpinOutSubOU): &ProposalConfig {
    &self.create_subou_config
}

// === Handler authority ===

/// `Permit<SpinOutSubOU>` for this package's handler: the only way to spend or close
/// an `ExecutionTicket<SpinOutSubOU>` (see `proposal::ticket_request`).
public(package) fun permit(): Permit<SpinOutSubOU> { internal::permit() }

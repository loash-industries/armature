module armature::enable_bypass_type;

use armature::proposal::ProposalConfig;
use std::internal::{Self, Permit};
use std::type_name::TypeName;

/// Enable a new proposal type on the DAO with bypass-execution authorization.
/// In addition to the standard `EnableProposalType` effects (register the type
/// under its Move type), the handler mints an `ExternalExecutionCap<NewType>`
/// into the DAO's `CapabilityVault`.
///
/// `type_name` pins the exact Move type the voters approved; the handler
/// (`external_execution::execute_enable_bypass_type<NewType>`) asserts that
/// `NewType` matches it.
///
/// The payload lives in its own leaf module (rather than `external_execution`)
/// so `dao` can name the type when seeding default slots and classifying
/// undisableable types without creating a module dependency cycle.
public struct EnableBypassType has drop, store {
    /// Human-readable label shown in events and the UI. Unique per DAO.
    type_key: std::ascii::String,
    /// Canonical Move type (`std::type_name::with_defining_ids<T>()`) being enabled.
    type_name: TypeName,
    config: ProposalConfig,
}

// === Constructor ===

public fun new(
    type_key: std::ascii::String,
    type_name: TypeName,
    config: ProposalConfig,
): EnableBypassType {
    EnableBypassType { type_key, type_name, config }
}

// === Accessors ===

public fun type_key(self: &EnableBypassType): std::ascii::String { self.type_key }

public fun type_name(self: &EnableBypassType): TypeName { self.type_name }

public fun config(self: &EnableBypassType): &ProposalConfig { &self.config }

// === Handler authority ===

/// `Permit<EnableBypassType>` for this package's handler: the only way to spend or close
/// an `ExecutionTicket<EnableBypassType>` (see `proposal::ticket_request`).
public(package) fun permit(): Permit<EnableBypassType> { internal::permit() }

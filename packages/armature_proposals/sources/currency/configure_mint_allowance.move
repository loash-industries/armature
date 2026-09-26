/// Board-voted configuration for `MintAllowance<T>` bypass minting: which
/// addresses may mint without a vote, the most they may mint per call, and a
/// kill-switch. Stored as DAO type-state keyed by `ConfigureMintAllowance<T>`,
/// the only type that writes it; `currency_ops::mint_allowance_bypass` reads
/// it before minting a bypass ticket.
///
/// This is the authorization half of a bypass type (see
/// `docs/package-boundaries.md`): the `ExternalExecutionCap<MintAllowance<T>>`
/// in the vault is the DAO's opt-in, and this allowlist says who may use it.
/// Mirrors `armature_world_bridge::configure_autojoin`.
module armature_proposals::configure_mint_allowance;

use armature::dao::DAO;
use armature::proposal::ExecutionTicket;
use std::internal;
use sui::event;
use sui::vec_set::{Self, VecSet};

// === Errors ===

const EDaoMismatch: u64 = 0;
const ETooManyOps: u64 = 1;
const ETooManyMinters: u64 = 2;

// === Constants ===

/// Ceiling on a single payload's add/remove vectors.
const MAX_OPS_PER_CALL: u64 = 16;
/// Ceiling on the allowlist, so every bypass mint reads a small state.
const MAX_MINTERS: u64 = 32;

// === Structs ===

/// Payload: apply an add/remove diff to the minter allowlist, and optionally
/// set the per-call cap and the kill-switch.
public struct ConfigureMintAllowance<phantom T> has drop, store {
    add_minters: vector<address>,
    remove_minters: vector<address>,
    max_per_call: Option<u64>,
    set_enabled: Option<bool>,
}

/// Type-state: the allowlist for `MintAllowance<T>`. Created disabled with no
/// minters and a zero cap on the first `ConfigureMintAllowance<T>` execution.
public struct MintAllowanceConfig has drop, store {
    enabled: bool,
    minters: VecSet<address>,
    max_per_call: u64,
}

// === Events ===

public struct MintAllowanceConfigured has copy, drop {
    dao_id: ID,
    coin_type: std::ascii::String,
    added: vector<address>,
    removed: vector<address>,
    max_per_call: u64,
    enabled: bool,
}

// === Constructor ===

public fun new<T>(
    add_minters: vector<address>,
    remove_minters: vector<address>,
    max_per_call: Option<u64>,
    set_enabled: Option<bool>,
): ConfigureMintAllowance<T> {
    ConfigureMintAllowance { add_minters, remove_minters, max_per_call, set_enabled }
}

// === Payload accessors ===

public fun add_minters<T>(self: &ConfigureMintAllowance<T>): &vector<address> { &self.add_minters }

public fun remove_minters<T>(self: &ConfigureMintAllowance<T>): &vector<address> {
    &self.remove_minters
}

public fun max_per_call<T>(self: &ConfigureMintAllowance<T>): &Option<u64> { &self.max_per_call }

public fun set_enabled<T>(self: &ConfigureMintAllowance<T>): &Option<bool> { &self.set_enabled }

// === State accessors ===

public fun is_enabled(self: &MintAllowanceConfig): bool { self.enabled }

public fun is_minter(self: &MintAllowanceConfig, addr: address): bool {
    self.minters.contains(&addr)
}

public fun minter_count(self: &MintAllowanceConfig): u64 { self.minters.length() }

public fun config_max_per_call(self: &MintAllowanceConfig): u64 { self.max_per_call }

public fun max_minters(): u64 { MAX_MINTERS }

// === Handler ===

/// Execute a `ConfigureMintAllowance<T>` proposal. Lazily creates the state
/// (disabled, empty, cap 0) on first call, then applies removals, additions,
/// the cap and the kill-switch, in that order.
public fun execute_configure_mint_allowance<T>(
    dao: &mut DAO,
    ticket: ExecutionTicket<ConfigureMintAllowance<T>>,
) {
    let dao_id = dao.id();
    assert!(dao_id == ticket.ticket_dao_id(), EDaoMismatch);
    let payload = ticket.ticket_payload();
    let req = ticket.ticket_request(internal::permit());

    assert!(payload.add_minters.length() <= MAX_OPS_PER_CALL, ETooManyOps);
    assert!(payload.remove_minters.length() <= MAX_OPS_PER_CALL, ETooManyOps);

    if (!dao.has_type_state<ConfigureMintAllowance<T>>()) {
        dao.init_type_state<ConfigureMintAllowance<T>, MintAllowanceConfig>(
            MintAllowanceConfig { enabled: false, minters: vec_set::empty(), max_per_call: 0 },
            req,
        );
    };

    let config: &mut MintAllowanceConfig = dao.borrow_type_state_mut<
        ConfigureMintAllowance<T>,
        MintAllowanceConfig,
    >(req);

    payload.remove_minters.do_ref!(|a| {
        if (config.minters.contains(a)) config.minters.remove(a);
    });
    payload.add_minters.do_ref!(|a| {
        if (!config.minters.contains(a)) config.minters.insert(*a);
    });
    assert!(config.minters.length() <= MAX_MINTERS, ETooManyMinters);

    if (payload.max_per_call.is_some()) config.max_per_call = *payload.max_per_call.borrow();
    if (payload.set_enabled.is_some()) config.enabled = *payload.set_enabled.borrow();
    let (max_per_call, enabled) = (config.max_per_call, config.enabled);

    event::emit(MintAllowanceConfigured {
        dao_id,
        coin_type: std::type_name::with_original_ids<T>().into_string(),
        added: payload.add_minters,
        removed: payload.remove_minters,
        max_per_call,
        enabled,
    });

    ticket.discharge(internal::permit());
}

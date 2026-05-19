/// Board-voted proposal that mutates the DAO's `TribeIdAllowlist`.
/// Lazily initialises the type-state on first execution so the DAO
/// doesn't need a separate "init" proposal between `EnableProposalType`
/// and the first config change.
///
/// Type-state key: `ConfigureAutojoin`. The state is keyed by this
/// payload type because `init_type_state<P, S>` / `borrow_type_state_mut<P, S>`
/// infer `P` from the `ExecutionRequest<P>`. Reads from `submit_autojoin`
/// use the explicit-type `borrow_type_state<ConfigureAutojoin, _>` accessor
/// which is `public` and doesn't require a request.
module armature_world_bridge::configure_autojoin;

use armature::dao::DAO;
use armature::proposal::{Self, ExecutionRequest, Proposal};
use armature_world_bridge::tribe_allowlist::{Self, TribeIdAllowlist};
use sui::event;

// === Errors ===

const EDaoMismatch: u64 = 0;
const ETooManyAdds: u64 = 1;
const ETooManyRemoves: u64 = 2;
const EZeroTribeIdNotAllowed: u64 = 3;

// === Constants ===

/// Hard ceiling on a single ConfigureAutojoin payload's add/remove vectors,
/// independent of the allowlist's MAX_TRIBE_IDS. Bounds payload size
/// and per-call work. Larger reconfigurations need multiple proposals.
const MAX_OPS_PER_CALL: u64 = 16;

// === Structs ===

/// Payload: bulk-update the DAO's tribe-id allowlist plus optionally
/// flip the kill-switch. `set_enabled` is `Option<bool>` so callers
/// can leave the flag untouched.
public struct ConfigureAutojoin has store {
    add_tribe_ids: vector<u32>,
    remove_tribe_ids: vector<u32>,
    set_enabled: Option<bool>,
}

// === Events ===

public struct AutojoinAllowlistUpdated has copy, drop {
    dao_id: ID,
    added: vector<u32>,
    removed: vector<u32>,
    enabled: bool,
}

// === Constructor ===

public fun new(
    add_tribe_ids: vector<u32>,
    remove_tribe_ids: vector<u32>,
    set_enabled: Option<bool>,
): ConfigureAutojoin {
    ConfigureAutojoin { add_tribe_ids, remove_tribe_ids, set_enabled }
}

// === Accessors ===

public fun add_tribe_ids(self: &ConfigureAutojoin): &vector<u32> { &self.add_tribe_ids }

public fun remove_tribe_ids(self: &ConfigureAutojoin): &vector<u32> { &self.remove_tribe_ids }

public fun set_enabled(self: &ConfigureAutojoin): &Option<bool> { &self.set_enabled }

// === Handler ===

/// Execute a ConfigureAutojoin proposal. Lazily creates the allowlist
/// on first call (with `enabled = false`), then applies the payload diff.
///
/// Per-call bounds (`MAX_OPS_PER_CALL`) are checked before consulting
/// the allowlist's own bound (`MAX_TRIBE_IDS`) so the cheaper check
/// fails fast.
public fun execute_configure_autojoin(
    dao: &mut DAO,
    proposal: &Proposal<ConfigureAutojoin>,
    request: ExecutionRequest<ConfigureAutojoin>,
) {
    assert!(dao.id() == request.req_dao_id(), EDaoMismatch);
    let payload = proposal.payload();

    assert!(payload.add_tribe_ids.length() <= MAX_OPS_PER_CALL, ETooManyAdds);
    assert!(payload.remove_tribe_ids.length() <= MAX_OPS_PER_CALL, ETooManyRemoves);

    // Reject tribe_id == 0 in adds. world::character::create_character /
    // update_tribe both reject 0 today (ETribeIdEmpty), but defending at
    // config time prevents a bad allowlist entry from existing in the
    // first place — independent of any future world-contracts change.
    let mut i = 0;
    while (i < payload.add_tribe_ids.length()) {
        assert!(payload.add_tribe_ids[i] != 0, EZeroTribeIdNotAllowed);
        i = i + 1;
    };

    if (!dao.has_type_state<ConfigureAutojoin>()) {
        dao.init_type_state<ConfigureAutojoin, TribeIdAllowlist>(
            tribe_allowlist::empty(),
            &request,
        );
    };

    let allowlist: &mut TribeIdAllowlist =
        dao.borrow_type_state_mut<ConfigureAutojoin, TribeIdAllowlist>(&request);

    allowlist.apply(payload.add_tribe_ids, payload.remove_tribe_ids);
    if (payload.set_enabled.is_some()) {
        allowlist.set_enabled(*payload.set_enabled.borrow());
    };

    let enabled = allowlist.is_enabled();

    event::emit(AutojoinAllowlistUpdated {
        dao_id: dao.id(),
        added: payload.add_tribe_ids,
        removed: payload.remove_tribe_ids,
        enabled,
    });

    proposal::finalize(request, proposal);
}

/// Tribe-ID allowlist used by AutojoinDAO. Stored as DAO type-state keyed
/// by `ConfigureAutojoin` (the only proposal type that mutates it). Reads
/// from `submit_autojoin` use the explicit-type `borrow_type_state<P, S>`
/// accessor which does not require an `ExecutionRequest`.
///
/// Threat model notes:
///   - The allowlist itself is the DAO's declaration of which in-game
///     tribes are synonymous with this DAO. Trust in the contents is
///     trust in the DAO board's `ConfigureAutojoin` vote.
///   - The `enabled` flag is a fast kill-switch: the DAO can pass a
///     ConfigureAutojoin with `set_enabled: some(false)` to stop all
///     self-joins in a single proposal without disabling the
///     proposal type entirely (which would require DisableProposalType).
///   - Bounded size: MAX_TRIBE_IDS keeps the type-state cheap to read on
///     every `submit_autojoin` and bounds gas. A tribe DAO declaring
///     more than 8 synonymous in-game tribes is unusual; raise later
///     if a real use case appears.
module armature_world_bridge::tribe_allowlist;

use sui::vec_set::{Self, VecSet};

// === Errors ===

const EAllowlistFull: u64 = 0;

// === Constants ===

/// Maximum number of tribe IDs in a single DAO's allowlist.
const MAX_TRIBE_IDS: u64 = 8;

// === Structs ===

/// Per-DAO autojoin allowlist. The DAO's `ConfigureAutojoin` handler is the
/// only writer; `submit_autojoin` is the only on-path reader.
public struct TribeIdAllowlist has store {
    enabled: bool,
    owner_ids: VecSet<u32>,
}

// === Constructor ===

/// Create an empty allowlist with `enabled = false`. The DAO must run
/// `ConfigureAutojoin { set_enabled: some(true), .. }` to activate it.
public(package) fun empty(): TribeIdAllowlist {
    TribeIdAllowlist {
        enabled: false,
        owner_ids: vec_set::empty(),
    }
}

// === Accessors ===

public fun is_enabled(self: &TribeIdAllowlist): bool { self.enabled }

public fun contains(self: &TribeIdAllowlist, owner_id: u32): bool {
    self.owner_ids.contains(&owner_id)
}

public fun size(self: &TribeIdAllowlist): u64 { self.owner_ids.size() }

public fun max_size(): u64 { MAX_TRIBE_IDS }

// === Mutators (package-internal — only ConfigureAutojoin handler calls these) ===

/// Apply a batch of additions and removals atomically. Aborts if the
/// resulting allowlist would exceed `MAX_TRIBE_IDS`, leaving the
/// allowlist completely unchanged on failure.
///
/// Removals that don't exist and additions that already exist are
/// silently no-ops — the resulting state is what matters, not the diff.
/// (Same forgiveness as `BatchAddMembers`'s skip-existing behaviour:
/// bulk ops shouldn't fail on benign overlap.)
///
/// Atomicity is enforced by a two-pass approach: pass 1 computes the
/// post-state size without mutating, aborts if it would overflow.
/// Pass 2 mutates. A first-pass abort leaves `self` untouched.
public(package) fun apply(
    self: &mut TribeIdAllowlist,
    add_ids: vector<u32>,
    remove_ids: vector<u32>,
) {
    // Pass 1: simulate the diff against a fresh copy of the key set to
    // compute the post-apply size. Internal duplicates in either input
    // collapse naturally since we check membership before counting.
    let mut sim = vec_set::empty<u32>();
    let existing_keys = self.owner_ids.keys();
    let mut k = 0;
    while (k < existing_keys.length()) {
        sim.insert(existing_keys[k]);
        k = k + 1;
    };
    let mut i = 0;
    while (i < remove_ids.length()) {
        let id = remove_ids[i];
        if (sim.contains(&id)) { sim.remove(&id); };
        i = i + 1;
    };
    let mut j = 0;
    while (j < add_ids.length()) {
        let id = add_ids[j];
        if (!sim.contains(&id)) { sim.insert(id); };
        j = j + 1;
    };
    assert!(sim.size() <= MAX_TRIBE_IDS, EAllowlistFull);

    // Pass 2: actually mutate. Removals first so that a simultaneous
    // add+remove of the same id ends up present (set-the-state semantics).
    let mut ri = 0;
    while (ri < remove_ids.length()) {
        let id = remove_ids[ri];
        if (self.owner_ids.contains(&id)) { self.owner_ids.remove(&id); };
        ri = ri + 1;
    };
    let mut ai = 0;
    while (ai < add_ids.length()) {
        let id = add_ids[ai];
        if (!self.owner_ids.contains(&id)) { self.owner_ids.insert(id); };
        ai = ai + 1;
    };
}

public(package) fun set_enabled(self: &mut TribeIdAllowlist, enabled: bool) {
    self.enabled = enabled;
}

// === Test helpers ===

#[test_only]
public fun new_for_testing(enabled: bool, owner_ids: vector<u32>): TribeIdAllowlist {
    let mut set = vec_set::empty<u32>();
    let mut i = 0;
    while (i < owner_ids.length()) {
        if (!set.contains(&owner_ids[i])) {
            set.insert(owner_ids[i]);
        };
        i = i + 1;
    };
    TribeIdAllowlist { enabled, owner_ids: set }
}

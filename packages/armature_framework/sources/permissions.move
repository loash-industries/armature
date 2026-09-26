/// Permission bits a proposal type may hold in `ProposalConfig.permissions`.
///
/// Each framework mutator that changes DAO-wide state names the bit it
/// requires and calls `dao::assert_permitted<P>(bit, req)`: the request's type
/// `P` must hold that bit in its slot on the DAO, or the request must be
/// privileged (a controller override). Deny-by-default: a type holds no bits
/// unless they are seeded at DAO creation or granted by a type-admin vote.
///
/// Mutators scoped to the caller's own type-state (keyed by `P`) need no bit.
module armature::permissions;

// === Errors ===

/// A permissions mask sets a bit that is not defined below.
const EUnknownPermission: u64 = 0;

// === Bits ===

/// Add board members.
const BOARD_ADD: u64 = 1 << 0;
/// Remove board members.
const BOARD_REMOVE: u64 = 1 << 1;
/// Apply a SetBoard diff (add and remove in one change).
const BOARD_SET: u64 = 1 << 2;
/// Enable, disable or reconfigure proposal types.
const TYPE_ADMIN: u64 = 1 << 3;
/// Pause or resume proposal execution.
const PAUSE: u64 = 1 << 4;
/// Move the DAO into the Migrating state.
const MIGRATE: u64 = 1 << 5;
/// Update the DAO's charter metadata.
const METADATA: u64 = 1 << 6;
/// Withdraw from the DAO's TreasuryVault.
const TREASURY_WITHDRAW: u64 = 1 << 7;
/// Store a capability in the DAO's CapabilityVault.
const VAULT_STORE: u64 = 1 << 8;
/// Borrow or loan a capability from the CapabilityVault.
const VAULT_BORROW: u64 = 1 << 9;
/// Extract a capability from the CapabilityVault, or create or destroy a
/// SubDAOControl.
const VAULT_EXTRACT: u64 = 1 << 10;

/// Union of every defined bit.
const ALL: u64 = (1 << 11) - 1;

// === Accessors ===

public fun board_add(): u64 { BOARD_ADD }

public fun board_remove(): u64 { BOARD_REMOVE }

public fun board_set(): u64 { BOARD_SET }

public fun type_admin(): u64 { TYPE_ADMIN }

public fun pause(): u64 { PAUSE }

public fun migrate(): u64 { MIGRATE }

public fun metadata(): u64 { METADATA }

public fun treasury_withdraw(): u64 { TREASURY_WITHDRAW }

public fun vault_store(): u64 { VAULT_STORE }

public fun vault_borrow(): u64 { VAULT_BORROW }

public fun vault_extract(): u64 { VAULT_EXTRACT }

public fun all(): u64 { ALL }

/// Whether `mask` holds every bit of `bits`.
public fun contains(mask: u64, bits: u64): bool { mask & bits == bits }

/// Abort with EUnknownPermission if `mask` sets an undefined bit.
public fun assert_valid(mask: u64) {
    assert!(mask & ALL == mask, EUnknownPermission);
}

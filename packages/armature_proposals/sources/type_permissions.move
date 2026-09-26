/// The permission bits each armature_proposals payload type needs, for the
/// config that enables it: a `ProposalTypeInit` override at DAO creation, or
/// the config in an `EnableProposalType` / `EnableBypassType` payload. A type
/// enabled without them aborts with `proposal::EPermissionDenied` when its
/// handler runs. Configs holding an 80% bit (see `dao::permission_floor`)
/// need `approval_threshold >= 8000`.
///
/// Framework types (`armature::types`) are not listed: their bits are fixed
/// by `dao::framework_permissions`.
module armature_proposals::type_permissions;

use armature::capability_vault::SubDAOControl;
use armature::permissions;
use std::type_name::{Self, TypeName};
use sui::coin::TreasuryCap;
use sui::package::UpgradeCap;

/// SendCoin<T>, SendCoinToDAO<T>, SendSmallPayment<T>, SendBatchMulticoinToAddress,
/// SendBatchMulticoinToDAO: they withdraw from the treasury.
public fun treasury_spend(): u64 { permissions::treasury_withdraw() }

/// AdoptCurrency<T>: stores the TreasuryCap in the capability vault.
public fun adopt_currency(): u64 { permissions::vault_store() }

/// MintCoin<T>, MintAllowance<T>: borrow the TreasuryCap mutably to mint.
public fun mint(): u64 { permissions::vault_borrow() }

/// Borrow scope for MintCoin<T>, MintAllowance<T>, BurnCoin<T>: only
/// `TreasuryCap<T>`, so a type minting one coin cannot reach any other cap.
public fun currency_scope<T>(): vector<TypeName> {
    vector[type_name::with_defining_ids<TreasuryCap<T>>()]
}

/// ConfigureMintAllowance<T>: writes only its own type-state, so no bits.
public fun configure_mint_allowance(): u64 { 0 }

/// BurnCoin<T>: withdraws the coins and borrows the TreasuryCap to burn them.
public fun burn_coin(): u64 { permissions::treasury_withdraw() | permissions::vault_borrow() }

/// ReturnCurrencyCap<T>: extracts the TreasuryCap.
public fun return_currency_cap(): u64 { permissions::vault_extract() }

/// ProposeUpgrade: loans the UpgradeCap.
public fun propose_upgrade(): u64 { permissions::vault_borrow() }

/// Borrow scope for ProposeUpgrade: only `UpgradeCap`.
public fun propose_upgrade_scope(): vector<TypeName> {
    vector[type_name::with_defining_ids<UpgradeCap>()]
}

/// TransferCapToSubDAO: extracts the cap and hands it to the SubDAO's vault.
public fun transfer_cap_to_subdao(): u64 { permissions::vault_extract() }

/// ReclaimCapFromSubDAO: loans the SubDAOControl and stores the reclaimed cap.
public fun reclaim_cap_from_subdao(): u64 {
    permissions::vault_borrow() | permissions::vault_store()
}

/// PauseSubDAOExecution, UnpauseSubDAOExecution, ControllerBatchAddMembers,
/// ControllerBatchRemoveMembers: loan the SubDAOControl; the SubDAO-side
/// change runs on a privileged request.
public fun subdao_control(): u64 { permissions::vault_borrow() }

/// Borrow scope for ReclaimCapFromSubDAO, PauseSubDAOExecution,
/// UnpauseSubDAOExecution, ControllerBatchAddMembers and
/// ControllerBatchRemoveMembers: only `SubDAOControl`.
public fun subdao_control_scope(): vector<TypeName> {
    vector[type_name::with_defining_ids<SubDAOControl>()]
}

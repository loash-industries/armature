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

use armature::permissions;

/// SendCoin<T>, SendCoinToDAO<T>, SendSmallPayment<T>, SendBatchMulticoinToAddress,
/// SendBatchMulticoinToDAO: they withdraw from the treasury.
public fun treasury_spend(): u64 { permissions::treasury_withdraw() }

/// AdoptCurrency<T>: stores the TreasuryCap in the capability vault.
public fun adopt_currency(): u64 { permissions::vault_store() }

/// MintCoin<T>, MintAllowance<T>: borrow the TreasuryCap mutably to mint.
public fun mint(): u64 { permissions::vault_borrow() }

/// BurnCoin<T>: withdraws the coins and borrows the TreasuryCap to burn them.
public fun burn_coin(): u64 { permissions::treasury_withdraw() | permissions::vault_borrow() }

/// ReturnCurrencyCap<T>: extracts the TreasuryCap.
public fun return_currency_cap(): u64 { permissions::vault_extract() }

/// ProposeUpgrade: loans the UpgradeCap.
public fun propose_upgrade(): u64 { permissions::vault_borrow() }

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

/// UpdateFreezeConfig, UpdateFreezeExemptTypes: change the EmergencyFreeze.
public fun freeze_config(): u64 { permissions::emergency_freeze() }

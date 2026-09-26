#[test_only]
module armature::emergency_tests;

use armature::emergency::{Self, EmergencyFreeze, FreezeAdminCap};
use armature::transfer_freeze_admin::TransferFreezeAdmin;
use armature::unfreeze_proposal_type::UnfreezeProposalType;
use std::type_name;
use sui::clock;
use sui::test_utils::destroy;

// === Test payload types ===

public struct TreasuryWithdraw has drop {}
public struct SetBoard has drop {}
public struct CustomType has drop {}

/// Generic payload, to check that instantiations are frozen independently.
public struct PlaceOrder<phantom T> has drop {}
public struct CredA has drop {}
public struct CredB has drop {}

/// Shares its module-local name with the framework's mandatory exempt type
/// but is a different Move type, so it gets no exemption.
public struct TransferFreezeAdminLookalike has drop {}

// === Helpers ===

fun setup(): (EmergencyFreeze, FreezeAdminCap, sui::clock::Clock) {
    let mut ctx = tx_context::dummy();
    let dao_id = object::id_from_address(@0xDA0);
    let freeze = emergency::new_for_testing(dao_id, &mut ctx);
    let cap = emergency::new_admin_cap_for_testing(dao_id, &mut ctx);
    let clock = clock::create_for_testing(&mut ctx);
    (freeze, cap, clock)
}

fun teardown(freeze: EmergencyFreeze, cap: FreezeAdminCap, clock: sui::clock::Clock) {
    destroy(freeze);
    destroy(cap);
    clock.destroy_for_testing();
}

// === Tests ===

#[test]
/// Freezing a type and then attempting execution should detect frozen status.
fun test_freeze__blocks_execution_of_frozen_type() {
    let (mut freeze, cap, clock) = setup();

    freeze.freeze_type<TreasuryWithdraw>(&cap, &clock);

    assert!(freeze.is_frozen<TreasuryWithdraw>(&clock));
    assert!(freeze.is_frozen_by_name(&type_name::with_defining_ids<TreasuryWithdraw>(), &clock));

    teardown(freeze, cap, clock);
}

#[test, expected_failure(abort_code = emergency::EFrozen)]
/// assert_not_frozen aborts for a frozen type.
fun test_freeze__assert_not_frozen_aborts() {
    let (mut freeze, cap, clock) = setup();

    freeze.freeze_type<TreasuryWithdraw>(&cap, &clock);
    freeze.assert_not_frozen<TreasuryWithdraw>(&clock);

    teardown(freeze, cap, clock);
}

#[test]
/// Freezing one type should not affect other types.
fun test_freeze__does_not_block_unfrozen_types() {
    let (mut freeze, cap, clock) = setup();

    freeze.freeze_type<TreasuryWithdraw>(&cap, &clock);

    assert!(freeze.is_frozen<TreasuryWithdraw>(&clock));
    assert!(!freeze.is_frozen<SetBoard>(&clock));
    freeze.assert_not_frozen<SetBoard>(&clock);

    teardown(freeze, cap, clock);
}

#[test]
/// Freezing one instantiation of a generic payload leaves the others unaffected.
fun test_freeze__generic_instantiations_are_independent() {
    let (mut freeze, cap, clock) = setup();

    freeze.freeze_type<PlaceOrder<CredA>>(&cap, &clock);

    assert!(freeze.is_frozen<PlaceOrder<CredA>>(&clock));
    assert!(!freeze.is_frozen<PlaceOrder<CredB>>(&clock));
    freeze.assert_not_frozen<PlaceOrder<CredB>>(&clock);

    teardown(freeze, cap, clock);
}

#[test, expected_failure(abort_code = emergency::EDAOMismatch)]
/// Only the cap holder with matching DAO ID can freeze.
fun test_freeze__requires_freeze_admin_cap() {
    let (mut freeze, cap, clock) = setup();

    // Create a cap for a different DAO
    let mut ctx = tx_context::dummy();
    let wrong_dao_id = object::id_from_address(@0xBAD);
    let wrong_cap = emergency::new_admin_cap_for_testing(wrong_dao_id, &mut ctx);

    // Should abort — wrong DAO
    freeze.freeze_type<TreasuryWithdraw>(&wrong_cap, &clock);

    destroy(wrong_cap);
    teardown(freeze, cap, clock);
}

#[test]
/// Freeze should set expiry to now + max_freeze_duration_ms.
fun test_freeze__sets_expiry() {
    let (mut freeze, cap, mut clock) = setup();

    let now = 1_000_000;
    clock.set_for_testing(now);

    freeze.freeze_type<TreasuryWithdraw>(&cap, &clock);

    let expiry = *freeze.frozen_types().get(&type_name::with_defining_ids<TreasuryWithdraw>());
    assert!(expiry == now + freeze.max_freeze_duration_ms());

    teardown(freeze, cap, clock);
}

#[test]
/// Cap holder can unfreeze a frozen type.
fun test_unfreeze__cap_holder_can_unfreeze() {
    let (mut freeze, cap, clock) = setup();

    freeze.freeze_type<TreasuryWithdraw>(&cap, &clock);
    assert!(freeze.is_frozen<TreasuryWithdraw>(&clock));

    freeze.unfreeze_type<TreasuryWithdraw>(&cap);
    assert!(!freeze.is_frozen<TreasuryWithdraw>(&clock));
    assert!(freeze.is_empty());

    teardown(freeze, cap, clock);
}

#[test, expected_failure(abort_code = emergency::ENotFrozen)]
/// Unfreezing a type that is not frozen aborts.
fun test_unfreeze__not_frozen_aborts() {
    let (mut freeze, cap, clock) = setup();

    freeze.unfreeze_type<TreasuryWithdraw>(&cap);

    teardown(freeze, cap, clock);
}

#[test]
/// Governance can unfreeze via the package-internal function.
fun test_unfreeze__governance_can_unfreeze() {
    let (mut freeze, cap, clock) = setup();

    freeze.freeze_type<TreasuryWithdraw>(&cap, &clock);
    assert!(freeze.is_frozen<TreasuryWithdraw>(&clock));

    freeze.governance_unfreeze(type_name::with_defining_ids<TreasuryWithdraw>());
    assert!(!freeze.is_frozen<TreasuryWithdraw>(&clock));

    teardown(freeze, cap, clock);
}

#[test]
/// An expired freeze should be treated as inactive.
fun test_auto_expiry__expired_freeze_treated_as_inactive() {
    let (mut freeze, cap, mut clock) = setup();

    let now = 1_000_000;
    clock.set_for_testing(now);

    freeze.freeze_type<TreasuryWithdraw>(&cap, &clock);
    assert!(freeze.is_frozen<TreasuryWithdraw>(&clock));

    // Advance clock past expiry
    clock.set_for_testing(now + freeze.max_freeze_duration_ms() + 1);

    // Should no longer be frozen, and assert_not_frozen should not abort
    assert!(!freeze.is_frozen<TreasuryWithdraw>(&clock));
    freeze.assert_not_frozen<TreasuryWithdraw>(&clock);

    teardown(freeze, cap, clock);
}

#[test, expected_failure(abort_code = emergency::EProtectedType)]
/// TransferFreezeAdmin cannot be frozen.
fun test_protected__transfer_freeze_admin_cannot_be_frozen() {
    let (mut freeze, cap, clock) = setup();

    freeze.freeze_type<TransferFreezeAdmin>(&cap, &clock);

    teardown(freeze, cap, clock);
}

#[test, expected_failure(abort_code = emergency::EProtectedType)]
/// UnfreezeProposalType cannot be frozen.
fun test_protected__unfreeze_proposal_type_cannot_be_frozen() {
    let (mut freeze, cap, clock) = setup();

    freeze.freeze_type<UnfreezeProposalType>(&cap, &clock);

    teardown(freeze, cap, clock);
}

#[test]
/// Protection follows the Move type, not a name: a lookalike type can be frozen.
fun test_protected__lookalike_type_is_not_exempt() {
    let (mut freeze, cap, clock) = setup();

    assert!(
        !emergency::is_mandatory_exempt(
            &type_name::with_defining_ids<TransferFreezeAdminLookalike>(),
        ),
    );
    freeze.freeze_type<TransferFreezeAdminLookalike>(&cap, &clock);
    assert!(freeze.is_frozen<TransferFreezeAdminLookalike>(&clock));

    teardown(freeze, cap, clock);
}

// === Freeze Exempt Types Tests ===

#[test]
/// Default exempt types are exactly TransferFreezeAdmin and UnfreezeProposalType.
fun test_exempt__default_types_include_mandatory() {
    let (freeze, cap, clock) = setup();

    let transfer_admin = type_name::with_defining_ids<TransferFreezeAdmin>();
    let unfreeze = type_name::with_defining_ids<UnfreezeProposalType>();

    assert!(freeze.freeze_exempt_types().length() == 2);
    assert!(freeze.is_exempt_by_name(&transfer_admin));
    assert!(freeze.is_exempt_by_name(&unfreeze));
    assert!(emergency::is_mandatory_exempt(&transfer_admin));
    assert!(emergency::is_mandatory_exempt(&unfreeze));

    teardown(freeze, cap, clock);
}

#[test, expected_failure(abort_code = emergency::EProtectedType)]
/// Custom exempt type added via test helper cannot be frozen.
fun test_exempt__custom_exempt_type_cannot_be_frozen() {
    let (mut freeze, cap, clock) = setup();

    freeze.add_exempt_type_for_testing<CustomType>();
    // Should abort — now exempt
    freeze.freeze_type<CustomType>(&cap, &clock);

    teardown(freeze, cap, clock);
}

#[test]
/// Removing an exempt type allows it to be frozen again.
fun test_exempt__removed_type_can_be_frozen() {
    let (mut freeze, cap, clock) = setup();
    let name = type_name::with_defining_ids<CustomType>();

    freeze.add_exempt_type_for_testing<CustomType>();
    assert!(freeze.is_exempt_by_name(&name));

    freeze.remove_exempt_type_for_testing<CustomType>();
    assert!(!freeze.is_exempt_by_name(&name));

    // Should succeed — no longer exempt
    freeze.freeze_type<CustomType>(&cap, &clock);
    assert!(freeze.is_frozen<CustomType>(&clock));

    teardown(freeze, cap, clock);
}

#[test, expected_failure(abort_code = emergency::EMandatoryExemptType)]
/// Mandatory exempt types cannot be removed.
fun test_exempt__mandatory_type_cannot_be_removed() {
    let (mut freeze, cap, clock) = setup();

    freeze.remove_exempt_type_for_testing<TransferFreezeAdmin>();

    teardown(freeze, cap, clock);
}

#[test, expected_failure(abort_code = emergency::EMandatoryExemptType)]
/// Mandatory exempt types cannot be removed (UnfreezeProposalType).
fun test_exempt__mandatory_unfreeze_type_cannot_be_removed() {
    let (mut freeze, cap, clock) = setup();

    freeze.remove_exempt_type_for_testing<UnfreezeProposalType>();

    teardown(freeze, cap, clock);
}

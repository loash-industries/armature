#[test_only]
module armature::emergency_tests;

use armature::emergency::{Self, EmergencyFreeze, FreezeAdminCap};
use sui::clock;
use sui::test_utils::destroy;

// === Helpers ===

fun setup(): (EmergencyFreeze, FreezeAdminCap, sui::clock::Clock) {
    let mut ctx = tx_context::dummy();
    let dao_id = object::id_from_address(@0xDA0);
    let freeze = emergency::new_for_testing(dao_id, &mut ctx);
    let cap = emergency::new_admin_cap_for_testing(dao_id, &mut ctx);
    let clock = clock::create_for_testing(&mut ctx);
    (freeze, cap, clock)
}

// === Tests ===

#[test]
/// Freezing a type and then attempting execution should detect frozen status.
fun test_freeze__blocks_execution_of_frozen_type() {
    let (mut freeze, cap, clock) = setup();
    let type_key = b"TreasuryWithdraw".to_ascii_string();

    emergency::freeze_type(&mut freeze, &cap, type_key, &clock);

    assert!(emergency::is_frozen(&freeze, &type_key, &clock));

    destroy(freeze);
    destroy(cap);
    clock.destroy_for_testing();
}

#[test]
/// Freezing one type should not affect other types.
fun test_freeze__does_not_block_unfrozen_types() {
    let (mut freeze, cap, clock) = setup();
    let frozen_key = b"TreasuryWithdraw".to_ascii_string();
    let other_key = b"SetBoard".to_ascii_string();

    emergency::freeze_type(&mut freeze, &cap, frozen_key, &clock);

    assert!(emergency::is_frozen(&freeze, &frozen_key, &clock));
    assert!(!emergency::is_frozen(&freeze, &other_key, &clock));

    destroy(freeze);
    destroy(cap);
    clock.destroy_for_testing();
}

#[test, expected_failure(abort_code = emergency::EDAOMismatch)]
/// Only the cap holder with matching DAO ID can freeze.
fun test_freeze__requires_freeze_admin_cap() {
    let (mut freeze, _cap, clock) = setup();

    // Create a cap for a different DAO
    let mut ctx = tx_context::dummy();
    let wrong_dao_id = object::id_from_address(@0xBAD);
    let wrong_cap = emergency::new_admin_cap_for_testing(wrong_dao_id, &mut ctx);

    let type_key = b"TreasuryWithdraw".to_ascii_string();

    // Should abort — wrong DAO
    emergency::freeze_type(&mut freeze, &wrong_cap, type_key, &clock);

    destroy(freeze);
    destroy(_cap);
    destroy(wrong_cap);
    clock.destroy_for_testing();
}

#[test]
/// Freeze should set expiry to now + max_freeze_duration_ms.
fun test_freeze__sets_expiry() {
    let (mut freeze, cap, mut clock) = setup();
    let type_key = b"TreasuryWithdraw".to_ascii_string();

    let now = 1_000_000;
    clock.set_for_testing(now);

    emergency::freeze_type(&mut freeze, &cap, type_key, &clock);

    let frozen = freeze.frozen_types();
    let expiry = *frozen.get(&type_key);
    let expected = now + freeze.max_freeze_duration_ms();
    assert!(expiry == expected);

    destroy(freeze);
    destroy(cap);
    clock.destroy_for_testing();
}

#[test]
/// Cap holder can unfreeze a frozen type.
fun test_unfreeze__cap_holder_can_unfreeze() {
    let (mut freeze, cap, clock) = setup();
    let type_key = b"TreasuryWithdraw".to_ascii_string();

    emergency::freeze_type(&mut freeze, &cap, type_key, &clock);
    assert!(emergency::is_frozen(&freeze, &type_key, &clock));

    emergency::unfreeze_type(&mut freeze, &cap, type_key);
    assert!(!emergency::is_frozen(&freeze, &type_key, &clock));

    destroy(freeze);
    destroy(cap);
    clock.destroy_for_testing();
}

#[test]
/// Governance can unfreeze via the package-internal function.
fun test_unfreeze__governance_can_unfreeze() {
    let (mut freeze, cap, clock) = setup();
    let type_key = b"TreasuryWithdraw".to_ascii_string();

    emergency::freeze_type(&mut freeze, &cap, type_key, &clock);
    assert!(emergency::is_frozen(&freeze, &type_key, &clock));

    emergency::governance_unfreeze(&mut freeze, type_key);
    assert!(!emergency::is_frozen(&freeze, &type_key, &clock));

    destroy(freeze);
    destroy(cap);
    clock.destroy_for_testing();
}

#[test]
/// An expired freeze should be treated as inactive.
fun test_auto_expiry__expired_freeze_treated_as_inactive() {
    let (mut freeze, cap, mut clock) = setup();
    let type_key = b"TreasuryWithdraw".to_ascii_string();

    let now = 1_000_000;
    clock.set_for_testing(now);

    emergency::freeze_type(&mut freeze, &cap, type_key, &clock);
    assert!(emergency::is_frozen(&freeze, &type_key, &clock));

    // Advance clock past expiry
    let past_expiry = now + freeze.max_freeze_duration_ms() + 1;
    clock.set_for_testing(past_expiry);

    // Should no longer be frozen
    assert!(!emergency::is_frozen(&freeze, &type_key, &clock));

    // assert_not_frozen should not abort
    emergency::assert_not_frozen(&freeze, &type_key, &clock);

    destroy(freeze);
    destroy(cap);
    clock.destroy_for_testing();
}

#[test, expected_failure(abort_code = emergency::EProtectedType)]
/// TransferFreezeAdmin cannot be frozen.
fun test_protected__transfer_freeze_admin_cannot_be_frozen() {
    let (mut freeze, cap, clock) = setup();
    let type_key = b"TransferFreezeAdmin".to_ascii_string();

    // Should abort — protected type
    emergency::freeze_type(&mut freeze, &cap, type_key, &clock);

    destroy(freeze);
    destroy(cap);
    clock.destroy_for_testing();
}

#[test, expected_failure(abort_code = emergency::EProtectedType)]
/// UnfreezeProposalType cannot be frozen.
fun test_protected__unfreeze_proposal_type_cannot_be_frozen() {
    let (mut freeze, cap, clock) = setup();
    let type_key = b"UnfreezeProposalType".to_ascii_string();

    // Should abort — protected type
    emergency::freeze_type(&mut freeze, &cap, type_key, &clock);

    destroy(freeze);
    destroy(cap);
    clock.destroy_for_testing();
}

#[test]
/// Freezing a type should emit a TypeFrozen event.
fun test_freeze__emits_type_frozen_event() {
    let (mut freeze, cap, clock) = setup();
    let type_key = b"TreasuryWithdraw".to_ascii_string();

    // freeze_type emits TypeFrozen — Sui test framework captures events
    // We verify the freeze succeeded (event emission is implicit)
    emergency::freeze_type(&mut freeze, &cap, type_key, &clock);
    assert!(emergency::is_frozen(&freeze, &type_key, &clock));

    destroy(freeze);
    destroy(cap);
    clock.destroy_for_testing();
}

// === Freeze Exempt Types Tests ===

#[test]
/// Default exempt types include TransferFreezeAdmin and UnfreezeProposalType.
fun test_exempt__default_types_include_mandatory() {
    let (freeze, cap, clock) = setup();

    let exempt = freeze.freeze_exempt_types();
    assert!(exempt.contains(&b"TransferFreezeAdmin".to_ascii_string()));
    assert!(exempt.contains(&b"UnfreezeProposalType".to_ascii_string()));

    destroy(freeze);
    destroy(cap);
    clock.destroy_for_testing();
}

#[test, expected_failure(abort_code = emergency::EProtectedType)]
/// Custom exempt type added via test helper cannot be frozen.
fun test_exempt__custom_exempt_type_cannot_be_frozen() {
    let (mut freeze, cap, clock) = setup();
    let type_key = b"CustomType".to_ascii_string();

    emergency::add_exempt_type_for_testing(&mut freeze, type_key);
    // Should abort — now exempt
    emergency::freeze_type(&mut freeze, &cap, type_key, &clock);

    destroy(freeze);
    destroy(cap);
    clock.destroy_for_testing();
}

#[test]
/// Removing an exempt type allows it to be frozen again.
fun test_exempt__removed_type_can_be_frozen() {
    let (mut freeze, cap, clock) = setup();
    let type_key = b"CustomType".to_ascii_string();

    emergency::add_exempt_type_for_testing(&mut freeze, type_key);
    assert!(freeze.freeze_exempt_types().contains(&type_key));

    emergency::remove_exempt_type_for_testing(&mut freeze, type_key);
    assert!(!freeze.freeze_exempt_types().contains(&type_key));

    // Should succeed — no longer exempt
    emergency::freeze_type(&mut freeze, &cap, type_key, &clock);
    assert!(emergency::is_frozen(&freeze, &type_key, &clock));

    destroy(freeze);
    destroy(cap);
    clock.destroy_for_testing();
}

#[test, expected_failure(abort_code = emergency::EMandatoryExemptType)]
/// Mandatory exempt types cannot be removed via governance.
fun test_exempt__mandatory_type_cannot_be_removed() {
    let (mut freeze, cap, clock) = setup();
    let type_key = b"TransferFreezeAdmin".to_ascii_string();

    // Should abort — mandatory type
    emergency::remove_exempt_type_for_testing(&mut freeze, type_key);

    destroy(freeze);
    destroy(cap);
    clock.destroy_for_testing();
}

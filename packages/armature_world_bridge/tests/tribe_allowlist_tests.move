#[test_only]
module armature_world_bridge::tribe_allowlist_tests;

use armature_world_bridge::tribe_allowlist;
use sui::test_utils::destroy;

#[test]
fun empty_starts_disabled_and_empty() {
    let a = tribe_allowlist::new_for_testing(false, vector[]);
    assert!(!a.is_enabled());
    assert!(a.size() == 0);
    assert!(!a.contains(42));
    destroy(a);
}

#[test]
fun apply_adds_new_ids() {
    let mut a = tribe_allowlist::new_for_testing(true, vector[]);
    a.apply(vector[1, 2, 3], vector[]);
    assert!(a.size() == 3);
    assert!(a.contains(1));
    assert!(a.contains(2));
    assert!(a.contains(3));
    destroy(a);
}

#[test]
fun apply_silently_skips_existing_adds() {
    let mut a = tribe_allowlist::new_for_testing(true, vector[5, 7]);
    a.apply(vector[5, 9], vector[]); // 5 already present, 9 is new
    assert!(a.size() == 3);
    assert!(a.contains(5));
    assert!(a.contains(7));
    assert!(a.contains(9));
    destroy(a);
}

#[test]
fun apply_silently_skips_nonexistent_removes() {
    let mut a = tribe_allowlist::new_for_testing(true, vector[5, 7]);
    a.apply(vector[], vector[5, 999]); // 5 exists, 999 doesn't
    assert!(a.size() == 1);
    assert!(!a.contains(5));
    assert!(a.contains(7));
    destroy(a);
}

#[test]
fun apply_simultaneous_add_and_remove_same_id_ends_present() {
    // "Set the state to this" semantics: removals applied first, then adds.
    // So add+remove of the same id ends with it present.
    let mut a = tribe_allowlist::new_for_testing(true, vector[]);
    a.apply(vector[42], vector[42]);
    assert!(a.contains(42));
    assert!(a.size() == 1);
    destroy(a);
}

#[test]
fun apply_handles_internal_duplicates_in_inputs() {
    let mut a = tribe_allowlist::new_for_testing(true, vector[]);
    // Internal dups in adds collapse to a single insert.
    a.apply(vector[1, 1, 2, 2], vector[]);
    assert!(a.size() == 2);
    destroy(a);
}

#[test, expected_failure(abort_code = armature_world_bridge::tribe_allowlist::EAllowlistFull)]
fun apply_overflow_aborts() {
    // Pre-fill 7 entries (max is 8). Adding 2 distinct new ids would bring
    // total to 9, must abort.
    let mut a = tribe_allowlist::new_for_testing(true, vector[1, 2, 3, 4, 5, 6, 7]);
    a.apply(vector[100, 200], vector[]);
    destroy(a);
}

#[test]
fun apply_at_max_boundary_succeeds() {
    // 7 existing + 1 new = 8 (exactly MAX_TRIBE_IDS) is legal.
    let mut a = tribe_allowlist::new_for_testing(true, vector[1, 2, 3, 4, 5, 6, 7]);
    a.apply(vector[100], vector[]);
    assert!(a.size() == 8);
    assert!(a.contains(100));
    destroy(a);
}

#[test]
fun apply_remove_then_add_at_boundary() {
    // Starting at MAX (8), remove 1 and add 1 → net 0, still at 8. Legal.
    let mut a = tribe_allowlist::new_for_testing(true, vector[1, 2, 3, 4, 5, 6, 7, 8]);
    a.apply(vector[100], vector[8]);
    assert!(a.size() == 8);
    assert!(!a.contains(8));
    assert!(a.contains(100));
    destroy(a);
}

#[test, expected_failure(abort_code = armature_world_bridge::tribe_allowlist::EAllowlistFull)]
fun apply_remove_then_add_overflow_aborts() {
    // Starting at MAX (8), remove 1 and add 2 → net +1, exceeds MAX. Abort.
    let mut a = tribe_allowlist::new_for_testing(true, vector[1, 2, 3, 4, 5, 6, 7, 8]);
    a.apply(vector[100, 200], vector[8]);
    destroy(a);
}

#[test]
fun set_enabled_flips_flag() {
    let mut a = tribe_allowlist::new_for_testing(false, vector[1, 2]);
    assert!(!a.is_enabled());
    a.set_enabled(true);
    assert!(a.is_enabled());
    a.set_enabled(false);
    assert!(!a.is_enabled());
    destroy(a);
}

#[test]
fun max_size_is_8() {
    assert!(tribe_allowlist::max_size() == 8);
}

#[test_only]
module armature::spend_guard_tests;

use armature::spend_guard::{Self, SpendWindow};

// === Constants ===

const EPOCH_MS: u64 = 86_400_000; // 24 hours
const MAX_SPEND: u64 = 1_000;

// === Helpers ===

fun new_window(start_ms: u64): SpendWindow {
    spend_guard::new(start_ms, MAX_SPEND, EPOCH_MS)
}

// === Tests ===

#[test]
/// A freshly created SpendWindow starts with zero spend and correct limits.
fun new_spend_window_starts_empty() {
    let w = new_window(0);
    assert!(w.epoch_spend() == 0);
    assert!(w.max_epoch_spend() == MAX_SPEND);
    assert!(w.epoch_start_ms() == 0);
    assert!(w.epoch_duration_ms() == EPOCH_MS);
    sui::test_utils::destroy(w);
}

#[test]
/// charge within the epoch limit succeeds and accumulates spend.
fun charge_within_limit_succeeds() {
    let mut w = new_window(0);
    w.charge(400, 0);
    assert!(w.epoch_spend() == 400);
    w.charge(300, 0);
    assert!(w.epoch_spend() == 700);
    sui::test_utils::destroy(w);
}

#[test]
/// charge at the exact epoch limit succeeds.
fun charge_at_exact_limit_succeeds() {
    let mut w = new_window(0);
    w.charge(MAX_SPEND, 0);
    assert!(w.epoch_spend() == MAX_SPEND);
    sui::test_utils::destroy(w);
}

#[test, expected_failure(abort_code = armature::spend_guard::EExceedsEpochLimit)]
/// charge that pushes cumulative spend past max_epoch_spend aborts.
fun charge_exceeds_limit_aborts() {
    let mut w = new_window(0);
    w.charge(MAX_SPEND, 0);
    // One more unit over the cap → abort
    w.charge(1, 0);
    sui::test_utils::destroy(w);
}

#[test]
/// Charging after the epoch duration has elapsed rolls the epoch and resets spend.
fun charge_rolls_epoch_after_duration() {
    let mut w = new_window(0);
    w.charge(MAX_SPEND, 0); // fill the first epoch

    // Advance into the next epoch
    let next_epoch_ms = EPOCH_MS + 1;
    w.charge(1, next_epoch_ms);

    assert!(w.epoch_spend() == 1);
    assert!(w.epoch_start_ms() == EPOCH_MS);
    sui::test_utils::destroy(w);
}

#[test]
/// Multiple whole epoch periods elapsed at once still resets spend correctly.
fun charge_skips_multiple_epochs() {
    let mut w = new_window(0);
    w.charge(500, 0);

    // Skip 3 full epochs
    w.charge(200, 3 * EPOCH_MS + 500);

    assert!(w.epoch_spend() == 200);
    assert!(w.epoch_start_ms() == 3 * EPOCH_MS);
    sui::test_utils::destroy(w);
}

#[test]
/// set_max updates the per-epoch cap; subsequent charges respect the new limit.
fun set_max_updates_cap() {
    let mut w = new_window(0);
    w.charge(500, 0);

    w.set_max(600);
    assert!(w.max_epoch_spend() == 600);

    // 100 more brings spend to 600 — exactly at new cap
    w.charge(100, 0);
    assert!(w.epoch_spend() == 600);
    sui::test_utils::destroy(w);
}

#[test, expected_failure(abort_code = armature::spend_guard::EExceedsEpochLimit)]
/// charge aborts after set_max lowers the cap below current spend.
fun charge_aborts_when_set_max_lowers_cap_below_existing_spend() {
    let mut w = new_window(0);
    w.charge(800, 0); // spend = 800

    w.set_max(500); // cap now below current spend

    // Any additional charge should abort (800 + 1 > 500)
    w.charge(1, 0);
    sui::test_utils::destroy(w);
}

#[test]
/// Accessors return the correct values after mutations.
fun accessors_return_correct_values() {
    let mut w = spend_guard::new(5_000, 2_000, 3_600_000);
    assert!(w.epoch_start_ms() == 5_000);
    assert!(w.max_epoch_spend() == 2_000);
    assert!(w.epoch_duration_ms() == 3_600_000);
    assert!(w.epoch_spend() == 0);

    w.charge(100, 5_000);
    assert!(w.epoch_spend() == 100);

    w.set_max(3_000);
    assert!(w.max_epoch_spend() == 3_000);

    sui::test_utils::destroy(w);
}

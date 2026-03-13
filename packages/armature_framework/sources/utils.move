module armature::utils;

// === Constants ===

/// 10,000 basis points = 100%.
const BPS_SCALE: u64 = 10_000;

// === Public Functions ===

/// Apply basis points to a value: `value * bps / 10_000`.
/// Uses u128 intermediate to prevent overflow on large balances.
public fun mul_bps(value: u64, bps: u64): u64 {
    ((value as u128) * (bps as u128) / (BPS_SCALE as u128)) as u64
}

/// Check if `numerator / denominator >= threshold_bps / 10_000`.
/// Cross-multiplies with u128 to avoid both division and overflow.
public fun gte_bps(numerator: u64, denominator: u64, threshold_bps: u64): bool {
    (numerator as u128) * (BPS_SCALE as u128) >= (threshold_bps as u128) * (denominator as u128)
}

/// The basis point scale factor (10,000 = 100%).
public fun bps_scale(): u64 { BPS_SCALE }

// === Tests ===

#[test]
fun mul_bps_basic() {
    // 1% of 1_000_000 = 10_000
    assert!(mul_bps(1_000_000, 100) == 10_000);
    // 50% of 200 = 100
    assert!(mul_bps(200, 5_000) == 100);
    // 100% of 42 = 42
    assert!(mul_bps(42, 10_000) == 42);
}

#[test]
fun mul_bps_zero() {
    assert!(mul_bps(0, 5_000) == 0);
    assert!(mul_bps(1_000_000, 0) == 0);
    assert!(mul_bps(0, 0) == 0);
}

#[test]
fun mul_bps_large_value_no_overflow() {
    // u64::MAX = 18_446_744_073_709_551_615
    // 1% of u64::MAX — would overflow with naive u64 multiply
    let max = 18_446_744_073_709_551_615;
    let result = mul_bps(max, 100);
    // Expected: max * 100 / 10_000 = max / 100 = 184_467_440_737_095_516
    assert!(result == 184_467_440_737_095_516);
}

#[test]
fun mul_bps_precision() {
    // 9_999 / 10_000 * 100 = 99 (truncated, not 100)
    // But with u128: 9_999 * 100 / 10_000 = 999_900 / 10_000 = 99
    assert!(mul_bps(9_999, 100) == 99);
    // Compare old divide-first: 9_999 / 10_000 * 100 = 0 * 100 = 0
    // u128 approach preserves precision for small values
    assert!(mul_bps(5_000, 1) == 0); // 0.01% of 5000 = 0.5, truncates to 0
    assert!(mul_bps(10_000, 1) == 1); // 0.01% of 10_000 = 1
}

#[test]
fun gte_bps_exact_threshold() {
    // 50 / 100 = 50% = 5_000 bps → should pass at exactly 5_000
    assert!(gte_bps(50, 100, 5_000) == true);
    // Just below
    assert!(gte_bps(49, 100, 5_000) == false);
    // Just above
    assert!(gte_bps(51, 100, 5_000) == true);
}

#[test]
fun gte_bps_edge_cases() {
    // 0 / 100 >= 0 bps → true (0 >= 0)
    assert!(gte_bps(0, 100, 0) == true);
    // 0 / 100 >= 1 bps → false
    assert!(gte_bps(0, 100, 1) == false);
    // 100% check: 100 / 100 >= 10_000 bps → true
    assert!(gte_bps(100, 100, 10_000) == true);
    // Anything / 0 >= any bps → true (zero-denominator: numerator*SCALE >= 0)
    assert!(gte_bps(0, 0, 10_000) == true);
}

#[test]
fun gte_bps_large_values_no_overflow() {
    let max = 18_446_744_073_709_551_615;
    // max / max = 100% >= 50% → true
    assert!(gte_bps(max, max, 5_000) == true);
    // max / max = 100% >= 100% → true
    assert!(gte_bps(max, max, 10_000) == true);
    // floor(max/2) is just under 50% of max (max is odd) → false
    assert!(gte_bps(max / 2, max, 5_000) == false);
    // (max/2 + 1) is just over 50% → true
    assert!(gte_bps(max / 2 + 1, max, 5_000) == true);
}

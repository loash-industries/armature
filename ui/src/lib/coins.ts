/**
 * Shared utilities for coin amount formatting and parsing.
 */

/**
 * Format a raw bigint balance to a human-readable decimal string.
 * Uses pure bigint arithmetic to avoid floating-point precision loss.
 */
export function formatBalance(raw: bigint, decimals = 9): string {
  if (decimals === 0) return raw.toString();
  const divisor = BigInt(10 ** decimals);
  const whole = raw / divisor;
  const frac = raw % divisor;
  if (frac === 0n) return whole.toString();
  const fracStr = frac.toString().padStart(decimals, "0").replace(/0+$/, "");
  return `${whole}.${fracStr}`;
}

/**
 * Parse a human-readable decimal string (e.g. "1.5") into base units (bigint).
 * Returns null if the input is not a valid non-negative number.
 * Truncates fractional digits beyond `decimals`.
 */
export function parseAmount(human: string, decimals: number): bigint | null {
  const trimmed = human.trim();
  if (!trimmed || trimmed === ".") return null;

  // Only allow digits and at most one decimal point.
  if (!/^\d*\.?\d*$/.test(trimmed)) return null;

  const parts = trimmed.split(".");
  if (parts.length > 2) return null;

  const wholeStr = parts[0] || "0";
  let fracStr = parts[1] ?? "";

  // Truncate fractional digits beyond the coin's decimals.
  if (fracStr.length > decimals) {
    fracStr = fracStr.slice(0, decimals);
  } else {
    fracStr = fracStr.padEnd(decimals, "0");
  }

  try {
    const whole = BigInt(wholeStr);
    const frac = fracStr ? BigInt(fracStr) : 0n;
    return whole * BigInt(10 ** decimals) + frac;
  } catch {
    return null;
  }
}

/* ------------------------------------------------------------------ */
/*  Helpers for FloatingAnimatedNumber props                           */
/* ------------------------------------------------------------------ */

export interface FloatingParts {
  whole: number;
  decimal: number;
  decimalPlaces: number;
}

const DEFAULT_SIG_FIGS = 6;

/**
 * Split a bigint base-unit balance into { whole, decimal, decimalPlaces }
 * for FloatingAnimatedNumber consumption.
 *
 * `sigFigs` controls the maximum decimal digits shown (default 6).
 * Trailing zeros in the decimal portion are trimmed.
 */
export function splitBalance(
  raw: bigint,
  coinDecimals: number,
  sigFigs = DEFAULT_SIG_FIGS,
): FloatingParts {
  if (coinDecimals === 0) {
    return { whole: Number(raw), decimal: 0, decimalPlaces: 0 };
  }
  const divisor = BigInt(10 ** coinDecimals);
  const wholeBig = raw / divisor;
  const fracBig = raw % divisor;

  const places = Math.min(coinDecimals, sigFigs);
  const truncDivisor = BigInt(10 ** (coinDecimals - places));
  const truncFrac = Number(fracBig / truncDivisor);

  const fracStr = truncFrac.toString().padStart(places, "0");
  const trimmed = fracStr.replace(/0+$/, "");
  const decimalPlaces = trimmed.length || 0;
  const decimal = decimalPlaces > 0 ? parseInt(trimmed, 10) : 0;

  return { whole: Number(wholeBig), decimal, decimalPlaces };
}

/**
 * Split a regular JS number into { whole, decimal, decimalPlaces } props,
 * capped to `sigFigs` decimal places with trailing zeros removed.
 */
export function splitNumber(
  value: number,
  sigFigs = DEFAULT_SIG_FIGS,
): FloatingParts {
  const whole = Math.trunc(value);
  const frac = Math.abs(value - whole);
  if (frac === 0) return { whole, decimal: 0, decimalPlaces: 0 };

  const fracStr = frac.toFixed(sigFigs).slice(2).replace(/0+$/, "");
  const decimalPlaces = fracStr.length || 0;
  const decimal = decimalPlaces > 0 ? parseInt(fracStr, 10) : 0;

  return { whole, decimal, decimalPlaces };
}

/**
 * Address → display name utilities.
 *
 * Names are derived deterministically from the address bytes so that the same
 * address always maps to the same name regardless of encounter order or page
 * reload.  No address ever falls back to a truncated hex.
 *
 * Uses `unique-names-generator` (adjective + animal, ~427k unique combos).
 */
import {
  uniqueNamesGenerator,
  adjectives,
  animals,
} from "unique-names-generator";

/**
 * Fold all 32 address bytes (64 hex chars after "0x") into a 32-bit seed
 * by accumulating with a multiply-xor step for good avalanche behaviour.
 */
function addressToSeed(address: string): number {
  const hex = address.startsWith("0x") ? address.slice(2) : address;
  let seed = 0;
  for (let i = 0; i < hex.length - 1; i += 2) {
    const byte = parseInt(hex.slice(i, i + 2), 16);
    seed = (Math.imul(seed, 31) ^ byte) >>> 0;
  }
  return seed;
}

/**
 * Returns the generated name for `address` (no `@` prefix).
 * The result is fully deterministic — the same address always produces the
 * same name regardless of call order or session state.
 */
export function getAddressNameRaw(address: string): string {
  return uniqueNamesGenerator({
    dictionaries: [adjectives, animals],
    separator: " ",
    style: "capital",
    seed: addressToSeed(address),
  });
}

/**
 * Returns the `@Name` display string for `address`.
 */
export function getAddressName(address: string): string {
  return `@${getAddressNameRaw(address)}`;
}

/**
 * Resolves a Sui address to a display name, always prefixed with `@`.
 * Prefers a resolved character name; falls back to the session-assigned fake name.
 */
export function resolveDisplayName(address: string, charName?: string | null): string {
  if (charName) return `@${charName}`;
  return getAddressName(address);
}

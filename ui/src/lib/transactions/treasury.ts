/**
 * Direct treasury transaction builders (permissionless, not proposal-gated).
 */

import { Transaction, fw, MODULES } from "./helpers";

/**
 * Claim a coin that was transferred directly to the treasury vault (not via proposal).
 * Uses Sui's transfer::Receiving pattern — the coinToClaimId must be the object ID
 * of a Coin<T> that was sent to the vault's address.
 */
/**
 * Claim a coin that was transferred directly to the treasury vault (not via proposal).
 * Uses Sui's transfer::Receiving pattern — the caller must supply the full ObjectRef
 * (objectId, version, digest) for the coin object that was sent to the vault's address.
 */
export function buildClaimCoin(args: {
  treasuryId: string;
  /** Full ObjectRef of the Coin<T> sent to the treasury address */
  coinRef: { objectId: string; version: string | number; digest: string };
  coinType: string;
}): Transaction {
  const tx = new Transaction();

  tx.moveCall({
    target: fw(MODULES.treasury_vault, "claim_coin"),
    arguments: [
      tx.object(args.treasuryId),
      tx.receivingRef(args.coinRef),
    ],
    typeArguments: [args.coinType],
  });

  return tx;
}

/** Deposit a coin into the DAO treasury. */
export function buildDeposit(args: {
  treasuryId: string;
  coinObjectId: string;
  coinType: string;
}): Transaction {
  const tx = new Transaction();

  tx.moveCall({
    target: fw(MODULES.treasury_vault, "deposit"),
    arguments: [
      tx.object(args.treasuryId),
      tx.object(args.coinObjectId),
    ],
    typeArguments: [args.coinType],
  });

  return tx;
}

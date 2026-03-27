/**
 * Direct treasury transaction builders (permissionless, not proposal-gated).
 */

import { Transaction, fw, MODULES } from "./helpers";

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

/**
 * Merge all coin objects of the same type and deposit an amount into the DAO treasury.
 * If `amount` is provided the transaction splits that amount and deposits only the split;
 * otherwise the entire merged coin is deposited.
 */
export function buildSplitAndDeposit(args: {
  treasuryId: string;
  /** All coin objects of this type owned by the wallet. */
  coinObjectIds: string[];
  coinType: string;
  /** Amount in base units to deposit. Omit to deposit the full balance. */
  amount?: bigint;
}): Transaction {
  if (args.coinObjectIds.length === 0) throw new Error("No coin objects provided");

  const tx = new Transaction();
  const isSui = args.coinType === "0x2::sui::SUI" ||
    args.coinType === "0x0000000000000000000000000000000000000000000000000000000000000002::sui::SUI";

  if (isSui) {
    // For SUI, just split from tx.gas. The Sui SDK automatically selects
    // and consolidates all of the sender's SUI coins into the gas payment,
    // so we must NOT manually merge wallet objects into tx.gas — doing so
    // would double-reference the coin the SDK already picked for gas,
    // making it unavailable for gas selection.
    if (args.amount === undefined) {
      throw new Error("An explicit amount is required when depositing SUI (cannot deposit entire balance — gas must be reserved).");
    }

    const coinToDeposit = tx.splitCoins(tx.gas, [tx.pure.u64(args.amount)])[0];

    tx.moveCall({
      target: fw(MODULES.treasury_vault, "deposit"),
      arguments: [tx.object(args.treasuryId), coinToDeposit],
      typeArguments: [args.coinType],
    });

    return tx;
  }

  // Non-SUI path: merge all objects into the first, then optionally split.
  const [primaryId, ...restIds] = args.coinObjectIds;
  const primaryCoin = tx.object(primaryId);

  if (restIds.length > 0) {
    tx.mergeCoins(primaryCoin, restIds.map((id) => tx.object(id)));
  }

  const coinToDeposit =
    args.amount !== undefined
      ? tx.splitCoins(primaryCoin, [tx.pure.u64(args.amount)])[0]
      : primaryCoin;

  tx.moveCall({
    target: fw(MODULES.treasury_vault, "deposit"),
    arguments: [tx.object(args.treasuryId), coinToDeposit],
    typeArguments: [args.coinType],
  });

  return tx;
}

/**
 * Direct emergency action transaction builders (FreezeAdminCap-gated, not proposal-gated).
 */

import { Transaction, fw, SUI_CLOCK, MODULES } from "./helpers";

/** Freeze a proposal type (direct FreezeAdminCap action, not proposal-gated). */
export function buildFreezeType(args: {
  emergencyFreezeId: string;
  freezeAdminCapId: string;
  typeKey: string;
}): Transaction {
  const tx = new Transaction();

  tx.moveCall({
    target: fw(MODULES.emergency, "freeze_type"),
    arguments: [
      tx.object(args.emergencyFreezeId),
      tx.object(args.freezeAdminCapId),
      tx.pure.string(args.typeKey),
      tx.object(SUI_CLOCK),
    ],
  });

  return tx;
}

/** Unfreeze a proposal type (direct FreezeAdminCap action). */
export function buildUnfreezeType(args: {
  emergencyFreezeId: string;
  freezeAdminCapId: string;
  typeKey: string;
}): Transaction {
  const tx = new Transaction();

  tx.moveCall({
    target: fw(MODULES.emergency, "unfreeze_type"),
    arguments: [
      tx.object(args.emergencyFreezeId),
      tx.object(args.freezeAdminCapId),
      tx.pure.string(args.typeKey),
    ],
  });

  return tx;
}

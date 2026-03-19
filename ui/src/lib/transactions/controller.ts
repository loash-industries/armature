/**
 * Controller (privileged SubDAO) transaction builders.
 *
 * Privileged operations bypass board voting for SubDAO management.
 * The flow is: privileged_submit → [any exec side-effects] → privileged_consume.
 * Both calls must happen in the same PTB (ExecutionRequest<P> is a hot potato).
 *
 * See armature_framework::controller for the on-chain module.
 */

import { Transaction, fw, SUI_CLOCK, MODULES } from "./helpers";

/**
 * Privileged operation PTB — submit + consume in one transaction.
 *
 * Use this for arbitrary payloads by passing the pre-built payload result.
 * The `payload` argument is the result of a prior moveCall in the same PTB
 * (e.g., the result of `set_board::new`, `update_metadata::new`, etc.).
 *
 * Example:
 * ```ts
 * const tx = new Transaction();
 * const payload = tx.moveCall({ target: prop("set_board", "new"), ... });
 * buildPrivilegedOp(tx, { controlId, subdaoId, typeKey: "SetBoard", metadataIpfs, payload, proposalType });
 * ```
 */
export function buildPrivilegedOp(
  tx: Transaction,
  args: {
    controlId: string;
    subdaoId: string;
    typeKey: string;
    metadataIpfs: string;
    payload: ReturnType<Transaction["moveCall"]>;
    proposalType: string;
  },
): void {
  const req = tx.moveCall({
    target: fw(MODULES.controller, "privileged_submit"),
    arguments: [
      tx.object(args.controlId),
      tx.object(args.subdaoId),
      tx.pure.string(args.typeKey),
      tx.pure.string(args.metadataIpfs),
      args.payload,
      tx.object(SUI_CLOCK),
    ],
    typeArguments: [args.proposalType],
  });

  tx.moveCall({
    target: fw(MODULES.controller, "privileged_consume"),
    arguments: [req, tx.object(args.controlId)],
    typeArguments: [args.proposalType],
  });
}

/**
 * DAO lifecycle transaction builders.
 */

import { Transaction, fw, prop, SUI_CLOCK, MODULES, PROPOSAL_MODULES, PROPOSALS_PACKAGE_ID } from "./helpers";

/**
 * Build an Option<String> argument for submit_proposal's metadata_ipfs parameter.
 */
function optionalString(tx: Transaction, value: string) {
  if (value) {
    return tx.moveCall({
      target: "0x1::option::some",
      arguments: [tx.pure.string(value)],
      typeArguments: ["0x1::string::String"],
    });
  }
  return tx.moveCall({
    target: "0x1::option::none",
    typeArguments: ["0x1::string::String"],
  });
}

/** Create a new root DAO. Returns a Transaction (DAO ID is emitted as event). */
export function buildCreateDao(args: {
  name: string;
  description: string;
  imageUrl: string;
  initialMembers: string[];
}): Transaction {
  const tx = new Transaction();

  // 1. Init board governance
  const govInit = tx.moveCall({
    target: fw(MODULES.governance, "init_board"),
    arguments: [
      tx.pure.vector("address", args.initialMembers),
    ],
  });

  // 2. Create DAO
  tx.moveCall({
    target: fw(MODULES.dao, "create"),
    arguments: [
      govInit,
      tx.pure.string(args.name),
      tx.pure.string(args.description),
      tx.pure.string(args.imageUrl),
    ],
  });

  return tx;
}

/** Create a SubDAO via proposal execution flow. */
export function buildSubmitCreateSubDAO(args: {
  daoId: string;
  name: string;
  description: string;
  initialBoard: string[];
  metadataIpfs: string;
}): Transaction {
  const tx = new Transaction();

  const payload = tx.moveCall({
    target: prop(PROPOSAL_MODULES.create_subdao, "new"),
    arguments: [
      tx.pure.string(args.name),
      tx.pure.string(args.description),
      tx.pure.vector("address", args.initialBoard),
      tx.pure.string(args.metadataIpfs),
    ],
  });

  tx.moveCall({
    target: fw(MODULES.board_voting, "submit_proposal"),
    arguments: [
      tx.object(args.daoId),
      tx.pure.string("CreateSubDAO"),
      optionalString(tx, args.metadataIpfs),
      payload,
      tx.object(SUI_CLOCK),
    ],
    typeArguments: [
      `${PROPOSALS_PACKAGE_ID}::${PROPOSAL_MODULES.create_subdao}::CreateSubDAO`,
    ],
  });

  return tx;
}

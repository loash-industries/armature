/**
 * Integration tests: TransferAssets governance operation
 *
 * Covers: buildSubmitTransferAssets, buildExecuteTransferAssets
 * Requires: make dev (localnet + deployed packages)
 *
 * Setup: 3-member parent DAO creates a SubDAO, deposits SUI into the parent
 * treasury, then proposes and executes a TransferAssets to move SUI to the
 * SubDAO's treasury.
 */

import { describe, it, expect, beforeAll } from "vitest";
import { SuiJsonRpcClient } from "@mysten/sui/jsonRpc";
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";
import {
  PROPOSALS_PACKAGE_ID,
  createClient,
  newFundedKeypair,
  createTestDao,
  execute,
  submitAndGetProposalId,
  voteOnProposal,
  assertEvent,
  enableProposalType,
  createSubDAO,
  type TestDao,
  type SubDAOInfo,
} from "./test-utils";
import { buildDeposit } from "../../treasury";
import { buildSubmitTransferAssets } from "../../proposal";
import { buildExecuteTransferAssets } from "../../execution";

const SUI_TYPE = "0x2::sui::SUI";
const TRANSFER_ASSETS_TYPE = `${PROPOSALS_PACKAGE_ID}::transfer_assets::TransferAssets`;

let client: SuiJsonRpcClient;
let member1: Ed25519Keypair;
let member2: Ed25519Keypair;
let member3: Ed25519Keypair;
let dao: TestDao;
let subdaoInfo: SubDAOInfo;

beforeAll(async () => {
  client = createClient();
  [member1, member2, member3] = await Promise.all([
    newFundedKeypair(client),
    newFundedKeypair(client),
    newFundedKeypair(client),
  ]);
  dao = await createTestDao(client, member1, [member2, member3]);
  subdaoInfo = await createSubDAO(client, dao, member1, member2);
  await enableProposalType(client, dao, member1, member2, "TransferAssets");

  // Deposit SUI into the parent treasury so there's something to transfer.
  await depositSui(200_000_000);
});

// ---------------------------------------------------------------------------
// Deposit helper (adapted from treasury-extended.test.ts)
// ---------------------------------------------------------------------------

async function depositSui(amount: number): Promise<void> {
  const { Transaction } = await import("@mysten/sui/transactions");
  const splitTx = new Transaction();
  const [coin] = splitTx.splitCoins(splitTx.gas, [splitTx.pure.u64(amount)]);
  splitTx.transferObjects([coin], member1.toSuiAddress());
  const splitResult = await execute(client, splitTx, member1);

  const createdCoin = splitResult.objectChanges?.find(
    (c) =>
      c.type === "created" &&
      c.objectType === "0x2::coin::Coin<0x2::sui::SUI>" &&
      c.owner &&
      typeof c.owner === "object" &&
      "AddressOwner" in c.owner &&
      (c.owner as { AddressOwner: string }).AddressOwner === member1.toSuiAddress(),
  );
  if (!createdCoin || createdCoin.type !== "created") {
    throw new Error("Failed to split SUI coin for deposit");
  }

  await execute(
    client,
    buildDeposit({
      treasuryId: dao.treasuryId,
      coinObjectId: createdCoin.objectId,
      coinType: SUI_TYPE,
    }),
    member1,
  );
}

// ---------------------------------------------------------------------------
// TransferAssets
// ---------------------------------------------------------------------------

describe("TransferAssets", () => {
  it("submit → vote → execute transfers SUI from parent treasury to SubDAO treasury", async () => {
    const TRANSFER_AMOUNT = "50000000";

    const submitTx = buildSubmitTransferAssets({
      daoId: dao.daoId,
      targetDaoId: subdaoInfo.subdaoId,
      targetTreasuryId: subdaoInfo.subdaoTreasuryId,
      targetVaultId: subdaoInfo.subdaoVaultId,
      coinTypes: [SUI_TYPE],
      capIds: [],
      metadataIpfs: "ipfs://test",
    });

    const proposalId = await submitAndGetProposalId(client, submitTx, member1);
    await voteOnProposal(client, proposalId, TRANSFER_ASSETS_TYPE, true, member1);
    await voteOnProposal(client, proposalId, TRANSFER_ASSETS_TYPE, true, member2);

    const result = await execute(
      client,
      buildExecuteTransferAssets({
        daoId: dao.daoId,
        proposalId,
        sourceTreasuryId: dao.treasuryId,
        sourceVaultId: dao.capabilityVaultId,
        targetTreasuryId: subdaoInfo.subdaoTreasuryId,
        targetVaultId: subdaoInfo.subdaoVaultId,
        emergencyFreezeId: dao.emergencyFreezeId,
        coinTransfers: [{ coinType: SUI_TYPE, amount: TRANSFER_AMOUNT }],
      }),
      member1,
    );

    expect(result.effects?.status?.status).toBe("success");
    assertEvent(result, "::subdao_ops::AssetsTransferInitiated");

    // The SubDAO treasury should have been mutated.
    const subdaoTreasuryMutation = result.objectChanges?.find(
      (c) => c.type === "mutated" && c.objectId === subdaoInfo.subdaoTreasuryId,
    );
    expect(subdaoTreasuryMutation).toBeDefined();
  });
});

/**
 * Integration tests: Treasury operations
 *
 * Covers e2e scenario 04-treasury-operations.md
 * Requires: make dev (localnet + deployed packages)
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
  type TestDao,
} from "./test-utils";
import { buildDeposit } from "../../treasury";
import { buildSubmitSendCoin } from "../../proposal";
import { buildExecuteSendCoin } from "../../execution";

const SUI_TYPE = "0x2::sui::SUI";
const SEND_COIN_TYPE = `${PROPOSALS_PACKAGE_ID}::send_coin::SendCoin`;

let client: SuiJsonRpcClient;
let member1: Ed25519Keypair;
let member2: Ed25519Keypair;
let dao: TestDao;

beforeAll(async () => {
  client = createClient();
  [member1, member2] = await Promise.all([
    newFundedKeypair(client),
    newFundedKeypair(client),
  ]);
  dao = await createTestDao(client, member1, [member2]);
});

// ---------------------------------------------------------------------------
// Deposit (scenario 4.x)
// ---------------------------------------------------------------------------

describe("buildDeposit", () => {
  it("deposits SUI into the treasury vault", async () => {
    // Split a small SUI coin to deposit
    const splitTx = new (await import("@mysten/sui/transactions")).Transaction();
    const [coin] = splitTx.splitCoins(splitTx.gas, [splitTx.pure.u64(100_000_000)]);
    splitTx.transferObjects([coin], member1.toSuiAddress());
    const splitResult = await execute(client, splitTx, member1);

    // Find the new coin object
    const createdCoin = splitResult.objectChanges?.find(
      (c) =>
        c.type === "created" &&
        c.objectType === "0x2::coin::Coin<0x2::sui::SUI>" &&
        c.owner &&
        "AddressOwner" in c.owner &&
        c.owner.AddressOwner === member1.toSuiAddress(),
    );
    expect(createdCoin).toBeDefined();

    const coinId = (createdCoin as { objectId: string }).objectId;

    const depositTx = buildDeposit({
      treasuryId: dao.treasuryId,
      coinObjectId: coinId,
      coinType: SUI_TYPE,
    });

    const result = await execute(client, depositTx, member1);
    expect(result.effects?.status?.status).toBe("success");

    // The treasury object should be mutated
    const treasuryMutation = result.objectChanges?.find(
      (c) => c.type === "mutated" && c.objectId === dao.treasuryId,
    );
    expect(treasuryMutation).toBeDefined();
  });
});

// ---------------------------------------------------------------------------
// Send coin proposal — submit → vote → execute (scenario 4.x)
// ---------------------------------------------------------------------------

describe("treasury withdraw via SendCoin proposal", () => {
  it("submit → 2 votes → execute SendCoin succeeds", async () => {
    const recipient = (await newFundedKeypair(client)).toSuiAddress();

    // First deposit some SUI into the treasury
    const splitTx = new (await import("@mysten/sui/transactions")).Transaction();
    const [coin] = splitTx.splitCoins(splitTx.gas, [splitTx.pure.u64(200_000_000)]);
    splitTx.transferObjects([coin], member1.toSuiAddress());
    const splitResult = await execute(client, splitTx, member1);
    const createdCoin = splitResult.objectChanges?.find(
      (c) =>
        c.type === "created" &&
        c.objectType === "0x2::coin::Coin<0x2::sui::SUI>" &&
        c.owner &&
        "AddressOwner" in c.owner &&
        c.owner.AddressOwner === member1.toSuiAddress(),
    );
    expect(createdCoin).toBeDefined();
    const coinId = (createdCoin as { objectId: string }).objectId;

    await execute(
      client,
      buildDeposit({ treasuryId: dao.treasuryId, coinObjectId: coinId, coinType: SUI_TYPE }),
      member1,
    );

    // Submit SendCoin proposal
    const submitTx = buildSubmitSendCoin({
      daoId: dao.daoId,
      recipient,
      amount: "50000000",
      coinType: SUI_TYPE,
      metadataIpfs: "ipfs://test",
    });
    const proposalId = await submitAndGetProposalId(client, submitTx, member1);

    // Pass
    await voteOnProposal(client, proposalId, SEND_COIN_TYPE, true, member1);
    await voteOnProposal(client, proposalId, SEND_COIN_TYPE, true, member2);

    // Execute
    const execTx = buildExecuteSendCoin({
      daoId: dao.daoId,
      proposalId,
      treasuryId: dao.treasuryId,
      emergencyFreezeId: dao.emergencyFreezeId,
      coinType: SUI_TYPE,
    });

    const result = await execute(client, execTx, member1);
    expect(result.effects?.status?.status).toBe("success");
    assertEvent(result, "::proposal::ProposalExecuted");
  });
});

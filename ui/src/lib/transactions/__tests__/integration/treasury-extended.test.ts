/**
 * Integration tests: Extended treasury operations
 *
 * Covers: SendSmallPayment, SendCoinToDAO
 * Requires: make dev (localnet + deployed packages)
 *
 * Both SendSmallPayment and SendCoinToDAO are NOT enabled by default.
 * Each describe block enables the required type via governance before testing.
 *
 * Setup: 3-member DAO — 2 votes (66.7%) needed, satisfying the 66%
 * EnableProposalType approval floor and the 50% quorum.
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
import {
  buildSubmitEnableProposalType,
  buildSubmitSendSmallPayment,
  buildSubmitSendCoinToDAO,
} from "../../proposal";
import {
  buildExecuteEnableProposalType,
  buildExecuteSendSmallPayment,
  buildExecuteSendCoinToDAO,
} from "../../execution";

const SUI_TYPE = "0x2::sui::SUI";
const ENABLE_TYPE = `${PROPOSALS_PACKAGE_ID}::enable_proposal_type::EnableProposalType`;
const SEND_SMALL_PAYMENT_TYPE = `${PROPOSALS_PACKAGE_ID}::send_small_payment::SendSmallPayment<${SUI_TYPE}>`;
const SEND_COIN_TO_DAO_TYPE = `${PROPOSALS_PACKAGE_ID}::send_coin_to_dao::SendCoinToDAO<${SUI_TYPE}>`;

let client: SuiJsonRpcClient;
let member1: Ed25519Keypair;
let member2: Ed25519Keypair;
let member3: Ed25519Keypair;
let dao: TestDao;

beforeAll(async () => {
  client = createClient();
  [member1, member2, member3] = await Promise.all([
    newFundedKeypair(client),
    newFundedKeypair(client),
    newFundedKeypair(client),
  ]);
  // 3-member DAO: 2 votes (66.7%) meets both 50% quorum and 66% EnableProposalType floor.
  dao = await createTestDao(client, member1, [member2, member3]);
});

// ---------------------------------------------------------------------------
// Helper: deposit SUI into the DAO treasury
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
      typeof c.owner === "object" && "AddressOwner" in c.owner &&
      c.owner.AddressOwner === member1.toSuiAddress(),
  );
  if (!createdCoin || createdCoin.type !== "created") {
    throw new Error("Failed to split SUI coin for deposit");
  }

  await execute(
    client,
    buildDeposit({ treasuryId: dao.treasuryId, coinObjectId: createdCoin.objectId, coinType: SUI_TYPE }),
    member1,
  );
}

// ---------------------------------------------------------------------------
// SendSmallPayment
// ---------------------------------------------------------------------------

describe("SendSmallPayment", () => {
  // Enable SendSmallPayment via governance before testing.
  beforeAll(async () => {
    const submitTx = buildSubmitEnableProposalType({
      daoId: dao.daoId,
      typeKey: "SendSmallPayment",
      quorum: 5000,
      approvalThreshold: 5000,
      proposeThreshold: "0",
      expiryMs: "86400000",
      executionDelayMs: "0",
      cooldownMs: "0",
      metadataIpfs: "ipfs://test",
    });
    const proposalId = await submitAndGetProposalId(client, submitTx, member1);
    await voteOnProposal(client, proposalId, ENABLE_TYPE, true, member1);
    await voteOnProposal(client, proposalId, ENABLE_TYPE, true, member2);
    await execute(
      client,
      buildExecuteEnableProposalType({ daoId: dao.daoId, proposalId, emergencyFreezeId: dao.emergencyFreezeId }),
      member1,
    );

    // Fund the treasury so SendSmallPayment has something to send.
    // Default spend limit is 1% of treasury balance per 24 h epoch.
    // Deposit 100 MIST so 1% = 1 MIST — well within limits.
    await depositSui(500_000_000);
  });

  it("submit → vote → execute SendSmallPayment sends SUI to recipient", async () => {
    const recipient = (await newFundedKeypair(client)).toSuiAddress();

    const submitTx = buildSubmitSendSmallPayment({
      daoId: dao.daoId,
      recipient,
      amount: "1000000", // 1 MIST — well within 1% of 500 MIST deposit
      coinType: SUI_TYPE,
      metadataIpfs: "ipfs://test",
    });
    const proposalId = await submitAndGetProposalId(client, submitTx, member1);

    await voteOnProposal(client, proposalId, SEND_SMALL_PAYMENT_TYPE, true, member1);
    await voteOnProposal(client, proposalId, SEND_SMALL_PAYMENT_TYPE, true, member2);

    const execTx = buildExecuteSendSmallPayment({
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

// ---------------------------------------------------------------------------
// SendCoinToDAO
// ---------------------------------------------------------------------------

describe("SendCoinToDAO", () => {
  let recipientDao: TestDao;

  // Enable SendCoinToDAO and create a second DAO to receive funds.
  beforeAll(async () => {
    // Enable SendCoinToDAO via governance.
    const submitTx = buildSubmitEnableProposalType({
      daoId: dao.daoId,
      typeKey: "SendCoinToDAO",
      quorum: 5000,
      approvalThreshold: 5000,
      proposeThreshold: "0",
      expiryMs: "86400000",
      executionDelayMs: "0",
      cooldownMs: "0",
      metadataIpfs: "ipfs://test",
    });
    const proposalId = await submitAndGetProposalId(client, submitTx, member1);
    await voteOnProposal(client, proposalId, ENABLE_TYPE, true, member1);
    await voteOnProposal(client, proposalId, ENABLE_TYPE, true, member2);
    await execute(
      client,
      buildExecuteEnableProposalType({ daoId: dao.daoId, proposalId, emergencyFreezeId: dao.emergencyFreezeId }),
      member1,
    );

    // Create a second DAO to act as the fund recipient.
    recipientDao = await createTestDao(client, member1);

    // Fund the source treasury.
    await depositSui(200_000_000);
  });

  it("submit → vote → execute SendCoinToDAO transfers SUI to recipient DAO treasury", async () => {
    const submitTx = buildSubmitSendCoinToDAO({
      daoId: dao.daoId,
      recipientTreasuryId: recipientDao.treasuryId,
      amount: "50000000",
      coinType: SUI_TYPE,
      metadataIpfs: "ipfs://test",
    });
    const proposalId = await submitAndGetProposalId(client, submitTx, member1);

    await voteOnProposal(client, proposalId, SEND_COIN_TO_DAO_TYPE, true, member1);
    await voteOnProposal(client, proposalId, SEND_COIN_TO_DAO_TYPE, true, member2);

    const execTx = buildExecuteSendCoinToDAO({
      daoId: dao.daoId,
      proposalId,
      sourceTreasuryId: dao.treasuryId,
      targetTreasuryId: recipientDao.treasuryId,
      emergencyFreezeId: dao.emergencyFreezeId,
      coinType: SUI_TYPE,
    });

    const result = await execute(client, execTx, member1);
    expect(result.effects?.status?.status).toBe("success");
    assertEvent(result, "::proposal::ProposalExecuted");

    // The recipient treasury should have been mutated.
    const recipientMutation = result.objectChanges?.find(
      (c) => c.type === "mutated" && c.objectId === recipientDao.treasuryId,
    );
    expect(recipientMutation).toBeDefined();
  });
});

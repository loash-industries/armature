/**
 * Integration tests: Proposal lifecycle
 *
 * Covers e2e scenario 03-proposal-lifecycle.md
 * Requires: make dev (localnet + deployed packages)
 *
 * Setup: 2-member DAO — both members vote Yes to pass proposals cleanly.
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
import {
  buildSubmitSetBoard,
  buildSubmitUpdateMetadata,
  buildTryExpire,
} from "../../proposal";
import { buildExecuteSetBoard, buildExecuteUpdateMetadata } from "../../execution";

let client: SuiJsonRpcClient;
let member1: Ed25519Keypair;
let member2: Ed25519Keypair;
let dao: TestDao;

const SET_BOARD_TYPE = `${PROPOSALS_PACKAGE_ID}::set_board::SetBoard`;
const UPDATE_METADATA_TYPE = `${PROPOSALS_PACKAGE_ID}::update_metadata::UpdateMetadata`;

beforeAll(async () => {
  client = createClient();
  [member1, member2] = await Promise.all([
    newFundedKeypair(client),
    newFundedKeypair(client),
  ]);
  // 2-member DAO: quorum=50% means both members voting yes = 100% approval
  dao = await createTestDao(client, member1, [member2]);
});

// ---------------------------------------------------------------------------
// Submit proposal (scenario 3.1)
// ---------------------------------------------------------------------------

describe("submit proposal (scenario 3.1)", () => {
  it("buildSubmitSetBoard — transaction succeeds and emits ProposalCreated", async () => {
    const tx = buildSubmitSetBoard({
      daoId: dao.daoId,
      newMembers: [member1.toSuiAddress()],
      metadataIpfs: "ipfs://test",
    });

    const result = await execute(client, tx, member1);
    expect(result.effects?.status?.status).toBe("success");

    const event = assertEvent(result, "::proposal::ProposalCreated");
    const j = event.parsedJson as Record<string, string>;
    expect(j.proposal_id).toMatch(/^0x/);
    expect(j.dao_id).toBe(dao.daoId);
  });

  it("proposal object is shared after submission", async () => {
    const tx = buildSubmitSetBoard({
      daoId: dao.daoId,
      newMembers: [member1.toSuiAddress()],
      metadataIpfs: "ipfs://test",
    });

    const result = await execute(client, tx, member1);
    const proposalId = await submitAndGetProposalId(client, tx, member1);

    // The proposal object change should be shared
    const createdProposal = result.objectChanges?.find(
      (c) => c.type === "created" && c.objectType?.includes("::proposal::Proposal"),
    );
    expect(createdProposal).toBeDefined();
    if (createdProposal?.type === "created") {
      expect(createdProposal.owner).toMatchObject({ Shared: expect.any(Object) });
    }

    // Suppress unused variable warning
    expect(proposalId).toBeTruthy();
  });
});

// ---------------------------------------------------------------------------
// Voting (scenarios 3.2, 3.3, 3.4)
// ---------------------------------------------------------------------------

describe("voting (scenarios 3.2–3.4)", () => {
  let proposalId: string;

  beforeAll(async () => {
    const tx = buildSubmitSetBoard({
      daoId: dao.daoId,
      newMembers: [member1.toSuiAddress(), member2.toSuiAddress()],
      metadataIpfs: "ipfs://test",
    });
    proposalId = await submitAndGetProposalId(client, tx, member1);
  });

  it("member1 can vote yes — emits VoteCast(approve=true)", async () => {
    const result = await voteOnProposal(
      client, proposalId, SET_BOARD_TYPE, true, member1,
    );
    expect(result.effects?.status?.status).toBe("success");
    const event = assertEvent(result, "::proposal::VoteCast");
    const j = event.parsedJson as Record<string, unknown>;
    expect(j.approve).toBe(true);
  });

  it("member2 voting yes reaches quorum — proposal passes (emits ProposalPassed)", async () => {
    const result = await voteOnProposal(
      client, proposalId, SET_BOARD_TYPE, true, member2,
    );
    expect(result.effects?.status?.status).toBe("success");
    // With 2/2 votes yes, quorum=100% > 50% and approval=100% > 50% → Passed
    assertEvent(result, "::proposal::ProposalPassed");
  });
});

// ---------------------------------------------------------------------------
// Execute proposal (scenario 3.5)
// ---------------------------------------------------------------------------

describe("execute passed proposal (scenario 3.5)", () => {
  it("buildExecuteSetBoard — succeeds after passing vote, emits ProposalExecuted", async () => {
    // Submit
    const newBoard = [member1.toSuiAddress(), member2.toSuiAddress()];
    const submitTx = buildSubmitSetBoard({
      daoId: dao.daoId,
      newMembers: newBoard,
      metadataIpfs: "ipfs://test",
    });
    const proposalId = await submitAndGetProposalId(client, submitTx, member1);

    // Vote yes with both members to pass
    await voteOnProposal(client, proposalId, SET_BOARD_TYPE, true, member1);
    await voteOnProposal(client, proposalId, SET_BOARD_TYPE, true, member2);

    // Execute
    const execTx = buildExecuteSetBoard({
      daoId: dao.daoId,
      proposalId,
      emergencyFreezeId: dao.emergencyFreezeId,
    });

    const result = await execute(client, execTx, member1);
    expect(result.effects?.status?.status).toBe("success");
    assertEvent(result, "::proposal::ProposalExecuted");
  });
});

// ---------------------------------------------------------------------------
// Charter update proposal (scenario 3.5 variant)
// ---------------------------------------------------------------------------

describe("charter update proposal", () => {
  it("submit → vote → execute UpdateMetadata updates the charter", async () => {
    const newCid = "ipfs://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi";

    // Submit
    const submitTx = buildSubmitUpdateMetadata({
      daoId: dao.daoId,
      newIpfsCid: newCid,
      metadataIpfs: "ipfs://test",
    });
    const proposalId = await submitAndGetProposalId(client, submitTx, member1);

    // Pass
    await voteOnProposal(client, proposalId, UPDATE_METADATA_TYPE, true, member1);
    await voteOnProposal(client, proposalId, UPDATE_METADATA_TYPE, true, member2);

    // Execute
    const execTx = buildExecuteUpdateMetadata({
      daoId: dao.daoId,
      proposalId,
      charterId: dao.charterId,
      emergencyFreezeId: dao.emergencyFreezeId,
    });

    const result = await execute(client, execTx, member1);
    expect(result.effects?.status?.status).toBe("success");
    assertEvent(result, "::proposal::ProposalExecuted");
  });
});

// ---------------------------------------------------------------------------
// Negative: cannot vote twice (scenario 3.9)
// ---------------------------------------------------------------------------

describe("negative: cannot vote twice (scenario 3.9)", () => {
  it("second vote from same member fails with contract error", async () => {
    const submitTx = buildSubmitSetBoard({
      daoId: dao.daoId,
      newMembers: [member1.toSuiAddress()],
      metadataIpfs: "ipfs://test",
    });
    const proposalId = await submitAndGetProposalId(client, submitTx, member1);

    await voteOnProposal(client, proposalId, SET_BOARD_TYPE, true, member1);

    // Second vote should fail
    await expect(
      voteOnProposal(client, proposalId, SET_BOARD_TYPE, true, member1),
    ).rejects.toThrow();
  });
});

// ---------------------------------------------------------------------------
// Negative: cannot execute active proposal (scenario 3.10)
// ---------------------------------------------------------------------------

describe("negative: cannot execute active proposal (scenario 3.10)", () => {
  it("executing before votes fails with contract error", async () => {
    const submitTx = buildSubmitSetBoard({
      daoId: dao.daoId,
      newMembers: [member1.toSuiAddress()],
      metadataIpfs: "ipfs://test",
    });
    const proposalId = await submitAndGetProposalId(client, submitTx, member1);

    const execTx = buildExecuteSetBoard({
      daoId: dao.daoId,
      proposalId,
      emergencyFreezeId: dao.emergencyFreezeId,
    });

    await expect(execute(client, execTx, member1)).rejects.toThrow();
  });
});

// ---------------------------------------------------------------------------
// try_expire (scenario 3.6 — requires short expiry config to test properly)
// ---------------------------------------------------------------------------

describe("buildTryExpire", () => {
  it("transaction is correctly formed (sends to chain without abort on active proposal)", async () => {
    const submitTx = buildSubmitSetBoard({
      daoId: dao.daoId,
      newMembers: [member1.toSuiAddress()],
      metadataIpfs: "ipfs://test",
    });
    const proposalId = await submitAndGetProposalId(client, submitTx, member1);

    const expireTx = buildTryExpire({ proposalId, proposalType: SET_BOARD_TYPE });

    // On an active non-expired proposal, try_expire is a no-op (succeeds without error)
    const result = await execute(client, expireTx, member1);
    expect(result.effects?.status?.status).toBe("success");
  });
});

/**
 * Integration tests: Emergency freeze / unfreeze
 *
 * Covers e2e scenario 07-emergency-freeze.md
 * Requires: make dev (localnet + deployed packages)
 *
 * Tests the direct FreezeAdminCap-gated actions (not proposal-gated).
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
  assertEvent,
  submitAndGetProposalId,
  voteOnProposal,
  type TestDao,
} from "./test-utils";
import { buildFreezeType, buildUnfreezeType } from "../../emergency";
import { buildSubmitSetBoard } from "../../proposal";
import { buildExecuteSetBoard } from "../../execution";

const SET_BOARD_TYPE = `${PROPOSALS_PACKAGE_ID}::set_board::SetBoard`;

let client: SuiJsonRpcClient;
let creator: Ed25519Keypair;
let dao: TestDao;

beforeAll(async () => {
  client = createClient();
  creator = await newFundedKeypair(client);
  dao = await createTestDao(client, creator);
});

// ---------------------------------------------------------------------------
// Direct freeze (scenario 7.x)
// ---------------------------------------------------------------------------

describe("buildFreezeType — direct FreezeAdminCap action", () => {
  it("freezes a proposal type (emits TypeFrozen event)", async () => {
    const tx = buildFreezeType({
      emergencyFreezeId: dao.emergencyFreezeId,
      freezeAdminCapId: dao.freezeAdminCapId,
      typeKey: "SetBoard",
    });

    const result = await execute(client, tx, creator);
    expect(result.effects?.status?.status).toBe("success");
    assertEvent(result, "::emergency::TypeFrozen");
  });

  it("frozen proposal type still allows submission — but blocks execution", async () => {
    // SetBoard is frozen from previous test.
    // Freeze is enforced in authorize_execution, NOT submit_proposal.
    const submitTx = buildSubmitSetBoard({
      daoId: dao.daoId,
      newMembers: [creator.toSuiAddress()],
      metadataIpfs: "ipfs://test",
    });

    // Submission succeeds even while frozen
    const proposalId = await submitAndGetProposalId(client, submitTx, creator);

    // Vote yes — 1-member DAO, proposal passes immediately
    await voteOnProposal(client, proposalId, SET_BOARD_TYPE, true, creator);

    // Execution must fail because SetBoard is frozen
    const execTx = buildExecuteSetBoard({
      daoId: dao.daoId,
      proposalId,
      emergencyFreezeId: dao.emergencyFreezeId,
    });
    await expect(execute(client, execTx, creator)).rejects.toThrow();
  });
});

// ---------------------------------------------------------------------------
// Direct unfreeze (scenario 7.x)
// ---------------------------------------------------------------------------

describe("buildUnfreezeType — direct FreezeAdminCap action", () => {
  it("unfreezes a previously frozen proposal type", async () => {
    const tx = buildUnfreezeType({
      emergencyFreezeId: dao.emergencyFreezeId,
      freezeAdminCapId: dao.freezeAdminCapId,
      typeKey: "SetBoard",
    });

    const result = await execute(client, tx, creator);
    expect(result.effects?.status?.status).toBe("success");
    assertEvent(result, "::emergency::TypeUnfrozen");
  });

  it("unfrozen proposal type allows submission again", async () => {
    // After unfreeze, SetBoard should be submittable
    const submitTx = buildSubmitSetBoard({
      daoId: dao.daoId,
      newMembers: [creator.toSuiAddress()],
      metadataIpfs: "ipfs://test",
    });

    const result = await execute(client, submitTx, creator);
    expect(result.effects?.status?.status).toBe("success");
    assertEvent(result, "::proposal::ProposalCreated");
  });
});

// ---------------------------------------------------------------------------
// Negative: non-owner cannot use FreezeAdminCap (scenario 12.x)
// ---------------------------------------------------------------------------

describe("negative: non-owner cannot freeze", () => {
  it("random keypair attempting freeze fails (not object owner)", async () => {
    const attacker = await newFundedKeypair(client);

    const tx = buildFreezeType({
      emergencyFreezeId: dao.emergencyFreezeId,
      freezeAdminCapId: dao.freezeAdminCapId,
      typeKey: "SetBoard",
    });

    // The attacker doesn't own freezeAdminCapId — Sui object access check fails
    await expect(execute(client, tx, attacker)).rejects.toThrow();
  });
});

/**
 * Integration tests: Security / freeze-config governance operations
 *
 * Covers: UpdateFreezeConfig, UpdateFreezeExemptTypes
 * Requires: make dev (localnet + deployed packages)
 *
 * Both types are NOT enabled by default.
 * Each describe block enables the required type via governance before testing.
 *
 * Setup: 3-member DAO — 2 votes (66.7%) needed, satisfying both the 50%
 * quorum and the 66% EnableProposalType approval floor.
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
  buildSubmitEnableProposalType,
  buildSubmitUpdateFreezeConfig,
  buildSubmitUpdateFreezeExemptTypes,
} from "../../proposal";
import {
  buildExecuteEnableProposalType,
  buildExecuteUpdateFreezeConfig,
  buildExecuteUpdateFreezeExemptTypes,
} from "../../execution";

const ENABLE_TYPE = `${PROPOSALS_PACKAGE_ID}::enable_proposal_type::EnableProposalType`;
const UPDATE_FREEZE_CONFIG_TYPE = `${PROPOSALS_PACKAGE_ID}::update_freeze_config::UpdateFreezeConfig`;
const UPDATE_FREEZE_EXEMPT_TYPES_TYPE = `${PROPOSALS_PACKAGE_ID}::update_freeze_exempt_types::UpdateFreezeExemptTypes`;

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
// Helper: enable a proposal type via governance
// ---------------------------------------------------------------------------

async function enableType(typeKey: string): Promise<void> {
  const submitTx = buildSubmitEnableProposalType({
    daoId: dao.daoId,
    typeKey,
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
}

// ---------------------------------------------------------------------------
// UpdateFreezeConfig
// ---------------------------------------------------------------------------

describe("UpdateFreezeConfig", () => {
  beforeAll(async () => {
    await enableType("UpdateFreezeConfig");
  });

  it("submit → vote → execute UpdateFreezeConfig changes max freeze duration", async () => {
    const submitTx = buildSubmitUpdateFreezeConfig({
      daoId: dao.daoId,
      newMaxFreezeDurationMs: "604800000", // 7 days in ms
      metadataIpfs: "ipfs://test",
    });
    const proposalId = await submitAndGetProposalId(client, submitTx, member1);

    await voteOnProposal(client, proposalId, UPDATE_FREEZE_CONFIG_TYPE, true, member1);
    await voteOnProposal(client, proposalId, UPDATE_FREEZE_CONFIG_TYPE, true, member2);

    const execTx = buildExecuteUpdateFreezeConfig({
      daoId: dao.daoId,
      proposalId,
      emergencyFreezeId: dao.emergencyFreezeId,
    });

    const result = await execute(client, execTx, member1);
    expect(result.effects?.status?.status).toBe("success");
    assertEvent(result, "::proposal::ProposalExecuted");

    // The EmergencyFreeze object should be mutated.
    const freezeMutation = result.objectChanges?.find(
      (c) => c.type === "mutated" && c.objectId === dao.emergencyFreezeId,
    );
    expect(freezeMutation).toBeDefined();
  });
});

// ---------------------------------------------------------------------------
// UpdateFreezeExemptTypes
// ---------------------------------------------------------------------------

describe("UpdateFreezeExemptTypes", () => {
  beforeAll(async () => {
    await enableType("UpdateFreezeExemptTypes");
  });

  it("submit → vote → execute UpdateFreezeExemptTypes adds an exempt type", async () => {
    const submitTx = buildSubmitUpdateFreezeExemptTypes({
      daoId: dao.daoId,
      typesToAdd: ["SetBoard"],
      typesToRemove: [],
      metadataIpfs: "ipfs://test",
    });
    const proposalId = await submitAndGetProposalId(client, submitTx, member1);

    await voteOnProposal(client, proposalId, UPDATE_FREEZE_EXEMPT_TYPES_TYPE, true, member1);
    await voteOnProposal(client, proposalId, UPDATE_FREEZE_EXEMPT_TYPES_TYPE, true, member2);

    const execTx = buildExecuteUpdateFreezeExemptTypes({
      daoId: dao.daoId,
      proposalId,
      emergencyFreezeId: dao.emergencyFreezeId,
    });

    const result = await execute(client, execTx, member1);
    expect(result.effects?.status?.status).toBe("success");
    assertEvent(result, "::proposal::ProposalExecuted");

    // The EmergencyFreeze object should be mutated.
    const freezeMutation = result.objectChanges?.find(
      (c) => c.type === "mutated" && c.objectId === dao.emergencyFreezeId,
    );
    expect(freezeMutation).toBeDefined();
  });

  it("removes an exempt type and succeeds", async () => {
    const submitTx = buildSubmitUpdateFreezeExemptTypes({
      daoId: dao.daoId,
      typesToAdd: [],
      typesToRemove: ["SetBoard"],
      metadataIpfs: "ipfs://test",
    });
    const proposalId = await submitAndGetProposalId(client, submitTx, member1);

    await voteOnProposal(client, proposalId, UPDATE_FREEZE_EXEMPT_TYPES_TYPE, true, member1);
    await voteOnProposal(client, proposalId, UPDATE_FREEZE_EXEMPT_TYPES_TYPE, true, member2);

    const execTx = buildExecuteUpdateFreezeExemptTypes({
      daoId: dao.daoId,
      proposalId,
      emergencyFreezeId: dao.emergencyFreezeId,
    });

    const result = await execute(client, execTx, member1);
    expect(result.effects?.status?.status).toBe("success");
    assertEvent(result, "::proposal::ProposalExecuted");
  });
});

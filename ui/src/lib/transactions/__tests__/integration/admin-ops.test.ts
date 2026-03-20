/**
 * Integration tests: Admin governance operations
 *
 * Covers: DisableProposalType, UpdateProposalConfig,
 *         UnfreezeProposalType (governance path), TransferFreezeAdmin
 * Requires: make dev (localnet + deployed packages)
 *
 * Setup: 3-member DAO — 2 votes (66.7%) needed to meet 50% quorum.
 * Tests are ordered so TransferFreezeAdmin (which consumes the cap) runs last.
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
  buildSubmitDisableProposalType,
  buildSubmitUpdateProposalConfig,
  buildSubmitTransferFreezeAdmin,
  buildSubmitUnfreezeProposalType,
  buildSubmitUpdateMetadata,
} from "../../proposal";
import {
  buildExecuteDisableProposalType,
  buildExecuteUpdateProposalConfig,
  buildExecuteTransferFreezeAdmin,
  buildExecuteUnfreezeProposalType,
} from "../../execution";
import { buildFreezeType } from "../../emergency";

const DISABLE_TYPE = `${PROPOSALS_PACKAGE_ID}::disable_proposal_type::DisableProposalType`;
const UPDATE_CONFIG_TYPE = `${PROPOSALS_PACKAGE_ID}::update_proposal_config::UpdateProposalConfig`;
const TRANSFER_FREEZE_ADMIN_TYPE = `${PROPOSALS_PACKAGE_ID}::transfer_freeze_admin::TransferFreezeAdmin`;
const UNFREEZE_TYPE = `${PROPOSALS_PACKAGE_ID}::unfreeze_proposal_type::UnfreezeProposalType`;

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
  // 3-member DAO: quorum 50% → 2 of 3 votes (66.7%) needed to pass.
  dao = await createTestDao(client, member1, [member2, member3]);
});

// ---------------------------------------------------------------------------
// DisableProposalType (scenario: disable CharterUpdate)
// ---------------------------------------------------------------------------

describe("DisableProposalType", () => {
  it("submit → vote → execute disables CharterUpdate", async () => {
    const submitTx = buildSubmitDisableProposalType({
      daoId: dao.daoId,
      typeKey: "CharterUpdate",
      metadataIpfs: "ipfs://test",
    });
    const proposalId = await submitAndGetProposalId(client, submitTx, member1);

    await voteOnProposal(client, proposalId, DISABLE_TYPE, true, member1);
    await voteOnProposal(client, proposalId, DISABLE_TYPE, true, member2);

    const execTx = buildExecuteDisableProposalType({
      daoId: dao.daoId,
      proposalId,
      emergencyFreezeId: dao.emergencyFreezeId,
    });

    const result = await execute(client, execTx, member1);
    expect(result.effects?.status?.status).toBe("success");
    assertEvent(result, "::proposal::ProposalExecuted");
  });

  it("disabled CharterUpdate type blocks new UpdateMetadata proposals", async () => {
    // CharterUpdate (UpdateMetadata) is now disabled — submitting should abort.
    const submitTx = buildSubmitUpdateMetadata({
      daoId: dao.daoId,
      newIpfsCid: "ipfs://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi",
      metadataIpfs: "ipfs://test",
    });
    await expect(execute(client, submitTx, member1)).rejects.toThrow();
  });
});

// ---------------------------------------------------------------------------
// UpdateProposalConfig (update SetBoard's expiry window)
// ---------------------------------------------------------------------------

describe("UpdateProposalConfig", () => {
  it("submit → vote → execute updates SetBoard expiry to 48 h", async () => {
    const submitTx = buildSubmitUpdateProposalConfig({
      daoId: dao.daoId,
      targetTypeKey: "SetBoard",
      expiryMs: "172800000", // 48 h in ms
      metadataIpfs: "ipfs://test",
    });
    const proposalId = await submitAndGetProposalId(client, submitTx, member1);

    await voteOnProposal(client, proposalId, UPDATE_CONFIG_TYPE, true, member1);
    await voteOnProposal(client, proposalId, UPDATE_CONFIG_TYPE, true, member2);

    const execTx = buildExecuteUpdateProposalConfig({
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
// UnfreezeProposalType via governance (governance-gated unfreeze)
// ---------------------------------------------------------------------------

describe("UnfreezeProposalType via governance", () => {
  // Freeze SetBoard via the direct admin cap, then unfreeze it via a governance proposal.
  beforeAll(async () => {
    const freezeTx = buildFreezeType({
      emergencyFreezeId: dao.emergencyFreezeId,
      freezeAdminCapId: dao.freezeAdminCapId,
      typeKey: "SetBoard",
    });
    await execute(client, freezeTx, member1);
  });

  it("submit → vote → execute UnfreezeProposalType unfreezes SetBoard", async () => {
    const submitTx = buildSubmitUnfreezeProposalType({
      daoId: dao.daoId,
      typeKey: "SetBoard",
      metadataIpfs: "ipfs://test",
    });
    const proposalId = await submitAndGetProposalId(client, submitTx, member1);

    await voteOnProposal(client, proposalId, UNFREEZE_TYPE, true, member1);
    await voteOnProposal(client, proposalId, UNFREEZE_TYPE, true, member2);

    const execTx = buildExecuteUnfreezeProposalType({
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
// TransferFreezeAdmin — placed last because it consumes the FreezeAdminCap
// ---------------------------------------------------------------------------

describe("TransferFreezeAdmin", () => {
  it("submit → vote → execute transfers FreezeAdminCap to member2", async () => {
    const submitTx = buildSubmitTransferFreezeAdmin({
      daoId: dao.daoId,
      newAdmin: member2.toSuiAddress(),
      metadataIpfs: "ipfs://test",
    });
    const proposalId = await submitAndGetProposalId(client, submitTx, member1);

    await voteOnProposal(client, proposalId, TRANSFER_FREEZE_ADMIN_TYPE, true, member1);
    await voteOnProposal(client, proposalId, TRANSFER_FREEZE_ADMIN_TYPE, true, member2);

    const execTx = buildExecuteTransferFreezeAdmin({
      daoId: dao.daoId,
      proposalId,
      emergencyFreezeId: dao.emergencyFreezeId,
      freezeAdminCapId: dao.freezeAdminCapId,
    });

    const result = await execute(client, execTx, member1);
    expect(result.effects?.status?.status).toBe("success");
    assertEvent(result, "::proposal::ProposalExecuted");

    // Verify the FreezeAdminCap moved to member2
    const capTransfer = result.objectChanges?.find(
      (c) =>
        c.type === "mutated" &&
        c.objectType?.includes("::emergency::FreezeAdminCap") &&
        c.owner &&
        "AddressOwner" in c.owner &&
        c.owner.AddressOwner === member2.toSuiAddress(),
    );
    expect(capTransfer).toBeDefined();
  });
});

/**
 * Integration tests: SubDAO lifecycle operations
 *
 * Covers: CreateSubDAO, TransferCapToSubDAO, ReclaimCapFromSubDAO,
 *         PauseSubDAOExecution, UnpauseSubDAOExecution, SpinOutSubDAO, SpawnDAO
 * Requires: make dev (localnet + deployed packages)
 *
 * Setup: 3-member DAO — 2 votes (66.7%) satisfies both 50% quorum and
 * the 66% EnableProposalType approval floor.
 *
 * Test order is significant:
 *   1. CreateSubDAO       — creates subdaoInfo used by subsequent tests
 *   2. TransferCapToSubDAO — moves SubDAO FreezeAdminCap to SubDAO vault
 *   3. ReclaimCapFromSubDAO — returns it to parent vault
 *   4. PauseSubDAOExecution — pauses the SubDAO
 *   5. UnpauseSubDAOExecution — unpauses it
 *   6. SpinOutSubDAO       — destroys SubDAOControl (SubDAO becomes independent)
 *   7. SpawnDAO            — marks parent DAO as Migrating (must be last)
 */

import { describe, it, expect, beforeAll } from "vitest";
import { SuiJsonRpcClient } from "@mysten/sui/jsonRpc";
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";
import {
  PACKAGE_ID,
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
import {
  buildSubmitTransferCapToSubDAO,
  buildSubmitReclaimCapFromSubDAO,
  buildSubmitPauseSubDAOExecution,
  buildSubmitUnpauseSubDAOExecution,
  buildSubmitSpinOutSubDAO,
  buildSubmitSpawnDAO,
} from "../../proposal";
import {
  buildExecuteTransferCapToSubDAO,
  buildExecuteReclaimCap,
  buildExecutePauseSubDAOExecution,
  buildExecuteUnpauseSubDAOExecution,
  buildExecuteSpinOutSubDAO,
  buildExecuteSpawnDAO,
} from "../../execution";

const FREEZE_ADMIN_CAP_TYPE = `${PACKAGE_ID}::emergency::FreezeAdminCap`;

const TRANSFER_CAP_TYPE = `${PROPOSALS_PACKAGE_ID}::transfer_cap_to_subdao::TransferCapToSubDAO`;
const RECLAIM_CAP_TYPE = `${PROPOSALS_PACKAGE_ID}::reclaim_cap_from_subdao::ReclaimCapFromSubDAO`;
const PAUSE_TYPE = `${PROPOSALS_PACKAGE_ID}::pause_execution::PauseSubDAOExecution`;
const UNPAUSE_TYPE = `${PROPOSALS_PACKAGE_ID}::pause_execution::UnpauseSubDAOExecution`;
const SPIN_OUT_TYPE = `${PROPOSALS_PACKAGE_ID}::spin_out_subdao::SpinOutSubDAO`;
const SPAWN_DAO_TYPE = `${PROPOSALS_PACKAGE_ID}::spawn_dao::SpawnDAO`;

let client: SuiJsonRpcClient;
let member1: Ed25519Keypair;
let member2: Ed25519Keypair;
let member3: Ed25519Keypair;
let dao: TestDao;
// Populated by the CreateSubDAO describe block; used by all subsequent describes.
let subdaoInfo: SubDAOInfo;

beforeAll(async () => {
  client = createClient();
  [member1, member2, member3] = await Promise.all([
    newFundedKeypair(client),
    newFundedKeypair(client),
    newFundedKeypair(client),
  ]);
  dao = await createTestDao(client, member1, [member2, member3]);
});

// ---------------------------------------------------------------------------
// CreateSubDAO
// ---------------------------------------------------------------------------

describe("CreateSubDAO", () => {
  it("submit → vote → execute creates a child DAO with SubDAOControl in parent vault", async () => {
    subdaoInfo = await createSubDAO(client, dao, member1, member2, {
      name: "SubDAO Alpha",
      description: "Integration test SubDAO",
    });

    expect(subdaoInfo.subdaoId).toBeTruthy();
    expect(subdaoInfo.controlCapId).toBeTruthy();
    expect(subdaoInfo.subdaoFreezeAdminCapId).toBeTruthy();
    expect(subdaoInfo.subdaoVaultId).toBeTruthy();
    expect(subdaoInfo.subdaoTreasuryId).toBeTruthy();
    expect(subdaoInfo.subdaoEmergencyFreezeId).toBeTruthy();
  });
});

// ---------------------------------------------------------------------------
// TransferCapToSubDAO — move the SubDAO's FreezeAdminCap into SubDAO's vault
// ---------------------------------------------------------------------------

describe("TransferCapToSubDAO", () => {
  beforeAll(async () => {
    await enableProposalType(client, dao, member1, member2, "TransferCapToSubDAO");
  });

  it("submit → vote → execute transfers FreezeAdminCap from parent vault to SubDAO vault", async () => {
    const submitTx = buildSubmitTransferCapToSubDAO({
      daoId: dao.daoId,
      capId: subdaoInfo.subdaoFreezeAdminCapId,
      targetSubdao: subdaoInfo.subdaoId,
      metadataIpfs: "ipfs://test",
    });
    const proposalId = await submitAndGetProposalId(client, submitTx, member1);
    await voteOnProposal(client, proposalId, TRANSFER_CAP_TYPE, true, member1);
    await voteOnProposal(client, proposalId, TRANSFER_CAP_TYPE, true, member2);

    const result = await execute(
      client,
      buildExecuteTransferCapToSubDAO({
        daoId: dao.daoId,
        proposalId,
        sourceVaultId: dao.capabilityVaultId,
        targetVaultId: subdaoInfo.subdaoVaultId,
        emergencyFreezeId: dao.emergencyFreezeId,
        capType: FREEZE_ADMIN_CAP_TYPE,
      }),
      member1,
    );

    expect(result.effects?.status?.status).toBe("success");
    assertEvent(result, "::subdao_ops::CapTransferredToSubDAO");
  });
});

// ---------------------------------------------------------------------------
// ReclaimCapFromSubDAO — reclaim the FreezeAdminCap back to parent vault
// ---------------------------------------------------------------------------

describe("ReclaimCapFromSubDAO", () => {
  beforeAll(async () => {
    await enableProposalType(client, dao, member1, member2, "ReclaimCapFromSubDAO");
  });

  it("submit → vote → execute reclaims FreezeAdminCap from SubDAO vault to parent vault", async () => {
    const submitTx = buildSubmitReclaimCapFromSubDAO({
      daoId: dao.daoId,
      subdaoId: subdaoInfo.subdaoId,
      capId: subdaoInfo.subdaoFreezeAdminCapId,
      controlId: subdaoInfo.controlCapId,
      metadataIpfs: "ipfs://test",
    });
    const proposalId = await submitAndGetProposalId(client, submitTx, member1);
    await voteOnProposal(client, proposalId, RECLAIM_CAP_TYPE, true, member1);
    await voteOnProposal(client, proposalId, RECLAIM_CAP_TYPE, true, member2);

    const result = await execute(
      client,
      buildExecuteReclaimCap({
        daoId: dao.daoId,
        proposalId,
        controllerVaultId: dao.capabilityVaultId,
        subdaoVaultId: subdaoInfo.subdaoVaultId,
        emergencyFreezeId: dao.emergencyFreezeId,
        capType: FREEZE_ADMIN_CAP_TYPE,
      }),
      member1,
    );

    expect(result.effects?.status?.status).toBe("success");
    assertEvent(result, "::subdao_ops::CapReclaimedFromSubDAO");
  });
});

// ---------------------------------------------------------------------------
// PauseSubDAOExecution
// ---------------------------------------------------------------------------

describe("PauseSubDAOExecution", () => {
  beforeAll(async () => {
    await enableProposalType(client, dao, member1, member2, "PauseSubDAOExecution");
  });

  it("submit → vote → execute pauses the SubDAO's execution", async () => {
    const submitTx = buildSubmitPauseSubDAOExecution({
      daoId: dao.daoId,
      controlId: subdaoInfo.controlCapId,
      metadataIpfs: "ipfs://test",
    });
    const proposalId = await submitAndGetProposalId(client, submitTx, member1);
    await voteOnProposal(client, proposalId, PAUSE_TYPE, true, member1);
    await voteOnProposal(client, proposalId, PAUSE_TYPE, true, member2);

    const result = await execute(
      client,
      buildExecutePauseSubDAOExecution({
        daoId: dao.daoId,
        proposalId,
        controllerVaultId: dao.capabilityVaultId,
        subdaoId: subdaoInfo.subdaoId,
        emergencyFreezeId: dao.emergencyFreezeId,
      }),
      member1,
    );

    expect(result.effects?.status?.status).toBe("success");
    assertEvent(result, "::subdao_ops::SubDAOExecutionPaused");
  });
});

// ---------------------------------------------------------------------------
// UnpauseSubDAOExecution
// ---------------------------------------------------------------------------

describe("UnpauseSubDAOExecution", () => {
  beforeAll(async () => {
    await enableProposalType(client, dao, member1, member2, "UnpauseSubDAOExecution");
  });

  it("submit → vote → execute unpauses the SubDAO's execution", async () => {
    const submitTx = buildSubmitUnpauseSubDAOExecution({
      daoId: dao.daoId,
      controlId: subdaoInfo.controlCapId,
      metadataIpfs: "ipfs://test",
    });
    const proposalId = await submitAndGetProposalId(client, submitTx, member1);
    await voteOnProposal(client, proposalId, UNPAUSE_TYPE, true, member1);
    await voteOnProposal(client, proposalId, UNPAUSE_TYPE, true, member2);

    const result = await execute(
      client,
      buildExecuteUnpauseSubDAOExecution({
        daoId: dao.daoId,
        proposalId,
        controllerVaultId: dao.capabilityVaultId,
        subdaoId: subdaoInfo.subdaoId,
        emergencyFreezeId: dao.emergencyFreezeId,
      }),
      member1,
    );

    expect(result.effects?.status?.status).toBe("success");
    assertEvent(result, "::subdao_ops::SubDAOExecutionUnpaused");
  });
});

// ---------------------------------------------------------------------------
// SpinOutSubDAO — grant the SubDAO full independence (destroys SubDAOControl)
// ---------------------------------------------------------------------------

describe("SpinOutSubDAO", () => {
  beforeAll(async () => {
    await enableProposalType(client, dao, member1, member2, "SpinOutSubDAO");
  });

  it("submit → vote → execute spins out the SubDAO, destroying SubDAOControl", async () => {
    const submitTx = buildSubmitSpinOutSubDAO({
      daoId: dao.daoId,
      subDaoId: subdaoInfo.subdaoId,
      controlCapId: subdaoInfo.controlCapId,
      freezeAdminCapId: subdaoInfo.subdaoFreezeAdminCapId,
      metadataIpfs: "ipfs://test",
    });
    const proposalId = await submitAndGetProposalId(client, submitTx, member1);
    await voteOnProposal(client, proposalId, SPIN_OUT_TYPE, true, member1);
    await voteOnProposal(client, proposalId, SPIN_OUT_TYPE, true, member2);

    const result = await execute(
      client,
      buildExecuteSpinOutSubDAO({
        daoId: dao.daoId,
        proposalId,
        capabilityVaultId: dao.capabilityVaultId,
        subdaoVaultId: subdaoInfo.subdaoVaultId,
        subdaoId: subdaoInfo.subdaoId,
        emergencyFreezeId: dao.emergencyFreezeId,
      }),
      member1,
    );

    expect(result.effects?.status?.status).toBe("success");
    assertEvent(result, "::subdao_ops::SubDAOSpunOut");
  });
});

// ---------------------------------------------------------------------------
// SpawnDAO — create a successor DAO, marking origin as Migrating (must be last)
// ---------------------------------------------------------------------------

describe("SpawnDAO", () => {
  beforeAll(async () => {
    await enableProposalType(client, dao, member1, member2, "SpawnDAO");
  });

  it("submit → vote → execute creates a successor DAO and marks origin as Migrating", async () => {
    const submitTx = buildSubmitSpawnDAO({
      daoId: dao.daoId,
      name: "Successor DAO",
      description: "Spawned by integration test",
      metadataIpfs: "ipfs://test",
    });
    const proposalId = await submitAndGetProposalId(client, submitTx, member1);
    await voteOnProposal(client, proposalId, SPAWN_DAO_TYPE, true, member1);
    await voteOnProposal(client, proposalId, SPAWN_DAO_TYPE, true, member2);

    const result = await execute(
      client,
      buildExecuteSpawnDAO({
        daoId: dao.daoId,
        proposalId,
        emergencyFreezeId: dao.emergencyFreezeId,
      }),
      member1,
    );

    expect(result.effects?.status?.status).toBe("success");
    assertEvent(result, "::subdao_ops::SuccessorDAOSpawned");
  });
});

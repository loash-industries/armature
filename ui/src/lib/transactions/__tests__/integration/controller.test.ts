/**
 * Integration tests: Privileged controller operations (buildPrivilegedOp)
 *
 * Covers: buildPrivilegedOp — parent DAO bypass of SubDAO governance
 * Requires: make dev (localnet + deployed packages)
 *
 * Setup: 3-member parent DAO creates a SubDAO. The parent then uses
 * buildPrivilegedOp to submit a proposal directly to the SubDAO, bypassing
 * the SubDAO's board voting. The SubDAOControl (stored as a dynamic object
 * field in the parent's capability vault) authorizes the bypass.
 */

import { describe, it, expect, beforeAll } from "vitest";
import { SuiJsonRpcClient } from "@mysten/sui/jsonRpc";
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";
import { Transaction } from "@mysten/sui/transactions";
import {
  PROPOSALS_PACKAGE_ID,
  createClient,
  newFundedKeypair,
  createTestDao,
  execute,
  createSubDAO,
  assertEvent,
  type TestDao,
  type SubDAOInfo,
} from "./test-utils";
import { buildPrivilegedOp } from "../../controller";

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
});

// ---------------------------------------------------------------------------
// buildPrivilegedOp
// ---------------------------------------------------------------------------

describe("buildPrivilegedOp", () => {
  it("creates a privileged proposal on the SubDAO, bypassing board voting", async () => {
    // Use PauseSubDAOExecution as the payload type — privileged_submit does NOT
    // check the type registry, so any `store` payload works without prior
    // EnableProposalType governance on the SubDAO.
    const PAUSE_PROPOSAL_TYPE = `${PROPOSALS_PACKAGE_ID}::pause_execution::PauseSubDAOExecution`;

    const tx = new Transaction();

    // Build the payload in the same PTB.
    const payload = tx.moveCall({
      target: `${PROPOSALS_PACKAGE_ID}::pause_execution::new_pause`,
      arguments: [tx.pure.id(subdaoInfo.controlCapId)],
    });

    // Submit + consume in one privileged PTB.
    // SubDAOControl is stored as a dynamic object field in the parent vault
    // and is addressable by its object ID.
    buildPrivilegedOp(tx, {
      controlId: subdaoInfo.controlCapId,
      subdaoId: subdaoInfo.subdaoId,
      typeKey: "PauseSubDAOExecution",
      metadataIpfs: "ipfs://privileged-test",
      payload,
      proposalType: PAUSE_PROPOSAL_TYPE,
    });

    const result = await execute(client, tx, member1);
    expect(result.effects?.status?.status).toBe("success");
    // A Proposal in Executed status is shared on the SubDAO for audit.
    assertEvent(result, "::proposal::ProposalCreated");
  });
});

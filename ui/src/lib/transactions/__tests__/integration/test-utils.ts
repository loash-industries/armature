/**
 * Shared helpers for integration tests.
 *
 * Requires a running localnet (`make dev`). All helpers are async and use
 * the JSON-RPC fullnode at VITE_RPC_URL (default: http://localhost:9000)
 * and faucet at VITE_FAUCET_URL (default: http://localhost:9123).
 */

import { SuiJsonRpcClient } from "@mysten/sui/jsonRpc";
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";
import { requestSuiFromFaucetV2 } from "@mysten/sui/faucet";
import type { SuiTransactionBlockResponse, SuiEvent } from "@mysten/sui/jsonRpc";
import { Transaction } from "@mysten/sui/transactions";

// ---------------------------------------------------------------------------
// Environment
// ---------------------------------------------------------------------------

export const RPC_URL =
  process.env.VITE_RPC_URL ?? "http://localhost:9000";

export const FAUCET_URL =
  process.env.VITE_FAUCET_URL ?? "http://localhost:9123";

export const PACKAGE_ID: string =
  process.env.VITE_PACKAGE_ID ??
  (() => { throw new Error("VITE_PACKAGE_ID is not set — run `make dev` first"); })();

export const PROPOSALS_PACKAGE_ID: string =
  process.env.VITE_PROPOSALS_PACKAGE_ID ??
  (() => { throw new Error("VITE_PROPOSALS_PACKAGE_ID is not set — run `make dev` first"); })();

// ---------------------------------------------------------------------------
// Client factory
// ---------------------------------------------------------------------------

export function createClient(): SuiJsonRpcClient {
  return new SuiJsonRpcClient({ url: RPC_URL, network: { name: "localnet" } as never });
}

// ---------------------------------------------------------------------------
// Keypair + funding helpers
// ---------------------------------------------------------------------------

/** Generate a fresh Ed25519 keypair, fund it from the faucet, and return it. */
export async function newFundedKeypair(client: SuiJsonRpcClient): Promise<Ed25519Keypair> {
  const keypair = Ed25519Keypair.generate();
  const address = keypair.toSuiAddress();

  await requestSuiFromFaucetV2({ host: FAUCET_URL, recipient: address });

  // Wait until the account has a coin object (faucet is async).
  await waitFor(async () => {
    const coins = await client.getCoins({ owner: address, coinType: "0x2::sui::SUI" });
    return coins.data.length > 0;
  }, { timeoutMs: 20_000, intervalMs: 500, label: `fund ${address.slice(0, 10)}` });

  return keypair;
}

// ---------------------------------------------------------------------------
// Transaction execution helper
// ---------------------------------------------------------------------------

/**
 * Sign and execute a transaction, waiting for effects to be committed.
 * Throws if the transaction fails.
 */
export async function execute(
  client: SuiJsonRpcClient,
  tx: Transaction,
  signer: Ed25519Keypair,
): Promise<SuiTransactionBlockResponse> {
  tx.setSenderIfNotSet(signer.toSuiAddress());
  const result = await client.signAndExecuteTransaction({
    transaction: tx,
    signer,
    options: {
      showEffects: true,
      showEvents: true,
      showObjectChanges: true,
    },
  });

  if (result.effects?.status?.status !== "success") {
    const error = result.effects?.status?.error ?? "unknown error";
    throw new Error(`Transaction failed: ${error}`);
  }

  // Wait for the fullnode to fully index the transaction before returning.
  // Without this, the next tx that references objects created here will fail
  // with "Object does not exist" because the node hasn't indexed them yet.
  await client.waitForTransaction({
    digest: result.digest,
    timeout: 30_000,
    pollInterval: 300,
  });

  return result;
}

// ---------------------------------------------------------------------------
// DAO creation helper
// ---------------------------------------------------------------------------

export interface TestDao {
  daoId: string;
  treasuryId: string;
  capabilityVaultId: string;
  charterId: string;
  emergencyFreezeId: string;
  /** The ID of the FreezeAdminCap object owned by the creator. */
  freezeAdminCapId: string;
}

/**
 * Create a DAO on-chain and return all companion object IDs extracted from
 * the DAOCreated event. The creator keypair receives the FreezeAdminCap.
 */
export async function createTestDao(
  client: SuiJsonRpcClient,
  creator: Ed25519Keypair,
  extraMembers: Ed25519Keypair[] = [],
): Promise<TestDao> {
  const { buildCreateDao } = await import("../../dao");

  const members = [
    creator.toSuiAddress(),
    ...extraMembers.map((k) => k.toSuiAddress()),
  ];

  const tx = buildCreateDao({
    name: "Integration Test DAO",
    description: "Created by integration test",
    imageUrl: "",
    initialMembers: members,
  });

  const result = await execute(client, tx, creator);
  return extractDaoCreatedFields(result, creator.toSuiAddress());
}

// ---------------------------------------------------------------------------
// Event / object extraction helpers
// ---------------------------------------------------------------------------

/** Extract TestDao fields from a DAOCreated event in the tx result. */
export function extractDaoCreatedFields(
  result: SuiTransactionBlockResponse,
  creatorAddress: string,
): TestDao {
  const event = result.events?.find((e: SuiEvent) =>
    e.type.includes("::dao::DAOCreated")
  );
  if (!event?.parsedJson) {
    throw new Error("DAOCreated event not found in tx result");
  }

  const j = event.parsedJson as Record<string, string>;

  // Find the FreezeAdminCap transferred to the creator.
  const freezeAdminCapChange = result.objectChanges?.find(
    (c) =>
      c.type === "created" &&
      c.objectType?.includes("::emergency::FreezeAdminCap") &&
      c.owner &&
      typeof c.owner === "object" && "AddressOwner" in c.owner &&
      (c.owner as { AddressOwner: string }).AddressOwner === creatorAddress,
  );

  if (!freezeAdminCapChange || freezeAdminCapChange.type !== "created") {
    throw new Error("FreezeAdminCap not found in object changes");
  }

  return {
    daoId: j.dao_id,
    treasuryId: j.treasury_id,
    capabilityVaultId: j.capability_vault_id,
    charterId: j.charter_id,
    emergencyFreezeId: j.emergency_freeze_id,
    freezeAdminCapId: freezeAdminCapChange.objectId,
  };
}

/**
 * Extract a proposal ID from a ProposalCreated event.
 */
export function extractProposalId(result: SuiTransactionBlockResponse): string {
  const event = result.events?.find((e: SuiEvent) =>
    e.type.includes("::proposal::ProposalCreated")
  );
  if (!event?.parsedJson) {
    throw new Error("ProposalCreated event not found in tx result");
  }
  const j = event.parsedJson as Record<string, string>;
  return j.proposal_id;
}

/**
 * Assert that a transaction result contains a specific event type.
 */
export function assertEvent(
  result: SuiTransactionBlockResponse,
  typeFragment: string,
): SuiEvent {
  const event = result.events?.find((e: SuiEvent) => e.type.includes(typeFragment));
  if (!event) {
    const types = (result.events ?? []).map((e: SuiEvent) => e.type).join(", ");
    throw new Error(
      `Expected event containing "${typeFragment}" but got: [${types}]`,
    );
  }
  return event;
}

// ---------------------------------------------------------------------------
// Polling helper
// ---------------------------------------------------------------------------

interface WaitForOptions {
  timeoutMs?: number;
  intervalMs?: number;
  label?: string;
}

/** Poll `fn` until it returns a truthy value or the timeout expires. */
export async function waitFor(
  fn: () => Promise<boolean>,
  { timeoutMs = 15_000, intervalMs = 400, label = "condition" }: WaitForOptions = {},
): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (await fn()) return;
    await sleep(intervalMs);
  }
  throw new Error(`Timed out waiting for: ${label}`);
}

export const sleep = (ms: number) =>
  new Promise<void>((resolve) => setTimeout(resolve, ms));

// ---------------------------------------------------------------------------
// Proposal lifecycle helpers
// ---------------------------------------------------------------------------

/**
 * Submit a proposal and return its proposal ID.
 */
export async function submitAndGetProposalId(
  client: SuiJsonRpcClient,
  tx: Transaction,
  signer: Ed25519Keypair,
): Promise<string> {
  const result = await execute(client, tx, signer);
  return extractProposalId(result);
}

/**
 * Vote on a proposal and wait for the tx to succeed.
 */
export async function voteOnProposal(
  client: SuiJsonRpcClient,
  proposalId: string,
  proposalType: string,
  approve: boolean,
  voter: Ed25519Keypair,
): Promise<SuiTransactionBlockResponse> {
  const { buildVote } = await import("../../proposal");
  const tx = buildVote({ proposalId, approve, proposalType });
  return execute(client, tx, voter);
}

// ---------------------------------------------------------------------------
// Reusable governance setup helpers
// ---------------------------------------------------------------------------

const ENABLE_TYPE_STRING = (proposalsPackageId: string) =>
  `${proposalsPackageId}::enable_proposal_type::EnableProposalType`;

/**
 * Enable a proposal type on a DAO via a full governance vote.
 * Requires 2 of 3 members (66.7%) to satisfy the EnableProposalType
 * approval floor and the default 50% quorum.
 */
export async function enableProposalType(
  client: SuiJsonRpcClient,
  dao: TestDao,
  member1: Ed25519Keypair,
  member2: Ed25519Keypair,
  typeKey: string,
): Promise<void> {
  const { buildSubmitEnableProposalType } = await import("../../proposal");
  const { buildExecuteEnableProposalType } = await import("../../execution");

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
  const enableType = ENABLE_TYPE_STRING(PROPOSALS_PACKAGE_ID);
  await voteOnProposal(client, proposalId, enableType, true, member1);
  await voteOnProposal(client, proposalId, enableType, true, member2);
  await execute(
    client,
    buildExecuteEnableProposalType({
      daoId: dao.daoId,
      proposalId,
      emergencyFreezeId: dao.emergencyFreezeId,
    }),
    member1,
  );
}

// ---------------------------------------------------------------------------
// SubDAO creation helper
// ---------------------------------------------------------------------------

export interface SubDAOInfo {
  subdaoId: string;
  /** Object ID of the SubDAOControl stored as a dof in the parent capability vault. */
  controlCapId: string;
  /** Object ID of the SubDAO's FreezeAdminCap stored in the parent capability vault. */
  subdaoFreezeAdminCapId: string;
  subdaoVaultId: string;
  subdaoTreasuryId: string;
  subdaoEmergencyFreezeId: string;
}

/**
 * Extract SubDAOInfo from a CreateSubDAO execution result.
 * Reads SubDAOCreated + DAOCreated events and objectChanges.
 */
export function extractSubDAOCreatedFields(
  result: SuiTransactionBlockResponse,
  parentVaultId: string,
): SubDAOInfo {
  // SubDAOCreated gives us subdaoId + controlCapId
  const subdaoCreatedEvent = result.events?.find((e: SuiEvent) =>
    e.type.includes("::subdao_ops::SubDAOCreated"),
  );
  if (!subdaoCreatedEvent?.parsedJson) {
    throw new Error("SubDAOCreated event not found");
  }
  const sc = subdaoCreatedEvent.parsedJson as Record<string, string>;

  // DAOCreated for the child DAO gives us vault, treasury, emergency freeze IDs
  const daoCreatedEvent = result.events?.find((e: SuiEvent) =>
    e.type.includes("::dao::DAOCreated"),
  );
  if (!daoCreatedEvent?.parsedJson) {
    throw new Error("DAOCreated event not found in CreateSubDAO result");
  }
  const dc = daoCreatedEvent.parsedJson as Record<string, string>;

  // FreezeAdminCap stored in parent vault (ObjectOwner = parentVaultId)
  const freezeCapChange = result.objectChanges?.find(
    (c) =>
      c.type === "created" &&
      c.objectType?.includes("::emergency::FreezeAdminCap") &&
      c.owner &&
      typeof c.owner === "object" &&
      "ObjectOwner" in c.owner &&
      (c.owner as { ObjectOwner: string }).ObjectOwner === parentVaultId,
  );
  if (!freezeCapChange || freezeCapChange.type !== "created") {
    throw new Error("SubDAO FreezeAdminCap not found in parent vault objectChanges");
  }

  return {
    subdaoId: sc.subdao_id,
    controlCapId: sc.control_cap_id,
    subdaoFreezeAdminCapId: freezeCapChange.objectId,
    subdaoVaultId: dc.capability_vault_id,
    subdaoTreasuryId: dc.treasury_id,
    subdaoEmergencyFreezeId: dc.emergency_freeze_id,
  };
}

/**
 * Create a SubDAO under parentDao via the CreateSubDAO governance flow.
 * Enables CreateSubDAO if not already enabled, submits + votes + executes.
 */
export async function createSubDAO(
  client: SuiJsonRpcClient,
  parentDao: TestDao,
  member1: Ed25519Keypair,
  member2: Ed25519Keypair,
  opts: { name?: string; description?: string } = {},
): Promise<SubDAOInfo> {
  const { buildSubmitCreateSubDAO } = await import("../../proposal");
  const { buildExecuteCreateSubDAO } = await import("../../execution");

  await enableProposalType(client, parentDao, member1, member2, "CreateSubDAO");

  const CREATE_SUBDAO_TYPE = `${PROPOSALS_PACKAGE_ID}::create_subdao::CreateSubDAO`;

  const submitTx = buildSubmitCreateSubDAO({
    daoId: parentDao.daoId,
    name: opts.name ?? "Test SubDAO",
    description: opts.description ?? "Created by integration test",
    initialMembers: [member1.toSuiAddress(), member2.toSuiAddress()],
    metadataIpfs: "ipfs://test",
  });

  const proposalId = await submitAndGetProposalId(client, submitTx, member1);
  await voteOnProposal(client, proposalId, CREATE_SUBDAO_TYPE, true, member1);
  await voteOnProposal(client, proposalId, CREATE_SUBDAO_TYPE, true, member2);

  const result = await execute(
    client,
    buildExecuteCreateSubDAO({
      daoId: parentDao.daoId,
      proposalId,
      capabilityVaultId: parentDao.capabilityVaultId,
      emergencyFreezeId: parentDao.emergencyFreezeId,
    }),
    member1,
  );

  return extractSubDAOCreatedFields(result, parentDao.capabilityVaultId);
}

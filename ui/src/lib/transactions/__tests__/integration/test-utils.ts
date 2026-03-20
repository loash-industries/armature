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
      "AddressOwner" in c.owner &&
      c.owner.AddressOwner === creatorAddress,
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

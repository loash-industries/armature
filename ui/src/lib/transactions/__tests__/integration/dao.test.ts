/**
 * Integration tests: DAO lifecycle
 *
 * Covers e2e scenario 01-dao-creation.md
 * Requires: make dev (localnet + deployed packages)
 */

import { describe, it, expect, beforeAll } from "vitest";
import { SuiJsonRpcClient } from "@mysten/sui/jsonRpc";
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";
import {
  PACKAGE_ID,
  createClient,
  newFundedKeypair,
  createTestDao,
  execute,
  assertEvent,
} from "./test-utils";
import { buildCreateDao } from "../../dao";

let client: SuiJsonRpcClient;
let creator: Ed25519Keypair;
let member2: Ed25519Keypair;

beforeAll(async () => {
  client = createClient();
  [creator, member2] = await Promise.all([
    newFundedKeypair(client),
    newFundedKeypair(client),
  ]);
});

describe("buildCreateDao — happy path (scenario 1.1)", () => {
  it("transaction succeeds", async () => {
    const tx = buildCreateDao({
      name: "Test DAO Alpha",
      description: "Integration test DAO",
      imageUrl: "",
      initialMembers: [creator.toSuiAddress(), member2.toSuiAddress()],
    });

    const result = await execute(client, tx, creator);
    expect(result.effects?.status?.status).toBe("success");
  });

  it("emits DAOCreated event with all companion IDs", async () => {
    const tx = buildCreateDao({
      name: "Test DAO Beta",
      description: "Integration test DAO",
      imageUrl: "",
      initialMembers: [creator.toSuiAddress()],
    });

    const result = await execute(client, tx, creator);
    const event = assertEvent(result, "::dao::DAOCreated");

    const j = event.parsedJson as Record<string, string>;
    expect(j.dao_id).toMatch(/^0x/);
    expect(j.treasury_id).toMatch(/^0x/);
    expect(j.capability_vault_id).toMatch(/^0x/);
    expect(j.charter_id).toMatch(/^0x/);
    expect(j.emergency_freeze_id).toMatch(/^0x/);
  });

  it("creates companion objects: DAO, TreasuryVault, CapabilityVault, Charter, EmergencyFreeze", async () => {
    const dao = await createTestDao(client, creator, [member2]);

    // Each companion ID should be a non-zero Sui object ID
    for (const id of [
      dao.daoId,
      dao.treasuryId,
      dao.capabilityVaultId,
      dao.charterId,
      dao.emergencyFreezeId,
    ]) {
      expect(id).toMatch(/^0x[a-fA-F0-9]{64}$/);
    }
  });

  it("transfers FreezeAdminCap to the creator", async () => {
    const dao = await createTestDao(client, creator);

    // FreezeAdminCap should be owned by creator
    const obj = await client.getObject({
      id: dao.freezeAdminCapId,
      options: { showOwner: true },
    });

    expect(obj.data?.owner).toMatchObject({
      AddressOwner: creator.toSuiAddress(),
    });
  });

  it("DAO object is shared (accessible by all)", async () => {
    const dao = await createTestDao(client, creator);

    const obj = await client.getObject({
      id: dao.daoId,
      options: { showOwner: true, showType: true },
    });

    expect(obj.data?.owner).toMatchObject({ Shared: expect.any(Object) });
    expect(obj.data?.type).toContain(`${PACKAGE_ID}::dao::DAO`);
  });
});

describe("buildCreateDao — single-member board (scenario 1.2)", () => {
  it("single-member DAO is valid", async () => {
    const tx = buildCreateDao({
      name: "Solo DAO",
      description: "Single member",
      imageUrl: "",
      initialMembers: [creator.toSuiAddress()],
    });

    const result = await execute(client, tx, creator);
    expect(result.effects?.status?.status).toBe("success");
    assertEvent(result, "::dao::DAOCreated");
  });
});

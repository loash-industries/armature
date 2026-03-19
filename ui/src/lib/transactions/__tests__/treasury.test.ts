import { describe, it, expect } from "vitest";
import { buildDeposit, buildClaimCoin } from "../treasury";
import { PACKAGE_ID } from "@/config/constants";

const TREASURY_ID = "0x" + "a".repeat(64);
const COIN_OBJECT_ID = "0x" + "b".repeat(64);
const SUI_TYPE = "0x2::sui::SUI";

const COIN_REF = { objectId: "0x" + "c".repeat(64), version: 1, digest: "AAAA" };

describe("buildClaimCoin", () => {
  it("produces a single treasury_vault::claim_coin move call", () => {
    const tx = buildClaimCoin({ treasuryId: TREASURY_ID, coinRef: COIN_REF, coinType: SUI_TYPE });
    const { commands } = tx.getData();
    expect(commands).toHaveLength(1);
    expect(commands[0].MoveCall?.module).toBe("treasury_vault");
    expect(commands[0].MoveCall?.function).toBe("claim_coin");
  });

  it("uses PACKAGE_ID", () => {
    const tx = buildClaimCoin({ treasuryId: TREASURY_ID, coinRef: COIN_REF, coinType: SUI_TYPE });
    expect(tx.getData().commands[0].MoveCall?.package).toContain(PACKAGE_ID.replace(/^0x0*/, ""));
  });

  it("passes coinType as typeArgument", () => {
    const tx = buildClaimCoin({ treasuryId: TREASURY_ID, coinRef: COIN_REF, coinType: SUI_TYPE });
    expect(tx.getData().commands[0].MoveCall?.typeArguments[0]).toBe(SUI_TYPE);
  });

  it("uses a Receiving input for the coin ref", () => {
    const tx = buildClaimCoin({ treasuryId: TREASURY_ID, coinRef: COIN_REF, coinType: SUI_TYPE });
    const receivingInput = tx.getData().inputs.find(
      (i) => i.$kind === "Object" && i.Object?.$kind === "Receiving",
    );
    expect(receivingInput).toBeDefined();
  });
});

describe("buildDeposit", () => {
  it("produces a single treasury_vault::deposit move call", () => {
    const tx = buildDeposit({ treasuryId: TREASURY_ID, coinObjectId: COIN_OBJECT_ID, coinType: SUI_TYPE });
    const { commands } = tx.getData();
    expect(commands).toHaveLength(1);
    expect(commands[0].MoveCall?.module).toBe("treasury_vault");
    expect(commands[0].MoveCall?.function).toBe("deposit");
  });

  it("uses PACKAGE_ID", () => {
    const tx = buildDeposit({ treasuryId: TREASURY_ID, coinObjectId: COIN_OBJECT_ID, coinType: SUI_TYPE });
    expect(tx.getData().commands[0].MoveCall?.package).toContain(PACKAGE_ID.replace(/^0x0*/, ""));
  });

  it("passes coinType as typeArgument", () => {
    const tx = buildDeposit({ treasuryId: TREASURY_ID, coinObjectId: COIN_OBJECT_ID, coinType: SUI_TYPE });
    expect(tx.getData().commands[0].MoveCall?.typeArguments[0]).toBe(SUI_TYPE);
  });

  it("passes 2 object arguments: treasury and coin", () => {
    const tx = buildDeposit({ treasuryId: TREASURY_ID, coinObjectId: COIN_OBJECT_ID, coinType: SUI_TYPE });
    expect(tx.getData().commands[0].MoveCall?.arguments).toHaveLength(2);
  });
});

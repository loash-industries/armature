import { describe, it, expect } from "vitest";
import { buildDeposit } from "../treasury";
import { PACKAGE_ID } from "@/config/constants";

const TREASURY_ID = "0x" + "a".repeat(64);
const COIN_OBJECT_ID = "0x" + "b".repeat(64);
const SUI_TYPE = "0x2::sui::SUI";

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

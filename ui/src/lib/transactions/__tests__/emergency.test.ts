import { describe, it, expect } from "vitest";
import { buildFreezeType, buildUnfreezeType } from "../emergency";
import { PACKAGE_ID } from "@/config/constants";

const FREEZE_ID = "0x" + "a".repeat(64);
const FREEZE_CAP_ID = "0x" + "b".repeat(64);
const TYPE_KEY = "SetBoard";

describe("buildFreezeType", () => {
  it("produces a single emergency::freeze_type move call", () => {
    const tx = buildFreezeType({ emergencyFreezeId: FREEZE_ID, freezeAdminCapId: FREEZE_CAP_ID, typeKey: TYPE_KEY });
    const { commands } = tx.getData();
    expect(commands).toHaveLength(1);
    expect(commands[0].MoveCall?.module).toBe("emergency");
    expect(commands[0].MoveCall?.function).toBe("freeze_type");
  });

  it("uses PACKAGE_ID", () => {
    const tx = buildFreezeType({ emergencyFreezeId: FREEZE_ID, freezeAdminCapId: FREEZE_CAP_ID, typeKey: TYPE_KEY });
    expect(tx.getData().commands[0].MoveCall?.package).toContain(PACKAGE_ID.replace(/^0x0*/, ""));
  });

  it("passes 4 arguments: emergencyFreezeId, freezeAdminCapId, typeKey, clock", () => {
    const tx = buildFreezeType({ emergencyFreezeId: FREEZE_ID, freezeAdminCapId: FREEZE_CAP_ID, typeKey: TYPE_KEY });
    expect(tx.getData().commands[0].MoveCall?.arguments).toHaveLength(4);
  });

  it("includes clock (0x6) as an input", () => {
    const tx = buildFreezeType({ emergencyFreezeId: FREEZE_ID, freezeAdminCapId: FREEZE_CAP_ID, typeKey: TYPE_KEY });
    const clockInput = tx.getData().inputs.find(
      (i) =>
        i.$kind === "UnresolvedObject" &&
        i.UnresolvedObject?.objectId ===
          "0x0000000000000000000000000000000000000000000000000000000000000006",
    );
    expect(clockInput).toBeDefined();
  });
});

describe("buildUnfreezeType", () => {
  it("produces a single emergency::unfreeze_type move call", () => {
    const tx = buildUnfreezeType({ emergencyFreezeId: FREEZE_ID, freezeAdminCapId: FREEZE_CAP_ID, typeKey: TYPE_KEY });
    const { commands } = tx.getData();
    expect(commands).toHaveLength(1);
    expect(commands[0].MoveCall?.module).toBe("emergency");
    expect(commands[0].MoveCall?.function).toBe("unfreeze_type");
  });

  it("uses PACKAGE_ID", () => {
    const tx = buildUnfreezeType({ emergencyFreezeId: FREEZE_ID, freezeAdminCapId: FREEZE_CAP_ID, typeKey: TYPE_KEY });
    expect(tx.getData().commands[0].MoveCall?.package).toContain(PACKAGE_ID.replace(/^0x0*/, ""));
  });

  it("passes 3 arguments: emergencyFreezeId, freezeAdminCapId, typeKey (no clock)", () => {
    const tx = buildUnfreezeType({ emergencyFreezeId: FREEZE_ID, freezeAdminCapId: FREEZE_CAP_ID, typeKey: TYPE_KEY });
    expect(tx.getData().commands[0].MoveCall?.arguments).toHaveLength(3);
  });
});

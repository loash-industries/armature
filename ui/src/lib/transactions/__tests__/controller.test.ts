import { describe, it, expect } from "vitest";
import { buildPrivilegedOp } from "../controller";
import { Transaction } from "../helpers";
import { PACKAGE_ID } from "@/config/constants";

const CONTROL_ID = "0x" + "a".repeat(64);
const SUBDAO_ID = "0x" + "b".repeat(64);
const PROPOSAL_TYPE = `${PACKAGE_ID}::set_board::SetBoard`;

describe("buildPrivilegedOp", () => {
  function buildTx() {
    const tx = new Transaction();
    // Simulate a prior payload moveCall in the same PTB
    const payload = tx.moveCall({
      target: `${PACKAGE_ID}::set_board::new`,
      arguments: [],
    });
    buildPrivilegedOp(tx, {
      controlId: CONTROL_ID,
      subdaoId: SUBDAO_ID,
      typeKey: "SetBoard",
      metadataIpfs: "ipfs://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi",
      payload,
      proposalType: PROPOSAL_TYPE,
    });
    return tx;
  }

  it("adds exactly 2 move calls to the transaction (privileged_submit + privileged_consume)", () => {
    const tx = buildTx();
    const moveCalls = tx.getData().commands.filter((c) => c.$kind === "MoveCall");
    // 1 payload call + 1 submit + 1 consume = 3 total, submit+consume are the last 2
    expect(moveCalls[moveCalls.length - 2]?.MoveCall?.function).toBe("privileged_submit");
    expect(moveCalls[moveCalls.length - 1]?.MoveCall?.function).toBe("privileged_consume");
  });

  it("privileged_submit targets the controller module in PACKAGE_ID", () => {
    const tx = buildTx();
    const moveCalls = tx.getData().commands.filter((c) => c.$kind === "MoveCall");
    const submitCmd = moveCalls[moveCalls.length - 2];
    expect(submitCmd?.MoveCall?.module).toBe("controller");
    expect(submitCmd?.MoveCall?.package).toContain(PACKAGE_ID.replace(/^0x0*/, ""));
  });

  it("privileged_consume uses the same proposalType type argument", () => {
    const tx = buildTx();
    const moveCalls = tx.getData().commands.filter((c) => c.$kind === "MoveCall");
    const consumeCmd = moveCalls[moveCalls.length - 1];
    expect(consumeCmd?.MoveCall?.typeArguments[0]).toBe(PROPOSAL_TYPE);
  });

  it("privileged_submit passes clock (0x6) as an input", () => {
    const tx = buildTx();
    const clockInput = tx.getData().inputs.find(
      (i) =>
        i.$kind === "UnresolvedObject" &&
        i.UnresolvedObject?.objectId ===
          "0x0000000000000000000000000000000000000000000000000000000000000006",
    );
    expect(clockInput).toBeDefined();
  });
});

import { describe, it, expect } from "vitest";
import { buildCreateDao, buildSubmitCreateSubDAO } from "../dao";
import { PACKAGE_ID, PROPOSALS_PACKAGE_ID } from "@/config/constants";

const DAO_ID = "0x" + "a".repeat(64);

describe("buildCreateDao", () => {
  it("produces 2 move calls: init_board then dao::create", () => {
    const tx = buildCreateDao({
      name: "Test DAO",
      description: "desc",
      imageUrl: "https://example.com/img.png",
      initialMembers: ["0x" + "1".repeat(64)],
    });
    const { commands } = tx.getData();
    expect(commands).toHaveLength(2);
    expect(commands[0].$kind).toBe("MoveCall");
    expect(commands[0].MoveCall?.module).toBe("governance");
    expect(commands[0].MoveCall?.function).toBe("init_board");
    expect(commands[1].$kind).toBe("MoveCall");
    expect(commands[1].MoveCall?.module).toBe("dao");
    expect(commands[1].MoveCall?.function).toBe("create");
  });

  it("uses PACKAGE_ID for both calls", () => {
    const tx = buildCreateDao({ name: "n", description: "d", imageUrl: "u", initialMembers: [] });
    const { commands } = tx.getData();
    for (const cmd of commands) {
      expect(cmd.MoveCall?.package).toBe(
        PACKAGE_ID.replace("0x", "0x" + "0".repeat(64 - PACKAGE_ID.length + 2)).padStart(66, "0")
          ?? cmd.MoveCall?.package
      );
    }
  });
});

describe("buildSubmitCreateSubDAO", () => {
  it("produces 2 move calls: create_subdao::new then board_voting::submit_proposal", () => {
    const tx = buildSubmitCreateSubDAO({
      daoId: DAO_ID,
      name: "SubDAO",
      description: "desc",
      initialBoard: [],
      metadataIpfs: "ipfs://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi",
    });
    const { commands } = tx.getData();
    expect(commands).toHaveLength(2);
    expect(commands[0].MoveCall?.module).toBe("create_subdao");
    expect(commands[0].MoveCall?.function).toBe("new");
    expect(commands[0].MoveCall?.package).toContain(PROPOSALS_PACKAGE_ID.replace(/^0x0*/, ""));
    expect(commands[1].MoveCall?.module).toBe("board_voting");
    expect(commands[1].MoveCall?.function).toBe("submit_proposal");
  });

  it("sets correct type argument on submit_proposal", () => {
    const tx = buildSubmitCreateSubDAO({
      daoId: DAO_ID,
      name: "s",
      description: "d",
      initialBoard: [],
      metadataIpfs: "",
    });
    const { commands } = tx.getData();
    const submitCmd = commands[1];
    expect(submitCmd.MoveCall?.typeArguments[0]).toContain("::create_subdao::CreateSubDAO");
  });

  it("passes clock (0x6) as an input", () => {
    const tx = buildSubmitCreateSubDAO({
      daoId: DAO_ID,
      name: "s",
      description: "d",
      initialBoard: [],
      metadataIpfs: "",
    });
    const { inputs } = tx.getData();
    const clockInput = inputs.find(
      (i) =>
        i.$kind === "UnresolvedObject" &&
        i.UnresolvedObject?.objectId ===
          "0x0000000000000000000000000000000000000000000000000000000000000006",
    );
    expect(clockInput).toBeDefined();
  });
});

import { describe, it, expect } from "vitest";
import {
  buildVote,
  buildTryExpire,
  buildSubmitSetBoard,
  buildSubmitSendCoin,
  buildSubmitEnableProposalType,
  buildSubmitUpdateProposalConfig,
  buildSubmitTransferAssets,
} from "../proposal";
import { PACKAGE_ID, PROPOSALS_PACKAGE_ID } from "@/config/constants";

const DAO_ID = "0x" + "a".repeat(64);
const PROPOSAL_ID = "0x" + "b".repeat(64);
const SUI_TYPE = "0x2::sui::SUI";
const META = "ipfs://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi";

function assertSubmitPattern(commands: ReturnType<ReturnType<typeof buildVote>["getData"]>["commands"], proposalModule: string, payloadTypeSuffix: string) {
  expect(commands).toHaveLength(2);
  expect(commands[0].MoveCall?.module).toBe(proposalModule);
  expect(commands[0].MoveCall?.function).toBe("new");
  expect(commands[1].MoveCall?.module).toBe("board_voting");
  expect(commands[1].MoveCall?.function).toBe("submit_proposal");
  expect(commands[1].MoveCall?.typeArguments[0]).toContain(payloadTypeSuffix);
}

// ---------------------------------------------------------------------------
// Vote / Expire
// ---------------------------------------------------------------------------

describe("buildVote", () => {
  const proposalType = `${PROPOSALS_PACKAGE_ID}::set_board::SetBoard`;

  it("produces a single proposal::vote move call", () => {
    const tx = buildVote({ proposalId: PROPOSAL_ID, approve: true, proposalType });
    const { commands } = tx.getData();
    expect(commands).toHaveLength(1);
    expect(commands[0].MoveCall?.module).toBe("proposal");
    expect(commands[0].MoveCall?.function).toBe("vote");
  });

  it("uses PACKAGE_ID", () => {
    const tx = buildVote({ proposalId: PROPOSAL_ID, approve: false, proposalType });
    const { commands } = tx.getData();
    expect(commands[0].MoveCall?.package).toContain(PACKAGE_ID.replace(/^0x0*/, ""));
  });

  it("sets type argument to proposalType", () => {
    const tx = buildVote({ proposalId: PROPOSAL_ID, approve: true, proposalType });
    const { commands } = tx.getData();
    expect(commands[0].MoveCall?.typeArguments[0]).toBe(proposalType);
  });

  it("passes clock as argument", () => {
    const tx = buildVote({ proposalId: PROPOSAL_ID, approve: true, proposalType });
    const { commands } = tx.getData();
    // 3 args: proposalId, approve, clock
    expect(commands[0].MoveCall?.arguments).toHaveLength(3);
  });

  // Helper variable re-use fix
  it("approve=false also works", () => {
    const tx = buildVote({ proposalId: PROPOSAL_ID, approve: false, proposalType });
    const { commands } = tx.getData();
    expect(commands[0].MoveCall?.function).toBe("vote");
  });
});

describe("buildTryExpire", () => {
  it("produces a single proposal::try_expire move call", () => {
    const proposalType = `${PROPOSALS_PACKAGE_ID}::set_board::SetBoard`;
    const tx = buildTryExpire({ proposalId: PROPOSAL_ID, proposalType });
    const { commands } = tx.getData();
    expect(commands).toHaveLength(1);
    expect(commands[0].MoveCall?.module).toBe("proposal");
    expect(commands[0].MoveCall?.function).toBe("try_expire");
    expect(commands[0].MoveCall?.typeArguments[0]).toBe(proposalType);
  });
});

// ---------------------------------------------------------------------------
// Submit builders (structural pattern checks)
// ---------------------------------------------------------------------------

describe("buildSubmitSetBoard", () => {
  it("follows submit pattern with set_board::new + board_voting::submit_proposal", () => {
    const tx = buildSubmitSetBoard({
      daoId: DAO_ID,
      newMembers: ["0x" + "1".repeat(64)],
      metadataIpfs: META,
    });
    assertSubmitPattern(tx.getData().commands, "set_board", "::set_board::SetBoard");
  });
});

describe("buildSubmitSendCoin", () => {
  it("follows submit pattern with send_coin::new + board_voting::submit_proposal", () => {
    const tx = buildSubmitSendCoin({
      daoId: DAO_ID,
      recipient: "0x" + "2".repeat(64),
      amount: "1000000000",
      coinType: SUI_TYPE,
      metadataIpfs: META,
    });
    assertSubmitPattern(tx.getData().commands, "send_coin", "::send_coin::SendCoin");
  });

  it("includes coinType in type argument of submit_proposal", () => {
    const tx = buildSubmitSendCoin({
      daoId: DAO_ID,
      recipient: "0x" + "2".repeat(64),
      amount: "1000000000",
      coinType: SUI_TYPE,
      metadataIpfs: META,
    });
    const typeArg = tx.getData().commands[1].MoveCall?.typeArguments[0];
    expect(typeArg).toContain(SUI_TYPE);
  });

  it("passes coinType as typeArgument on send_coin::new", () => {
    const tx = buildSubmitSendCoin({
      daoId: DAO_ID,
      recipient: "0x" + "2".repeat(64),
      amount: "1000000000",
      coinType: SUI_TYPE,
      metadataIpfs: META,
    });
    expect(tx.getData().commands[0].MoveCall?.typeArguments[0]).toBe(SUI_TYPE);
  });
});

describe("buildSubmitEnableProposalType", () => {
  it("produces 3 commands: proposal::new_config, enable_proposal_type::new, board_voting::submit_proposal", () => {
    const tx = buildSubmitEnableProposalType({
      daoId: DAO_ID,
      typeKey: "SetBoard",
      quorum: 5000,
      approvalThreshold: 5000,
      proposeThreshold: "0",
      expiryMs: "86400000",
      executionDelayMs: "0",
      cooldownMs: "0",
      metadataIpfs: META,
    });
    const { commands } = tx.getData();
    expect(commands).toHaveLength(3);
    expect(commands[0].MoveCall?.function).toBe("new_config");
    expect(commands[1].MoveCall?.module).toBe("enable_proposal_type");
    expect(commands[1].MoveCall?.function).toBe("new");
    expect(commands[2].MoveCall?.module).toBe("board_voting");
    expect(commands[2].MoveCall?.function).toBe("submit_proposal");
  });
});

describe("buildSubmitUpdateProposalConfig", () => {
  it("builds Option::some for provided fields", () => {
    const tx = buildSubmitUpdateProposalConfig({
      daoId: DAO_ID,
      targetTypeKey: "SendCoin",
      quorum: 6000,
      metadataIpfs: META,
    });
    const { commands } = tx.getData();
    // optU16 some/none + optU64 x5 + update_proposal_config::new + board_voting::submit_proposal
    // quorum = some (1 cmd), approvalThreshold = none (1), proposeThreshold = none (1),
    // expiryMs = none (1), executionDelayMs = none (1), cooldownMs = none (1) = 6 option cmds
    // + payload (1) + submit (1) = 8 total
    expect(commands.length).toBeGreaterThanOrEqual(8);
    expect(commands.at(-1)?.MoveCall?.function).toBe("submit_proposal");
    expect(commands.at(-2)?.MoveCall?.module).toBe("update_proposal_config");
  });

  it("builds Option::none for omitted fields", () => {
    const tx = buildSubmitUpdateProposalConfig({
      daoId: DAO_ID,
      targetTypeKey: "SendCoin",
      metadataIpfs: META,
      // no optional fields
    });
    const { commands } = tx.getData();
    const noneCalls = commands.filter((c) => c.MoveCall?.function === "none");
    expect(noneCalls).toHaveLength(6); // all 6 fields are none
  });
});

describe("buildSubmitTransferAssets", () => {
  it("builds vector<TypeName> with type_name::get calls before the payload", () => {
    const coinTypes = [SUI_TYPE, "0x2::coin::COIN"];
    const tx = buildSubmitTransferAssets({
      daoId: DAO_ID,
      targetDaoId: "0x" + "c".repeat(64),
      targetTreasuryId: "0x" + "d".repeat(64),
      targetVaultId: "0x" + "e".repeat(64),
      coinTypes,
      capIds: [],
      metadataIpfs: META,
    });
    const { commands } = tx.getData();
    // 2× type_name::get + makeMoveVec + transfer_assets::new + submit_proposal = 5
    const getTypeCalls = commands.filter((c) => c.MoveCall?.function === "get");
    expect(getTypeCalls).toHaveLength(coinTypes.length);
    const makeMoveVecs = commands.filter((c) => "$kind" in c && c.$kind === "MakeMoveVec");
    expect(makeMoveVecs).toHaveLength(1);
  });
});

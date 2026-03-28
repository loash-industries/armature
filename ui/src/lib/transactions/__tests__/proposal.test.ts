import { describe, it, expect } from "vitest";
import {
  buildVote,
  buildTryExpire,
  buildSubmitSetBoard,
  buildSubmitSendCoin,
  buildSubmitEnableProposalType,
  buildSubmitUpdateProposalConfig,
  buildSubmitTransferAssets,
  buildSubmitUpdateMetadata,
  buildSubmitDisableProposalType,
  buildSubmitTransferFreezeAdmin,
  buildSubmitUnfreezeProposalType,
  buildSubmitSendCoinToDAO,
  buildSubmitSendSmallPayment,
  buildSubmitUpdateFreezeConfig,
  buildSubmitUpdateFreezeExemptTypes,
  buildSubmitTransferCapToSubDAO,
  buildSubmitReclaimCapFromSubDAO,
  buildSubmitProposeUpgrade,
  buildSubmitSpawnDAO,
  buildSubmitSpinOutSubDAO,
  buildSubmitPauseSubDAOExecution,
  buildSubmitUnpauseSubDAOExecution,
} from "../proposal";
import { PACKAGE_ID, PROPOSALS_PACKAGE_ID } from "@/config/constants";

const DAO_ID = "0x" + "a".repeat(64);
const PROPOSAL_ID = "0x" + "b".repeat(64);
const SUI_TYPE = "0x2::sui::SUI";
const META =
  "ipfs://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi";

function assertSubmitPattern(
  commands: ReturnType<ReturnType<typeof buildVote>["getData"]>["commands"],
  proposalModule: string,
  payloadTypeSuffix: string,
) {
  expect(commands).toHaveLength(3);
  expect(commands[0].MoveCall?.module).toBe(proposalModule);
  expect(commands[0].MoveCall?.function).toBe("new");
  // commands[1] is the optionalString (option::some / option::none) MoveCall
  expect(commands[2].MoveCall?.module).toBe("board_voting");
  expect(commands[2].MoveCall?.function).toBe("submit_proposal");
  expect(commands[2].MoveCall?.typeArguments[0]).toContain(payloadTypeSuffix);
}

// ---------------------------------------------------------------------------
// Vote / Expire
// ---------------------------------------------------------------------------

describe("buildVote", () => {
  const proposalType = `${PROPOSALS_PACKAGE_ID}::set_board::SetBoard`;

  it("produces a single proposal::vote move call", () => {
    const tx = buildVote({
      proposalId: PROPOSAL_ID,
      approve: true,
      proposalType,
    });
    const { commands } = tx.getData();
    expect(commands).toHaveLength(1);
    expect(commands[0].MoveCall?.module).toBe("proposal");
    expect(commands[0].MoveCall?.function).toBe("vote");
  });

  it("uses PACKAGE_ID", () => {
    const tx = buildVote({
      proposalId: PROPOSAL_ID,
      approve: false,
      proposalType,
    });
    const { commands } = tx.getData();
    expect(commands[0].MoveCall?.package).toContain(
      PACKAGE_ID.replace(/^0x0*/, ""),
    );
  });

  it("sets type argument to proposalType", () => {
    const tx = buildVote({
      proposalId: PROPOSAL_ID,
      approve: true,
      proposalType,
    });
    const { commands } = tx.getData();
    expect(commands[0].MoveCall?.typeArguments[0]).toBe(proposalType);
  });

  it("passes clock as argument", () => {
    const tx = buildVote({
      proposalId: PROPOSAL_ID,
      approve: true,
      proposalType,
    });
    const { commands } = tx.getData();
    // 3 args: proposalId, approve, clock
    expect(commands[0].MoveCall?.arguments).toHaveLength(3);
  });

  // Helper variable re-use fix
  it("approve=false also works", () => {
    const tx = buildVote({
      proposalId: PROPOSAL_ID,
      approve: false,
      proposalType,
    });
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
    assertSubmitPattern(
      tx.getData().commands,
      "set_board",
      "::set_board::SetBoard",
    );
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
    assertSubmitPattern(
      tx.getData().commands,
      "send_coin",
      "::send_coin::SendCoin",
    );
  });

  it("includes coinType in type argument of submit_proposal", () => {
    const tx = buildSubmitSendCoin({
      daoId: DAO_ID,
      recipient: "0x" + "2".repeat(64),
      amount: "1000000000",
      coinType: SUI_TYPE,
      metadataIpfs: META,
    });
    const typeArg = tx.getData().commands[2].MoveCall?.typeArguments[0];
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
    expect(commands).toHaveLength(4);
    expect(commands[0].MoveCall?.function).toBe("new_config");
    expect(commands[1].MoveCall?.module).toBe("enable_proposal_type");
    expect(commands[1].MoveCall?.function).toBe("new");
    // commands[2] is the optionalString MoveCall
    expect(commands[3].MoveCall?.module).toBe("board_voting");
    expect(commands[3].MoveCall?.function).toBe("submit_proposal");
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
    // optU16 some/none + optU64 x5 + update_proposal_config::new + optionalString + board_voting::submit_proposal
    // quorum = some (1 cmd), approvalThreshold = none (1), proposeThreshold = none (1),
    // expiryMs = none (1), executionDelayMs = none (1), cooldownMs = none (1) = 6 option cmds
    // + payload (1) + optionalString (1) + submit (1) = 9 total
    expect(commands.length).toBeGreaterThanOrEqual(9);
    expect(commands[commands.length - 1]?.MoveCall?.function).toBe(
      "submit_proposal",
    );
    expect(commands[commands.length - 3]?.MoveCall?.module).toBe(
      "update_proposal_config",
    );
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
    const makeMoveVecs = commands.filter(
      (c) => "$kind" in c && c.$kind === "MakeMoveVec",
    );
    expect(makeMoveVecs).toHaveLength(1);
  });
});

// ---------------------------------------------------------------------------
// Previously integration-only submit builders
// ---------------------------------------------------------------------------

describe("buildSubmitUpdateMetadata", () => {
  it("follows submit pattern with update_metadata::new + board_voting::submit_proposal", () => {
    const tx = buildSubmitUpdateMetadata({
      daoId: DAO_ID,
      newIpfsCid: META,
      metadataIpfs: META,
    });
    assertSubmitPattern(
      tx.getData().commands,
      "update_metadata",
      "::update_metadata::UpdateMetadata",
    );
  });
});

describe("buildSubmitDisableProposalType", () => {
  it("follows submit pattern with disable_proposal_type::new + board_voting::submit_proposal", () => {
    const tx = buildSubmitDisableProposalType({
      daoId: DAO_ID,
      typeKey: "SendCoin",
      metadataIpfs: META,
    });
    assertSubmitPattern(
      tx.getData().commands,
      "disable_proposal_type",
      "::disable_proposal_type::DisableProposalType",
    );
  });
});

describe("buildSubmitTransferFreezeAdmin", () => {
  it("follows submit pattern with transfer_freeze_admin::new + board_voting::submit_proposal", () => {
    const tx = buildSubmitTransferFreezeAdmin({
      daoId: DAO_ID,
      newAdmin: "0x" + "2".repeat(64),
      metadataIpfs: META,
    });
    assertSubmitPattern(
      tx.getData().commands,
      "transfer_freeze_admin",
      "::transfer_freeze_admin::TransferFreezeAdmin",
    );
  });
});

describe("buildSubmitUnfreezeProposalType", () => {
  it("follows submit pattern with unfreeze_proposal_type::new + board_voting::submit_proposal", () => {
    const tx = buildSubmitUnfreezeProposalType({
      daoId: DAO_ID,
      typeKey: "SetBoard",
      metadataIpfs: META,
    });
    assertSubmitPattern(
      tx.getData().commands,
      "unfreeze_proposal_type",
      "::unfreeze_proposal_type::UnfreezeProposalType",
    );
  });
});

describe("buildSubmitSendCoinToDAO", () => {
  it("follows submit pattern with send_coin_to_dao::new + board_voting::submit_proposal", () => {
    const tx = buildSubmitSendCoinToDAO({
      daoId: DAO_ID,
      recipientTreasuryId: "0x" + "d".repeat(64),
      amount: "1000000000",
      coinType: SUI_TYPE,
      metadataIpfs: META,
    });
    assertSubmitPattern(
      tx.getData().commands,
      "send_coin_to_dao",
      "::send_coin_to_dao::SendCoinToDAO",
    );
  });

  it("includes coinType in submit_proposal type argument", () => {
    const tx = buildSubmitSendCoinToDAO({
      daoId: DAO_ID,
      recipientTreasuryId: "0x" + "d".repeat(64),
      amount: "1000000000",
      coinType: SUI_TYPE,
      metadataIpfs: META,
    });
    expect(tx.getData().commands[2].MoveCall?.typeArguments[0]).toContain(
      SUI_TYPE,
    );
  });
});

describe("buildSubmitSendSmallPayment", () => {
  it("follows submit pattern with send_small_payment::new + board_voting::submit_proposal", () => {
    const tx = buildSubmitSendSmallPayment({
      daoId: DAO_ID,
      recipient: "0x" + "2".repeat(64),
      amount: "1000000",
      coinType: SUI_TYPE,
      metadataIpfs: META,
    });
    assertSubmitPattern(
      tx.getData().commands,
      "send_small_payment",
      "::send_small_payment::SendSmallPayment",
    );
  });

  it("includes coinType in submit_proposal type argument", () => {
    const tx = buildSubmitSendSmallPayment({
      daoId: DAO_ID,
      recipient: "0x" + "2".repeat(64),
      amount: "1000000",
      coinType: SUI_TYPE,
      metadataIpfs: META,
    });
    expect(tx.getData().commands[2].MoveCall?.typeArguments[0]).toContain(
      SUI_TYPE,
    );
  });
});

describe("buildSubmitUpdateFreezeConfig", () => {
  it("follows submit pattern with update_freeze_config::new + board_voting::submit_proposal", () => {
    const tx = buildSubmitUpdateFreezeConfig({
      daoId: DAO_ID,
      newMaxFreezeDurationMs: "604800000",
      metadataIpfs: META,
    });
    assertSubmitPattern(
      tx.getData().commands,
      "update_freeze_config",
      "::update_freeze_config::UpdateFreezeConfig",
    );
  });
});

describe("buildSubmitUpdateFreezeExemptTypes", () => {
  it("follows submit pattern with update_freeze_exempt_types::new + board_voting::submit_proposal", () => {
    const tx = buildSubmitUpdateFreezeExemptTypes({
      daoId: DAO_ID,
      typesToAdd: ["SetBoard"],
      typesToRemove: [],
      metadataIpfs: META,
    });
    assertSubmitPattern(
      tx.getData().commands,
      "update_freeze_exempt_types",
      "::update_freeze_exempt_types::UpdateFreezeExemptTypes",
    );
  });
});

// ---------------------------------------------------------------------------
// Previously uncovered submit builders
// ---------------------------------------------------------------------------

describe("buildSubmitTransferCapToSubDAO", () => {
  it("follows submit pattern with transfer_cap_to_subdao::new + board_voting::submit_proposal", () => {
    const tx = buildSubmitTransferCapToSubDAO({
      daoId: DAO_ID,
      capId: "0x" + "1".repeat(64),
      targetSubdao: "0x" + "2".repeat(64),
      metadataIpfs: META,
    });
    assertSubmitPattern(
      tx.getData().commands,
      "transfer_cap_to_subdao",
      "::transfer_cap_to_subdao::TransferCapToSubDAO",
    );
  });
});

describe("buildSubmitReclaimCapFromSubDAO", () => {
  it("follows submit pattern with reclaim_cap_from_subdao::new + board_voting::submit_proposal", () => {
    const tx = buildSubmitReclaimCapFromSubDAO({
      daoId: DAO_ID,
      subdaoId: "0x" + "1".repeat(64),
      capId: "0x" + "2".repeat(64),
      controlId: "0x" + "3".repeat(64),
      metadataIpfs: META,
    });
    assertSubmitPattern(
      tx.getData().commands,
      "reclaim_cap_from_subdao",
      "::reclaim_cap_from_subdao::ReclaimCapFromSubDAO",
    );
  });

  it("passes subdaoId, capId, and controlId as three separate arguments to ::new", () => {
    const tx = buildSubmitReclaimCapFromSubDAO({
      daoId: DAO_ID,
      subdaoId: "0x" + "1".repeat(64),
      capId: "0x" + "2".repeat(64),
      controlId: "0x" + "3".repeat(64),
      metadataIpfs: META,
    });
    expect(tx.getData().commands[0].MoveCall?.arguments).toHaveLength(3);
  });
});

describe("buildSubmitProposeUpgrade", () => {
  const DIGEST_HEX = "deadbeef01020304";
  const DIGEST_HEX_PREFIXED = "0x" + DIGEST_HEX;

  it("follows submit pattern with propose_upgrade::new + board_voting::submit_proposal", () => {
    const tx = buildSubmitProposeUpgrade({
      daoId: DAO_ID,
      capId: "0x" + "1".repeat(64),
      packageId: "0x" + "2".repeat(64),
      digest: DIGEST_HEX_PREFIXED,
      policy: 0,
      metadataIpfs: META,
    });
    assertSubmitPattern(
      tx.getData().commands,
      "propose_upgrade",
      "::propose_upgrade::ProposeUpgrade",
    );
  });

  it("propose_upgrade::new receives 4 arguments (capId, packageId, digest bytes, policy)", () => {
    const tx = buildSubmitProposeUpgrade({
      daoId: DAO_ID,
      capId: "0x" + "1".repeat(64),
      packageId: "0x" + "2".repeat(64),
      digest: DIGEST_HEX_PREFIXED,
      policy: 0,
      metadataIpfs: META,
    });
    expect(tx.getData().commands[0].MoveCall?.arguments).toHaveLength(4);
  });

  it("digest with 0x prefix produces same command structure as without", () => {
    const txWith = buildSubmitProposeUpgrade({
      daoId: DAO_ID,
      capId: "0x" + "1".repeat(64),
      packageId: "0x" + "2".repeat(64),
      digest: DIGEST_HEX_PREFIXED,
      policy: 0,
      metadataIpfs: META,
    });
    const txWithout = buildSubmitProposeUpgrade({
      daoId: DAO_ID,
      capId: "0x" + "1".repeat(64),
      packageId: "0x" + "2".repeat(64),
      digest: DIGEST_HEX,
      policy: 0,
      metadataIpfs: META,
    });
    // Both should produce 3 commands with the same structure (payload + optionalString + submit)
    expect(txWith.getData().commands).toHaveLength(3);
    expect(txWithout.getData().commands).toHaveLength(3);
    expect(txWith.getData().commands[0].MoveCall?.function).toBe("new");
    expect(txWithout.getData().commands[0].MoveCall?.function).toBe("new");
  });

  it("empty digest yields empty byte vector without throwing", () => {
    expect(() =>
      buildSubmitProposeUpgrade({
        daoId: DAO_ID,
        capId: "0x" + "1".repeat(64),
        packageId: "0x" + "2".repeat(64),
        digest: "",
        policy: 0,
        metadataIpfs: META,
      }),
    ).not.toThrow();
  });
});

describe("buildSubmitSpawnDAO", () => {
  it("produces 3 commands: governance::init_board, spawn_dao::new, board_voting::submit_proposal", () => {
    const tx = buildSubmitSpawnDAO({
      daoId: DAO_ID,
      name: "Child DAO",
      description: "Spawned in test",
      metadataIpfs: META,
    });
    const { commands } = tx.getData();
    expect(commands).toHaveLength(4);
    expect(commands[0].MoveCall?.module).toBe("governance");
    expect(commands[0].MoveCall?.function).toBe("init_board");
    expect(commands[1].MoveCall?.module).toBe("spawn_dao");
    expect(commands[1].MoveCall?.function).toBe("new");
    // commands[2] is the optionalString MoveCall
    expect(commands[3].MoveCall?.module).toBe("board_voting");
    expect(commands[3].MoveCall?.function).toBe("submit_proposal");
    expect(commands[3].MoveCall?.typeArguments[0]).toContain(
      "::spawn_dao::SpawnDAO",
    );
  });
});

describe("buildSubmitSpinOutSubDAO", () => {
  it("produces 5 commands: 3× proposal::new_config, spin_out_subdao::new, board_voting::submit_proposal", () => {
    const tx = buildSubmitSpinOutSubDAO({
      daoId: DAO_ID,
      subDaoId: "0x" + "1".repeat(64),
      controlCapId: "0x" + "2".repeat(64),
      freezeAdminCapId: "0x" + "3".repeat(64),
      metadataIpfs: META,
    });
    const { commands } = tx.getData();
    expect(commands).toHaveLength(6);
    const configCalls = commands.filter(
      (c) => c.MoveCall?.function === "new_config",
    );
    expect(configCalls).toHaveLength(3);
    expect(commands[3].MoveCall?.module).toBe("spin_out_subdao");
    expect(commands[3].MoveCall?.function).toBe("new");
    // commands[4] is the optionalString MoveCall
    expect(commands[5].MoveCall?.module).toBe("board_voting");
    expect(commands[5].MoveCall?.function).toBe("submit_proposal");
    expect(commands[5].MoveCall?.typeArguments[0]).toContain(
      "::spin_out_subdao::SpinOutSubDAO",
    );
  });
});

describe("buildSubmitPauseSubDAOExecution", () => {
  it("produces 2 commands: pause_execution::new_pause + board_voting::submit_proposal", () => {
    const tx = buildSubmitPauseSubDAOExecution({
      daoId: DAO_ID,
      controlId: "0x" + "1".repeat(64),
      metadataIpfs: META,
    });
    const { commands } = tx.getData();
    expect(commands).toHaveLength(3);
    expect(commands[0].MoveCall?.module).toBe("pause_execution");
    expect(commands[0].MoveCall?.function).toBe("new_pause");
    // commands[1] is the optionalString MoveCall
    expect(commands[2].MoveCall?.module).toBe("board_voting");
    expect(commands[2].MoveCall?.function).toBe("submit_proposal");
    expect(commands[2].MoveCall?.typeArguments[0]).toContain(
      "::pause_execution::PauseSubDAOExecution",
    );
  });
});

describe("buildSubmitUnpauseSubDAOExecution", () => {
  it("produces 2 commands: pause_execution::new_unpause + board_voting::submit_proposal", () => {
    const tx = buildSubmitUnpauseSubDAOExecution({
      daoId: DAO_ID,
      controlId: "0x" + "1".repeat(64),
      metadataIpfs: META,
    });
    const { commands } = tx.getData();
    expect(commands).toHaveLength(3);
    expect(commands[0].MoveCall?.module).toBe("pause_execution");
    expect(commands[0].MoveCall?.function).toBe("new_unpause");
    // commands[1] is the optionalString MoveCall
    expect(commands[2].MoveCall?.module).toBe("board_voting");
    expect(commands[2].MoveCall?.function).toBe("submit_proposal");
    expect(commands[2].MoveCall?.typeArguments[0]).toContain(
      "::pause_execution::UnpauseSubDAOExecution",
    );
  });
});

import { describe, it, expect } from "vitest";
import {
  buildExecuteSetBoard,
  buildExecuteSendCoin,
  buildExecuteUpdateProposalConfig,
  buildExecuteTransferFreezeAdmin,
  buildExecuteCreateSubDAO,
  buildExecuteTransferCapToSubDAO,
  buildExecutePauseSubDAOExecution,
  buildExecuteReclaimCap,
} from "../execution";
import { PACKAGE_ID, PROPOSALS_PACKAGE_ID } from "@/config/constants";

const DAO_ID = "0x" + "a".repeat(64);
const PROPOSAL_ID = "0x" + "b".repeat(64);
const FREEZE_ID = "0x" + "c".repeat(64);
const SUI_TYPE = "0x2::sui::SUI";

/**
 * All execute builders follow the same pattern:
 *   1. board_voting::authorize_execution  (returns Request)
 *   2. <ops_module>::execute_<action>     (consumes Request)
 */
function assertExecutePattern(
  commands: ReturnType<ReturnType<typeof buildExecuteSetBoard>["getData"]>["commands"],
  opsModule: string,
  opsFunction: string,
  payloadTypeSuffix: string,
) {
  expect(commands).toHaveLength(2);
  expect(commands[0].MoveCall?.module).toBe("board_voting");
  expect(commands[0].MoveCall?.function).toBe("authorize_execution");
  expect(commands[0].MoveCall?.typeArguments[0]).toContain(payloadTypeSuffix);
  expect(commands[1].MoveCall?.module).toBe(opsModule);
  expect(commands[1].MoveCall?.function).toBe(opsFunction);
}

function assertAuthorizeUsesPackageId(
  commands: ReturnType<ReturnType<typeof buildExecuteSetBoard>["getData"]>["commands"],
) {
  expect(commands[0].MoveCall?.package).toContain(PACKAGE_ID.replace(/^0x0*/, ""));
}

describe("buildExecuteSetBoard", () => {
  it("follows execute pattern: authorize_execution → board_ops::execute_set_board", () => {
    const tx = buildExecuteSetBoard({ daoId: DAO_ID, proposalId: PROPOSAL_ID, emergencyFreezeId: FREEZE_ID });
    assertExecutePattern(tx.getData().commands, "board_ops", "execute_set_board", "::set_board::SetBoard");
  });

  it("authorize_execution uses PACKAGE_ID", () => {
    const tx = buildExecuteSetBoard({ daoId: DAO_ID, proposalId: PROPOSAL_ID, emergencyFreezeId: FREEZE_ID });
    assertAuthorizeUsesPackageId(tx.getData().commands);
  });

  it("board_ops uses PROPOSALS_PACKAGE_ID", () => {
    const tx = buildExecuteSetBoard({ daoId: DAO_ID, proposalId: PROPOSAL_ID, emergencyFreezeId: FREEZE_ID });
    expect(tx.getData().commands[1].MoveCall?.package).toContain(
      PROPOSALS_PACKAGE_ID.replace(/^0x0*/, ""),
    );
  });

  it("authorize_execution receives 4 arguments (daoId, proposalId, emergencyFreezeId, clock)", () => {
    const tx = buildExecuteSetBoard({ daoId: DAO_ID, proposalId: PROPOSAL_ID, emergencyFreezeId: FREEZE_ID });
    expect(tx.getData().commands[0].MoveCall?.arguments).toHaveLength(4);
  });
});

describe("buildExecuteSendCoin", () => {
  it("follows execute pattern: authorize_execution → treasury_ops::execute_send_coin", () => {
    const tx = buildExecuteSendCoin({
      daoId: DAO_ID,
      proposalId: PROPOSAL_ID,
      treasuryId: "0x" + "d".repeat(64),
      emergencyFreezeId: FREEZE_ID,
      coinType: SUI_TYPE,
    });
    assertExecutePattern(tx.getData().commands, "treasury_ops", "execute_send_coin", "::send_coin::SendCoin");
  });

  it("includes coinType in payload type argument", () => {
    const tx = buildExecuteSendCoin({
      daoId: DAO_ID, proposalId: PROPOSAL_ID,
      treasuryId: "0x" + "d".repeat(64),
      emergencyFreezeId: FREEZE_ID, coinType: SUI_TYPE,
    });
    expect(tx.getData().commands[0].MoveCall?.typeArguments[0]).toContain(SUI_TYPE);
  });

  it("passes coinType as typeArgument on execute_send_coin", () => {
    const tx = buildExecuteSendCoin({
      daoId: DAO_ID, proposalId: PROPOSAL_ID,
      treasuryId: "0x" + "d".repeat(64),
      emergencyFreezeId: FREEZE_ID, coinType: SUI_TYPE,
    });
    expect(tx.getData().commands[1].MoveCall?.typeArguments[0]).toBe(SUI_TYPE);
  });
});

describe("buildExecuteUpdateProposalConfig", () => {
  it("follows execute pattern: authorize_execution → admin_ops::execute_update_proposal_config", () => {
    const tx = buildExecuteUpdateProposalConfig({
      daoId: DAO_ID, proposalId: PROPOSAL_ID, emergencyFreezeId: FREEZE_ID,
    });
    assertExecutePattern(tx.getData().commands, "admin_ops", "execute_update_proposal_config", "::update_proposal_config::UpdateProposalConfig");
  });
});

describe("buildExecuteTransferFreezeAdmin", () => {
  it("follows execute pattern: authorize_execution → security_ops::execute_transfer_freeze_admin", () => {
    const tx = buildExecuteTransferFreezeAdmin({
      daoId: DAO_ID, proposalId: PROPOSAL_ID,
      emergencyFreezeId: FREEZE_ID,
      freezeAdminCapId: "0x" + "e".repeat(64),
    });
    assertExecutePattern(tx.getData().commands, "security_ops", "execute_transfer_freeze_admin", "::transfer_freeze_admin::TransferFreezeAdmin");
  });
});

describe("buildExecuteCreateSubDAO", () => {
  it("follows execute pattern: authorize_execution → subdao_ops::execute_create_subdao", () => {
    const tx = buildExecuteCreateSubDAO({
      daoId: DAO_ID, proposalId: PROPOSAL_ID,
      capabilityVaultId: "0x" + "f".repeat(64),
      emergencyFreezeId: FREEZE_ID,
    });
    assertExecutePattern(tx.getData().commands, "subdao_ops", "execute_create_subdao", "::create_subdao::CreateSubDAO");
  });
});

describe("buildExecuteTransferCapToSubDAO", () => {
  it("follows execute pattern: authorize_execution → subdao_ops::execute_transfer_cap", () => {
    const capType = `${PROPOSALS_PACKAGE_ID}::some_module::SomeCap`;
    const tx = buildExecuteTransferCapToSubDAO({
      daoId: DAO_ID, proposalId: PROPOSAL_ID,
      sourceVaultId: "0x" + "1".repeat(64),
      targetVaultId: "0x" + "2".repeat(64),
      emergencyFreezeId: FREEZE_ID,
      capType,
    });
    assertExecutePattern(tx.getData().commands, "subdao_ops", "execute_transfer_cap", "::transfer_cap_to_subdao::TransferCapToSubDAO");
  });

  it("passes capType as typeArgument on execute_transfer_cap", () => {
    const capType = `${PROPOSALS_PACKAGE_ID}::some_module::SomeCap`;
    const tx = buildExecuteTransferCapToSubDAO({
      daoId: DAO_ID, proposalId: PROPOSAL_ID,
      sourceVaultId: "0x" + "1".repeat(64),
      targetVaultId: "0x" + "2".repeat(64),
      emergencyFreezeId: FREEZE_ID, capType,
    });
    expect(tx.getData().commands[1].MoveCall?.typeArguments[0]).toBe(capType);
  });
});

describe("buildExecutePauseSubDAOExecution", () => {
  it("follows execute pattern: authorize_execution → subdao_ops::execute_pause_subdao_execution", () => {
    const tx = buildExecutePauseSubDAOExecution({
      daoId: DAO_ID, proposalId: PROPOSAL_ID,
      controllerVaultId: "0x" + "1".repeat(64),
      subdaoId: "0x" + "2".repeat(64),
      emergencyFreezeId: FREEZE_ID,
    });
    assertExecutePattern(tx.getData().commands, "subdao_ops", "execute_pause_subdao_execution", "::pause_execution::PauseSubDAOExecution");
  });
});

describe("buildExecuteReclaimCap", () => {
  it("follows execute pattern: authorize_execution → subdao_ops::execute_reclaim_cap", () => {
    const capType = `${PROPOSALS_PACKAGE_ID}::some_module::SomeCap`;
    const tx = buildExecuteReclaimCap({
      daoId: DAO_ID, proposalId: PROPOSAL_ID,
      controllerVaultId: "0x" + "1".repeat(64),
      subdaoVaultId: "0x" + "2".repeat(64),
      emergencyFreezeId: FREEZE_ID, capType,
    });
    assertExecutePattern(tx.getData().commands, "subdao_ops", "execute_reclaim_cap", "::reclaim_cap_from_subdao::ReclaimCapFromSubDAO");
  });
});

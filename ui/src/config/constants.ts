/**
 * On-chain package and module identifiers.
 * Update PACKAGE_ID / PROPOSALS_PACKAGE_ID after each publish/upgrade.
 */
export const PACKAGE_ID =
  import.meta.env.VITE_PACKAGE_ID ??
  "0x0000000000000000000000000000000000000000000000000000000000000000";

export const PROPOSALS_PACKAGE_ID =
  import.meta.env.VITE_PROPOSALS_PACKAGE_ID ??
  "0x0000000000000000000000000000000000000000000000000000000000000000";

/** EVE Frontier world-contracts package (Character / PlayerProfile). */
export const WORLD_PACKAGE_ID =
  import.meta.env.VITE_WORLD_PACKAGE_ID ??
  "0x0000000000000000000000000000000000000000000000000000000000000000";

/** armature_framework modules */
export const MODULES = {
  dao: "dao",
  proposal: "proposal",
  treasury_vault: "treasury_vault",
  charter: "charter",
  emergency: "emergency",
  capability_vault: "capability_vault",
  board_voting: "board_voting",
  governance: "governance",
  controller: "controller",
} as const;

/** armature_proposals modules */
export const PROPOSAL_MODULES = {
  send_coin: "send_coin",
  send_coin_to_dao: "send_coin_to_dao",
  send_small_payment: "send_small_payment",
  set_board: "set_board",
  update_metadata: "update_metadata",
  enable_proposal_type: "enable_proposal_type",
  disable_proposal_type: "disable_proposal_type",
  update_proposal_config: "update_proposal_config",
  transfer_freeze_admin: "transfer_freeze_admin",
  unfreeze_proposal_type: "unfreeze_proposal_type",
  update_freeze_config: "update_freeze_config",
  update_freeze_exempt_types: "update_freeze_exempt_types",
  create_subdao: "create_subdao",
  pause_execution: "pause_execution",
  reclaim_cap_from_subdao: "reclaim_cap_from_subdao",
  spawn_dao: "spawn_dao",
  spin_out_subdao: "spin_out_subdao",
  transfer_assets: "transfer_assets",
  transfer_cap_to_subdao: "transfer_cap_to_subdao",
  propose_upgrade: "propose_upgrade",
  // ops (execution handlers)
  treasury_ops: "treasury_ops",
  admin_ops: "admin_ops",
  board_ops: "board_ops",
  security_ops: "security_ops",
  subdao_ops: "subdao_ops",
  upgrade_ops: "upgrade_ops",
} as const;

/**
 * On-chain package and module identifiers.
 * Update PACKAGE_ID after each publish/upgrade.
 */
export const PACKAGE_ID =
  import.meta.env.VITE_PACKAGE_ID ??
  "0x0000000000000000000000000000000000000000000000000000000000000000";

export const MODULES = {
  dao: "dao",
  proposal: "proposal",
  treasury_vault: "treasury_vault",
  charter: "charter",
  emergency: "emergency",
  capability_vault: "capability_vault",
  board_voting: "board_voting",
} as const;

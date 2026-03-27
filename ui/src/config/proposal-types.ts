/** Central registry of all known proposal types in the Armature framework. */

export type ProposalTypeCategory = {
  label: string;
  types: ProposalTypeDef[];
};

export type ProposalTypeDef = {
  key: string;
  label: string;
  description: string;
};

export const PROPOSAL_TYPE_CATEGORIES: ProposalTypeCategory[] = [
  {
    label: "Board & Governance",
    types: [
      {
        key: "SetBoard",
        label: "Set Board",
        description: "Replace the current board member list",
      },
      {
        key: "EnableProposalType",
        label: "Enable Proposal Type",
        description: "Enable a new proposal type with voting config",
      },
      {
        key: "DisableProposalType",
        label: "Disable Proposal Type",
        description: "Disable an existing proposal type",
      },
      {
        key: "UpdateProposalConfig",
        label: "Update Proposal Config",
        description:
          "Change quorum, threshold, or timing for a proposal type",
      },
    ],
  },
  {
    label: "Treasury",
    types: [
      {
        key: "TreasuryWithdraw",
        label: "Treasury Withdraw",
        description: "Send coins from the treasury to a recipient",
      },
      {
        key: "SendCoinToDAO",
        label: "Send Coin to DAO",
        description: "Transfer coins from treasury to another DAO's treasury",
      },
      {
        key: "SendSmallPayment",
        label: "Send Small Payment",
        description: "Rate-limited small payment from treasury",
      },
    ],
  },
  {
    label: "Charter",
    types: [
      {
        key: "CharterUpdate",
        label: "Amend Charter",
        description:
          "Update the DAO charter name, description, or image",
      },
    ],
  },
  {
    label: "Security",
    types: [
      {
        key: "TransferFreezeAdmin",
        label: "Transfer Freeze Admin",
        description: "Transfer the freeze admin capability",
      },
      {
        key: "UnfreezeProposalType",
        label: "Unfreeze Proposal Type",
        description: "Governance-driven unfreeze of a proposal type",
      },
      {
        key: "UpdateFreezeConfig",
        label: "Update Freeze Config",
        description: "Change the maximum freeze duration",
      },
      {
        key: "UpdateFreezeExemptTypes",
        label: "Update Freeze-Exempt Types",
        description: "Add or remove types from the freeze-exempt set",
      },
    ],
  },
  {
    label: "SubDAO",
    types: [
      {
        key: "CreateSubDAO",
        label: "Create SubDAO",
        description: "Create a new controlled SubDAO",
      },
      {
        key: "SpinOutSubDAO",
        label: "Spin Out SubDAO",
        description: "Release a SubDAO from parent control",
      },
      {
        key: "SpawnDAO",
        label: "Spawn DAO",
        description: "Create an independent DAO via migration",
      },
      {
        key: "TransferCapToSubDAO",
        label: "Transfer Cap to SubDAO",
        description: "Transfer a capability from DAO vault to SubDAO vault",
      },
      {
        key: "ReclaimCapFromSubDAO",
        label: "Reclaim Cap from SubDAO",
        description: "Reclaim a capability from a SubDAO's vault",
      },
      {
        key: "PauseSubDAOExecution",
        label: "Pause SubDAO Execution",
        description: "Pause proposal execution on a SubDAO",
      },
      {
        key: "UnpauseSubDAOExecution",
        label: "Unpause SubDAO Execution",
        description: "Resume proposal execution on a SubDAO",
      },
      {
        key: "TransferAssets",
        label: "Transfer Assets",
        description: "Transfer coins and capabilities to another DAO",
      },
    ],
  },
  {
    label: "Upgrade",
    types: [
      {
        key: "ProposeUpgrade",
        label: "Propose Upgrade",
        description: "Authorize a package upgrade using a stored UpgradeCap",
      },
    ],
  },
];

/** Flat list of all proposal type keys. */
export const ALL_PROPOSAL_TYPE_KEYS: string[] =
  PROPOSAL_TYPE_CATEGORIES.flatMap((cat) => cat.types.map((t) => t.key));

/** Map of type key → ProposalTypeDef for quick lookups. */
export const PROPOSAL_TYPE_MAP: Record<string, ProposalTypeDef> =
  Object.fromEntries(
    PROPOSAL_TYPE_CATEGORIES.flatMap((cat) =>
      cat.types.map((t) => [t.key, t]),
    ),
  );

/** Union of every known proposal type key. Add new keys here to enforce display-name coverage. */
export type KnownProposalTypeKey =
  | "SetBoard"
  | "EnableProposalType"
  | "DisableProposalType"
  | "UpdateProposalConfig"
  | "TreasuryWithdraw"
  | "SendCoinToDAO"
  | "SendSmallPayment"
  | "CharterUpdate"
  | "TransferFreezeAdmin"
  | "UnfreezeProposalType"
  | "UpdateFreezeConfig"
  | "UpdateFreezeExemptTypes"
  | "CreateSubDAO"
  | "SpinOutSubDAO"
  | "SpawnDAO"
  | "TransferCapToSubDAO"
  | "ReclaimCapFromSubDAO"
  | "PauseSubDAOExecution"
  | "UnpauseSubDAOExecution"
  | "TransferAssets"
  | "ProposeUpgrade";

/**
 * User-readable display titles for each proposal type.
 * Typed as `Record<KnownProposalTypeKey, string>` via `satisfies` so TypeScript
 * will error if any key is missing — add a new type key above and you must
 * add its label here too.
 */
export const PROPOSAL_TYPE_DISPLAY_NAME = {
  SetBoard: "Set Board",
  EnableProposalType: "Enable Proposal Type",
  DisableProposalType: "Disable Proposal Type",
  UpdateProposalConfig: "Update Governance Config",
  TreasuryWithdraw: "Send from Treasury",
  SendCoinToDAO: "Send to DAO Treasury",
  SendSmallPayment: "Small Treasury Payment",
  CharterUpdate: "Amend Charter",
  TransferFreezeAdmin: "Transfer Freeze Admin",
  UnfreezeProposalType: "Unfreeze Proposal Type",
  UpdateFreezeConfig: "Update Freeze Config",
  UpdateFreezeExemptTypes: "Update Freeze-Exempt Types",
  CreateSubDAO: "Create SubDAO",
  SpinOutSubDAO: "Spin Out SubDAO",
  SpawnDAO: "Spawn DAO",
  TransferCapToSubDAO: "Transfer Cap to SubDAO",
  ReclaimCapFromSubDAO: "Reclaim Cap from SubDAO",
  PauseSubDAOExecution: "Pause SubDAO Execution",
  UnpauseSubDAOExecution: "Unpause SubDAO Execution",
  TransferAssets: "Transfer Assets",
  ProposeUpgrade: "Propose Upgrade",
} as const satisfies Record<KnownProposalTypeKey, string>;

/** Tier classification: determines which form to render. */
export type ProposalTier = "tier1" | "tier2" | "wizard";

export const PROPOSAL_TYPE_TIER: Record<string, ProposalTier> = {
  // Tier 1 — generic form (simple fields)
  DisableProposalType: "tier1",
  TransferFreezeAdmin: "tier1",
  UnfreezeProposalType: "tier1",
  SpinOutSubDAO: "tier1",
  SpawnDAO: "tier1",
  UpdateFreezeConfig: "tier1",
  UpdateFreezeExemptTypes: "tier1",
  TransferCapToSubDAO: "tier1",
  ReclaimCapFromSubDAO: "tier1",
  ProposeUpgrade: "tier1",
  PauseSubDAOExecution: "tier1",
  UnpauseSubDAOExecution: "tier1",
  TransferAssets: "tier1",

  // Tier 2 — custom forms
  TreasuryWithdraw: "tier2",
  SendCoinToDAO: "tier2",
  SendSmallPayment: "tier2",
  SetBoard: "tier2",
  EnableProposalType: "tier2",
  UpdateProposalConfig: "tier2",
  CharterUpdate: "tier2",

  // Wizard
  CreateSubDAO: "wizard",
};

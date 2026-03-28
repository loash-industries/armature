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
export const PROPOSAL_TYPE_DISPLAY_NAME: Record<KnownProposalTypeKey, string> = {
  SetBoard: "Set Board",
  EnableProposalType: "Enable Action",
  DisableProposalType: "Disable Action",
  UpdateProposalConfig: "Update Action Settings",
  TreasuryWithdraw: "Send from Treasury",
  SendCoinToDAO: "Send to Organization or OU Treasury",
  SendSmallPayment: "Small Treasury Payment",
  CharterUpdate: "Amend Charter",
  TransferFreezeAdmin: "Transfer Freeze Admin",
  UnfreezeProposalType: "Unfreeze Action",
  UpdateFreezeConfig: "Update Freeze Config",
  UpdateFreezeExemptTypes: "Update Freeze-Exempt Types",
  CreateSubDAO: "Create Organizational Unit",
  SpinOutSubDAO: "Spin Out Organizational Unit",
  SpawnDAO: "Spawn New Organization",
  TransferCapToSubDAO: "Transfer Cap to Organizational Unit",
  ReclaimCapFromSubDAO: "Reclaim Cap from Organizational Unit",
  PauseSubDAOExecution: "Pause Organizational Unit Execution",
  UnpauseSubDAOExecution: "Unpause Organizational Unit Execution",
  TransferAssets: "Transfer Assets",
  ProposeUpgrade: "Propose Upgrade",
}

export const PROPOSAL_TYPE_CATEGORIES: ProposalTypeCategory[] = [
  {
    label: "Board & Governance",
    types: [
      {
        key: "SetBoard",
        label: PROPOSAL_TYPE_DISPLAY_NAME["SetBoard"],
        description: "Replace the current board member list",
      },
      {
        key: "EnableProposalType",
        label: PROPOSAL_TYPE_DISPLAY_NAME["EnableProposalType"],
        description: "Enable a new type of action for this organization",
      },
      {
        key: "DisableProposalType",
        label: PROPOSAL_TYPE_DISPLAY_NAME["DisableProposalType"],
        description: "Disable an existing proposal type",
      },
      {
        key: "UpdateProposalConfig",
        label: PROPOSAL_TYPE_DISPLAY_NAME["UpdateProposalConfig"],
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
        label: PROPOSAL_TYPE_DISPLAY_NAME["TreasuryWithdraw"],
        description: "Send coins from the treasury to a recipient",
      },
      {
        key: "SendCoinToDAO",
        label: PROPOSAL_TYPE_DISPLAY_NAME["SendCoinToDAO"],
        description: "Transfer coins from treasury to another DAO's treasury",
      },
      {
        key: "SendSmallPayment",
        label: PROPOSAL_TYPE_DISPLAY_NAME["SendSmallPayment"],
        description: "Rate-limited small payment from treasury",
      },
    ],
  },
  {
    label: "Charter",
    types: [
      {
        key: "CharterUpdate",
        label: PROPOSAL_TYPE_DISPLAY_NAME["CharterUpdate"],
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
        label: PROPOSAL_TYPE_DISPLAY_NAME["TransferFreezeAdmin"],
        description: "Transfer the freeze admin capability",
      },
      {
        key: "UnfreezeProposalType",
        label: PROPOSAL_TYPE_DISPLAY_NAME["UnfreezeProposalType"],
        description: "Governance-driven unfreeze of a proposal type",
      },
      {
        key: "UpdateFreezeConfig",
        label: PROPOSAL_TYPE_DISPLAY_NAME["UpdateFreezeConfig"],
        description: "Change the maximum freeze duration",
      },
      {
        key: "UpdateFreezeExemptTypes",
        label: PROPOSAL_TYPE_DISPLAY_NAME["UpdateFreezeExemptTypes"],
        description: "Add or remove types from the freeze-exempt set",
      },
    ],
  },
  {
    label: "SubDAO",
    types: [
      {
        key: "CreateSubDAO",
        label: PROPOSAL_TYPE_DISPLAY_NAME["CreateSubDAO"],
        description: "Create a new controlled SubDAO",
      },
      {
        key: "SpinOutSubDAO",
        label: PROPOSAL_TYPE_DISPLAY_NAME["SpinOutSubDAO"],
        description: "Release a SubDAO from parent control",
      },
      {
        key: "SpawnDAO",
        label: PROPOSAL_TYPE_DISPLAY_NAME["SpawnDAO"],
        description: "Create an independent DAO via migration",
      },
      {
        key: "TransferCapToSubDAO",
        label: PROPOSAL_TYPE_DISPLAY_NAME["TransferCapToSubDAO"],
        description: "Transfer a capability from DAO vault to SubDAO vault",
      },
      {
        key: "ReclaimCapFromSubDAO",
        label: PROPOSAL_TYPE_DISPLAY_NAME["ReclaimCapFromSubDAO"],
        description: "Reclaim a capability from a SubDAO's vault",
      },
      {
        key: "PauseSubDAOExecution",
        label: PROPOSAL_TYPE_DISPLAY_NAME["PauseSubDAOExecution"],
        description: "Pause proposal execution on a SubDAO",
      },
      {
        key: "UnpauseSubDAOExecution",
        label: PROPOSAL_TYPE_DISPLAY_NAME["UnpauseSubDAOExecution"],
        description: "Resume proposal execution on a SubDAO",
      },
      {
        key: "TransferAssets",
        label: PROPOSAL_TYPE_DISPLAY_NAME["TransferAssets"],
        description: "Transfer coins and capabilities to another DAO",
      },
    ],
  },
  {
    label: "Upgrade",
    types: [
      {
        key: "ProposeUpgrade",
        label: PROPOSAL_TYPE_DISPLAY_NAME["ProposeUpgrade"],
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

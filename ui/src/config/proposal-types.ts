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
    ],
  },
  {
    label: "Capabilities",
    types: [
      {
        key: "CapabilityExtract",
        label: "Extract Capability",
        description: "Extract a capability from the vault",
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
        key: "EmergencyFreeze",
        label: "Emergency Freeze",
        description: "Freeze one or more proposal types",
      },
      {
        key: "EmergencyUnfreeze",
        label: "Emergency Unfreeze",
        description: "Unfreeze a previously frozen proposal type",
      },
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
  EmergencyFreeze: "tier1",
  EmergencyUnfreeze: "tier1",
  CapabilityExtract: "tier1",
  SpawnDAO: "tier1",

  // Tier 2 — custom forms
  TreasuryWithdraw: "tier2",
  SetBoard: "tier2",
  EnableProposalType: "tier2",
  UpdateProposalConfig: "tier2",
  CharterUpdate: "tier2",

  // Wizard
  CreateSubDAO: "wizard",
};

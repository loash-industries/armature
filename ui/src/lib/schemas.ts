import { z } from "zod";

const suiAddress = z
  .string()
  .regex(/^0x[a-fA-F0-9]{64}$/, "Must be a valid Sui address (0x + 64 hex)");

const suiObjectId = suiAddress;

const metadataIpfs = z.string();

/** Shared proposal config schema (quorum, threshold, etc.). */
export const proposalConfigSchema = z.object({
  quorum: z
    .number()
    .min(0.01, "Quorum must be at least 0.01%")
    .max(100, "Quorum cannot exceed 100%"),
  approvalThreshold: z
    .number()
    .min(0.01, "Threshold must be at least 0.01%")
    .max(100, "Threshold cannot exceed 100%"),
  proposeThreshold: z.number().int().min(0),
  expiryMs: z.number().int().min(1, "Minimum voting period is 1 hour"),
  executionDelayMs: z.number().int().min(0),
  cooldownMs: z.number().int().min(0),
});

// --- Tier 1 schemas ---

export const disableProposalTypeSchema = z.object({
  typeKey: z.string().min(1, "Select a type to disable"),
  metadataIpfs,
});

export const transferFreezeAdminSchema = z.object({
  recipient: suiAddress,
  metadataIpfs,
});

export const unfreezeProposalTypeSchema = z.object({
  typeKey: z.string().min(1, "Select a type to unfreeze"),
  metadataIpfs,
});

export const spinOutSubDAOSchema = z.object({
  subDaoId: suiObjectId,
  metadataIpfs,
});

export const spawnDAOSchema = z.object({
  name: z.string().min(1, "DAO name is required"),
  description: z.string().min(1, "Description is required"),
  metadataIpfs,
});

export const updateFreezeConfigSchema = z.object({
  newMaxFreezeDurationMs: z
    .string()
    .min(1, "Duration is required"),
  metadataIpfs,
});

export const updateFreezeExemptTypesSchema = z.object({
  typesToAdd: z.string(),
  typesToRemove: z.string(),
  metadataIpfs,
});

export const transferCapToSubDAOSchema = z.object({
  capId: suiObjectId,
  targetSubdao: suiObjectId,
  metadataIpfs,
});

export const reclaimCapFromSubDAOSchema = z.object({
  subdaoId: suiObjectId,
  capId: suiObjectId,
  controlId: suiObjectId,
  metadataIpfs,
});

export const proposeUpgradeSchema = z.object({
  capId: suiObjectId,
  packageId: suiObjectId,
  digest: z.string().min(1, "Digest is required"),
  policy: z.number().int().min(0).max(255),
  metadataIpfs,
});

export const pauseSubDAOExecutionSchema = z.object({
  controlId: suiObjectId,
  metadataIpfs,
});

export const unpauseSubDAOExecutionSchema = z.object({
  controlId: suiObjectId,
  metadataIpfs,
});

export const transferAssetsSchema = z.object({
  targetDaoId: suiObjectId,
  targetTreasuryId: suiObjectId,
  targetVaultId: suiObjectId,
  coinTypes: z.string(),
  capIds: z.string(),
  metadataIpfs,
});

// --- Tier 2 schemas ---

export const treasuryWithdrawSchema = z.object({
  coinType: z.string().min(1, "Select a currency"),
  amount: z.string().min(1, "Amount is required"),
  recipient: suiAddress,
  metadataIpfs,
});

export const sendCoinToDAOSchema = z.object({
  recipientTreasuryId: suiObjectId,
  amount: z.string().min(1, "Amount is required"),
  coinType: z.string().min(1, "Select a currency"),
  metadataIpfs,
});

export const sendSmallPaymentSchema = z.object({
  recipient: suiAddress,
  amount: z.string().min(1, "Amount is required"),
  coinType: z.string().min(1, "Select a currency"),
  metadataIpfs,
});

export const setBoardSchema = z.object({
  members: z
    .array(suiAddress)
    .min(1, "At least one board member is required"),
  metadataIpfs,
});

export const enableProposalTypeSchema = z.object({
  typeKey: z.string().min(1, "Select a proposal type"),
  config: proposalConfigSchema,
  metadataIpfs,
});

export const updateProposalConfigSchema = z.object({
  typeKey: z.string().min(1, "Select a proposal type"),
  config: proposalConfigSchema,
  metadataIpfs,
});

export const charterUpdateSchema = z.object({
  name: z.string().min(1, "Charter name is required"),
  description: z.string().min(1, "Charter description is required"),
  imageUrl: z.string(),
  metadataIpfs,
});

// --- Wizard schema ---

export const createSubDAOSchema = z.object({
  name: z.string().min(1, "SubDAO name is required"),
  metadataIpfs,
  board: z
    .array(suiAddress)
    .min(1, "At least one board member is required"),
  charterName: z.string().min(1, "Charter name is required"),
  charterDescription: z.string().min(1, "Charter description is required"),
  charterImageUrl: z.string(),
  proposalTypes: z
    .array(
      z.object({
        typeKey: z.string().min(1),
        config: proposalConfigSchema,
      }),
    )
    .min(1, "At least one proposal type must be enabled"),
  fundingAmount: z.string(),
});

/** Map of type key → zod schema. */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export const PROPOSAL_SCHEMAS: Record<string, z.ZodObject<any>> = {
  DisableProposalType: disableProposalTypeSchema,
  TransferFreezeAdmin: transferFreezeAdminSchema,
  UnfreezeProposalType: unfreezeProposalTypeSchema,
  SpinOutSubDAO: spinOutSubDAOSchema,
  SpawnDAO: spawnDAOSchema,
  UpdateFreezeConfig: updateFreezeConfigSchema,
  UpdateFreezeExemptTypes: updateFreezeExemptTypesSchema,
  TransferCapToSubDAO: transferCapToSubDAOSchema,
  ReclaimCapFromSubDAO: reclaimCapFromSubDAOSchema,
  ProposeUpgrade: proposeUpgradeSchema,
  TreasuryWithdraw: treasuryWithdrawSchema,
  SendCoinToDAO: sendCoinToDAOSchema,
  SendSmallPayment: sendSmallPaymentSchema,
  SetBoard: setBoardSchema,
  EnableProposalType: enableProposalTypeSchema,
  UpdateProposalConfig: updateProposalConfigSchema,
  CharterUpdate: charterUpdateSchema,
  CreateSubDAO: createSubDAOSchema,
  PauseSubDAOExecution: pauseSubDAOExecutionSchema,
  UnpauseSubDAOExecution: unpauseSubDAOExecutionSchema,
  TransferAssets: transferAssetsSchema,
};

import { useState } from "react";
import { useNavigate } from "@tanstack/react-router";
import { useQueryClient } from "@tanstack/react-query";
import { useSuiClient } from "@mysten/dapp-kit";
import { toast } from "sonner";
import { useWalletSigner } from "@/hooks/useWalletSigner";
import { cacheKeys } from "@/lib/cache-keys";
import {
  buildSubmitSetBoard,
  buildSubmitSendCoin,
  buildSubmitUpdateMetadata,
  buildSubmitEnableProposalType,
  buildSubmitDisableProposalType,
  buildSubmitUpdateProposalConfig,
  buildSubmitTransferFreezeAdmin,
  buildSubmitUnfreezeProposalType,
  buildSubmitCreateSubDAO,
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
  buildSubmitTransferAssets,
} from "@/lib/transactions";
import type {
  SetBoardPayload,
  TreasuryWithdrawPayload,
  CharterUpdatePayload,
  EnableProposalTypePayload,
  DisableProposalTypePayload,
  UpdateProposalConfigPayload,
  TransferFreezeAdminPayload,
  UnfreezeProposalTypePayload,
  CreateSubDAOPayload,
  SendCoinToDAOPayload,
  SendSmallPaymentPayload,
  UpdateFreezeConfigPayload,
  UpdateFreezeExemptTypesPayload,
  TransferCapToSubDAOPayload,
  ReclaimCapFromSubDAOPayload,
  ProposeUpgradePayload,
  SpawnDAOPayload,
  SpinOutSubDAOPayload,
  PauseSubDAOExecutionPayload,
  UnpauseSubDAOExecutionPayload,
  TransferAssetsPayload,
} from "@/types/proposal";
import type { Transaction } from "@mysten/sui/transactions";

const NOT_IMPLEMENTED_TYPES = new Set<string>([]);

function buildTransaction(
  typeKey: string,
  data: unknown,
  daoId: string,
): Transaction | null {
  switch (typeKey) {
    case "SetBoard": {
      const d = data as SetBoardPayload;
      return buildSubmitSetBoard({
        daoId,
        newMembers: d.members,
        metadataIpfs: d.metadataIpfs,
      });
    }
    case "TreasuryWithdraw": {
      const d = data as TreasuryWithdrawPayload;
      return buildSubmitSendCoin({
        daoId,
        recipient: d.recipient,
        amount: d.amount,
        coinType: d.coinType,
        metadataIpfs: d.metadataIpfs,
      });
    }
    case "CharterUpdate": {
      const d = data as CharterUpdatePayload;
      return buildSubmitUpdateMetadata({
        daoId,
        newIpfsCid: d.metadataIpfs,
        metadataIpfs: d.metadataIpfs,
      });
    }
    case "EnableProposalType": {
      const d = data as EnableProposalTypePayload;
      return buildSubmitEnableProposalType({
        daoId,
        typeKey: d.typeKey,
        quorum: d.config.quorum,
        approvalThreshold: d.config.approvalThreshold,
        proposeThreshold: String(d.config.proposeThreshold),
        expiryMs: String(d.config.expiryMs),
        executionDelayMs: String(d.config.executionDelayMs),
        cooldownMs: String(d.config.cooldownMs),
        metadataIpfs: d.metadataIpfs,
      });
    }
    case "DisableProposalType": {
      const d = data as DisableProposalTypePayload;
      return buildSubmitDisableProposalType({
        daoId,
        typeKey: d.typeKey,
        metadataIpfs: d.metadataIpfs,
      });
    }
    case "UpdateProposalConfig": {
      const d = data as UpdateProposalConfigPayload;
      return buildSubmitUpdateProposalConfig({
        daoId,
        targetTypeKey: d.typeKey,
        quorum: d.config.quorum,
        approvalThreshold: d.config.approvalThreshold,
        proposeThreshold: String(d.config.proposeThreshold),
        expiryMs: String(d.config.expiryMs),
        executionDelayMs: String(d.config.executionDelayMs),
        cooldownMs: String(d.config.cooldownMs),
        metadataIpfs: d.metadataIpfs,
      });
    }
    case "TransferFreezeAdmin": {
      const d = data as TransferFreezeAdminPayload;
      return buildSubmitTransferFreezeAdmin({
        daoId,
        newAdmin: d.recipient,
        metadataIpfs: d.metadataIpfs,
      });
    }
    case "UnfreezeProposalType": {
      const d = data as UnfreezeProposalTypePayload;
      return buildSubmitUnfreezeProposalType({
        daoId,
        typeKey: d.typeKey,
        metadataIpfs: d.metadataIpfs,
      });
    }
    case "CreateSubDAO": {
      const d = data as CreateSubDAOPayload;
      return buildSubmitCreateSubDAO({
        daoId,
        name: d.name,
        description: d.charterDescription,
        initialBoard: d.board.filter(Boolean),
        metadataIpfs: d.metadataIpfs,
      });
    }
    case "SendCoinToDAO": {
      const d = data as SendCoinToDAOPayload;
      return buildSubmitSendCoinToDAO({
        daoId,
        recipientTreasuryId: d.recipientTreasuryId,
        amount: d.amount,
        coinType: d.coinType,
        metadataIpfs: d.metadataIpfs,
      });
    }
    case "SendSmallPayment": {
      const d = data as SendSmallPaymentPayload;
      return buildSubmitSendSmallPayment({
        daoId,
        recipient: d.recipient,
        amount: d.amount,
        coinType: d.coinType,
        metadataIpfs: d.metadataIpfs,
      });
    }
    case "UpdateFreezeConfig": {
      const d = data as UpdateFreezeConfigPayload;
      return buildSubmitUpdateFreezeConfig({
        daoId,
        newMaxFreezeDurationMs: d.newMaxFreezeDurationMs,
        metadataIpfs: d.metadataIpfs,
      });
    }
    case "UpdateFreezeExemptTypes": {
      const d = data as UpdateFreezeExemptTypesPayload;
      const typesToAdd = d.typesToAdd.split(",").map((s) => s.trim()).filter(Boolean);
      const typesToRemove = d.typesToRemove.split(",").map((s) => s.trim()).filter(Boolean);
      return buildSubmitUpdateFreezeExemptTypes({
        daoId,
        typesToAdd,
        typesToRemove,
        metadataIpfs: d.metadataIpfs,
      });
    }
    case "TransferCapToSubDAO": {
      const d = data as TransferCapToSubDAOPayload;
      return buildSubmitTransferCapToSubDAO({
        daoId,
        capId: d.capId,
        targetSubdao: d.targetSubdao,
        metadataIpfs: d.metadataIpfs,
      });
    }
    case "ReclaimCapFromSubDAO": {
      const d = data as ReclaimCapFromSubDAOPayload;
      return buildSubmitReclaimCapFromSubDAO({
        daoId,
        subdaoId: d.subdaoId,
        capId: d.capId,
        controlId: d.controlId,
        metadataIpfs: d.metadataIpfs,
      });
    }
    case "ProposeUpgrade": {
      const d = data as ProposeUpgradePayload;
      return buildSubmitProposeUpgrade({
        daoId,
        capId: d.capId,
        packageId: d.packageId,
        digest: d.digest,
        policy: d.policy,
        metadataIpfs: d.metadataIpfs,
      });
    }
    case "SpawnDAO": {
      const d = data as SpawnDAOPayload;
      return buildSubmitSpawnDAO({
        daoId,
        name: d.name,
        description: d.description,
        metadataIpfs: d.metadataIpfs,
      });
    }
    case "SpinOutSubDAO": {
      const d = data as SpinOutSubDAOPayload;
      return buildSubmitSpinOutSubDAO({
        daoId,
        subDaoId: d.subDaoId,
        metadataIpfs: d.metadataIpfs,
      });
    }
    case "PauseSubDAOExecution": {
      const d = data as PauseSubDAOExecutionPayload;
      return buildSubmitPauseSubDAOExecution({
        daoId,
        controlId: d.controlId,
        metadataIpfs: d.metadataIpfs,
      });
    }
    case "UnpauseSubDAOExecution": {
      const d = data as UnpauseSubDAOExecutionPayload;
      return buildSubmitUnpauseSubDAOExecution({
        daoId,
        controlId: d.controlId,
        metadataIpfs: d.metadataIpfs,
      });
    }
    case "TransferAssets": {
      const d = data as TransferAssetsPayload;
      const coinTypes = d.coinTypes.split(",").map((s) => s.trim()).filter(Boolean);
      const capIds = d.capIds.split(",").map((s) => s.trim()).filter(Boolean);
      return buildSubmitTransferAssets({
        daoId,
        targetDaoId: d.targetDaoId,
        targetTreasuryId: d.targetTreasuryId,
        targetVaultId: d.targetVaultId,
        coinTypes,
        capIds,
        metadataIpfs: d.metadataIpfs,
      });
    }
    default:
      return null;
  }
}

export function useSubmitProposal(daoId: string) {
  const client = useSuiClient();
  const { signAndExecuteTransaction } = useWalletSigner();
  const queryClient = useQueryClient();
  const navigate = useNavigate();
  const [isPending, setIsPending] = useState(false);

  async function submitProposal(typeKey: string, data: unknown) {
    if (NOT_IMPLEMENTED_TYPES.has(typeKey)) {
      toast.info(`${typeKey} is not yet implemented`);
      return;
    }

    const transaction = buildTransaction(typeKey, data, daoId);
    if (!transaction) {
      toast.error(`Unknown proposal type: ${typeKey}`);
      return;
    }

    setIsPending(true);
    try {
      const result = await signAndExecuteTransaction({ transaction });
      toast.success("Proposal created");
      await queryClient.invalidateQueries({
        queryKey: cacheKeys.proposals(daoId),
      });

      // Extract proposal ID from transaction events to redirect to detail page
      let proposalId: string | null = null;
      try {
        const txDetail = await client.waitForTransaction({
          digest: result.digest,
          options: { showEvents: true },
        });
        const createdEvent = txDetail.events?.find((e) =>
          e.type.endsWith("::ProposalCreated"),
        );
        if (createdEvent) {
          const parsed = createdEvent.parsedJson as Record<string, unknown>;
          proposalId = (parsed.proposal_id as string) ?? null;
        }
      } catch {
        // Fall back to proposals list if event extraction fails
      }

      if (proposalId) {
        navigate({
          to: "/dao/$daoId/proposals/$proposalId",
          params: { daoId, proposalId },
        });
      } else {
        navigate({
          to: "/dao/$daoId/proposals",
          params: { daoId },
        });
      }
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Transaction failed");
    } finally {
      setIsPending(false);
    }
  }

  return { submitProposal, isPending };
}

import { useState, useEffect } from "react";
import { useParams, useNavigate } from "@tanstack/react-router";
import { useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardHeader,
  CardTitle,
  CardDescription,
  CardContent,
} from "@/components/ui/card";
import { Separator } from "@/components/ui/separator";
import { Skeleton } from "@/components/ui/skeleton";
import { useSuiClient } from "@mysten/dapp-kit";
import { useProposal } from "@/hooks/useProposals";
import { useWalletSigner } from "@/hooks/useWalletSigner";
import { useDaoSummary, useGovernanceDetail } from "@/hooks/useDao";
import { useFreezeAdminCap } from "@/hooks/useFreezeAdminCap";
import {
  buildVote,
  buildTryExpire,
  buildExecuteSetBoard,
  buildExecuteUpdateMetadata,
  buildExecuteSendCoin,
  buildExecuteDisableProposalType,
  buildExecuteEnableProposalType,
  buildExecuteUpdateProposalConfig,
  buildExecuteUnfreezeProposalType,
  buildExecuteCreateSubDAO,
  buildExecuteTransferFreezeAdmin,
  buildExecuteUpdateFreezeConfig,
  buildExecuteUpdateFreezeExemptTypes,
  buildExecuteSendSmallPayment,
  buildExecuteSpawnDAO,
  buildExecuteSendCoinToDAO,
  buildExecuteSpinOutSubDAO,
  buildExecutePauseSubDAOExecution,
  buildExecuteUnpauseSubDAOExecution,
  buildExecuteTransferCapToSubDAO,
  buildExecuteReclaimCap,
} from "@/lib/transactions";
import { cacheKeys } from "@/lib/cache-keys";
import { PROPOSAL_TYPE_MAP } from "@/config/proposal-types";
import { PayloadSummary } from "@/components/proposals/PayloadSummary";
import { useCharacterNames } from "@/hooks/useCharacterNames";
import { getAddressName } from "@/lib/address-namer";

function formatBps(bps: number): string {
  return `${(bps / 100).toFixed(2)}%`;
}

function formatDate(ms: number): string {
  return new Date(ms).toLocaleString();
}

function Countdown({ targetMs }: { targetMs: number }) {
  const [now, setNow] = useState(() => Date.now());

  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), 60_000);
    return () => clearInterval(id);
  }, []);

  const diff = targetMs - now;
  if (diff <= 0) return <span className="text-muted-foreground">Ended</span>;

  const hours = Math.floor(diff / 3600000);
  const mins = Math.floor((diff % 3600000) / 60000);
  if (hours > 24) {
    const days = Math.floor(hours / 24);
    return (
      <span className="font-mono">
        {days}d {hours % 24}h remaining
      </span>
    );
  }
  return (
    <span className="font-mono">
      {hours}h {mins}m remaining
    </span>
  );
}

/** Execution-time approval floors enforced by admin_ops (basis points). */
const ENABLE_APPROVAL_FLOOR_BPS = 6_600;
const SELF_UPDATE_APPROVAL_FLOOR_BPS = 8_000;

/**
 * Returns the hardcoded execution-time approval floor (bps) for proposal types
 * that enforce one in admin_ops, or null if no floor applies.
 *
 * EnableProposalType:        66% of total_snapshot_weight
 * UpdateProposalConfig self: 80% of total_snapshot_weight
 */
function getApprovalFloorBps(
  typeKey: string,
  payload: Record<string, unknown> | undefined,
): number | null {
  if (typeKey === "EnableProposalType") return ENABLE_APPROVAL_FLOOR_BPS;
  if (typeKey === "UpdateProposalConfig") {
    const targetKey = String(payload?.target_type_key ?? "");
    if (targetKey === "UpdateProposalConfig") return SELF_UPDATE_APPROVAL_FLOOR_BPS;
  }
  return null;
}

function statusVariant(
  status: string,
): "default" | "secondary" | "destructive" | "outline" {
  const map: Record<
    string,
    "default" | "secondary" | "destructive" | "outline"
  > = {
    active: "default",
    passed: "outline",
    executed: "secondary",
    expired: "destructive",
  };
  return map[status] ?? "outline";
}

export function ProposalDetail() {
  const { proposalId, daoId } = useParams({ strict: false });
  const navigate = useNavigate();
  const { data: proposal, isLoading } = useProposal(proposalId ?? "");
  const { data: daoSummary } = useDaoSummary(daoId ?? "");
  const { data: governance } = useGovernanceDetail(daoId ?? "");
  const { data: freezeAdminCapId } = useFreezeAdminCap(daoId ?? "");
  const client = useSuiClient();
  const { address, signAndExecuteTransaction } = useWalletSigner();
  const queryClient = useQueryClient();
  const [actionPending, setActionPending] = useState<string | null>(null);
  const hasVoted = proposal && address ? address in proposal.votesCast : false;
  const priorVote = proposal && address ? proposal.votesCast[address] : undefined;
  const isMember = governance?.members.some(m => m.address === address) ?? false;
  const { data: proposerNameMap } = useCharacterNames(
    proposal?.proposer ? [proposal.proposer] : [],
  );
  const proposerName = proposal ? (proposerNameMap?.get(proposal.proposer) ?? null) : null;

  async function handleVote(approve: boolean) {
    if (!proposal?.payloadType) {
      toast.error("Cannot determine proposal type for voting");
      return;
    }
    setActionPending(approve ? "yes" : "no");
    try {
      const transaction = buildVote({
        proposalId: proposal.id,
        approve,
        proposalType: proposal.payloadType,
      });
      const result = await signAndExecuteTransaction({ transaction });
      toast.success(approve ? "Voted Yes" : "Voted No");
      await client.waitForTransaction({ digest: result.digest });
      await queryClient.invalidateQueries({
        queryKey: cacheKeys.proposal(proposal.id),
      });
      if (daoId) {
        await queryClient.invalidateQueries({
          queryKey: cacheKeys.proposals(daoId),
        });
      }
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Vote failed");
    } finally {
      setActionPending(null);
    }
  }

  async function handleExpire() {
    if (!proposal?.payloadType) {
      toast.error("Cannot determine proposal type");
      return;
    }
    setActionPending("expire");
    try {
      const transaction = buildTryExpire({
        proposalId: proposal.id,
        proposalType: proposal.payloadType,
      });
      const result = await signAndExecuteTransaction({ transaction });
      toast.success("Proposal marked as expired");
      await client.waitForTransaction({ digest: result.digest });
      await queryClient.invalidateQueries({
        queryKey: cacheKeys.proposal(proposal.id),
      });
      if (daoId) {
        await queryClient.invalidateQueries({
          queryKey: cacheKeys.proposals(daoId),
        });
      }
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Expire failed");
    } finally {
      setActionPending(null);
    }
  }

  function buildExecuteTransaction() {
    if (!proposal || !daoSummary) return null;
    const { id: dao, treasuryId, charterId, emergencyFreezeId, capabilityVaultId } = daoSummary;
    const base = { daoId: dao, proposalId: proposal.id, emergencyFreezeId };

    switch (proposal.typeKey) {
      case "SetBoard":
        return buildExecuteSetBoard(base);
      case "CharterUpdate":
        return buildExecuteUpdateMetadata({ ...base, charterId });
      case "TreasuryWithdraw": {
        const pt = proposal.payloadType;
        const coinType = pt.slice(pt.indexOf("<") + 1, pt.lastIndexOf(">"));
        return buildExecuteSendCoin({ ...base, treasuryId, coinType });
      }
      case "DisableProposalType":
        return buildExecuteDisableProposalType(base);
      case "EnableProposalType":
        return buildExecuteEnableProposalType(base);
      case "UpdateProposalConfig":
        return buildExecuteUpdateProposalConfig(base);
      case "UnfreezeProposalType":
        return buildExecuteUnfreezeProposalType(base);
      case "CreateSubDAO":
        return buildExecuteCreateSubDAO({ ...base, capabilityVaultId });
      case "TransferFreezeAdmin":
        if (!freezeAdminCapId) return null;
        return buildExecuteTransferFreezeAdmin({
          ...base,
          freezeAdminCapId,
        });
      case "UpdateFreezeConfig":
        return buildExecuteUpdateFreezeConfig(base);
      case "UpdateFreezeExemptTypes":
        return buildExecuteUpdateFreezeExemptTypes(base);
      case "SendSmallPayment": {
        const pt = proposal.payloadType;
        const coinType = pt.slice(pt.indexOf("<") + 1, pt.lastIndexOf(">"));
        return buildExecuteSendSmallPayment({ ...base, treasuryId, coinType });
      }
      case "SendCoinToDAO": {
        const pt = proposal.payloadType;
        const coinType = pt.slice(pt.indexOf("<") + 1, pt.lastIndexOf(">"));
        const targetTreasuryId = String(proposal.payload.recipient_treasury ?? "");
        return buildExecuteSendCoinToDAO({ ...base, sourceTreasuryId: treasuryId, targetTreasuryId, coinType });
      }
      case "SpawnDAO":
        return buildExecuteSpawnDAO(base);
      case "SpinOutSubDAO": {
        const subdaoId = String(proposal.payload.subdao_id ?? "");
        return buildExecuteSpinOutSubDAO({ ...base, capabilityVaultId, subdaoVaultId: subdaoId, subdaoId });
      }
      case "PauseSubDAOExecution": {
        const subdaoId = String(proposal.payload.control_id ?? "");
        return buildExecutePauseSubDAOExecution({ ...base, controllerVaultId: capabilityVaultId, subdaoId });
      }
      case "UnpauseSubDAOExecution": {
        const subdaoId = String(proposal.payload.control_id ?? "");
        return buildExecuteUnpauseSubDAOExecution({ ...base, controllerVaultId: capabilityVaultId, subdaoId });
      }
      case "TransferCapToSubDAO": {
        const targetVault = String(proposal.payload.target_subdao ?? "");
        return buildExecuteTransferCapToSubDAO({ ...base, sourceVaultId: capabilityVaultId, targetVaultId: targetVault, capType: "" });
      }
      case "ReclaimCapFromSubDAO": {
        const subdaoVault = String(proposal.payload.subdao_id ?? "");
        return buildExecuteReclaimCap({ ...base, controllerVaultId: capabilityVaultId, subdaoVaultId: subdaoVault, capType: "" });
      }
      default:
        return null;
    }
  }

  async function handleExecute() {
    const transaction = buildExecuteTransaction();
    if (!transaction) {
      toast.info("Execute is not yet available for this proposal type");
      return;
    }
    setActionPending("execute");
    try {
      const result = await signAndExecuteTransaction({ transaction });
      toast.success("Proposal executed");
      await client.waitForTransaction({ digest: result.digest });
      await queryClient.invalidateQueries({
        queryKey: cacheKeys.proposal(proposal!.id),
      });
      if (daoId) {
        // Execution can change any DAO state — invalidate all related caches
        await Promise.all([
          queryClient.invalidateQueries({ queryKey: cacheKeys.proposals(daoId) }),
          queryClient.invalidateQueries({ queryKey: cacheKeys.dao(daoId) }),
          queryClient.invalidateQueries({ queryKey: cacheKeys.governance(daoId) }),
          queryClient.invalidateQueries({ queryKey: cacheKeys.board(daoId) }),
          queryClient.invalidateQueries({ queryKey: cacheKeys.charter(daoId) }),
          queryClient.invalidateQueries({ queryKey: cacheKeys.emergency(daoId) }),
          queryClient.invalidateQueries({ queryKey: cacheKeys.treasury(daoId) }),
          queryClient.invalidateQueries({ queryKey: cacheKeys.hierarchy(daoId) }),
          queryClient.invalidateQueries({ queryKey: cacheKeys.subdaos(daoId) }),
        ]);
        navigate({
          to: "/dao/$daoId/proposals",
          params: { daoId },
        });
      }
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Execution failed");
    } finally {
      setActionPending(null);
    }
  }

  if (isLoading) {
    return (
      <div className="space-y-4">
        <Skeleton className="h-48 w-full" />
        <Skeleton className="h-32 w-full" />
      </div>
    );
  }

  if (!proposal) {
    return (
      <Card>
        <CardContent className="py-8 text-center">
          <p className="text-muted-foreground">Proposal not found.</p>
        </CardContent>
      </Card>
    );
  }

  const typeDef = PROPOSAL_TYPE_MAP[proposal.typeKey];
  const totalVotes = proposal.yesWeight + proposal.noWeight;
  const yesPercent = totalVotes > 0 ? (proposal.yesWeight / totalVotes) * 100 : 0;
  const noPercent = totalVotes > 0 ? (proposal.noWeight / totalVotes) * 100 : 0;
  const totalWeight = governance
    ? governance.type === "Board"
      ? governance.members.length
      : governance.totalShares ?? 0
    : 0;
  const participationBps = totalWeight > 0
    ? Math.round((totalVotes / totalWeight) * 10000)
    : 0;
  const yesAbsolute = totalWeight > 0 ? (proposal.yesWeight / totalWeight) * 100 : 0;
  const noAbsolute = totalWeight > 0 ? (proposal.noWeight / totalWeight) * 100 : 0;

  // For types with a hardcoded execution floor, derive display threshold and floor check.
  // The floor is: yes_weight / total_snapshot_weight >= floor_bps / 10000
  const floorBps = getApprovalFloorBps(proposal.typeKey, proposal.payload);
  const effectiveThresholdBps =
    floorBps !== null
      ? Math.max(proposal.approvalThreshold, floorBps)
      : proposal.approvalThreshold;
  // approvalLinePercent: position of the threshold line on the 0–100% bar.
  // For floor-gated types the floor is expressed vs total_snapshot_weight (same denominator
  // as the bar), so floorBps / 100 is the correct bar position.
  const approvalLinePercent = effectiveThresholdBps / 100;
  const floorMet =
    floorBps === null
      ? true
      : proposal.totalSnapshotWeight > 0
        ? proposal.yesWeight * 10_000 >= proposal.totalSnapshotWeight * floorBps
        : proposal.yesWeight > 0;

  const expiryTimestamp = proposal.createdMs + proposal.expiryMs;
  const executableAt = expiryTimestamp + proposal.executionDelayMs;
  const canExecute = Date.now() >= executableAt;
  const isExpired = Date.now() >= expiryTimestamp;

  return (
    <div className="grid grid-cols-1 gap-6 lg:grid-cols-3">
      {/* Full-width vote progress bar */}
      <div className="lg:col-span-3">
        <Card>
          <CardContent className="pt-4 pb-4">
            <div className="space-y-2">
              <div className="flex justify-between text-sm">
                <span className="font-medium text-blue-500">
                  Yes &mdash; {proposal.yesWeight}{" "}
                  <span className="font-normal text-muted-foreground">({yesPercent.toFixed(1)}%)</span>
                </span>
                <span className="text-xs text-muted-foreground self-center">
                  {formatBps(participationBps)} participated{" "}
                  {floorBps !== null ? (
                    <>&middot; Voting: {formatBps(proposal.approvalThreshold)} &middot; Exec floor: {formatBps(floorBps)}</>
                  ) : (
                    <>&middot; Threshold: {formatBps(proposal.approvalThreshold)}</>
                  )}
                </span>
                <span className="font-medium text-red-500">
                  No &mdash; {proposal.noWeight}{" "}
                  <span className="font-normal text-muted-foreground">({noPercent.toFixed(1)}%)</span>
                </span>
              </div>
              <div className="relative h-3 w-full">
                <div className="absolute inset-0 overflow-hidden rounded-full bg-muted">
                  <div
                    className="absolute left-0 top-0 h-full bg-blue-500 transition-all"
                    style={{ width: `${yesAbsolute}%` }}
                  />
                  <div
                    className="absolute top-0 h-full bg-red-500 transition-all"
                    style={{ left: `${yesAbsolute}%`, width: `${noAbsolute}%` }}
                  />
                </div>
                {approvalLinePercent > 0 && (
                  <div
                    className={`absolute z-10 w-0.5 -top-1 -bottom-1 rounded-sm ${floorBps !== null ? "bg-amber-400/90" : "bg-white/80"}`}
                    style={{ left: `${Math.min(approvalLinePercent, 99.5)}%` }}
                  />
                )}
              </div>
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Left: content */}
      <div className="space-y-4 lg:col-span-2">
        <Card>
          <CardHeader>
            <div className="flex items-center justify-between">
              <div>
                <CardTitle>
                  {typeDef?.label ?? proposal.typeKey}
                </CardTitle>
                <CardDescription>
                  Proposed by {proposerName ?? getAddressName(proposal.proposer)}
                </CardDescription>
              </div>
              <Badge
                variant={statusVariant(proposal.status)}
                className={floorBps !== null && !floorMet && proposal.status === "passed" ? "border-amber-500 text-amber-500" : ""}
              >
                {proposal.status}
              </Badge>
            </div>
          </CardHeader>
          <CardContent className="space-y-3">
            {proposal.metadataIpfs && (
                <h5 className="text-md">
                  {proposal.metadataIpfs}
                </h5>
            )}
            <div className="grid grid-cols-2 gap-4 text-sm">
              <div>
                <span className="text-muted-foreground">Created:</span>{" "}
                {formatDate(proposal.createdMs)}
              </div>
              <div>
                <span className="text-muted-foreground">Expires:</span>{" "}
                {formatDate(expiryTimestamp)}
              </div>
              <div>
                <span className="text-muted-foreground">Quorum:</span>{" "}
                {formatBps(proposal.quorum)}
              </div>
              <div>
                <span className="text-muted-foreground">Threshold:</span>{" "}
                {formatBps(proposal.approvalThreshold)}
              </div>
              {floorBps !== null && (
                <div>
                  <span className="text-muted-foreground">Exec floor:</span>{" "}
                  {formatBps(floorBps)}
                  {!floorMet && (
                    <span className="text-amber-500 text-xs">{" "}(not met)</span>
                  )}
                </div>
              )}
            </div>
            {proposal.status === "active" && (
              <div>
                <span className="text-muted-foreground text-sm">
                  Voting ends:{" "}
                </span>
                <Countdown targetMs={expiryTimestamp} />
              </div>
            )}
            {proposal.status === "passed" && proposal.executionDelayMs > 0 && (
              <div>
                <span className="text-muted-foreground text-sm">
                  Executable in:{" "}
                </span>
                <Countdown targetMs={executableAt} />
              </div>
            )}
          </CardContent>
        </Card>

        {proposal.payload && Object.keys(proposal.payload).length > 0 && (
          <PayloadSummary typeKey={proposal.typeKey} payload={proposal.payload} />
        )}
      </div>

      {/* Right: voting panel */}
      <div className="space-y-4">
        <Card>
          <CardHeader>
            <CardTitle className="text-base">Votes</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <Separator />

            {proposal.status === "active" && hasVoted && (
              <div className="text-muted-foreground text-center text-sm">
                You voted `{priorVote ? "Yes" : "No"}`
              </div>
            )}

            {proposal.status === "active" && !hasVoted && (
              <>
                <div className="flex gap-2">
                  <Button
                    className="flex-1"
                    disabled={actionPending !== null || !isMember}
                    onClick={() => handleVote(true)}
                  >
                    {actionPending === "yes" ? "Voting..." : "Vote Yes"}
                  </Button>
                  <Button
                    variant="destructive"
                    className="flex-1"
                    disabled={actionPending !== null || !isMember}
                    onClick={() => handleVote(false)}
                  >
                    {actionPending === "no" ? "Voting..." : "Vote No"}
                  </Button>
                </div>
                {!isMember && address && (
                  <p className="text-muted-foreground text-center text-xs">
                    Only board members can vote
                  </p>
                )}
              </>
            )}

            {proposal.status === "passed" && (
              <>
                {floorBps !== null && !floorMet && (
                  <div className="space-y-1 text-center">
                    <p className="text-xs text-amber-500">
                      Execution requires {formatBps(floorBps)} of total voting weight (floor).
                      Current yes votes ({formatBps(Math.round((proposal.yesWeight * 10_000) / Math.max(proposal.totalSnapshotWeight, 1)))}) do not meet this threshold.
                    </p>
                    <p className="text-xs text-muted-foreground">
                      The proposal passed its voting threshold and is now closed to new votes.
                      It cannot be executed until the floor is met — a new proposal may be needed.
                    </p>
                  </div>
                )}
                {!canExecute && proposal.executionDelayMs > 0 ? (
                  <div className="text-center">
                    <Button className="w-full" disabled>
                      Execute Proposal
                    </Button>
                    <p className="text-muted-foreground mt-1 text-xs">
                      Executable in: <Countdown targetMs={executableAt} />
                    </p>
                  </div>
                ) : (
                  <Button
                    className="w-full"
                    disabled={actionPending !== null || !isMember}
                    onClick={() => handleExecute()}
                  >
                    {actionPending === "execute" ? "Executing..." : "Execute Proposal"}
                  </Button>
                )}
                {!isMember && address && canExecute && (
                  <p className="text-muted-foreground text-center text-xs">
                    Only board members can execute
                  </p>
                )}
              </>
            )}

            {proposal.status === "active" && isExpired && (
              <Button
                variant="outline"
                className="w-full"
                disabled={actionPending !== null}
                onClick={() => handleExpire()}
              >
                {actionPending === "expire" ? "Processing..." : "Mark Expired"}
              </Button>
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  );
}

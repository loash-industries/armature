import { useState, useEffect, useRef } from "react";
import { Copy, Check, ExternalLink, ChevronDown } from "lucide-react";
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
import {
  PROPOSAL_TYPE_MAP,
  PROPOSAL_TYPE_DISPLAY_NAME,
  type KnownProposalTypeKey,
} from "@/config/proposal-types";
import { PayloadSummary } from "@/components/proposals/PayloadSummary";
import { VoteBar } from "@/components/VoteBar";
import { useCharacterNames } from "@/hooks/useCharacterNames";
import { getAddressName } from "@/lib/address-namer";
import { AnimatedValue } from "@/components/ui/AnimatedValue";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";

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
  return status === "expired" ? "destructive" : "outline";
}

function statusClassName(status: string): string {
  const map: Record<string, string> = {
    active: "border-primary/60 text-primary",
    passed: "border-blue-500/70 text-blue-500",
    executed: "border-emerald-500/70 text-emerald-500",
  };
  return map[status] ?? "";
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
  const [txCopied, setTxCopied] = useState(false);
  const voteButtonRef = useRef<HTMLDivElement>(null);
  const hasVoted = proposal && address ? address in proposal.votesCast : false;
  const priorVote = proposal && address ? proposal.votesCast[address] : undefined;
  const isMember = governance?.members.some(m => m.address === address) ?? false;
  const voterAddresses = proposal ? Object.keys(proposal.votesCast) : [];
  const { data: proposerNameMap } = useCharacterNames(
    proposal?.proposer ? [proposal.proposer, ...voterAddresses] : [],
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

  async function handleVoteAndExecute() {
    if (!proposal?.payloadType) {
      toast.error("Cannot determine proposal type for voting");
      return;
    }
    setActionPending("vote-execute");
    try {
      const voteTx = buildVote({
        proposalId: proposal.id,
        approve: true,
        proposalType: proposal.payloadType,
      });
      const voteResult = await signAndExecuteTransaction({ transaction: voteTx });
      toast.success("Voted Yes");
      await client.waitForTransaction({ digest: voteResult.digest });
      await queryClient.invalidateQueries({
        queryKey: cacheKeys.proposal(proposal.id),
      });

      setActionPending("executing");
      const executeTx = buildExecuteTransaction();
      if (!executeTx) {
        toast.info("Voted but execute is not available for this proposal type");
        return;
      }
      const execResult = await signAndExecuteTransaction({ transaction: executeTx });
      toast.success("Proposal executed");
      await client.waitForTransaction({ digest: execResult.digest });
      await queryClient.invalidateQueries({
        queryKey: cacheKeys.proposal(proposal.id),
      });
      if (daoId) {
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
      toast.error(err instanceof Error ? err.message : "Vote & Execute failed");
    } finally {
      setActionPending(null);
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
  // Use the proposal's own snapshot weight — the governance weight captured at creation
  // time — so the bar always reflects the denominator the on-chain logic used.
  const totalWeight = proposal.totalSnapshotWeight;

  // For types with a hardcoded execution floor, derive display threshold and floor check.
  // The floor is: yes_weight / total_snapshot_weight >= floor_bps / 10000
  const floorBps = getApprovalFloorBps(proposal.typeKey, proposal.payload);
  const floorMet =
    floorBps === null
      ? true
      : proposal.totalSnapshotWeight > 0
        ? proposal.yesWeight * 10_000 >= proposal.totalSnapshotWeight * floorBps
        : proposal.yesWeight > 0;

  // Minimum additional yes votes needed to pass (matching on-chain logic).
  // On-chain: quorum = totalVoted / totalSnapshotWeight, threshold = yes / totalVoted.
  const totalVoted = proposal.yesWeight + proposal.noWeight;
  // For quorum: we need totalVoted >= ceil(totalWeight * quorum / 10000).
  // Each new yes vote adds 1 to totalVoted, so additional votes needed for quorum:
  const yesForQuorum =
    totalWeight > 0
      ? Math.max(0, Math.ceil((totalWeight * proposal.quorum) / 10_000) - totalVoted)
      : 0;
  // For threshold: we need yes / totalVoted >= threshold / 10000.
  // Optimistically assume all new votes are yes votes.
  // yes + n >= threshold * (totalVoted + n) / 10000
  // Solving: n >= (threshold * totalVoted - 10000 * yes) / (10000 - threshold)
  const thresholdDenom = 10_000 - proposal.approvalThreshold;
  const yesForThreshold =
    thresholdDenom > 0
      ? Math.max(
          0,
          Math.ceil(
            (proposal.approvalThreshold * totalVoted - 10_000 * proposal.yesWeight) /
              thresholdDenom,
          ),
        )
      : 0;
  const yesForFloor =
    floorBps !== null && totalWeight > 0
      ? Math.max(0, Math.ceil((totalWeight * floorBps) / 10_000) - proposal.yesWeight)
      : 0;
  const votesNeeded = Math.max(yesForQuorum, yesForThreshold, yesForFloor);

  const expiryTimestamp = proposal.createdMs + proposal.expiryMs;
  const executableAt = expiryTimestamp + proposal.executionDelayMs;
  const canExecute = Date.now() >= executableAt;
  const isExpired = Date.now() >= expiryTimestamp;

  // Determine if the current user's yes vote would push this proposal over threshold,
  // enabling the "Vote Yes & Execute" shortcut when executionDelayMs === 0.
  const userWeight =
    isMember && address
      ? governance?.type === "Board"
        ? 1
        : (governance?.members.find((m) => m.address === address)?.weight ?? 0)
      : 0;
  const newYesWeight = proposal.yesWeight + userWeight;
  const newTotalVoted = proposal.yesWeight + proposal.noWeight + userWeight;
  const quorumWouldBeMet =
    totalWeight > 0
      ? (newTotalVoted * 10_000) / totalWeight >= proposal.quorum
      : newTotalVoted > 0;
  const thresholdWouldBeMet =
    newTotalVoted > 0 &&
    (newYesWeight * 10_000) / newTotalVoted >= proposal.approvalThreshold;
  const floorWouldBeMet =
    floorBps === null
      ? true
      : totalWeight > 0
        ? newYesWeight * 10_000 >= totalWeight * floorBps
        : newYesWeight > 0;
  const wouldPassWithMyVote = quorumWouldBeMet && thresholdWouldBeMet && floorWouldBeMet;
  const canVoteAndExecute =
    proposal.status === "active" &&
    !hasVoted &&
    isMember &&
    proposal.executionDelayMs === 0 &&
    wouldPassWithMyVote &&
    buildExecuteTransaction() !== null;

  return (
    <div className="grid grid-cols-1 gap-6 lg:grid-cols-3">
      {/* Full-width vote progress bar */}
      <div className="lg:col-span-3">
        <Card>
          <CardContent className="py-4">
            <VoteBar
              yesWeight={proposal.yesWeight}
              noWeight={proposal.noWeight}
              totalSnapshotWeight={proposal.totalSnapshotWeight}
              quorum={proposal.quorum}
              approvalThreshold={proposal.approvalThreshold}
              floorBps={floorBps}
              showParticipation
              className="w-full space-y-2"
            />
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
                  {PROPOSAL_TYPE_DISPLAY_NAME[
                    proposal.typeKey as KnownProposalTypeKey
                  ] ?? typeDef?.label ?? proposal.typeKey}
                </CardTitle>
                <CardDescription>
                  Proposed by {proposerName ?? getAddressName(proposal.proposer)}
                </CardDescription>
              </div>
              <Badge
                variant={statusVariant(proposal.status)}
                className={
                  floorBps !== null && !floorMet && proposal.status === "passed"
                    ? "border-amber-500 text-amber-500"
                    : statusClassName(proposal.status)
                }
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
                <AnimatedValue value={proposal.quorum / 100} suffix="%" />
              </div>
              <div>
                <span className="text-muted-foreground">Threshold:</span>{" "}
                <AnimatedValue value={proposal.approvalThreshold / 100} suffix="%" />
              </div>
              {floorBps !== null && (
                <div>
                  <span className="text-muted-foreground">Exec floor:</span>{" "}
                  <AnimatedValue value={floorBps / 100} suffix="%" />
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
            {proposal.status === "executed" && proposal.executionTxHash && (
              <div className="flex items-center gap-2 text-sm">
                <span className="text-muted-foreground shrink-0">Executed tx:</span>
                <span className="font-mono text-xs truncate">
                  {proposal.executionTxHash.slice(0, 8)}&hellip;{proposal.executionTxHash.slice(-6)}
                </span>
                <button
                  type="button"
                  onClick={() => {
                    void navigator.clipboard.writeText(proposal.executionTxHash!);
                    setTxCopied(true);
                    setTimeout(() => setTxCopied(false), 2000);
                  }}
                  className="rounded p-0.5 hover:bg-muted transition-colors"
                  title="Copy transaction hash"
                >
                  {txCopied ? (
                    <Check className="h-3.5 w-3.5 text-green-500" />
                  ) : (
                    <Copy className="h-3.5 w-3.5 text-muted-foreground" />
                  )}
                </button>
                <a
                  href={`http://suiscan.xyz/testnet/tx/${proposal.executionTxHash}`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="rounded p-0.5 hover:bg-muted transition-colors"
                  title="View on SuiScan"
                >
                  <ExternalLink className="h-3.5 w-3.5 text-muted-foreground" />
                </a>
              </div>
            )}
          </CardContent>
        </Card>

        {proposal.payload && Object.keys(proposal.payload).length > 0 && (
          <PayloadSummary typeKey={proposal.typeKey} payload={proposal.payload} payloadType={proposal.payloadType} />
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

            {['active','executed'].includes(proposal.status) && hasVoted && (
              <div className="text-muted-foreground text-center text-sm">
                You voted '{priorVote ? "Yes" : "No"}' on this proposal.
              </div>
            )}

            {['active','executed'].includes(proposal.status) && !hasVoted && (
              <>
                <div className="flex gap-2">
                  {canVoteAndExecute ? (
                    <div ref={voteButtonRef} className="flex flex-1">
                      <Button
                        className="flex-1 rounded-r-none"
                        disabled={actionPending !== null || !isMember}
                        onClick={() => handleVote(true)}
                      >
                        {actionPending === "yes" || actionPending === "vote-execute"
                          ? "Voting..."
                          : actionPending === "executing"
                            ? "Executing..."
                            : "Vote Yes"}
                      </Button>
                      <DropdownMenu>
                        <DropdownMenuTrigger
                          disabled={actionPending !== null}
                          render={
                            <button
                              type="button"
                              className="inline-flex h-8 items-center rounded-r-lg border-l border-primary-foreground/20 bg-primary px-1.5 text-primary-foreground hover:bg-primary/80 disabled:pointer-events-none disabled:opacity-50"
                            />
                          }
                        >
                          <ChevronDown className="h-4 w-4" />
                        </DropdownMenuTrigger>
                        <DropdownMenuContent align="start" anchor={voteButtonRef}>
                          <DropdownMenuItem
                            disabled={actionPending !== null}
                            onClick={() => handleVoteAndExecute()}
                          >
                            Vote Yes & Execute
                          </DropdownMenuItem>
                        </DropdownMenuContent>
                      </DropdownMenu>
                    </div>
                  ) : (
                    <Button
                      className="flex-1"
                      disabled={actionPending !== null || !isMember}
                      onClick={() => handleVote(true)}
                    >
                      {actionPending === "yes" ? "Voting..." : "Vote Yes"}
                    </Button>
                  )}
                  <Button
                    variant="destructive"
                    className="flex-1"
                    disabled={actionPending !== null || !isMember}
                    onClick={() => handleVote(false)}
                  >
                    {actionPending === "no" ? "Voting..." : "Vote No"}
                  </Button>
                </div>
                {votesNeeded > 0 && (
                  <p className="text-muted-foreground text-center text-xs">
                    This proposal needs {votesNeeded} more approval {votesNeeded === 1 ? "vote" : "votes"} to pass
                  </p>
                )}
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
                      Execution requires <AnimatedValue value={floorBps / 100} suffix="%" /> of total voting weight (floor).
                      Current yes votes (<AnimatedValue value={Math.round((proposal.yesWeight * 10_000) / Math.max(proposal.totalSnapshotWeight, 1)) / 100} suffix="%" />) do not meet this threshold.
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
                    disabled={actionPending !== null || !isMember || !floorMet}
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
            {}
          </CardContent>
        </Card>

        {/* Votes cast list */}
        {proposal.votesCast && Object.keys(proposal.votesCast).length > 0 && (
          <Card>
            <CardHeader>
              <CardTitle className="text-base">Votes Cast</CardTitle>
            </CardHeader>
            <CardContent className="space-y-2">
              {Object.entries(proposal.votesCast).map(([addr, approved]) => (
                <div key={addr} className="flex items-center justify-between text-sm">
                  <span className="truncate font-mono text-xs">
                    {proposerNameMap?.get(addr) ?? getAddressName(addr)}
                  </span>
                  <Badge variant={approved ? "default" : "destructive"} className="ml-2 shrink-0">
                    {approved ? "Yes" : "No"}
                  </Badge>
                </div>
              ))}
            </CardContent>
          </Card>
        )}
      </div>
    </div>
  );
}

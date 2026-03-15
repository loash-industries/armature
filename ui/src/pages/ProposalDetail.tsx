import { useState, useEffect } from "react";
import { useParams } from "@tanstack/react-router";
import { useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import {
  Card,
  CardHeader,
  CardTitle,
  CardDescription,
  CardContent,
  Badge,
  Button,
  Skeleton,
  Progress,
  Separator,
} from "@awar.dev/ui";
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

function truncAddr(addr: string): string {
  if (addr.length <= 12) return addr;
  return `${addr.slice(0, 6)}...${addr.slice(-4)}`;
}

function formatBps(bps: number): string {
  return `${bps} bps`;
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
  const quorumProgress = proposal.quorum > 0
    ? Math.min((participationBps / proposal.quorum) * 100, 100)
    : 100;
  const expiryTimestamp = proposal.createdMs + proposal.expiryMs;
  const executableAt = expiryTimestamp + proposal.executionDelayMs;
  const canExecute = Date.now() >= executableAt;

  return (
    <div className="grid grid-cols-1 gap-6 lg:grid-cols-3">
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
                  Proposed by {truncAddr(proposal.proposer)}
                </CardDescription>
              </div>
              <Badge variant={statusVariant(proposal.status)}>
                {proposal.status}
              </Badge>
            </div>
          </CardHeader>
          <CardContent className="space-y-3">
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
            {proposal.metadataIpfs && (
              <div className="text-sm">
                <span className="text-muted-foreground">Metadata:</span>{" "}
                <span className="font-mono text-xs">
                  {proposal.metadataIpfs}
                </span>
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
            <div>
              <div className="mb-1 flex justify-between text-sm">
                <span>Yes</span>
                <span className="font-mono">
                  {proposal.yesWeight} ({yesPercent.toFixed(1)}%)
                </span>
              </div>
              <Progress value={yesPercent} className="h-2" />
            </div>
            <div>
              <div className="mb-1 flex justify-between text-sm">
                <span>No</span>
                <span className="font-mono">
                  {proposal.noWeight} ({noPercent.toFixed(1)}%)
                </span>
              </div>
              <Progress value={noPercent} className="h-2" />
            </div>

            <Separator />

            <div>
              <div className="mb-1 flex justify-between text-sm">
                <span>Quorum</span>
                <span className="font-mono">
                  {participationBps} / {proposal.quorum} bps
                </span>
              </div>
              <Progress value={quorumProgress} className="h-2" />
            </div>

            <Separator />

            {proposal.status === "active" && hasVoted && (
              <div className="text-muted-foreground text-center text-sm">
                You voted {priorVote ? "Yes" : "No"}
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

            {proposal.status === "active" && (
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

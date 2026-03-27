import { useState } from "react";
import type React from "react";
import { useParams, Link } from "@tanstack/react-router";
import { useCurrentAccount } from "@mysten/dapp-kit";
import { resolveDisplayName } from "@/lib/address-namer";
import { AddressName } from "@/components/AddressName";
import { Alert, AlertTitle, AlertDescription } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import {
  ArrowUpRight,
  PenTool,
  Vote,
  CheckCircle2,
  Play,
  TimerOff,
  Snowflake,
  Sun,
  ShieldAlert,
  Settings,
  ShieldCheck,
  ShieldMinus,
  ArrowDownToLine,
  ArrowUpFromLine,
  HandCoins,
  Send,
  ArrowRightLeft,
  ArrowRight,
  Banknote,
  UserPlus,
  FilePenLine,
  ToggleRight,
  ToggleLeft,
  SlidersHorizontal,
  Landmark,
  Trash2,
} from "lucide-react";
import {
  useDaoSummary,
  useDaoActivity,
  useCoinMetadataMap,
} from "@/hooks/useDao";
import type { CoinMeta } from "@/hooks/useDao";
import { useCharacterNames } from "@/hooks/useCharacterNames";
import { useLiveTreasury } from "@/hooks/useLiveTreasury";
import { useLiveProposals } from "@/hooks/useLiveProposals";
import { VoteBar } from "@/components/VoteBar";
import {
  PROPOSAL_TYPE_DISPLAY_NAME,
  type KnownProposalTypeKey,
} from "@/config/proposal-types";
import type { ActivityEvent } from "@/types/dao";
import type { LucideIcon } from "lucide-react";
import { AnimatedCoinBalance } from "@/components/ui/AnimatedCoinBalance";

function shortCoinType(coinType: string): string {
  const parts = coinType.split("::");
  return parts[parts.length - 1] ?? coinType;
}

function formatCoinBalance(raw: bigint, symbol: string, decimals = 6): string {
  const val = Number(raw) / Math.pow(10, decimals);
  const formatted =
    val >= 1_000_000
      ? `${(val / 1_000_000).toFixed(1)}M`
      : val.toLocaleString(undefined, { minimumFractionDigits: 0, maximumFractionDigits: 2 });
  return `${formatted} ${symbol}`;
}

function timeAgo(timestampMs: number): string {
  const diff = Date.now() - timestampMs;
  const seconds = Math.floor(diff / 1000);
  if (seconds < 60) return `${seconds}s ago`;
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  return `${days}d ago`;
}

function CoinIcon({ iconUrl, symbol }: { iconUrl: string | null; symbol: string }) {
  const [imgError, setImgError] = useState(false);
  if (iconUrl && !imgError) {
    return (
      <img
        src={iconUrl}
        alt={symbol}
        className="h-5 w-5 rounded-full object-cover"
        onError={() => setImgError(true)}
      />
    );
  }
  return (
    <div className="bg-muted text-muted-foreground flex h-5 w-5 items-center justify-center rounded-full text-[10px] font-bold uppercase">
      {symbol.slice(0, 2)}
    </div>
  );
}

/** Per-event-type icon mapping for the activity feed */
const EVENT_ICONS: Record<string, LucideIcon> = {
  // Proposals
  ProposalCreated: PenTool,
  VoteCast: Vote,
  ProposalPassed: CheckCircle2,
  ProposalExecuted: Play,
  ProposalExpired: TimerOff,
  ProposalTypeEnabled: ToggleRight,
  ProposalTypeDisabled: ToggleLeft,
  ProposalConfigUpdated: SlidersHorizontal,
  // Emergency
  TypeFrozen: Snowflake,
  TypeUnfrozen: Sun,
  FreezeAdminTransferred: ShieldAlert,
  FreezeConfigUpdated: Settings,
  FreezeExemptTypeAdded: ShieldCheck,
  FreezeExemptTypeRemoved: ShieldMinus,
  // Treasury
  CoinDeposited: ArrowDownToLine,
  CoinWithdrawn: ArrowUpFromLine,
  CoinClaimed: HandCoins,
  CoinSent: Send,
  CoinSentToDAO: ArrowRightLeft,
  SmallPaymentSent: Banknote,
  // Board
  BoardUpdated: UserPlus,
  // Charter / DAO lifecycle
  DAOCreated: Landmark,
  DAODestroyed: Trash2,
  MetadataUpdated: FilePenLine,
};

function getEventIcon(eventType: string): LucideIcon {
  return EVENT_ICONS[eventType] ?? PenTool;
}

function formatRawCoin(
  rawAmount: string | undefined,
  coinType: string | undefined,
  metaMap: Record<string, CoinMeta> | undefined,
): string {
  if (!rawAmount || !coinType) return rawAmount ?? "";
  const meta = metaMap?.[coinType];
  const symbol = meta?.symbol ?? shortCoinType(coinType);
  const decimals = meta?.decimals ?? 9;
  return formatCoinBalance(BigInt(rawAmount), symbol, decimals);
}

/** Build the action ReactNode for an activity event with AddressName components and coin amounts. */
function formatActivityDisplay(
  ev: ActivityEvent,
  nameMap: Map<string, string | null> | undefined,
  metaMap: Record<string, CoinMeta> | undefined,
): { action: React.ReactNode; context: string } {
  const coin = formatRawCoin(ev.coinAmount, ev.coinType, metaMap);
  const actor = ev.actor
    ? <AddressName address={ev.actor} charName={nameMap?.get(ev.actor)} />
    : null;
  const recipient = ev.recipient
    ? <AddressName address={ev.recipient} charName={nameMap?.get(ev.recipient)} />
    : null;

  switch (ev.eventType) {
    case "VoteCast": {
      const pid = ev.proposalId;
      const short = pid && pid.length > 10 ? `${pid.slice(0, 6)}\u2026${pid.slice(-4)}` : pid ?? "";
      const typeLabel = ev.typeKey ? ` (${ev.typeKey})` : "";
      return {
        action: <>{actor} voted '{ev.approve ? "Yes" : "No"}' on proposal {short}{typeLabel}</>,
        context: ev.label,
      };
    }
    case "ProposalCreated":
      return {
        action: <>{actor} created '{ev.typeKey ?? ""}' proposal</>,
        context: ev.label,
      };
    case "ProposalExecuted":
      return {
        action: <>{actor} executed proposal</>,
        context: ev.label,
      };
    case "ProposalPassed":
      return { action: ev.description, context: ev.label };
    case "ProposalExpired":
      return { action: ev.description, context: ev.label };
    case "CoinDeposited":
      return {
        action: <>{actor} deposited {coin}</>,
        context: ev.label,
      };
    case "CoinWithdrawn":
      return {
        action: <>Withdrew {coin} to {recipient}</>,
        context: ev.label,
      };
    case "CoinClaimed":
      return {
        action: <>{actor} claimed {coin}</>,
        context: ev.label,
      };
    case "CoinSent":
      return {
        action: <>Sent {coin} to {recipient}</>,
        context: ev.label,
      };
    case "CoinSentToDAO":
      return {
        action: <>Sent {coin} to DAO treasury</>,
        context: ev.label,
      };
    case "SmallPaymentSent":
      return {
        action: <>Small payment {coin} to {recipient}</>,
        context: ev.label,
      };
    case "TypeFrozen":
      return {
        action: <>Froze {ev.typeKey ?? "type"}</>,
        context: ev.label,
      };
    case "TypeUnfrozen":
      return {
        action: <>Unfroze {ev.typeKey ?? "type"}</>,
        context: ev.label,
      };
    case "BoardUpdated":
      return { action: "Board membership updated", context: ev.label };
    case "DAOCreated":
      return {
        action: <>{actor} created the DAO</>,
        context: ev.label,
      };
    default:
      return { action: ev.description, context: ev.label };
  }
}

// --- Stat Card (matches Figma DAO Stats component) ---

function StatCard({
  title,
  value,
  loading,
  to,
  daoId,
  live = false,
  children,
}: {
  title: string;
  value: string;
  loading: boolean;
  to: string;
  daoId: string;
  live?: boolean;
  children?: React.ReactNode;
}) {
  return (
    <Card className="flex-1 p-0">
      <CardContent className="flex items-start justify-between p-6">
        <div className="space-y-2">
          <div className="flex items-center gap-2">
            <p className="text-xl font-semibold">{title}</p>
            {live && (
              <span className="relative flex h-2 w-2">
                <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-green-400 opacity-75" />
                <span className="relative inline-flex h-2 w-2 rounded-full bg-green-500" />
              </span>
            )}
          </div>
          {loading ? (
            <Skeleton className="h-7 w-24" />
          ) : children ? (
            children
          ) : (
            <p className="text-lg text-muted-foreground">{value}</p>
          )}
        </div>
        <Button
          variant="ghost"
          size="icon"
          render={<Link to={to} params={{ daoId }} />}
        >
          <ArrowUpRight className="h-5 w-5" />
        </Button>
      </CardContent>
    </Card>
  );
}

// --- Activity Row (matches Figma DAO Activity row) ---

function ActivityRow({
  icon: Icon,
  action,
  context,
  timestamp,
  daoId,
  proposalId,
}: {
  icon: LucideIcon;
  action: React.ReactNode;
  context: string;
  timestamp: string;
  daoId?: string;
  proposalId?: string;
}) {
  const inner = (
    <div className="flex items-center gap-2 py-4">
      <div className="flex ml-4 h-8 w-8 flex-shrink-0 items-center justify-center">
        <Icon className="h-5 w-5 text-muted-foreground" />
      </div>
      <div className="flex-1 space-y-1 overflow-hidden">
        <p className="truncate text-sm">{action}</p>
        <p className="truncate text-sm text-muted-foreground">{context}</p>
      </div>
      <span className="flex-shrink-0 mr-4 text-sm text-muted-foreground">
        {timestamp}
      </span>
    </div>
  );

  if (daoId && proposalId) {
    return (
      <Link
        to="/dao/$daoId/proposals/$proposalId"
        params={{ daoId, proposalId }}
        className="block border-b last:border-b-0 hover:bg-muted/40 transition-colors"
      >
        {inner}
      </Link>
    );
  }
  return <div className="border-b last:border-b-0">{inner}</div>;
}

// --- Dashboard ---

export function DaoDashboard() {
  const { daoId } = useParams({ strict: false });
  const [renderTime] = useState(Date.now);
  const [activityFilter, setActivityFilter] = useState("");
  const {
    data: dao,
    isLoading: daoLoading,
    isError: daoError,
  } = useDaoSummary(daoId ?? "");
  const { data: balances, isLoading: balancesLoading, feed: treasuryFeed } = useLiveTreasury(
    dao?.treasuryId,
  );
  const { data: activity, isLoading: activityLoading } = useDaoActivity(
    daoId ?? "",
    dao?.treasuryId,
  );

  // Merge coin types from treasury balances + activity events for a single metadata lookup
  const treasuryCoinTypes = balances?.map((b) => b.coinType) ?? [];
  const activityCoinTypes = activity
    ?.map((ev) => ev.coinType)
    .filter((ct): ct is string => !!ct) ?? [];
  const allCoinTypes = [...new Set([...treasuryCoinTypes, ...activityCoinTypes])];
  const { data: metadataMap } = useCoinMetadataMap(allCoinTypes);

  // Resolve character names for all actors/recipients in activity events
  const activityAddresses = activity
    ? [...new Set(activity.flatMap((ev) => [ev.actor, ev.recipient].filter(Boolean) as string[]))]
    : [];
  const { data: activityNameMap } = useCharacterNames(activityAddresses);

  // Filter activity by keyword (matches actor/recipient address or name, label, event type, or typeKey)
  const filteredActivity = activity?.filter((ev) => {
    if (!activityFilter) return true;
    const q = activityFilter.toLowerCase();
    const actorName = ev.actor ? resolveDisplayName(ev.actor, activityNameMap?.get(ev.actor)) : "";
    const recipientName = ev.recipient ? resolveDisplayName(ev.recipient, activityNameMap?.get(ev.recipient)) : "";
    return (
      actorName.toLowerCase().includes(q) ||
      recipientName.toLowerCase().includes(q) ||
      (ev.actor ?? "").toLowerCase().includes(q) ||
      (ev.recipient ?? "").toLowerCase().includes(q) ||
      ev.label.toLowerCase().includes(q) ||
      ev.eventType.toLowerCase().includes(q) ||
      (ev.typeKey ?? "").toLowerCase().includes(q)
    );
  });
  const { data: proposals, isLoading: proposalsLoading } = useLiveProposals(
    daoId ?? "",
  );
  const account = useCurrentAccount();
  const unvotedProposals = proposals?.filter(
    (p) =>
      p.status === "active" &&
      !!account &&
      !(account.address in p.votesCast),
  ) ?? [];

  const treasuryLoading = daoLoading || balancesLoading;
  const treasuryValue = !dao
    ? "—"
    : !balances || balances.length === 0
      ? "Empty"
      : balances.length === 1
        ? formatCoinBalance(balances[0].balance, shortCoinType(balances[0].coinType), balances[0].decimals)
        : balances
            .map((b) => formatCoinBalance(b.balance, shortCoinType(b.coinType), b.decimals))
            .join(" · ");
  const hasLiveTreasuryActivity = treasuryFeed.length > 0;

  return (
    <div className="space-y-6">
      {daoError && (
        <Alert variant="destructive">
          <AlertTitle>Connection Error</AlertTitle>
          <AlertDescription>
            Could not fetch DAO data. Check that the network is reachable.
          </AlertDescription>
        </Alert>
      )}

      {dao?.status === "Migrating" && (
        <Alert variant="destructive">
          <AlertTitle>DAO Migrating</AlertTitle>
          <AlertDescription>
            This DAO is currently in migration mode. Some actions may be restricted.
          </AlertDescription>
        </Alert>
      )}

      {dao && dao.frozenTypes.length > 0 && (
        <Alert>
          <AlertTitle>Emergency Freeze Active</AlertTitle>
          <AlertDescription>
            {dao.frozenTypes.length} proposal type(s) currently frozen:{" "}
            {dao.frozenTypes.join(", ")}
          </AlertDescription>
        </Alert>
      )}

      {/* Stat Cards */}
      <div className="flex gap-4">
        <StatCard
          title="Members"
          value={dao ? `${dao.boardMemberCount}` : "—"}
          loading={daoLoading}
          to="/dao/$daoId/board"
          daoId={daoId ?? ""}
        />
        <StatCard
          title="Treasury"
          value={treasuryValue}
          loading={treasuryLoading}
          to="/dao/$daoId/treasury"
          daoId={daoId ?? ""}
          live={hasLiveTreasuryActivity}
        >
          {balances && balances.length > 0 ? (
            <div className="space-y-1">
              {balances.map((b) => {
                const meta = metadataMap?.[b.coinType];
                const symbol = meta?.symbol ?? shortCoinType(b.coinType);
                const decimals = meta?.decimals ?? b.decimals;
                return (
                  <div key={b.coinType} className="flex items-center gap-2">
                    <CoinIcon iconUrl={meta?.iconUrl ?? null} symbol={symbol} />
                    <AnimatedCoinBalance
                      balance={b.balance}
                      decimals={decimals}
                      symbol={symbol}
                      className="text-lg text-muted-foreground"
                    />
                  </div>
                );
              })}
            </div>
          ) : undefined}
        </StatCard>
        <StatCard
          title="Proposals"
          value={dao ? `${dao.enabledProposalTypes.length} active` : "—"}
          loading={daoLoading}
          to="/dao/$daoId/proposals"
          daoId={daoId ?? ""}
        />
      </div>

      {/* Needs Your Vote (Proposal Items) */}
      <div className="space-y-3">
        {}
        <h2 className="text-lg font-semibold">Proposals Awaiting Your Vote</h2>
        {proposalsLoading ? (
          Array.from({ length: 3 }).map((_, i) => (
            <Skeleton key={i} className="h-[76px] w-full rounded-md" />
          ))
        ) : unvotedProposals.length > 0 ? (
          unvotedProposals.map((p) => {
            const expiresAt = p.createdMs + p.expiryMs;
            const msLeft = expiresAt - renderTime;
            const hoursLeft = Math.max(0, Math.floor(msLeft / 3_600_000));
            const timeLabel =
              msLeft <= 0
                ? "Expired"
                : hoursLeft < 24
                  ? `${hoursLeft}h left`
                  : `${Math.floor(hoursLeft / 24)}d left`;
            return (
              <Link
                key={p.id}
                to="/dao/$daoId/proposals/$proposalId"
                params={{ daoId: daoId ?? "", proposalId: p.id }}
                className="block"
              >
                <Card className="transition-colors hover:bg-muted/50">
                  <CardContent className="flex items-center gap-4 p-4">
                    {/* Title + description */}
                    <div className="w-48 flex-shrink-0 space-y-0.5 overflow-hidden">
                      <p className="truncate font-semibold">
                        {PROPOSAL_TYPE_DISPLAY_NAME[
                          p.typeKey as KnownProposalTypeKey
                        ] ?? p.typeKey}
                      </p>
                      <p className="truncate text-sm text-muted-foreground">
                        {p.metadataIpfs || `${p.id.slice(0, 10)}…`}
                      </p>
                    </div>
                    {/* Vote bar — fills remaining space */}
                    <div className="min-w-0 flex-1">
                      <VoteBar
                        yesWeight={p.yesWeight}
                        noWeight={p.noWeight}
                        totalSnapshotWeight={p.totalSnapshotWeight}
                        quorum={p.quorum}
                        approvalThreshold={p.approvalThreshold}
                        className="w-full space-y-1"
                      />
                    </div>
                    {/* Time + arrow */}
                    <div className="flex flex-shrink-0 flex-col items-end gap-1">
                      <span className="text-xs text-muted-foreground">{timeLabel}</span>
                      <ArrowRight className="h-4 w-4 text-muted-foreground" />
                    </div>
                  </CardContent>
                </Card>
              </Link>
            );
          })
        ) : (
          !account ? (
            <p className="py-8 text-center text-sm text-muted-foreground">
              Connect your wallet to see proposals requiring your vote.
            </p>
          ) : (
          <p className="py-8 text-center text-sm text-muted-foreground">
            No votes pending! Check out the{" "}<Link
              to="/dao/$daoId/proposals"
              params={{ daoId: daoId ?? "" }}
              className="font-medium underline underline-offset-2 hover:opacity-80"
            >
             proposals history
            </Link>{" "}
            or explore the treasury and board.
          </p>
          )
        )}
      </div>

      {/* Activity Feed */}
      <div className="space-y-4">
        <h2 className="text-lg font-semibold">Activity</h2>
        <div className="flex items-center justify-between">
          <Input
            placeholder="Filter keywords ..."
            className="w-96"
            value={activityFilter}
            onChange={(e) => setActivityFilter(e.target.value)}
          />
          <Button variant="outline" size="sm">
            Filters
          </Button>
        </div>
        <div className="rounded-md border">
          {activityLoading ? (
            <div className="space-y-0 p-4">
              {Array.from({ length: 4 }).map((_, i) => (
                <Skeleton key={i} className="mb-4 h-16 w-full" />
              ))}
            </div>
          ) : filteredActivity && filteredActivity.length > 0 ? (
            filteredActivity.map((ev) => {
              const Icon = getEventIcon(ev.eventType);
              const { action, context } = formatActivityDisplay(
                ev,
                activityNameMap,
                metadataMap,
              );
              return (
                <ActivityRow
                  key={`${ev.txDigest}-${ev.eventType}`}
                  icon={Icon}
                  action={action}
                  context={context}
                  timestamp={ev.timestampMs > 0 ? timeAgo(ev.timestampMs) : "—"}
                  daoId={ev.proposalId ? daoId : undefined}
                  proposalId={ev.proposalId}
                />
              );
            })
          ) : (
            <p className="py-8 text-center text-sm text-muted-foreground">
              No recent activity.
            </p>
          )}
        </div>
      </div>
    </div>
  );
}

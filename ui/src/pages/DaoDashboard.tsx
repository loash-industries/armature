import { useParams, Link } from "@tanstack/react-router";
import { Alert, AlertTitle, AlertDescription } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import {
  ArrowUpRight,
  Users,
  Wallet,
  PenTool,
  BookOpen,
  AlertTriangle,
} from "lucide-react";
import {
  useDaoSummary,
  useTreasuryBalances,
  useDaoActivity,
} from "@/hooks/useDao";
import type { LucideIcon } from "lucide-react";

function formatBalance(raw: bigint): string {
  const sui = Number(raw) / 1_000_000_000;
  if (sui >= 1000) return `${(sui / 1000).toFixed(1)}K SUI`;
  return `${sui.toLocaleString(undefined, { minimumFractionDigits: 0, maximumFractionDigits: 2 })} SUI`;
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

/** Module label → icon mapping for activity feed */
const MODULE_ICONS: Record<string, LucideIcon> = {
  Proposals: PenTool,
  Treasury: Wallet,
  Emergency: AlertTriangle,
  Board: Users,
  Charter: BookOpen,
};

function getModuleIcon(label: string): LucideIcon {
  return MODULE_ICONS[label] ?? PenTool;
}

// --- Stat Card (matches Figma DAO Stats component) ---

function StatCard({
  title,
  value,
  loading,
  to,
  daoId,
}: {
  title: string;
  value: string;
  loading: boolean;
  to: string;
  daoId: string;
}) {
  return (
    <Card className="flex-1">
      <CardContent className="flex items-start justify-between p-6">
        <div className="space-y-2">
          <p className="text-xl font-semibold">{title}</p>
          {loading ? (
            <Skeleton className="h-7 w-24" />
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
}: {
  icon: LucideIcon;
  action: string;
  context: string;
  timestamp: string;
}) {
  return (
    <div className="flex items-center gap-2 border-b py-4 last:border-b-0">
      <div className="flex h-8 w-8 flex-shrink-0 items-center justify-center">
        <Icon className="h-5 w-5 text-muted-foreground" />
      </div>
      <div className="flex-1 space-y-1 overflow-hidden">
        <p className="truncate text-sm">{action}</p>
        <p className="truncate text-sm text-muted-foreground">{context}</p>
      </div>
      <span className="flex-shrink-0 text-sm text-muted-foreground">
        {timestamp}
      </span>
    </div>
  );
}

// --- Dashboard ---

export function DaoDashboard() {
  const { daoId } = useParams({ strict: false });
  const {
    data: dao,
    isLoading: daoLoading,
    isError: daoError,
  } = useDaoSummary(daoId ?? "");
  const { data: balances, isLoading: balancesLoading } = useTreasuryBalances(
    dao?.treasuryId,
  );
  const { data: activity, isLoading: activityLoading } = useDaoActivity(
    daoId ?? "",
  );

  const treasuryLoading = daoLoading || balancesLoading;
  const treasuryValue = dao
    ? formatBalance(balances?.reduce((sum, b) => sum + b.balance, 0n) ?? 0n)
    : "—";

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
        />
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
        {daoLoading ? (
          Array.from({ length: 3 }).map((_, i) => (
            <Skeleton key={i} className="h-[76px] w-full rounded-md" />
          ))
        ) : (
          // TODO: Replace with real unvoted proposals filtered to connected wallet
          <p className="py-8 text-center text-sm text-muted-foreground">
            No proposals requiring your vote.
          </p>
        )}
      </div>

      {/* Activity Feed */}
      <div className="space-y-4">
        <div className="flex items-center justify-between">
          <Input
            placeholder="Filter keywords ..."
            className="w-96"
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
          ) : activity && activity.length > 0 ? (
            activity.map((ev) => {
              const Icon = getModuleIcon(ev.label);
              return (
                <ActivityRow
                  key={`${ev.txDigest}-${ev.eventType}`}
                  icon={Icon}
                  action={ev.description}
                  context={`${ev.label} — ${ev.description}`}
                  timestamp={ev.timestampMs > 0 ? timeAgo(ev.timestampMs) : "—"}
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

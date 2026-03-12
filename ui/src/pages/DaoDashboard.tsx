import { useParams, Link } from "@tanstack/react-router";
import {
  Card,
  CardHeader,
  CardTitle,
  CardDescription,
  CardContent,
  Badge,
  Button,
  Alert,
  AlertTitle,
  AlertDescription,
  Skeleton,
  Table,
  TableHeader,
  TableHead,
  TableBody,
  TableRow,
  TableCell,
} from "@awar.dev/ui";
import {
  useDaoSummary,
  useTreasuryBalances,
  useDaoActivity,
} from "@/hooks/useDao";

function formatBalance(raw: bigint): string {
  const sui = Number(raw) / 1_000_000_000;
  return sui.toLocaleString(undefined, {
    minimumFractionDigits: 0,
    maximumFractionDigits: 2,
  });
}

function shortCoinType(coinType: string): string {
  const parts = coinType.split("::");
  return parts[parts.length - 1] ?? coinType;
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

export function DaoDashboard() {
  const { daoId } = useParams({ strict: false });
  const { data: dao, isLoading: daoLoading } = useDaoSummary(daoId ?? "");
  const { data: balances, isLoading: balancesLoading } = useTreasuryBalances(
    dao?.treasuryId,
  );
  const { data: activity, isLoading: activityLoading } = useDaoActivity(
    daoId ?? "",
  );

  const totalSui =
    balances?.reduce((sum, b) => sum + b.balance, 0n) ?? 0n;

  return (
    <div className="space-y-6">
      {dao?.status === "Migrating" && (
        <Alert variant="destructive">
          <AlertTitle>DAO Migrating</AlertTitle>
          <AlertDescription>
            This DAO is currently in migration mode. Some actions may be
            restricted.
          </AlertDescription>
        </Alert>
      )}

      {dao && dao.frozenTypes.length > 0 && (
        <Alert>
          <AlertTitle>Emergency Freeze Active</AlertTitle>
          <AlertDescription>
            {dao.frozenTypes.length} proposal type(s) currently frozen.
          </AlertDescription>
        </Alert>
      )}

      {/* Summary Cards */}
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <SummaryCard
          title="Treasury"
          loading={daoLoading || balancesLoading}
          value={`${formatBalance(totalSui)} SUI`}
          description={
            balances && balances.length > 1
              ? `${balances.length} coin types`
              : undefined
          }
        />
        <SummaryCard
          title="Board"
          loading={daoLoading}
          value={dao ? `${dao.boardMemberCount} members` : "—"}
        />
        <SummaryCard
          title="Charter"
          loading={daoLoading}
          value={dao?.charterName ?? "—"}
        />
        <SummaryCard
          title="Proposal Types"
          loading={daoLoading}
          value={dao ? `${dao.enabledProposalTypes.length} enabled` : "—"}
        />
      </div>

      {/* Treasury Breakdown */}
      {balances && balances.length > 0 && (
        <Card>
          <CardHeader>
            <div className="flex items-center justify-between">
              <CardTitle>Treasury Balances</CardTitle>
              <Button variant="ghost" size="sm" asChild>
                <Link
                  to="/dao/$daoId/treasury"
                  params={{ daoId: daoId ?? "" }}
                >
                  View All
                </Link>
              </Button>
            </div>
          </CardHeader>
          <CardContent>
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Coin</TableHead>
                  <TableHead className="text-right">Balance</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {balances.map((b) => (
                  <TableRow key={b.coinType}>
                    <TableCell>{shortCoinType(b.coinType)}</TableCell>
                    <TableCell className="text-right">
                      {formatBalance(b.balance)}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </CardContent>
        </Card>
      )}

      {/* Recent Activity */}
      <Card>
        <CardHeader>
          <CardTitle>Recent Activity</CardTitle>
          {activityLoading && <CardDescription>Loading...</CardDescription>}
        </CardHeader>
        <CardContent>
          {activityLoading ? (
            <div className="space-y-3">
              {Array.from({ length: 5 }).map((_, i) => (
                <Skeleton key={i} className="h-6 w-full" />
              ))}
            </div>
          ) : activity && activity.length > 0 ? (
            <div className="space-y-3">
              {activity.map((ev) => (
                <div
                  key={`${ev.txDigest}-${ev.eventType}`}
                  className="flex items-center gap-3 text-sm"
                >
                  <Badge variant="outline">{ev.label}</Badge>
                  <span className="flex-1 truncate">{ev.description}</span>
                  <span className="text-muted-foreground whitespace-nowrap text-xs">
                    {ev.timestampMs > 0 ? timeAgo(ev.timestampMs) : "—"}
                  </span>
                </div>
              ))}
            </div>
          ) : (
            <p className="text-muted-foreground text-sm">
              No recent activity.
            </p>
          )}
        </CardContent>
      </Card>
    </div>
  );
}

function SummaryCard({
  title,
  value,
  description,
  loading,
}: {
  title: string;
  value: string;
  description?: string;
  loading: boolean;
}) {
  return (
    <Card>
      <CardHeader>
        <CardDescription>{title}</CardDescription>
        <CardTitle className="text-2xl">
          {loading ? <Skeleton className="h-8 w-24" /> : value}
        </CardTitle>
      </CardHeader>
      {description && (
        <CardContent>
          <p className="text-muted-foreground text-xs">{description}</p>
        </CardContent>
      )}
    </Card>
  );
}

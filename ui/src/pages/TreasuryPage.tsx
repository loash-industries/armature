import { useParams } from "@tanstack/react-router";
import {
  Card,
  CardHeader,
  CardTitle,
  CardDescription,
  CardContent,
  Badge,
  Skeleton,
  Alert,
  AlertTitle,
  AlertDescription,
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
  useTreasuryEvents,
} from "@/hooks/useDao";

function formatBalance(raw: bigint): string {
  const sui = Number(raw) / 1_000_000_000;
  return sui.toLocaleString(undefined, {
    minimumFractionDigits: 0,
    maximumFractionDigits: 4,
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

export function TreasuryPage() {
  const { daoId } = useParams({ strict: false });
  const { data: dao, isError: daoError } = useDaoSummary(daoId ?? "");
  const { data: balances, isLoading: balancesLoading } = useTreasuryBalances(
    dao?.treasuryId,
  );
  const { data: events, isLoading: eventsLoading } = useTreasuryEvents(
    daoId ?? "",
  );

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

      <Card>
        <CardHeader>
          <CardTitle>Balances</CardTitle>
          <CardDescription>
            {balances
              ? `${balances.length} coin type${balances.length !== 1 ? "s" : ""}`
              : "Loading..."}
          </CardDescription>
        </CardHeader>
        <CardContent>
          {balancesLoading ? (
            <div className="space-y-3">
              {Array.from({ length: 3 }).map((_, i) => (
                <Skeleton key={i} className="h-8 w-full" />
              ))}
            </div>
          ) : balances && balances.length > 0 ? (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Coin Type</TableHead>
                  <TableHead className="text-right">Balance</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {balances.map((b) => (
                  <TableRow key={b.coinType}>
                    <TableCell className="font-mono">
                      {shortCoinType(b.coinType)}
                    </TableCell>
                    <TableCell className="text-right font-mono">
                      {formatBalance(b.balance)}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          ) : (
            <p className="text-muted-foreground text-sm">
              No coins in treasury.
            </p>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Transaction History</CardTitle>
        </CardHeader>
        <CardContent>
          {eventsLoading ? (
            <div className="space-y-3">
              {Array.from({ length: 3 }).map((_, i) => (
                <Skeleton key={i} className="h-6 w-full" />
              ))}
            </div>
          ) : events && events.length > 0 ? (
            <div className="space-y-3">
              {events.map((ev) => (
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
              No treasury transactions yet.
            </p>
          )}
        </CardContent>
      </Card>
    </div>
  );
}

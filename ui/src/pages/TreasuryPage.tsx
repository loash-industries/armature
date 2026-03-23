import { useParams } from "@tanstack/react-router";
import { useState } from "react";
import { Alert, AlertTitle, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardHeader,
  CardTitle,
  CardDescription,
  CardContent,
} from "@/components/ui/card";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
} from "@/components/ui/dialog";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectTrigger,
  SelectValue,
  SelectContent,
  SelectItem,
} from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import {
  Table,
  TableHeader,
  TableHead,
  TableBody,
  TableRow,
  TableCell,
} from "@/components/ui/table";
import { useSuiClient } from "@mysten/dapp-kit";
import { useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import {
  useDaoSummary,
  useTreasuryBalances,
  useTreasuryEvents,
} from "@/hooks/useDao";
import { useWalletSigner } from "@/hooks/useWalletSigner";
import { useWalletCoins } from "@/hooks/useWalletCoins";
import { buildDeposit } from "@/lib/transactions";
import { cacheKeys } from "@/lib/cache-keys";

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
  const { address, signAndExecuteTransaction } = useWalletSigner();
  const { data: walletCoins } = useWalletCoins();
  const client = useSuiClient();
  const queryClient = useQueryClient();
  const [depositOpen, setDepositOpen] = useState(false);
  const [selectedCoin, setSelectedCoin] = useState("");
  const [depositPending, setDepositPending] = useState(false);

  const selectedCoinObj = walletCoins?.find(
    (c) => c.coinObjectId === selectedCoin,
  );

  async function handleDeposit() {
    if (!dao || !selectedCoin || !selectedCoinObj) return;
    setDepositPending(true);
    try {
      const transaction = buildDeposit({
        treasuryId: dao.treasuryId,
        coinObjectId: selectedCoin,
        coinType: selectedCoinObj.coinType,
      });
      const result = await signAndExecuteTransaction({ transaction });
      toast.success("Deposit successful");
      await client.waitForTransaction({ digest: result.digest });
      await queryClient.invalidateQueries({
        queryKey: cacheKeys.dao(daoId ?? ""),
      });
      setDepositOpen(false);
      setSelectedCoin("");
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Deposit failed");
    } finally {
      setDepositPending(false);
    }
  }

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
          <div className="flex items-center justify-between">
            <div>
              <CardTitle>Balances</CardTitle>
              <CardDescription>
                {balances
                  ? `${balances.length} coin type${balances.length !== 1 ? "s" : ""}`
                  : "Loading..."}
              </CardDescription>
            </div>
            {address && (
              <Button variant="outline" size="sm" onClick={() => setDepositOpen(true)}>
                Deposit
              </Button>
            )}
          </div>
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

      <Dialog open={depositOpen} onOpenChange={setDepositOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Deposit to Treasury</DialogTitle>
            <DialogDescription>
              Select a coin from your wallet to deposit into the DAO treasury.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <div className="space-y-2">
              <Label>Coin to Deposit</Label>
              <Select value={selectedCoin} onValueChange={(v) => setSelectedCoin(v ?? "")}>
                <SelectTrigger>
                  <SelectValue placeholder="Select a coin..." />
                </SelectTrigger>
                <SelectContent>
                  {walletCoins?.map((c) => (
                    <SelectItem key={c.coinObjectId} value={c.coinObjectId}>
                      {shortCoinType(c.coinType)} — {formatBalance(c.balance)}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            {selectedCoinObj && (
              <p className="text-sm">
                <span className="text-muted-foreground">Amount:</span>{" "}
                <span className="font-mono">
                  {formatBalance(selectedCoinObj.balance)}{" "}
                  {shortCoinType(selectedCoinObj.coinType)}
                </span>
              </p>
            )}
            <Button
              className="w-full"
              disabled={!selectedCoin || depositPending}
              onClick={handleDeposit}
            >
              {depositPending ? "Depositing..." : "Deposit"}
            </Button>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
}

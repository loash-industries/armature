import { useParams } from "@tanstack/react-router";
import { useState, useEffect, useMemo } from "react";
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
  useTreasuryEvents,
  useCoinMetadataMap,
} from "@/hooks/useDao";
import { useLiveTreasury } from "@/hooks/useLiveTreasury";
import { useLiveCoinTransfers } from "@/hooks/useLiveCoinTransfers";
import type { TreasuryRelayEvent } from "@/hooks/useFrameworkRelay";
import type { CoinTransferEvent } from "@/hooks/useLiveCoinTransfers";
import { useWalletSigner } from "@/hooks/useWalletSigner";
import { useWalletCoins } from "@/hooks/useWalletCoins";
import { getAddressName } from "@/lib/address-namer";
import { AddressName } from "@/components/AddressName";
import { buildSplitAndDeposit } from "@/lib/transactions";
import { cacheKeys } from "@/lib/cache-keys";
import { CoinAmountInput } from "@/components/ui/CoinAmountInput";
import { formatBalance, parseAmount } from "@/lib/coins";

function CoinIcon({ iconUrl, symbol }: { iconUrl: string | null; symbol: string }) {
  const [imgError, setImgError] = useState(false);
  if (iconUrl && !imgError) {
    return (
      <img
        src={iconUrl}
        alt={symbol}
        className="h-5 w-5 rounded-full object-cover"
        onError={() => {
          setImgError(true);
        }}
      />
    );
  }
  return (
    <div className="bg-muted text-muted-foreground flex h-5 w-5 items-center justify-center rounded-full text-[10px] font-bold uppercase">
      {symbol.slice(0, 2)}
    </div>
  );
}

function formatBalanceLocale(raw: bigint, decimals = 9): string {
  // Use the shared formatBalance for precision, then apply locale formatting.
  const base = formatBalance(raw, decimals);
  const num = parseFloat(base);
  if (isNaN(num)) return base;
  return num.toLocaleString(undefined, {
    minimumFractionDigits: 0,
    maximumFractionDigits: 4,
  });
}

function shortCoinType(coinType: string): string {
  const parts = coinType.split("::");
  return parts[parts.length - 1] ?? coinType;
}

/** Shorten a full coin type to "0xABCD…EFGH::module::TYPE" */
function truncateCoinType(coinType: string): string {
  const parts = coinType.split("::");
  if (parts.length < 3) return coinType;
  const pkg = parts[0];
  const rest = parts.slice(1).join("::");
  if (pkg.length > 12) {
    const short = `${pkg.slice(0, 6)}…${pkg.slice(-4)}`;
    return `${short}::${rest}`;
  }
  return coinType;
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

// ─── Ticking clock ───────────────────────────────────────────────────────────

/** Re-renders the calling component every second so relative timestamps stay current. */
function useNow() {
  const [now, setNow] = useState(Date.now)
  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), 1000)
    return () => clearInterval(id)
  }, [])
  return now
}

// ─── Live Activity ────────────────────────────────────────────────────────────

type LiveRow = {
  key: string;
  badge: string;
  description: string;
  timestamp: number;
  /** True for rows that arrived via relay since page load, false for RPC history. */
  live: boolean;
  /** Flow direction for ingress / egress display. */
  direction: 'ingress' | 'egress';
  /** Fully-qualified coin type (e.g. "0x2::sui::SUI"). */
  coinType?: string;
  /** Raw amount string (smallest unit). */
  amount?: string;
  /** Counterparty address (depositor for ingress, recipient for egress). */
  counterparty?: string;
};

function buildLiveRows(
  relayFeed: TreasuryRelayEvent[],
  coinTransfers: CoinTransferEvent[],
  metadataMap: Record<string, { symbol?: string; decimals?: number }> | undefined,
  treasuryId: string,
): LiveRow[] {
  function coinLabel(coinType: string) {
    return metadataMap?.[coinType]?.symbol ?? shortCoinType(coinType);
  }
  function decimals(coinType: string) {
    return metadataMap?.[coinType]?.decimals ?? 9;
  }

  const frameworkRows: LiveRow[] = relayFeed.map((e) => ({
    key: `fw-${e.timestamp}-${e.coinType}-${e.kind}`,
    badge:
      e.kind === "deposited"
        ? "Deposit"
        : e.kind === "withdrawn"
          ? "Withdrawal"
          : "Claim",
    description: `${formatBalanceLocale(e.amount, decimals(e.coinType))} ${coinLabel(e.coinType)} by ${getAddressName(e.actor)}`,
    timestamp: e.timestamp,
    live: true,
    direction: e.kind === "withdrawn" ? "egress" : "ingress",
    coinType: e.coinType,
    amount: e.amount.toString(),
    counterparty: e.actor,
  }));

  const relevantTransfers = coinTransfers.filter((e) =>
    e.direction === "inbound"
      ? e.toOwner === treasuryId
      : e.fromOwner === treasuryId,
  );

  const transferRows: LiveRow[] = relevantTransfers.map((e) => ({
    key: `xfer-${e.txDigest}-${e.objectId}`,
    badge: e.direction === "inbound" ? "Received" : "Sent",
    description:
      e.direction === "inbound"
        ? `${formatBalanceLocale(BigInt(e.amount), decimals(e.coinType))} ${coinLabel(e.coinType)} from ${getAddressName(e.fromOwner ?? e.sender)}`
        : `${formatBalanceLocale(BigInt(e.amount), decimals(e.coinType))} ${coinLabel(e.coinType)} to ${getAddressName(e.toOwner)}`,
    timestamp: e.timestamp,
    live: true,
    direction: e.direction === "inbound" ? "ingress" : "egress",
    coinType: e.coinType,
    amount: e.amount,
    counterparty: e.direction === "inbound" ? (e.fromOwner ?? e.sender) : e.toOwner,
  }));

  return [...frameworkRows, ...transferRows].sort(
    (a, b) => b.timestamp - a.timestamp,
  );
}

function LiveActivitySection({
  relayFeed,
  coinTransfers,
  metadataMap,
  treasuryId,
  daoId,
}: {
  relayFeed: TreasuryRelayEvent[];
  coinTransfers: CoinTransferEvent[];
  metadataMap: Record<string, { symbol?: string; decimals?: number }> | undefined;
  treasuryId: string;
  daoId: string;
}) {
  useNow(); // drives 1s re-renders so timeAgo() stays current — scoped here, not the whole page
  const { data: events, isLoading: historyLoading } = useTreasuryEvents(daoId, treasuryId);

  const liveRows = buildLiveRows(relayFeed, coinTransfers, metadataMap, treasuryId);

  // Only surface relay rows that are newer than the most recent historical event.
  // Once React Query refetches (triggered by relay invalidation) the historical
  // list will catch up and the relay rows drop out automatically.
  const mostRecentHistoricalTs = events?.[0]?.timestampMs ?? 0;
  const newLiveRows = liveRows.filter((r) => r.timestamp > mostRecentHistoricalTs);

  const EGRESS_EVENTS = new Set(["CoinWithdrawn", "CoinSent", "CoinSentToDAO", "SmallPaymentSent"]);

  const historicalRows: LiveRow[] = (events ?? []).map((e) => ({
    key: `hist-${e.txDigest}-${e.eventType}`,
    badge: e.label,
    description: e.description,
    timestamp: e.timestampMs,
    live: false,
    direction: EGRESS_EVENTS.has(e.eventType) ? "egress" as const : "ingress" as const,
    coinType: e.coinType,
    amount: e.coinAmount,
    counterparty: e.actor ?? e.recipient,
  }));

  const allRows = [...newLiveRows, ...historicalRows].sort(
    (a, b) => b.timestamp - a.timestamp,
  );

  if (historyLoading && allRows.length === 0) {
    return (
      <div className="space-y-3">
        {Array.from({ length: 3 }).map((_, i) => (
          <Skeleton key={i} className="h-6 w-full" />
        ))}
      </div>
    );
  }

  if (allRows.length === 0) {
    return (
      <p className="text-muted-foreground text-sm">No treasury transactions yet.</p>
    );
  }

  const hasLive = newLiveRows.length > 0;

  return (
    <div className="space-y-2">
      {hasLive && (
        <div className="mb-1 flex items-center gap-1.5">
          <span className="relative flex h-2 w-2">
            <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-green-400 opacity-75" />
            <span className="relative inline-flex h-2 w-2 rounded-full bg-green-500" />
          </span>
          <span className="text-xs font-medium text-green-600">Live</span>
        </div>
      )}
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead className="w-10" />
            <TableHead>Type</TableHead>
            <TableHead>Coin</TableHead>
            <TableHead className="text-right">Amount</TableHead>
            <TableHead>Counterparty</TableHead>
            <TableHead className="text-right">Time</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {allRows.map((row) => {
            const isIngress = row.direction === "ingress";
            const meta = row.coinType ? metadataMap?.[row.coinType] : undefined;
            const symbol = row.coinType
              ? (meta?.symbol ?? shortCoinType(row.coinType))
              : undefined;
            const dec = meta?.decimals ?? 9;
            return (
              <TableRow key={row.key}>
                <TableCell className="text-center">
                  <span
                    className={isIngress ? "text-green-600" : "text-red-500"}
                    title={isIngress ? "Ingress" : "Egress"}
                  >
                    {isIngress ? "\u2193" : "\u2191"}
                  </span>
                </TableCell>
                <TableCell>
                  <Badge variant={row.live ? "secondary" : "outline"}>
                    {row.badge}
                  </Badge>
                </TableCell>
                <TableCell className="font-mono text-xs">
                  {symbol ?? "—"}
                </TableCell>
                <TableCell
                  className={`text-right font-mono ${
                    isIngress ? "text-green-600" : "text-red-500"
                  }`}
                >
                  {row.amount
                    ? `${isIngress ? "+" : "\u2212"}${formatBalanceLocale(BigInt(row.amount), dec)}`
                    : "—"}
                </TableCell>
                <TableCell className="font-mono text-xs">
                  {row.counterparty ? <AddressName address={row.counterparty} /> : "—"}
                </TableCell>
                <TableCell className="text-muted-foreground text-right text-xs whitespace-nowrap">
                  {row.timestamp > 0 ? timeAgo(row.timestamp) : "—"}
                </TableCell>
              </TableRow>
            );
          })}
        </TableBody>
      </Table>
    </div>
  );
}

// ─── Page ─────────────────────────────────────────────────────────────────────

export function TreasuryPage() {
  const { daoId } = useParams({ strict: false });
  const { data: dao, isError: daoError } = useDaoSummary(daoId ?? "");
  const {
    data: balances,
    isLoading: balancesLoading,
    feed: relayFeed,
  } = useLiveTreasury(dao?.treasuryId);
  const coinTransfers = useLiveCoinTransfers(dao?.treasuryId);
  const { data: treasuryEvents } = useTreasuryEvents(daoId ?? "", dao?.treasuryId);

  const { address, signAndExecuteTransaction } = useWalletSigner();
  const { data: walletCoins } = useWalletCoins();

  // Stabilise the coin-types array identity so useCoinMetadataMap doesn't
  // recompute its query key (and potentially refetch) on every render.
  // Include wallet coin types so the deposit dialog gets correct decimals
  // even for coins not yet held in the treasury.
  const coinTypes = useMemo(() => {
    const set = new Set<string>();
    for (const b of balances ?? []) set.add(b.coinType);
    for (const e of relayFeed) set.add(e.coinType);
    for (const e of coinTransfers.feed) set.add(e.coinType);
    for (const e of treasuryEvents ?? []) if (e.coinType) set.add(e.coinType);
    for (const c of walletCoins ?? []) set.add(c.coinType);
    return [...set];
  }, [balances, relayFeed, coinTransfers.feed, treasuryEvents, walletCoins]);
  const { data: metadataMap } = useCoinMetadataMap(coinTypes);
  const client = useSuiClient();
  const queryClient = useQueryClient();
  const [depositOpen, setDepositOpen] = useState(false);
  const [selectedCoinType, setSelectedCoinType] = useState("");
  const [depositAmount, setDepositAmount] = useState("");
  const [depositPending, setDepositPending] = useState(false);

  // Aggregate wallet coin objects by coin type so users see a single balance per token.
  const aggregatedCoins = useMemo(() => {
    if (!walletCoins) return [];
    const map = new Map<string, { coinType: string; totalBalance: bigint; objectIds: string[] }>();
    for (const c of walletCoins) {
      const existing = map.get(c.coinType);
      if (existing) {
        existing.totalBalance += c.balance;
        existing.objectIds.push(c.coinObjectId);
      } else {
        map.set(c.coinType, {
          coinType: c.coinType,
          totalBalance: c.balance,
          objectIds: [c.coinObjectId],
        });
      }
    }
    return [...map.values()];
  }, [walletCoins]);

  const selectedGroup = aggregatedCoins.find((c) => c.coinType === selectedCoinType);
  const selectedMeta = selectedCoinType ? metadataMap?.[selectedCoinType] : undefined;
  const selectedSymbol = selectedMeta?.symbol ?? (selectedCoinType ? shortCoinType(selectedCoinType) : "");
  const selectedDecimals = selectedMeta?.decimals ?? 9;

  async function handleDeposit() {
    if (!dao || !selectedCoinType || !selectedGroup) return;
    setDepositPending(true);

    let amount: bigint | undefined;
    const trimmed = depositAmount.trim();
    if (trimmed) {
      const rawAmount = parseAmount(trimmed, selectedDecimals);
      if (rawAmount === null || rawAmount <= 0n) {
        toast.error("Invalid amount");
        setDepositPending(false);
        return;
      }
      // Only split if the requested amount is strictly less than the total balance.
      if (rawAmount < selectedGroup.totalBalance) {
        amount = rawAmount;
      }
    }

    try {
      const transaction = buildSplitAndDeposit({
        treasuryId: dao.treasuryId,
        coinObjectIds: selectedGroup.objectIds,
        coinType: selectedCoinType,
        amount,
      });
      const result = await signAndExecuteTransaction({ transaction });
      toast.success("Deposit successful");
      await client.waitForTransaction({ digest: result.digest });
      await queryClient.invalidateQueries({
        queryKey: cacheKeys.dao(daoId ?? ""),
      });
      setDepositOpen(false);
      setSelectedCoinType("");
      setDepositAmount("");
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
                {balances.map((b) => {
                  const meta = metadataMap?.[b.coinType];
                  const symbol = meta?.symbol ?? shortCoinType(b.coinType);
                  const decimals = meta?.decimals ?? 9;
                  return (
                    <TableRow key={b.coinType}>
                      <TableCell>
                        <div className="flex items-center gap-2">
                          <CoinIcon iconUrl={meta?.iconUrl ?? null} symbol={symbol} />
                          <span className="font-mono">{symbol}</span>
                          {meta?.name && meta.name !== symbol && (
                            <span className="text-muted-foreground text-xs">{meta.name}</span>
                          )}
                        </div>
                      </TableCell>
                      <TableCell className="text-right font-mono">
                        {formatBalanceLocale(b.balance, decimals)}
                      </TableCell>
                    </TableRow>
                  );
                })}
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
          <LiveActivitySection
            relayFeed={relayFeed}
            coinTransfers={coinTransfers.feed}
            metadataMap={metadataMap}
            treasuryId={dao?.treasuryId ?? ""}
            daoId={daoId ?? ""}
          />
        </CardContent>
      </Card>

      <Dialog open={depositOpen} onOpenChange={(open) => {
        setDepositOpen(open);
        if (!open) { setSelectedCoinType(""); setDepositAmount(""); }
      }}>
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
              <Select
                value={selectedCoinType}
                onValueChange={(v) => {
                  setSelectedCoinType(v ?? "");
                  setDepositAmount("");
                }}
              >
                <SelectTrigger className="w-full">
                  {selectedCoinType ? (
                    <span className="flex min-w-0 items-center gap-1.5 overflow-hidden">
                      <span className="font-mono font-medium">{selectedSymbol}</span>
                      <span className="text-muted-foreground">—</span>
                      <span className="text-muted-foreground truncate font-mono text-xs">
                        {truncateCoinType(selectedCoinType)}
                      </span>
                    </span>
                  ) : (
                    <SelectValue placeholder="Select a coin..." />
                  )}
                </SelectTrigger>
                <SelectContent>
                  {aggregatedCoins.map((c) => {
                    const meta = metadataMap?.[c.coinType];
                    const sym = meta?.symbol ?? shortCoinType(c.coinType);
                    const dec = meta?.decimals ?? 9;
                    return (
                      <SelectItem key={c.coinType} value={c.coinType}>
                        <span className="flex min-w-0 items-center gap-1.5">
                          <span className="font-mono font-medium">{sym}</span>
                          <span className="text-muted-foreground">—</span>
                          <span className="text-muted-foreground font-mono text-xs">
                            {truncateCoinType(c.coinType)}
                          </span>
                          <span className="text-muted-foreground">·</span>
                          <span className="font-mono text-xs">{formatBalanceLocale(c.totalBalance, dec)}</span>
                        </span>
                      </SelectItem>
                    );
                  })}
                </SelectContent>
              </Select>
            </div>
            {selectedGroup && (
              <div className="space-y-2">
                <CoinAmountInput
                  value={depositAmount}
                  onChange={setDepositAmount}
                  symbol={selectedSymbol}
                  decimals={selectedDecimals}
                  maxBalance={selectedGroup.totalBalance}
                  label="Amount"
                  disabled={depositPending}
                />
                {selectedGroup.objectIds.length > 1 && (
                  <p className="text-muted-foreground text-xs">
                    {selectedGroup.objectIds.length} objects will be merged.
                  </p>
                )}
              </div>
            )}
            <Button
              className="w-full"
              disabled={!selectedCoinType || depositPending}
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

/**
 * CoinSelect — A treasury coin selector with truncated package IDs and balance display.
 *
 * Used by proposal forms that need to pick a coin type from the DAO treasury.
 * Shows the coin symbol, truncated full type (hover for full), and available balance.
 */

import {
  Select,
  SelectTrigger,
  SelectValue,
  SelectContent,
  SelectItem,
} from "@/components/ui/select";
import { formatBalance } from "@/lib/coins";
import type { CoinMeta } from "@/hooks/useDao";

export interface TreasuryBalance {
  coinType: string;
  balance: bigint;
}

/** Shorten "0xABCDEF0123456789…::module::TYPE" → "0xABCD…6789::module::TYPE" */
function truncateCoinType(coinType: string): string {
  const parts = coinType.split("::");
  if (parts.length < 3) return coinType;
  const pkg = parts[0];
  const rest = parts.slice(1).join("::");
  if (pkg.length > 12) {
    return `${pkg.slice(0, 6)}…${pkg.slice(-4)}::${rest}`;
  }
  return coinType;
}

function formatBalanceLocale(raw: bigint, decimals = 9): string {
  const base = formatBalance(raw, decimals);
  const num = parseFloat(base);
  if (isNaN(num)) return base;
  return num.toLocaleString(undefined, {
    minimumFractionDigits: 0,
    maximumFractionDigits: 4,
  });
}

interface CoinSelectProps {
  value: string;
  onValueChange: (coinType: string) => void;
  balances: TreasuryBalance[] | undefined;
  metadataMap: Record<string, CoinMeta> | undefined;
  placeholder?: string;
}

export function CoinSelect({
  value,
  onValueChange,
  balances,
  metadataMap,
  placeholder = "Select coin from treasury...",
}: CoinSelectProps) {
  const selectedMeta = value ? metadataMap?.[value] : undefined;
  const selectedSymbol =
    selectedMeta?.symbol ?? (value ? value.split("::").pop() ?? "" : "");

  return (
    <Select value={value} onValueChange={(v) => { if (v) onValueChange(v); }}>
      <SelectTrigger className="w-full">
        {value ? (
          <span className="flex min-w-0 items-center gap-1.5 overflow-hidden">
            <span className="font-mono font-medium">{selectedSymbol}</span>
            <span className="text-muted-foreground">—</span>
            <span className="text-muted-foreground truncate font-mono text-xs">
              {truncateCoinType(value)}
            </span>
          </span>
        ) : (
          <SelectValue placeholder={placeholder} />
        )}
      </SelectTrigger>
      <SelectContent alignItemWithTrigger={false}>
        {balances && balances.length > 0 ? (
          balances.map((b) => {
            const meta = metadataMap?.[b.coinType];
            const sym =
              meta?.symbol ?? b.coinType.split("::").pop() ?? b.coinType;
            const dec = meta?.decimals ?? 9;
            return (
              <SelectItem key={b.coinType} value={b.coinType}>
                <span className="flex min-w-0 items-center gap-1.5">
                  <span className="font-mono font-medium">{sym}</span>
                  <span className="text-muted-foreground">—</span>
                  <span className="text-muted-foreground font-mono text-xs">
                    {truncateCoinType(b.coinType)}
                  </span>
                  <span className="text-muted-foreground">·</span>
                  <span className="font-mono text-xs">
                    {formatBalanceLocale(b.balance, dec)}
                  </span>
                </span>
              </SelectItem>
            );
          })
        ) : (
          <SelectItem value="" disabled>
            No coins in treasury
          </SelectItem>
        )}
      </SelectContent>
    </Select>
  );
}

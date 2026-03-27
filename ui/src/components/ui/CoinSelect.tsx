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
  return (
    <Select value={value} onValueChange={(v) => { if (v) onValueChange(v); }}>
      <SelectTrigger className="w-full">
        <SelectValue placeholder={placeholder} />
      </SelectTrigger>
      <SelectContent>
        {balances && balances.length > 0 ? (
          balances.map((b) => {
            const meta = metadataMap?.[b.coinType];
            const sym =
              meta?.symbol ?? b.coinType.split("::").pop() ?? b.coinType;
            const dec = meta?.decimals ?? 9;
            return (
              <SelectItem key={b.coinType} value={b.coinType}>
                <span
                  className="flex items-center gap-1.5"
                  title={b.coinType}
                >
                  <span className="font-mono font-medium">{sym}</span>
                  <span className="text-muted-foreground text-xs">
                    ({truncateCoinType(b.coinType)})
                  </span>
                  <span className="text-muted-foreground text-xs">
                    — {formatBalance(b.balance, dec)} available
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

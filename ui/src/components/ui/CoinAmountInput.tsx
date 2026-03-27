/**
 * CoinAmountInput — A decimal-aware amount input with coin symbol and Max shortcut.
 *
 * Works standalone (plain useState) or inside a react-hook-form <FormField>.
 * When used inside a form, wrap it with <FormItem> in the render prop and pass
 * `errorMessage` from field state if you want inline validation display.
 *
 * Call `parseAmount(value, decimals)` from `@/lib/coins` to convert to base units
 * before submitting to the chain.
 */

import { Input } from "@/components/ui/input";
import { formatBalance } from "@/lib/coins";

interface CoinAmountInputProps {
  /** Human-readable amount value. */
  value: string;
  onChange: (newValue: string) => void;
  /** Coin symbol shown as a suffix (e.g. "SUI"). */
  symbol: string;
  /** Number of decimal places for this coin. */
  decimals: number;
  /** Raw bigint balance limit (base units). Omit to hide the Max button. */
  maxBalance?: bigint;
  /** Input label. */
  label?: string;
  /** Whether the input is disabled. */
  disabled?: boolean;
  /** Optional inline error message (e.g. from react-hook-form fieldState.error.message). */
  errorMessage?: string;
}

export function CoinAmountInput({
  value,
  onChange,
  symbol,
  decimals,
  maxBalance,
  label = "Amount",
  disabled,
  errorMessage,
}: CoinAmountInputProps) {
  const maxHuman =
    maxBalance !== undefined ? formatBalance(maxBalance, decimals) : undefined;

  return (
    <div className="space-y-1.5">
      <div className="flex items-center justify-between">
        <label className="text-sm leading-none font-medium peer-disabled:cursor-not-allowed peer-disabled:opacity-70">
          {label}
        </label>
        {maxHuman !== undefined && (
          <button
            type="button"
            className="text-muted-foreground hover:text-foreground text-xs transition-colors"
            onClick={() => onChange(maxHuman)}
            disabled={disabled}
          >
            Max:{" "}
            <span className="font-mono">
              {maxHuman} {symbol}
            </span>
          </button>
        )}
      </div>
      <div className="relative">
        <Input
          type="number"
          min="0"
          step="any"
          placeholder="0.00"
          value={value}
          onChange={(e) => onChange(e.target.value)}
          disabled={disabled}
          className={symbol ? "pr-14" : undefined}
        />
        {symbol && (
          <span className="text-muted-foreground pointer-events-none absolute right-3 top-1/2 -translate-y-1/2 font-mono text-xs">
            {symbol}
          </span>
        )}
      </div>
      {errorMessage && (
        <p className="text-destructive text-sm font-medium">{errorMessage}</p>
      )}
    </div>
  );
}


/**
 * CoinAmountInput — A coin-aware amount input backed by NumericInput.
 *
 * Accepts and emits raw base-unit bigint values (e.g. MIST for SUI).
 * Internally the user types human-readable decimal amounts (e.g. "1.5")
 * which NumericInput handles natively. Conversion to/from base units
 * happens at the boundary via the `decimals` prop.
 */

import { useCallback } from "react";
import { AnimatedNumber, NumericInput } from "@loash-industries/ui";
import { formatBalance } from "@/lib/coins";

interface CoinAmountInputProps {
  /** Raw bigint value in base units (e.g. MIST for SUI). */
  value: bigint | null;
  onChange: (newValue: bigint | null) => void;
  /** Coin symbol shown as a suffix label (e.g. "SUI"). */
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

/** Convert a human-readable number (e.g. 1.5) to base-unit bigint (e.g. 1_500_000_000n for 9 decimals). */
function humanToBigint(human: number, decimals: number): bigint {
  // Multiply first to keep precision, then truncate to integer.
  const scaled = Math.round(human * 10 ** decimals);
  return BigInt(scaled);
}

/** Convert a base-unit bigint to a human-readable number. */
function bigintToHuman(raw: bigint, decimals: number): number {
  return Number(raw) / 10 ** decimals;
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
  const maxHumanNum =
    maxBalance !== undefined ? bigintToHuman(maxBalance, decimals) : undefined;
  const humanValue = value != null ? bigintToHuman(value, decimals) : null;

  const handleNumericChange = useCallback(
    (num: number | null) => {
      if (num == null || num <= 0) {
        onChange(null);
        return;
      }
      onChange(humanToBigint(num, decimals));
    },
    [decimals, onChange],
  );

  return (
    <div className="space-y-1.5">
      <div className="flex items-center justify-between">
        <label className="text-sm leading-none font-medium peer-disabled:cursor-not-allowed peer-disabled:opacity-70">
          {label}
        </label>
        <div className="flex items-center gap-2">

          {maxHuman !== undefined && (
            <button
              type="button"
              className="text-muted-foreground hover:text-foreground text-xs transition-colors w-40 flex-row flex justify-end hover:cursor-pointer"
              onClick={() => onChange(maxBalance ?? null)}
              disabled={disabled}
            >
              Max:
              <AnimatedNumber
                className="font-mono pl-1"
                value={maxHumanNum ?? 0}
                decimalPlacesToDisplay={decimals}
              />
            </button>
          )}
          {symbol && (
            <span className="text-muted-foreground font-mono text-xs">{symbol}</span>
          )}
        </div>
      </div>
      <NumericInput
        value={humanValue}
        onChange={handleNumericChange}
        min={0}
        max={maxHumanNum}
        precision={decimals}
        disabled={disabled}
        placeholder="0"
        aria-invalid={!!errorMessage}
      />
      {errorMessage && (
        <p className="text-destructive text-sm font-medium">{errorMessage}</p>
      )}
    </div>
  );
}

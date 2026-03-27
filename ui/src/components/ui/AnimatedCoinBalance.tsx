/**
 * AnimatedCoinBalance — Renders a coin balance using FloatingAnimatedNumber.
 *
 * Splits a raw bigint base-unit balance into whole + decimal parts
 * suitable for FloatingAnimatedNumber, capped to 6 significant figures.
 */

import { FloatingAnimatedNumber } from "@loash-industries/ui";
import { splitBalance } from "@/lib/coins";

interface AnimatedCoinBalanceProps {
  /** Raw bigint balance in base units. */
  balance: bigint;
  /** Number of on-chain decimal places for this coin type. */
  decimals?: number;
  /** Coin symbol displayed after the number. */
  symbol?: string;
  /** Maximum decimal significant figures. Default: 6. */
  sigFigs?: number;
  /** Animation duration in ms. */
  duration?: number;
  className?: string;
}

export function AnimatedCoinBalance({
  balance,
  decimals = 9,
  symbol,
  sigFigs = 6,
  duration = 500,
  className,
}: AnimatedCoinBalanceProps) {
  const { whole, decimal, decimalPlaces } = splitBalance(balance, decimals, sigFigs);

  return (
    <span className={`inline-flex items-center gap-1 ${className ?? ""}`}>
      <FloatingAnimatedNumber
        wholeNumber={whole}
        decimalWholeNumber={decimal}
        decimalPlacesToDisplay={decimalPlaces}
        duration={duration}
      />
      {symbol && <span>{symbol}</span>}
    </span>
  );
}

/**
 * AnimatedValue — Renders a plain number using FloatingAnimatedNumber.
 *
 * Splits a JS number into whole + decimal parts for animated rendering.
 * Use for vote weights, percentages, share counts, etc.
 */

import { FloatingAnimatedNumber } from "@loash-industries/ui";
import { splitNumber } from "@/lib/coins";

interface AnimatedValueProps {
  /** The numeric value to display. */
  value: number;
  /** Maximum decimal significant figures. Default: 6. */
  sigFigs?: number;
  /** Suffix text (e.g. "%" or "shares"). */
  suffix?: string;
  /** Content rendered before the number. */
  prepend?: React.ReactNode;
  /** Content rendered after the number (but before the suffix). */
  append?: React.ReactNode;
  /** Animation duration in ms. */
  duration?: number;
  className?: string;
}

export function AnimatedValue({
  value,
  sigFigs = 6,
  suffix,
  prepend,
  append,
  duration = 500,
  className,
}: AnimatedValueProps) {
  const { whole, decimal, decimalPlaces } = splitNumber(value, sigFigs);

  return (
    <span className={`inline-flex items-center gap-1 ${className ?? ""}`}>
      <FloatingAnimatedNumber
        wholeNumber={whole}
        decimalWholeNumber={decimal}
        decimalPlacesToDisplay={decimalPlaces}
        duration={duration}
        prepend={prepend}
        append={append}
      />
      {suffix && <span>{suffix}</span>}
    </span>
  );
}

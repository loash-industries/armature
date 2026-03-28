import { AnimatedValue } from "@/components/ui/AnimatedValue";
import {
  Tooltip,
  TooltipTrigger,
  TooltipContent,
  TooltipProvider,
} from "@/components/ui/tooltip";

interface VoteBarProps {
  yesWeight: number;
  noWeight: number;
  totalSnapshotWeight: number;
  quorum: number;
  approvalThreshold: number;
  /**
   * When provided and non-null, the threshold line turns amber and floor info
   * is shown in the tooltip. Pass `floorBps` in basis-points (e.g. 5000 = 50%).
   */
  floorBps?: number | null;
  /** Show a participation % label centred between the Yes/No labels. */
  showParticipation?: boolean;
  /** Override the outer container width. Defaults to "w-32" when unset. */
  className?: string;
}

export function VoteBar({
  yesWeight,
  noWeight,
  totalSnapshotWeight,
  quorum,
  approvalThreshold,
  floorBps,
  showParticipation,
  className,
}: VoteBarProps) {
  const total = yesWeight + noWeight;
  const yesAbsolute =
    totalSnapshotWeight > 0 ? (yesWeight / totalSnapshotWeight) * 100 : 0;
  const noAbsolute =
    totalSnapshotWeight > 0 ? (noWeight / totalSnapshotWeight) * 100 : 0;
  const yesPercent = total > 0 ? (yesWeight / total) * 100 : 0;
  const noPercent = total > 0 ? (noWeight / total) * 100 : 0;
  const hasFloor = floorBps != null && floorBps > 0;
  const quorumPct = quorum / 100; // bps → %
  const thresholdPct = approvalThreshold / 100;
  const participationPct =
    totalSnapshotWeight > 0 ? (total / totalSnapshotWeight) * 100 : 0;
  // On-chain: threshold = yes / totalVoted, quorum = totalVoted / totalSnapshotWeight
  const quorumMet = participationPct >= quorumPct;
  const thresholdMet = total > 0 && yesPercent >= thresholdPct;
  const passing = quorumMet && thresholdMet;

  // Quorum line position (% of total weight bar)
  const quorumLinePercent = quorumPct;
  // Floor line position (% of total weight bar) — only when a floor applies
  const floorLinePercent = hasFloor ? floorBps! / 100 : 0;

  const tooltipContent = (
    <div className="w-56 space-y-3 text-xs">
      {/* Yes / No rows */}
      <div className="space-y-1.5">
        <div className="flex items-center gap-2">
          <span className="h-2 w-2 flex-shrink-0 rounded-full bg-blue-500" />
          <span className="w-6 text-background/60">Yes</span>
          <span className="font-semibold text-blue-400">
            {yesWeight.toLocaleString()}
          </span>
          <span className="ml-auto text-background/50">
            {yesPercent.toFixed(1)}% of cast
          </span>
        </div>
        <div className="flex items-center gap-2">
          <span className="h-2 w-2 flex-shrink-0 rounded-full bg-red-500" />
          <span className="w-6 text-background/60">No</span>
          <span className="font-semibold text-red-400">
            {noWeight.toLocaleString()}
          </span>
          <span className="ml-auto text-background/50">
            {noPercent.toFixed(1)}% of cast
          </span>
        </div>
      </div>

      {/* Stats */}
      <div className="space-y-1 border-t border-background/15 pt-2.5">
        <div className="flex justify-between gap-4">
          <span className="text-background/50">Votes cast</span>
          <span className="font-medium tabular-nums">
            {total.toLocaleString()} / {totalSnapshotWeight.toLocaleString()}
            {" "}({participationPct.toFixed(1)}%)
          </span>
        </div>
        {quorumPct > 0 && (
          <div className="flex justify-between gap-4">
            <span className="text-background/50">Quorum</span>
            <span className={`font-medium ${quorumMet ? "text-green-400" : ""}`}>
              {quorumPct.toFixed(1)}% participation
              {quorumMet ? " ✓" : ""}
            </span>
          </div>
        )}
        {thresholdPct > 0 && (
          <div className="flex justify-between gap-4">
            <span className="text-background/50">Threshold</span>
            <span className={`font-medium ${thresholdMet ? "text-green-400" : ""}`}>
              {thresholdPct.toFixed(1)}% of votes cast
              {thresholdMet ? " ✓" : ""}
            </span>
          </div>
        )}
        {hasFloor && (
          <div className="flex justify-between gap-4">
            <span className="text-amber-400/80">Exec floor</span>
            <span className="font-medium text-amber-400">
              {(floorBps! / 100).toFixed(1)}% of total weight
            </span>
          </div>
        )}
      </div>

      {/* Status badge */}
      <div
        className={`rounded-md py-1.5 text-center text-[11px] font-semibold tracking-wide ${
          total === 0
            ? "bg-background/10 text-background/40"
            : passing
              ? "bg-blue-500/15 text-blue-300"
              : "bg-red-500/15 text-red-300"
        }`}
      >
        {total === 0
          ? "No votes cast yet"
          : passing
            ? "Currently passing"
            : !quorumMet
              ? "Quorum not reached"
              : "Threshold not met"}
      </div>
    </div>
  );

  return (
    <TooltipProvider>
      <Tooltip>
        <TooltipTrigger render={<div />}>
          <div className={className ?? "w-32 space-y-1"}>
            <div className="flex items-center justify-between text-xs">
              <span className="font-medium text-blue-500">
                <AnimatedValue value={yesWeight} />{" "}
                <span className="text-muted-foreground">
                  (<AnimatedValue value={yesPercent} suffix="%" />)
                </span>
              </span>
              {showParticipation && (
                <span className="mx-2 text-muted-foreground">
                  <AnimatedValue value={parseFloat(participationPct.toFixed(2))} suffix="%" /> participated
                  {" "}· quorum{" "}
                  <AnimatedValue value={parseFloat(quorumPct.toFixed(2))} suffix="%" />
                  {hasFloor && (
                    <>
                      {" "}·{" "}
                      <span className="text-amber-400">
                        floor <AnimatedValue value={floorBps! / 100} suffix="%" />
                      </span>
                    </>
                  )}
                </span>
              )}
              <span className="font-medium text-red-500">
                <AnimatedValue value={noWeight} />{" "}
                <span className="text-muted-foreground">
                  (<AnimatedValue value={noPercent} suffix="%" />)
                </span>
              </span>
            </div>
            <div className="relative h-3 w-full">
              <div className="absolute inset-0 overflow-hidden rounded-full bg-muted">
                <div
                  className="absolute left-0 top-0 h-full bg-blue-500 transition-all"
                  style={{ width: `${yesAbsolute}%` }}
                />
                <div
                  className="absolute top-0 h-full bg-red-500 transition-all"
                  style={{ left: `${yesAbsolute}%`, width: `${noAbsolute}%` }}
                />
              </div>
              {/* Quorum line — marks participation threshold on the total-weight bar */}
              {quorumLinePercent > 0 && (
                <div
                  className="absolute z-10 -bottom-1 -top-1 w-0.5 rounded-sm bg-white/80"
                  style={{ left: `${Math.min(quorumLinePercent, 99.5)}%` }}
                />
              )}
              {/* Execution floor line — amber, only for types that require one */}
              {hasFloor && floorLinePercent > 0 && (
                <div
                  className="absolute z-10 -bottom-1 -top-1 w-0.5 rounded-sm bg-amber-400/90"
                  style={{ left: `${Math.min(floorLinePercent, 99.5)}%` }}
                />
              )}
            </div>
          </div>
        </TooltipTrigger>
        <TooltipContent side="bottom" className="p-3">
          {tooltipContent}
        </TooltipContent>
      </Tooltip>
    </TooltipProvider>
  );
}

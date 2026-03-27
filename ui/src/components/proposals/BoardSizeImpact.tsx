import { useGovernanceConfig } from "@/hooks/useDao";
import { PROPOSAL_TYPE_DISPLAY_NAME } from "@/config/proposal-types";
import { Badge } from "@/components/ui/badge";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { ArrowRight, TrendingUp, TrendingDown, Minus } from "lucide-react";

interface BoardSizeImpactProps {
  daoId: string;
  currentSize: number;
  newSize: number;
}

/** Minimum votes required to meet a threshold (basis points) for a given board size. */
function votesRequired(boardSize: number, thresholdBps: number): number {
  return Math.ceil((thresholdBps / 10_000) * boardSize);
}

/**
 * Shows how changing the board size affects the number of approvals needed
 * for each enabled proposal type, given their configured approval thresholds.
 */
export function BoardSizeImpact({ daoId, currentSize, newSize }: BoardSizeImpactProps) {
  const { data: govConfig } = useGovernanceConfig(daoId);

  if (!govConfig || currentSize === newSize) return null;

  const enabledWithThresholds = govConfig.filter(
    (t) => t.enabled && t.config && t.config.approvalThreshold > 0,
  );

  if (enabledWithThresholds.length === 0) return null;

  const rows = enabledWithThresholds.map((t) => {
    const thresholdBps = t.config!.approvalThreshold;
    const currentVotes = votesRequired(currentSize, thresholdBps);
    const newVotes = votesRequired(newSize, thresholdBps);
    const delta = newVotes - currentVotes;
    return {
      typeKey: t.typeKey,
      label:
        PROPOSAL_TYPE_DISPLAY_NAME[
          t.typeKey as keyof typeof PROPOSAL_TYPE_DISPLAY_NAME
        ] ?? t.typeKey,
      thresholdBps,
      currentVotes,
      newVotes,
      delta,
    };
  });

  const increasing = newSize > currentSize;

  return (
    <div className="bg-muted/30 space-y-3 rounded-lg border p-4">
      <div className="flex items-center gap-2">
        {increasing ? (
          <TrendingUp className="h-4 w-4 text-amber-500" />
        ) : (
          <TrendingDown className="h-4 w-4 text-blue-500" />
        )}
        <p className="text-sm font-semibold">
          Approval Impact — Board{" "}
          <span className="tabular-nums">{currentSize}</span>
          <ArrowRight className="mx-1 inline h-3 w-3" />
          <span className="tabular-nums">{newSize}</span>
        </p>
      </div>

      <Table>
        <TableHeader>
          <TableRow>
            <TableHead className="w-[40%]">Proposal Type</TableHead>
            <TableHead className="text-center">Threshold</TableHead>
            <TableHead className="text-center">Current</TableHead>
            <TableHead className="text-center">New</TableHead>
            <TableHead className="text-center">Change</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {rows.map((row) => (
            <TableRow key={row.typeKey}>
              <TableCell className="text-sm font-medium">{row.label}</TableCell>
              <TableCell className="text-center text-sm text-muted-foreground">
                {(row.thresholdBps / 100).toFixed(0)}%
              </TableCell>
              <TableCell className="text-center tabular-nums text-sm">
                {row.currentVotes} / {currentSize}
              </TableCell>
              <TableCell className="text-center tabular-nums text-sm font-medium">
                {row.newVotes} / {newSize}
              </TableCell>
              <TableCell className="text-center">
                {row.delta > 0 ? (
                  <Badge variant="secondary" className="bg-amber-500/15 text-amber-600">
                    +{row.delta}
                  </Badge>
                ) : row.delta < 0 ? (
                  <Badge variant="secondary" className="bg-blue-500/15 text-blue-600">
                    {row.delta}
                  </Badge>
                ) : (
                  <Minus className="mx-auto h-3 w-3 text-muted-foreground" />
                )}
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>

      <p className="text-xs text-muted-foreground">
        Votes required = ⌈threshold % × board size⌉
      </p>
    </div>
  );
}

import { useRef } from "react";
import { ChevronDown } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";

interface SubmitProposalButtonProps {
  actionType: string;
  isPending?: boolean;
  pendingStep?: "creating" | "voting" | null;
  onSubmit: () => void;
  onSubmitAndVote: () => void;
}

export function SubmitProposalButton({
  actionType,
  isPending,
  pendingStep,
  onSubmit,
  onSubmitAndVote,
}: SubmitProposalButtonProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  return (
    <div ref={containerRef} className="flex">
      <Button
        type="button"
        disabled={isPending}
        onClick={onSubmit}
        className="rounded-r-none"
      >
        {pendingStep === "voting"
          ? "Voting 'Yes'..."
          : pendingStep === "creating"
            ? "Creating proposal..."
            : isPending
              ? "Submitting..."
              : `Create Proposal to execute '${actionType}' action`}
      </Button>
      <DropdownMenu>
        <DropdownMenuTrigger
          disabled={isPending}
          render={
            <button
              type="button"
              className="inline-flex h-8 items-center rounded-r-lg border-l border-primary-foreground/20 bg-primary px-1.5 text-primary-foreground hover:bg-primary/80 disabled:pointer-events-none disabled:opacity-50"
            />
          }
        >
          <ChevronDown className="h-4 w-4" />
        </DropdownMenuTrigger>
        <DropdownMenuContent align="start" anchor={containerRef}>
          <DropdownMenuItem onClick={onSubmitAndVote}>
            Create & Vote Yes
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
    </div>
  );
}

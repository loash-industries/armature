import { useNavigate } from "@tanstack/react-router";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";

const CONTROLLER_ACTIONS = [
  { label: "Pause Execution", type: "PauseExecution" },
  { label: "Unpause Execution", type: "UnpauseExecution" },
  { label: "Transfer Capability", type: "CapabilityExtract" },
  { label: "Reclaim Capability", type: "CapabilityExtract" },
  { label: "Spin Out SubDAO", type: "SpinOutSubDAO" },
] as const;

export function ControllerActionsMenu({ daoId }: { daoId: string }) {
  const navigate = useNavigate();

  return (
    <DropdownMenu>
      <DropdownMenuTrigger render={<Button variant="outline" size="sm" />}>
        Controller Actions
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        {CONTROLLER_ACTIONS.map((action) => (
          <DropdownMenuItem
            key={action.label}
            onSelect={() => {
              navigate({
                to: "/dao/$daoId/proposals",
                params: { daoId },
                search: { type: action.type },
              });
            }}
          >
            {action.label}
          </DropdownMenuItem>
        ))}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}

import { useNavigate } from "@tanstack/react-router";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import type { CapabilityEntry } from "@/types/dao";

export function CapabilityActions({
  entry,
  daoId,
}: {
  entry: CapabilityEntry;
  daoId: string;
}) {
  const navigate = useNavigate();
  const isFreezeAdmin = entry.shortType === "FreezeAdminCap";

  return (
    <DropdownMenu>
      <DropdownMenuTrigger render={<Button variant="ghost" size="sm" />}>
        Actions
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        <DropdownMenuItem
          onSelect={() => {
            navigate({
              to: "/dao/$daoId/proposals",
              params: { daoId },
              search: { type: "CapabilityExtract" },
            });
          }}
        >
          Transfer to SubDAO
        </DropdownMenuItem>
        {entry.isSubDAOControl && (
          <DropdownMenuItem
            onSelect={() => {
              navigate({
                to: "/dao/$daoId/proposals",
                params: { daoId },
                search: { type: "CapabilityExtract" },
              });
            }}
          >
            Reclaim from SubDAO
          </DropdownMenuItem>
        )}
        {isFreezeAdmin && (
          <DropdownMenuItem
            onSelect={() => {
              navigate({
                to: "/dao/$daoId/proposals",
                params: { daoId },
                search: { type: "TransferFreezeAdmin" },
              });
            }}
          >
            Transfer Freeze Admin
          </DropdownMenuItem>
        )}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}

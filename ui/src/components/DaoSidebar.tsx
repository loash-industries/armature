import { useState } from "react";
import {
  useParams,
  useNavigate,
  useRouterState,
  Link,
} from "@tanstack/react-router";
import {
  Sidebar,
  SidebarHeader,
  SidebarContent,
  SidebarFooter,
  SidebarGroup,
  SidebarGroupLabel,
  SidebarMenu,
  SidebarMenuItem,
  SidebarMenuButton,
  LogoLockup,
  Button,
  Select,
  SelectTrigger,
  SelectValue,
  SelectContent,
  SelectItem,
} from "@awar.dev/ui";
import { useProposalFormOptions } from "@/hooks/useProposalFormOptions";
import { ProposalTypeSelector } from "@/components/proposals/ProposalTypeSelector";

const NAV_ITEMS = [
  { label: "Dashboard", path: "" },
  { label: "Treasury", path: "treasury" },
  { label: "Capability Vault", path: "vault" },
  { label: "Proposals", path: "proposals" },
  { label: "Board", path: "board" },
  { label: "Charter", path: "charter" },
  { label: "Governance", path: "governance" },
  { label: "Emergency", path: "emergency" },
  { label: "SubDAOs", path: "subdaos" },
] as const;

function useActivePath(): string {
  const pathname = useRouterState({ select: (s) => s.location.pathname });
  const parts = pathname.split("/").filter(Boolean);
  // URL shape: /dao/<id>/<page>
  return parts[2] ?? "";
}

export function DaoSidebar() {
  const { daoId } = useParams({ strict: false });
  const navigate = useNavigate();
  const activePath = useActivePath();
  const [selectorOpen, setSelectorOpen] = useState(false);
  const { enabledTypes, frozenTypes } = useProposalFormOptions(daoId ?? "");

  return (
    <Sidebar>
      <SidebarHeader>
        <LogoLockup text="Armature" />
      </SidebarHeader>

      <SidebarContent>
        <SidebarGroup>
          <SidebarGroupLabel>DAO</SidebarGroupLabel>
          <Select
            value={daoId}
            onValueChange={(value) => {
              navigate({ to: "/dao/$daoId", params: { daoId: value } });
            }}
          >
            <SelectTrigger className="w-full">
              <SelectValue placeholder="Select DAO" />
            </SelectTrigger>
            <SelectContent>
              {daoId && <SelectItem value={daoId}>{daoId}</SelectItem>}
            </SelectContent>
          </Select>
        </SidebarGroup>

        <SidebarGroup>
          <SidebarGroupLabel>Navigation</SidebarGroupLabel>
          <SidebarMenu>
            {NAV_ITEMS.map((item) => (
              <SidebarMenuItem key={item.label}>
                <SidebarMenuButton asChild isActive={activePath === item.path}>
                  <Link
                    to={item.path ? `/dao/$daoId/${item.path}` : "/dao/$daoId"}
                    params={{ daoId: daoId ?? "" }}
                  >
                    {item.label}
                  </Link>
                </SidebarMenuButton>
              </SidebarMenuItem>
            ))}
          </SidebarMenu>
        </SidebarGroup>
      </SidebarContent>

      <SidebarFooter>
        <Button className="w-full" onClick={() => setSelectorOpen(true)}>
          + New Proposal
        </Button>
        <ProposalTypeSelector
          open={selectorOpen}
          onOpenChange={setSelectorOpen}
          enabledTypes={enabledTypes}
          frozenTypes={frozenTypes}
          onSelect={(typeKey) => {
            navigate({
              to: `/dao/$daoId/proposals/new`,
              params: { daoId: daoId ?? "" },
              search: { type: typeKey },
            });
          }}
        />
      </SidebarFooter>
    </Sidebar>
  );
}

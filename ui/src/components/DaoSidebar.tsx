import { useParams, useNavigate, Link } from "@tanstack/react-router";
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

export function DaoSidebar() {
  const { daoId } = useParams({ strict: false });
  const navigate = useNavigate();

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
              <SidebarMenuItem key={item.path}>
                <SidebarMenuButton asChild>
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
        <Button className="w-full">+ New Proposal</Button>
      </SidebarFooter>
    </Sidebar>
  );
}

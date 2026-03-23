import {
  useParams,
  useRouterState,
  Link,
} from "@tanstack/react-router";
import {
  LayoutDashboard,
  Users,
  Wallet,
  PenTool,
  BookOpen,
  Network,
  AlertTriangle,
  Settings,
  ArrowRightToLine,
} from "lucide-react";
import {
  Tooltip,
  TooltipTrigger,
  TooltipContent,
} from "@/components/ui/tooltip";
import { cn } from "@/lib/utils";
import type { LucideIcon } from "lucide-react";

const MAIN_NAV = [
  { label: "Dashboard", path: "", icon: LayoutDashboard },
  { label: "Board", path: "board", icon: Users },
  { label: "Treasury", path: "treasury", icon: Wallet },
  { label: "Proposals", path: "proposals", icon: PenTool },
  { label: "Charter", path: "charter", icon: BookOpen },
  { label: "SubDAOs", path: "subdaos", icon: Network },
] as const;

const BOTTOM_NAV = [
  { label: "Emergency", path: "emergency", icon: AlertTriangle },
  { label: "Governance", path: "governance", icon: Settings },
] as const;

function useActivePath(): string {
  const pathname = useRouterState({ select: (s) => s.location.pathname });
  const parts = pathname.split("/").filter(Boolean);
  return parts[2] ?? "";
}

function NavItem({
  icon: Icon,
  label,
  path,
  daoId,
  isActive,
}: {
  icon: LucideIcon;
  label: string;
  path: string;
  daoId: string;
  isActive: boolean;
}) {
  return (
    <Tooltip>
      <TooltipTrigger
        render={
          <Link
            to={path ? (`/dao/$daoId/${path}` as string) : "/dao/$daoId"}
            params={{ daoId }}
          />
        }
        className={cn(
          "flex h-8 w-8 items-center justify-center rounded-md transition-colors",
          isActive
            ? "bg-sidebar-accent text-sidebar-accent-foreground"
            : "text-muted-foreground hover:bg-sidebar-accent hover:text-sidebar-accent-foreground",
        )}
      >
        <Icon className="h-5 w-5" />
      </TooltipTrigger>
      <TooltipContent side="right">{label}</TooltipContent>
    </Tooltip>
  );
}

export function DaoSidebar() {
  const { daoId } = useParams({ strict: false });
  const activePath = useActivePath();

  return (
    <nav className="bg-sidebar border-sidebar-border flex h-full w-14 flex-col items-center rounded-lg border">
      {/* Collapse/Expand button */}
      <div className="flex w-full items-center justify-end p-2">
        <div className="bg-sidebar-primary flex h-8 w-8 items-center justify-center rounded-lg">
          <ArrowRightToLine className="text-sidebar-primary-foreground h-5 w-5" />
        </div>
      </div>

      {/* Main nav group */}
      <div className="flex flex-1 flex-col gap-1 p-2">
        {MAIN_NAV.map((item) => (
          <NavItem
            key={item.label}
            icon={item.icon}
            label={item.label}
            path={item.path}
            daoId={daoId ?? ""}
            isActive={activePath === item.path}
          />
        ))}
      </div>

      {/* Bottom nav group */}
      <div className="flex flex-col gap-1 p-2">
        {BOTTOM_NAV.map((item) => (
          <NavItem
            key={item.label}
            icon={item.icon}
            label={item.label}
            path={item.path}
            daoId={daoId ?? ""}
            isActive={activePath === item.path}
          />
        ))}
      </div>
    </nav>
  );
}

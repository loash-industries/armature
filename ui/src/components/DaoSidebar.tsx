import { useState } from "react";
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
  ArrowLeftToLine,
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
  { label: "Members", path: "board", icon: Users },
  { label: "Treasury", path: "treasury", icon: Wallet },
  { label: "Proposals", path: "proposals", icon: PenTool },
  { label: "Charter", path: "charter", icon: BookOpen },
  { label: "Hierarchy", path: "subdaos", icon: Network },
] as const;

const BOTTOM_NAV = [
  { label: "Emergency", path: "emergency", icon: AlertTriangle },
  { label: "Settings", path: "governance", icon: Settings },
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
  isOpen,
}: {
  icon: LucideIcon;
  label: string;
  path: string;
  daoId: string;
  isActive: boolean;
  isOpen: boolean;
}) {
  const linkClass = cn(
    "flex items-center rounded-md transition-colors",
    isOpen ? "h-8 w-full gap-2 px-2" : "h-8 w-8 justify-center",
    isActive
      ? "bg-sidebar-accent text-sidebar-accent-foreground"
      : "text-muted-foreground hover:bg-sidebar-accent hover:text-sidebar-accent-foreground",
  );

  if (isOpen) {
    return (
      <Link
        to={path ? (`/dao/$daoId/${path}` as string) : "/dao/$daoId"}
        params={{ daoId }}
        className={linkClass}
      >
        <Icon className="h-5 w-5 shrink-0" />
        <span className="truncate text-sm">{label}</span>
      </Link>
    );
  }

  return (
    <Tooltip>
      <TooltipTrigger
        render={
          <Link
            to={path ? (`/dao/$daoId/${path}` as string) : "/dao/$daoId"}
            params={{ daoId }}
          />
        }
        className={linkClass}
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
  const [isOpen, setIsOpen] = useState(false);

  return (
    <div className="flex h-full items-center">
    <nav
      className={cn(
        "bg-sidebar border-sidebar-border flex h-[60vh] flex-col rounded-lg border transition-[width] duration-200 ease-in-out",
        isOpen ? "w-48 items-stretch" : "w-14 items-center",
      )}
    >
      {/* Collapse/Expand button */}
      <div className={cn("flex p-2", isOpen ? "justify-end" : "justify-center")}>
        <button
          onClick={() => setIsOpen((v) => !v)}
          className="bg-sidebar-primary flex h-8 w-8 shrink-0 items-center justify-center rounded-lg"
          aria-label={isOpen ? "Collapse sidebar" : "Expand sidebar"}
        >
          {isOpen ? (
            <ArrowLeftToLine className="text-sidebar-primary-foreground h-5 w-5" />
          ) : (
            <ArrowRightToLine className="text-sidebar-primary-foreground h-5 w-5" />
          )}
        </button>
      </div>

      {/* Main nav group */}
      <div className={cn("flex flex-1 flex-col gap-1 p-2", isOpen && "w-full")}>
        {MAIN_NAV.map((item) => (
          <NavItem
            key={item.label}
            icon={item.icon}
            label={item.label}
            path={item.path}
            daoId={daoId ?? ""}
            isActive={activePath === item.path}
            isOpen={isOpen}
          />
        ))}
      </div>

      {/* Bottom nav group */}
      <div className={cn("flex flex-col gap-1 p-2", isOpen && "w-full")}>
        {BOTTOM_NAV.map((item) => (
          <NavItem
            key={item.label}
            icon={item.icon}
            label={item.label}
            path={item.path}
            daoId={daoId ?? ""}
            isActive={activePath === item.path}
            isOpen={isOpen}
          />
        ))}
      </div>
    </nav>
    </div>
  );
}

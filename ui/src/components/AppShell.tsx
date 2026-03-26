import { Outlet, useParams, Link } from "@tanstack/react-router";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Button } from "@/components/ui/button";
import { ChevronsUpDown } from "lucide-react";
import { DaoSidebar } from "./DaoSidebar";
import { WalletStatus } from "./WalletStatus";
import { DaoRelayProvider } from "@/context/DaoRelayContext";
import { useDaoSummary } from "@/hooks/useDao";

function truncateDaoId(id: string): string {
  if (id.length <= 20) return id;
  return `${id.slice(0, 10)}...${id.slice(-6)}`;
}

export function AppShell() {
  const { daoId } = useParams({ strict: false });
  const { data: dao } = useDaoSummary(daoId ?? "");

  return (
    <div className="bg-background flex h-screen w-full overflow-hidden">
      {/* Icon Sidebar */}
      <div className="flex-shrink-0 p-4 pr-0">
        <DaoSidebar />
      </div>

      {/* Main Content Area */}
      <div className="flex min-w-0 flex-1 flex-col pt-4">
        {/* Topbar */}
        <header className="flex h-20 items-center justify-between px-4">
          {/* DAO Picker */}
          <Button variant="outline" render={<Link to="/pick" />} className="gap-2 p-4">
            <span className="max-w-[165px] truncate text-sm font-bold">
              {dao?.charterName ?? (daoId ? truncateDaoId(daoId) : "Select DAO")}
            </span>
            <ChevronsUpDown className="h-4 w-4 text-muted-foreground" />
          </Button>

          {/* Account */}
          <WalletStatus />
        </header>

        {/* Page Content */}
        <ScrollArea className="flex-1 min-h-0">
          <main className="p-4 mx-auto max-w-3xl">
            <DaoRelayProvider daoId={daoId ?? ""}>
              <Outlet />
            </DaoRelayProvider>
          </main>
        </ScrollArea>
      </div>
    </div>
  );
}

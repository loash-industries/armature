import { Outlet } from "@tanstack/react-router";
import {
  SidebarProvider,
  SidebarInset,
  SidebarTrigger,
  ScrollArea,
  Separator,
} from "@awar.dev/ui";
import { DaoSidebar } from "./DaoSidebar";
import { SubDAOBreadcrumb } from "./SubDAOBreadcrumb";
import { WalletStatus } from "./WalletStatus";

export function AppShell() {
  return (
    <SidebarProvider>
      <DaoSidebar />
      <SidebarInset>
        <header className="flex h-14 items-center gap-2 border-b px-4">
          <SidebarTrigger />
          <Separator orientation="vertical" className="h-6" />
          <SubDAOBreadcrumb />
          <div className="flex-1" />
          <WalletStatus />
        </header>
        <ScrollArea className="flex-1">
          <main className="p-4">
            <Outlet />
          </main>
        </ScrollArea>
      </SidebarInset>
    </SidebarProvider>
  );
}

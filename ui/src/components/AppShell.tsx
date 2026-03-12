import { Outlet } from "@tanstack/react-router";
import {
  SidebarProvider,
  SidebarInset,
  SidebarTrigger,
  ScrollArea,
  Badge,
  Separator,
} from "@awar.dev/ui";
import { useCurrentAccount } from "@mysten/dapp-kit";
import { DaoSidebar } from "./DaoSidebar";

function truncateAddress(address: string): string {
  if (address.length <= 10) return address;
  return `${address.slice(0, 6)}...${address.slice(-4)}`;
}

export function AppShell() {
  const account = useCurrentAccount();

  return (
    <SidebarProvider>
      <DaoSidebar />
      <SidebarInset>
        <header className="flex h-14 items-center gap-2 border-b px-4">
          <SidebarTrigger />
          <Separator orientation="vertical" className="h-6" />
          <div className="flex-1" />
          {account && (
            <Badge variant="outline">{truncateAddress(account.address)}</Badge>
          )}
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

import {
  createRootRoute,
  createRoute,
  createRouter,
} from "@tanstack/react-router";
import { AppShell } from "@/components/AppShell";
import { DaoDashboard } from "@/pages/DaoDashboard";
import { TreasuryPage } from "@/pages/TreasuryPage";
import { CapVaultPage } from "@/pages/CapVaultPage";
import { ProposalsList } from "@/pages/ProposalsList";
import { ProposalDetail } from "@/pages/ProposalDetail";
import { BoardPage } from "@/pages/BoardPage";
import { CharterPage } from "@/pages/CharterPage";
import { GovConfigPage } from "@/pages/GovConfigPage";
import { EmergencyPage } from "@/pages/EmergencyPage";
import { SubDAOListPage } from "@/pages/SubDAOListPage";
import { NewProposalPage } from "@/pages/NewProposalPage";

const rootRoute = createRootRoute();

const daoRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: "dao/$daoId",
  component: AppShell,
});

const dashboardRoute = createRoute({
  getParentRoute: () => daoRoute,
  path: "/",
  component: DaoDashboard,
});

const treasuryRoute = createRoute({
  getParentRoute: () => daoRoute,
  path: "treasury",
  component: TreasuryPage,
});

const vaultRoute = createRoute({
  getParentRoute: () => daoRoute,
  path: "vault",
  component: CapVaultPage,
});

const proposalsRoute = createRoute({
  getParentRoute: () => daoRoute,
  path: "proposals",
  component: ProposalsList,
});

const newProposalRoute = createRoute({
  getParentRoute: () => daoRoute,
  path: "proposals/new",
  component: NewProposalPage,
});

const proposalDetailRoute = createRoute({
  getParentRoute: () => daoRoute,
  path: "proposals/$proposalId",
  component: ProposalDetail,
});

const boardRoute = createRoute({
  getParentRoute: () => daoRoute,
  path: "board",
  component: BoardPage,
});

const charterRoute = createRoute({
  getParentRoute: () => daoRoute,
  path: "charter",
  component: CharterPage,
});

const governanceRoute = createRoute({
  getParentRoute: () => daoRoute,
  path: "governance",
  component: GovConfigPage,
});

const emergencyRoute = createRoute({
  getParentRoute: () => daoRoute,
  path: "emergency",
  component: EmergencyPage,
});

const subdaosRoute = createRoute({
  getParentRoute: () => daoRoute,
  path: "subdaos",
  component: SubDAOListPage,
});

const routeTree = rootRoute.addChildren([
  daoRoute.addChildren([
    dashboardRoute,
    treasuryRoute,
    vaultRoute,
    proposalsRoute,
    newProposalRoute,
    proposalDetailRoute,
    boardRoute,
    charterRoute,
    governanceRoute,
    emergencyRoute,
    subdaosRoute,
  ]),
]);

export const router = createRouter({ routeTree });

declare module "@tanstack/react-router" {
  interface Register {
    router: typeof router;
  }
}

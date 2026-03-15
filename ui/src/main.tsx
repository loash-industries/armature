import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { QueryClientProvider } from "@tanstack/react-query";
import { SuiClientProvider, WalletProvider } from "@mysten/dapp-kit";
import "@mysten/dapp-kit/dist/index.css";
import { RouterProvider } from "@tanstack/react-router";
import { AWARProvider, Toaster } from "@awar.dev/ui";
import { networkConfig } from "@/config/network";
import { queryClient } from "@/lib/query-client";
import { WalletSignerProvider } from "@/lib/wallet-provider";
import { router } from "@/router";
import "./index.css";

const defaultNetwork =
  (import.meta.env.VITE_NETWORK as keyof typeof networkConfig) ?? "localnet";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <QueryClientProvider client={queryClient}>
      <SuiClientProvider networks={networkConfig} defaultNetwork={defaultNetwork}>
        <WalletProvider autoConnect>
          <WalletSignerProvider>
            <AWARProvider>
              <RouterProvider router={router} />
              <Toaster />
            </AWARProvider>
          </WalletSignerProvider>
        </WalletProvider>
      </SuiClientProvider>
    </QueryClientProvider>
  </StrictMode>,
);

import { useContext } from "react";
import { useCurrentAccount, useSignAndExecuteTransaction } from "@mysten/dapp-kit";
import {
  WalletSignerContext,
  type SignAndExecuteResult,
} from "@/lib/wallet-provider";
import type { Transaction } from "@mysten/sui/transactions";

/**
 * Unified wallet hook that works in both localnet (env keypairs) and
 * testnet/mainnet (browser wallet) modes.
 *
 * Returns `{ address, isConnected, signAndExecuteTransaction }`.
 */
export function useWalletSigner() {
  const ctx = useContext(WalletSignerContext);

  // Browser wallet (testnet / mainnet)
  const browserAccount = useCurrentAccount();
  const { mutateAsync: browserSignAndExecute } =
    useSignAndExecuteTransaction();

  if (ctx.isLocalnet) {
    return {
      address: ctx.address,
      isConnected: ctx.isConnected,
      isLocalnet: true as const,
      signAndExecuteTransaction: ctx.signAndExecuteTransaction,
      localWallets: ctx.localWallets,
      activeWalletIndex: ctx.activeWalletIndex,
      setActiveWalletIndex: ctx.setActiveWalletIndex,
      disconnectWallet: ctx.disconnectWallet,
    };
  }

  // Browser wallet mode
  const signAndExecuteTransaction = async (args: {
    transaction: Transaction;
  }): Promise<SignAndExecuteResult> => {
    const result = await browserSignAndExecute({
      transaction: args.transaction,
    });
    return {
      digest: result.digest,
      effects: result.effects
        ? { status: { status: "success" } }
        : undefined,
    };
  };

  return {
    address: browserAccount?.address ?? null,
    isConnected: !!browserAccount,
    isLocalnet: false as const,
    signAndExecuteTransaction,
    localWallets: [] as const,
    activeWalletIndex: 0,
    setActiveWalletIndex: () => {},
  };
}

import {
  createContext,
  useCallback,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";
import { useSuiClient } from "@mysten/dapp-kit";
import type { Transaction } from "@mysten/sui/transactions";

/** A localnet wallet derived from an env-var keypair. */
export interface LocalWallet {
  label: string;
  address: string;
  keypair: Ed25519Keypair;
}

export interface SignAndExecuteResult {
  digest: string;
  effects?: { status?: { status: string } };
}

export interface WalletSignerContextValue {
  /** Currently active address (localnet keypair or browser wallet). */
  address: string | null;
  /** Whether a wallet is connected / available. */
  isConnected: boolean;
  /** True when running against localnet with env-injected keypairs. */
  isLocalnet: boolean;
  /** Sign and execute a transaction — abstracts over env keypair vs browser wallet. */
  signAndExecuteTransaction: (args: {
    transaction: Transaction;
  }) => Promise<SignAndExecuteResult>;
  /** All available localnet wallets (empty on testnet/mainnet). */
  localWallets: LocalWallet[];
  /** Index of the currently selected localnet wallet. */
  activeWalletIndex: number;
  /** Switch the active localnet wallet by index. */
  setActiveWalletIndex: (index: number) => void;
  /** Disconnect the current localnet wallet (no-op on testnet/mainnet). */
  disconnectWallet: () => void;
}

// eslint-disable-next-line react-refresh/only-export-components
export const WalletSignerContext = createContext<WalletSignerContextValue>({
  address: null,
  isConnected: false,
  isLocalnet: false,
  signAndExecuteTransaction: () =>
    Promise.reject(new Error("WalletSignerProvider not mounted")),
  localWallets: [],
  activeWalletIndex: 0,
  setActiveWalletIndex: () => {},
  disconnectWallet: () => {},
});

/** Parse VITE_WALLET_KEY_N env vars into Ed25519Keypair instances. */
function loadLocalWallets(): LocalWallet[] {
  const wallets: LocalWallet[] = [];
  for (let i = 1; i <= 10; i++) {
    const key =
      import.meta.env[`VITE_WALLET_KEY_${i}`] as string | undefined;
    const mnemonic =
      import.meta.env[`VITE_WALLET_MNEMONIC_${i}`] as string | undefined;

    let keypair: Ed25519Keypair | null = null;

    if (key) {
      keypair = Ed25519Keypair.fromSecretKey(key);
    } else if (mnemonic) {
      keypair = Ed25519Keypair.deriveKeypair(mnemonic);
    }

    if (keypair) {
      wallets.push({
        label: `User ${i}`,
        address: keypair.getPublicKey().toSuiAddress(),
        keypair,
      });
    }
  }
  return wallets;
}

const NETWORK = (import.meta.env.VITE_NETWORK as string) ?? "localnet";

export function WalletSignerProvider({ children }: { children: ReactNode }) {
  const client = useSuiClient();
  const isLocalnet = NETWORK === "localnet";

  const localWallets = useMemo(
    () => (isLocalnet ? loadLocalWallets() : []),
    [isLocalnet],
  );
  const [activeWalletIndex, _setActiveWalletIndex] = useState(0);
  const [localnetDisconnected, setLocalnetDisconnected] = useState(false);

  const setActiveWalletIndex = useCallback((index: number) => {
    _setActiveWalletIndex(index);
    setLocalnetDisconnected(false);
  }, []);

  const disconnectWallet = useCallback(() => {
    setLocalnetDisconnected(true);
  }, []);

  const activeWallet = isLocalnet && localnetDisconnected
    ? null
    : (localWallets[activeWalletIndex] ?? null);

  const signAndExecuteTransaction = useCallback(
    async (args: { transaction: Transaction }): Promise<SignAndExecuteResult> => {
      if (!isLocalnet || !activeWallet) {
        throw new Error(
          "Localnet wallet not available. Use the browser wallet hook for testnet/mainnet.",
        );
      }

      const result = await client.signAndExecuteTransaction({
        transaction: args.transaction,
        signer: activeWallet.keypair,
        options: { showEffects: true },
      });

      return {
        digest: result.digest,
        effects: result.effects
          ? { status: result.effects.status }
          : undefined,
      };
    },
    [client, isLocalnet, activeWallet],
  );

  const value = useMemo<WalletSignerContextValue>(
    () => ({
      address: activeWallet?.address ?? null,
      isConnected: !!activeWallet,
      isLocalnet,
      signAndExecuteTransaction,
      localWallets,
      activeWalletIndex,
      setActiveWalletIndex,
      disconnectWallet,
    }),
    [
      activeWallet,
      isLocalnet,
      signAndExecuteTransaction,
      localWallets,
      activeWalletIndex,
      setActiveWalletIndex,
      disconnectWallet,
    ],
  );

  return (
    <WalletSignerContext.Provider value={value}>
      {children}
    </WalletSignerContext.Provider>
  );
}

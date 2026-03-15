import {
  Badge,
  Button,
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@awar.dev/ui";
import { ConnectModal, useCurrentAccount, useDisconnectWallet } from "@mysten/dapp-kit";
import { useWalletSigner } from "@/hooks/useWalletSigner";

function truncateAddress(address: string): string {
  if (address.length <= 10) return address;
  return `${address.slice(0, 6)}...${address.slice(-4)}`;
}

function DappKitWallet() {
  const account = useCurrentAccount();
  const { mutate: disconnect } = useDisconnectWallet();

  if (!account) {
    return (
      <ConnectModal
        trigger={
          <Button variant="outline" size="sm">
            Connect Wallet
          </Button>
        }
      />
    );
  }

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <button className="cursor-pointer" type="button">
          <Badge variant="outline">
            {truncateAddress(account.address)} ▾
          </Badge>
        </button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        <DropdownMenuItem onSelect={() => disconnect()}>
          Disconnect
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}

/** Renders the appropriate wallet UI based on network mode. */
export function WalletStatus() {
  const wallet = useWalletSigner();

  // Testnet / mainnet: dapp-kit ConnectModal with AWAR-themed trigger
  if (!wallet.isLocalnet) {
    return <DappKitWallet />;
  }

  // Localnet: no wallets configured
  if (wallet.localWallets.length === 0) {
    return (
      <Badge variant="outline" className="text-muted-foreground">
        No wallets configured
      </Badge>
    );
  }

  // Localnet: single wallet
  if (wallet.localWallets.length === 1) {
    return (
      <Badge variant="outline">
        {wallet.localWallets[0].label}:{" "}
        {truncateAddress(wallet.localWallets[0].address)}
      </Badge>
    );
  }

  // Localnet: multiple wallets — dropdown switcher
  const active = wallet.localWallets[wallet.activeWalletIndex];

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <button className="cursor-pointer" type="button">
          <Badge variant="outline">
            {active.label}: {truncateAddress(active.address)} ▾
          </Badge>
        </button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        {wallet.localWallets.map((w, i) => (
          <DropdownMenuItem
            key={w.address}
            onSelect={() => wallet.setActiveWalletIndex(i)}
          >
            <span className={i === wallet.activeWalletIndex ? "font-bold" : ""}>
              {w.label}: {truncateAddress(w.address)}
            </span>
          </DropdownMenuItem>
        ))}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}

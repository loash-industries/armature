import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { ConnectModal, useCurrentAccount, useDisconnectWallet } from "@mysten/dapp-kit";
import { useWalletSigner } from "@/hooks/useWalletSigner";
import { resolveDisplayName } from "@/lib/address-namer";
import { useCharacterNames } from "@/hooks/useCharacterNames";
import { useNavigate } from "@tanstack/react-router";

function truncateAddress(address: string): string {
  if (address.length <= 10) return address;
  return `${address.slice(0, 6)}...${address.slice(-4)}`;
}

function DappKitWallet() {
  const account = useCurrentAccount();
  const { mutateAsync: disconnect } = useDisconnectWallet();
  const navigate = useNavigate();
  const { data: nameMap } = useCharacterNames(
    account ? [account.address] : [],
  );
  const charName = account ? nameMap?.get(account.address) : null;

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
      <DropdownMenuTrigger render={<button className="cursor-pointer" type="button" />}>
        <Badge variant="outline">
          {resolveDisplayName(account.address, charName)} ▾
        </Badge>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        {charName && (
          <DropdownMenuItem disabled className="text-muted-foreground text-xs">
            {truncateAddress(account.address)}
          </DropdownMenuItem>
        )}
        <DropdownMenuItem onClick={() => disconnect().then(() => navigate({ to: "/" }))}>
          Disconnect
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}

/** Localnet wallet UI — handles connected, disconnected, and multi-wallet states. */
function LocalnetWallet() {
  const wallet = useWalletSigner();
  const navigate = useNavigate();
  // Hooks must be called unconditionally — fetch names for all local wallets upfront.
  const allLocalAddrs = wallet.isLocalnet
    ? wallet.localWallets.map((w) => w.address)
    : [];
  const { data: localNameMap } = useCharacterNames(allLocalAddrs);

  if (!wallet.isLocalnet) return null;

  // Disconnected — offer reconnect
  if (!wallet.isConnected) {
    if (wallet.localWallets.length === 1) {
      return (
        <Button variant="outline" size="sm" onClick={() => wallet.setActiveWalletIndex(0)}>
          Connect Wallet
        </Button>
      );
    }
    return (
      <DropdownMenu>
        <DropdownMenuTrigger render={<button className="cursor-pointer" type="button" />}>
          <Button variant="outline" size="sm">
            Connect Wallet ▾
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end">
          {wallet.localWallets.map((w, i) => {
            const wName = localNameMap?.get(w.address);
            return (
              <DropdownMenuItem key={w.address} onClick={() => wallet.setActiveWalletIndex(i)}>
                {resolveDisplayName(w.address, wName)}
              </DropdownMenuItem>
            );
          })}
        </DropdownMenuContent>
      </DropdownMenu>
    );
  }

  const active = wallet.localWallets[wallet.activeWalletIndex];
  const activeName = localNameMap?.get(active.address);

  return (
    <DropdownMenu>
      <DropdownMenuTrigger render={<button className="cursor-pointer" type="button" />}>
        <Badge variant="outline">
          {resolveDisplayName(active.address, activeName)} ▾
        </Badge>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        {wallet.localWallets.length > 1 &&
          wallet.localWallets.map((w, i) => {
            const wName = localNameMap?.get(w.address);
            return (
              <DropdownMenuItem
                key={w.address}
                onClick={() => wallet.setActiveWalletIndex(i)}
              >
                <span className={i === wallet.activeWalletIndex ? "font-bold" : ""}>
                  {resolveDisplayName(w.address, wName)}
                </span>
              </DropdownMenuItem>
            );
          })}
        <DropdownMenuItem onClick={() => { wallet.disconnectWallet(); navigate({ to: "/" }); }}>
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

  return <LocalnetWallet />;
}

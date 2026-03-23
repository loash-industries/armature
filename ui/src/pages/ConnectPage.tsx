import { useState } from "react";
import { useNavigate } from "@tanstack/react-router";
import { ConnectModal, useCurrentAccount } from "@mysten/dapp-kit";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Separator } from "@/components/ui/separator";
import { ArmatureLogo } from "@/components/ArmatureLogo";
import { useWalletSigner } from "@/hooks/useWalletSigner";

const suiAddressRegex = /^0x[a-fA-F0-9]{64}$/;

export function ConnectPage() {
  const navigate = useNavigate();
  const wallet = useWalletSigner();
  const account = useCurrentAccount();
  const [browseAddress, setBrowseAddress] = useState("");

  // If wallet is connected, redirect to picker
  if (account || (wallet.isLocalnet && wallet.isConnected)) {
    navigate({ to: "/pick" });
    return null;
  }

  function handleBrowse() {
    const trimmed = browseAddress.trim();
    if (suiAddressRegex.test(trimmed)) {
      navigate({ to: "/dao/$daoId", params: { daoId: trimmed } });
    }
  }

  return (
    <div className="bg-background flex min-h-screen items-center justify-center">
      <Card className="w-full max-w-sm">
        <CardContent className="flex flex-col items-center gap-6 pt-6">
          <ArmatureLogo className="h-48 w-44 text-foreground" />

          {wallet.isLocalnet ? (
            <Button
              className="w-full"
              onClick={() => navigate({ to: "/pick" })}
            >
              Connect Wallet
            </Button>
          ) : (
            <ConnectModal
              trigger={
                <Button className="w-full">
                  Connect Wallet
                </Button>
              }
            />
          )}

          <Separator />

          <div className="w-full space-y-3">
            <p className="text-muted-foreground text-sm">
              Enter a DAO address to browse to
            </p>
            <div className="flex gap-4">
              <Input
                placeholder="0x123..."
                value={browseAddress}
                onChange={(e) => setBrowseAddress(e.target.value)}
                onKeyDown={(e) => e.key === "Enter" && handleBrowse()}
              />
              <Button
                variant="secondary"
                onClick={handleBrowse}
                disabled={!suiAddressRegex.test(browseAddress.trim())}
              >
                Go
              </Button>
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}

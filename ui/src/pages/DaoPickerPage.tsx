import { useState } from "react";
import { useNavigate } from "@tanstack/react-router";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Separator } from "@/components/ui/separator";
import { WalletStatus } from "@/components/WalletStatus";
import { Plus } from "lucide-react";
import { useWalletSigner } from "@/hooks/useWalletSigner";
import { useWalletDaos } from "@/hooks/useWalletDaos";

const suiAddressRegex = /^0x[a-fA-F0-9]{64}$/;

export function DaoPickerPage() {
  const navigate = useNavigate();
  const [browseAddress, setBrowseAddress] = useState("");
  const { address } = useWalletSigner();
  const { data: daos = [] } = useWalletDaos(address);
  console.log('[daos]:', daos)
  function handleBrowse() {
    const trimmed = browseAddress.trim();
    if (suiAddressRegex.test(trimmed)) {
      navigate({ to: "/dao/$daoId", params: { daoId: trimmed } });
    }
  }

  // Auto-redirect if exactly 1 DAO
  if (daos.length === 1) {
    navigate({ to: "/dao/$daoId", params: { daoId: daos[0].daoId } });
    return null;
  }

  return (
    <div className="bg-background min-h-screen">
      {/* Topbar */}
      <header className="flex items-center justify-end px-6 py-4">
        <WalletStatus />
      </header>

      {/* Content */}
      <main className="flex flex-col items-center justify-center px-4 pt-24">
        <Card className="w-full max-w-sm">
          <CardHeader>
            <div className="flex items-center justify-between">
              <CardTitle>Create Organization</CardTitle>
              <Button
                variant="ghost"
                size="icon"
                onClick={() => navigate({ to: "/create" })}
              >
                <Plus className="h-4 w-4" />
              </Button>
            </div>
          </CardHeader>
          <CardContent className="space-y-3">
            {daos.length === 0 ? (
              <p className="text-muted-foreground py-4 text-center text-sm">
                No organizations found for your wallet. Create one or browse by address.
              </p>
            ) : (
              daos.map((dao) => (
                <button
                  key={dao.daoId}
                  type="button"
                  className="bg-secondary hover:bg-secondary/80 w-full rounded-lg px-4 py-3 text-left transition-colors"
                  onClick={() =>
                    navigate({
                      to: "/dao/$daoId",
                      params: { daoId: dao.daoId },
                    })
                  }
                >
                  <div className="flex items-center justify-between">
                    <span className="text-sm font-medium">{dao.name}</span>
                    <span className="text-muted-foreground text-sm">
                      {dao.treasury}
                    </span>
                  </div>
                  <div className="text-muted-foreground mt-1 text-xs">
                    {dao.memberCount} Members &middot; {dao.activeProposals}{" "}
                    active proposals
                  </div>
                </button>
              ))
            )}

            <Separator />

            <div className="space-y-2">
              <p className="text-muted-foreground text-sm">
                Enter an organization's address to browse:
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
      </main>
    </div>
  );
}

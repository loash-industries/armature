import { useEffect, useState } from "react";
import { Play, Square, Loader2 } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { PACKAGE_ID } from "@/config/constants";

const SIGNER_API_KEY = "some-secure-api-key";
const SIGNER_API_BASE = "http://localhost:3000";
const COIN_TYPE =
  "0xe4cb182f957824bee442b63be2299e899c27fbf10c7efcaabe36618e9d00120f::cred::CRED";

interface WorkerInfo {
  workerKey: string;
  treasuryVaultObjectId: string;
  coinType: string;
  armaturePackageId: string;
}

async function apiRequest<T>(path: string, options?: RequestInit): Promise<T> {
  const url = `${SIGNER_API_BASE}${path}`;
  const res = await fetch(url, {
    ...options,
    headers: {
      "Content-Type": "application/json",
      "x-api-key": SIGNER_API_KEY,
      ...options?.headers,
    },
  });
  if (!res.ok) {
    const body = (await res.json().catch(() => ({}))) as { message?: string };
    throw new Error(body.message ?? `Request failed (${res.status})`);
  }
  return res.json() as Promise<T>;
}

interface Props {
  treasuryVaultObjectId: string;
}

export function TreasuryWorkerToggle({ treasuryVaultObjectId }: Props) {
  const [running, setRunning] = useState(false);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    apiRequest<{ workers: WorkerInfo[] }>("/v1/treasury-worker/status")
      .then((data) => {
        const active = data.workers.some(
          (w) =>
            w.treasuryVaultObjectId === treasuryVaultObjectId &&
            w.coinType === COIN_TYPE,
        );
        setRunning(active);
      })
      .catch(() => {});
  }, [treasuryVaultObjectId]);

  async function toggle() {
    setLoading(true);
    try {
      if (running) {
        await apiRequest("/v1/treasury-worker/stop", {
          method: "POST",
          body: JSON.stringify({ treasuryVaultObjectId, coinType: COIN_TYPE }),
        });
        toast.success("Worker stopped");
        setRunning(false);
      } else {
        await apiRequest("/v1/treasury-worker/start", {
          method: "POST",
          body: JSON.stringify({
            treasuryVaultObjectId,
            coinType: COIN_TYPE,
            armaturePackageId: PACKAGE_ID,
          }),
        });
        toast.success("Worker started");
        setRunning(true);
      }
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Request failed");
    } finally {
      setLoading(false);
    }
  }

  return (
    <Button
      variant="ghost"
      size="icon"
      className="h-8 w-8"
      title={running ? "Stop auto-deposit worker" : "Start auto-deposit worker"}
      disabled={loading}
      onClick={() => void toggle()}
    >
      {loading ? (
        <Loader2 className="h-4 w-4 animate-spin" />
      ) : running ? (
        <Square className="h-4 w-4 text-green-500" />
      ) : (
        <Play className="h-4 w-4" />
      )}
    </Button>
  );
}

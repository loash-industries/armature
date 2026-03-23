import { useState, useEffect } from "react";
import { useForm, useFieldArray } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import { useNavigate } from "@tanstack/react-router";
import { useSuiClient } from "@mysten/dapp-kit";
import { toast } from "sonner";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Form,
  FormField,
  FormItem,
  FormLabel,
  FormControl,
  FormMessage,
} from "@/components/ui/form";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { WalletStatus } from "@/components/WalletStatus";
import { useWalletSigner } from "@/hooks/useWalletSigner";
import { buildCreateDao } from "@/lib/transactions";

const suiAddressRegex = /^0x[a-fA-F0-9]{64}$/;

const createDaoSchema = z.object({
  name: z.string().min(1, "Name is required"),
  description: z.string().min(1, "Description is required"),
  imageUrl: z.string().url("Must be a valid URL").or(z.literal("")),
  members: z
    .array(
      z.object({
        address: z.string().regex(suiAddressRegex, "Invalid Sui address"),
      }),
    )
    .min(1, "At least one board member is required")
    .refine(
      (members) => {
        const addrs = members.map((m) => m.address);
        return new Set(addrs).size === addrs.length;
      },
      { message: "Duplicate addresses are not allowed" },
    ),
});

type CreateDaoFormValues = z.infer<typeof createDaoSchema>;

export function CreateDaoPage() {
  const wallet = useWalletSigner();
  const client = useSuiClient();
  const navigate = useNavigate();
  const [isPending, setIsPending] = useState(false);

  const form = useForm<CreateDaoFormValues>({
    resolver: zodResolver(createDaoSchema),
    defaultValues: {
      name: "",
      description: "",
      imageUrl: "",
      members: [{ address: wallet.address ?? "" }],
    },
  });

  const { fields, append, remove } = useFieldArray({
    control: form.control,
    name: "members",
  });

  // Keep first member slot in sync with connected wallet
  useEffect(() => {
    if (wallet.address) {
      form.setValue("members.0.address", wallet.address);
    }
  }, [wallet.address]);

  const [newAddr, setNewAddr] = useState("");

  async function onSubmit(data: CreateDaoFormValues) {
    if (!wallet.isConnected) return;

    setIsPending(true);
    try {
      const transaction = buildCreateDao({
        name: data.name,
        description: data.description,
        imageUrl: data.imageUrl,
        initialMembers: data.members.map((m) => m.address),
      });

      const result = await wallet.signAndExecuteTransaction({ transaction });

      // Extract DAO ID from DAOCreated event
      let daoId: string | null = null;
      try {
        const txDetail = await client.waitForTransaction({
          digest: result.digest,
          options: { showEvents: true },
        });
        const createdEvent = txDetail.events?.find((e) =>
          e.type.endsWith("::DAOCreated"),
        );
        if (createdEvent) {
          const parsed = createdEvent.parsedJson as Record<string, unknown>;
          daoId = (parsed.dao_id as string) ?? null;
        }
      } catch {
        // Event extraction failed — DAO was still created on-chain
      }

      if (daoId) {
        toast.success("DAO created successfully");
        navigate({ to: "/dao/$daoId", params: { daoId } });
      } else {
        toast.success("DAO created, but could not extract ID. Check your wallet for the transaction.");
      }
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Failed to create DAO");
    } finally {
      setIsPending(false);
    }
  }

  return (
    <div className="bg-background min-h-screen">
      <header className="border-b-border flex items-center justify-between border-b px-6 py-4">
        <span className="text-lg font-semibold tracking-tight">Armature</span>
        <WalletStatus />
      </header>

      <main className="mx-auto max-w-lg px-4 py-12">
        <Card>
          <CardHeader>
            <CardTitle>Create a DAO</CardTitle>
          </CardHeader>
          <CardContent>
            {!wallet.isConnected && (
              <Alert className="mb-6">
                <AlertDescription>
                  Connect your wallet to create a DAO.
                </AlertDescription>
              </Alert>
            )}

            <Form {...form}>
              <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-6">
                <FormField
                  control={form.control}
                  name="name"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>DAO Name</FormLabel>
                      <FormControl>
                        <Input placeholder="My DAO" {...field} />
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )}
                />

                <FormField
                  control={form.control}
                  name="description"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>Description</FormLabel>
                      <FormControl>
                        <Textarea
                          placeholder="What is this DAO about?"
                          {...field}
                        />
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )}
                />

                <FormField
                  control={form.control}
                  name="imageUrl"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>Image URL (optional)</FormLabel>
                      <FormControl>
                        <Input
                          placeholder="https://example.com/logo.png"
                          {...field}
                        />
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )}
                />

                <div>
                  <FormLabel>Board Members</FormLabel>
                  <div className="mt-2 space-y-2">
                    {fields.map((field, index) => (
                      <div key={field.id} className="flex items-center gap-2">
                        <FormField
                          control={form.control}
                          name={`members.${index}.address`}
                          render={({ field }) => (
                            <FormItem className="flex-1">
                              <FormControl>
                                <Input
                                  placeholder="0x..."
                                  {...field}
                                  disabled={index === 0}
                                />
                              </FormControl>
                              <FormMessage />
                            </FormItem>
                          )}
                        />
                        {index > 0 && (
                          <Button
                            type="button"
                            variant="destructive"
                            size="sm"
                            onClick={() => remove(index)}
                          >
                            Remove
                          </Button>
                        )}
                      </div>
                    ))}
                  </div>
                  <div className="mt-3 flex gap-2">
                    <Input
                      placeholder="Add member address 0x..."
                      value={newAddr}
                      onChange={(e) => setNewAddr(e.target.value)}
                    />
                    <Button
                      type="button"
                      variant="outline"
                      size="sm"
                      onClick={() => {
                        if (newAddr && suiAddressRegex.test(newAddr)) {
                          append({ address: newAddr });
                          setNewAddr("");
                        }
                      }}
                    >
                      Add
                    </Button>
                  </div>
                </div>

                <Button
                  type="submit"
                  className="w-full"
                  disabled={!wallet.isConnected || isPending}
                >
                  {isPending ? "Creating DAO..." : "Create DAO"}
                </Button>
              </form>
            </Form>
          </CardContent>
        </Card>
      </main>
    </div>
  );
}

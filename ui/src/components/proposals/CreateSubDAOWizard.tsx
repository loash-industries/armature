import { useState } from "react";
import { useForm, useFieldArray } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import {
  Form,
  FormField,
  FormItem,
  FormLabel,
  FormControl,
  FormDescription,
  FormMessage,
  Input,
  Textarea,
  Button,
  Badge,
  Card,
  CardHeader,
  CardTitle,
  CardContent,
  Checkbox,
} from "@awar.dev/ui";
import { createSubDAOSchema } from "@/lib/schemas";
import { ALL_PROPOSAL_TYPE_KEYS, PROPOSAL_TYPE_MAP } from "@/config/proposal-types";
import type { CreateSubDAOPayload, ProposalConfigInput } from "@/types/proposal";

interface CreateSubDAOWizardProps {
  daoId: string;
  isPending?: boolean;
  onSubmit: (data: CreateSubDAOPayload) => void;
}

const STEPS = [
  "Identity",
  "Board",
  "Charter",
  "Proposal Types",
  "Funding",
  "Review",
] as const;

const DEFAULT_CONFIG: ProposalConfigInput = {
  quorum: 5000,
  approvalThreshold: 5000,
  proposeThreshold: 0,
  expiryMs: 604800000,
  executionDelayMs: 0,
  cooldownMs: 0,
};

// Types blocked from SubDAOs
const SUBDAO_BLOCKED = new Set(["SpawnDAO", "SpinOutSubDAO", "CreateSubDAO"]);
const AVAILABLE_TYPES = ALL_PROPOSAL_TYPE_KEYS.filter(
  (k) => !SUBDAO_BLOCKED.has(k),
);

export function CreateSubDAOWizard({
  isPending,
  onSubmit,
}: CreateSubDAOWizardProps) {
  const [step, setStep] = useState(0);

  const form = useForm({
    resolver: zodResolver(createSubDAOSchema),
    defaultValues: {
      name: "",
      metadataIpfs: "",
      board: [""],
      charterName: "",
      charterDescription: "",
      charterImageUrl: "",
      proposalTypes: [] as Array<{
        typeKey: string;
        config: ProposalConfigInput;
      }>,
      fundingAmount: "0",
    },
  });

  const boardArray = useFieldArray({
    control: form.control,
    name: "board" as never,
  });

  const proposalTypesArray = useFieldArray({
    control: form.control,
    name: "proposalTypes" as never,
  });

  const watchedTypes = form.watch("proposalTypes") as Array<{
    typeKey: string;
    config: ProposalConfigInput;
  }>;
  const selectedTypeKeys = new Set(watchedTypes.map((t) => t.typeKey));

  function toggleType(typeKey: string) {
    if (selectedTypeKeys.has(typeKey)) {
      const idx = watchedTypes.findIndex((t) => t.typeKey === typeKey);
      if (idx >= 0) proposalTypesArray.remove(idx);
    } else {
      proposalTypesArray.append({
        typeKey,
        config: { ...DEFAULT_CONFIG },
      } as never);
    }
  }

  const canNext = step < STEPS.length - 1;
  const canBack = step > 0;

  return (
    <Form {...form}>
      <form
        onSubmit={form.handleSubmit((data) =>
          onSubmit(data as CreateSubDAOPayload),
        )}
        className="space-y-6"
      >
        {/* Step indicator */}
        <div className="flex gap-2">
          {STEPS.map((s, i) => (
            <Badge
              key={s}
              variant={i === step ? "default" : "outline"}
              className="cursor-pointer"
              onClick={() => setStep(i)}
            >
              {i + 1}. {s}
            </Badge>
          ))}
        </div>

        {/* Step 1: Identity */}
        {step === 0 && (
          <div className="space-y-4">
            <FormField
              control={form.control}
              name="name"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>SubDAO Name</FormLabel>
                  <FormControl>
                    <Input placeholder="My SubDAO" {...field} />
                  </FormControl>
                  <FormMessage />
                </FormItem>
              )}
            />
            <FormField
              control={form.control}
              name="metadataIpfs"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Description / Metadata CID</FormLabel>
                  <FormControl>
                    <Textarea
                      placeholder="Describe the purpose of this SubDAO..."
                      {...field}
                    />
                  </FormControl>
                  <FormMessage />
                </FormItem>
              )}
            />
          </div>
        )}

        {/* Step 2: Board */}
        {step === 1 && (
          <div className="space-y-4">
            <FormLabel>Board Members</FormLabel>
            {boardArray.fields.map((field, index) => (
              <div key={field.id} className="flex items-center gap-2">
                <FormField
                  control={form.control}
                  name={`board.${index}`}
                  render={({ field }) => (
                    <FormItem className="flex-1">
                      <FormControl>
                        <Input placeholder="0x..." {...field} />
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )}
                />
                <Button
                  type="button"
                  variant="destructive"
                  size="sm"
                  onClick={() => boardArray.remove(index)}
                >
                  Remove
                </Button>
              </div>
            ))}
            <Button
              type="button"
              variant="outline"
              onClick={() => boardArray.append("" as never)}
            >
              + Add Member
            </Button>
          </div>
        )}

        {/* Step 3: Charter */}
        {step === 2 && (
          <div className="space-y-4">
            <FormField
              control={form.control}
              name="charterName"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Charter Name</FormLabel>
                  <FormControl>
                    <Input {...field} />
                  </FormControl>
                  <FormMessage />
                </FormItem>
              )}
            />
            <FormField
              control={form.control}
              name="charterDescription"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Charter Description</FormLabel>
                  <FormControl>
                    <Textarea rows={6} {...field} />
                  </FormControl>
                  <FormDescription className="text-xs">
                    Supports markdown. For long charters, upload to Walrus and
                    reference the blob ID.
                  </FormDescription>
                  <FormMessage />
                </FormItem>
              )}
            />
            <FormField
              control={form.control}
              name="charterImageUrl"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Image URL</FormLabel>
                  <FormControl>
                    <Input placeholder="https://..." {...field} />
                  </FormControl>
                  <FormMessage />
                </FormItem>
              )}
            />
          </div>
        )}

        {/* Step 4: Proposal Types */}
        {step === 3 && (
          <div className="space-y-4">
            <p className="text-sm">
              Select which proposal types to enable for the SubDAO.
            </p>
            <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
              {AVAILABLE_TYPES.map((typeKey) => {
                const def = PROPOSAL_TYPE_MAP[typeKey];
                return (
                  <label
                    key={typeKey}
                    className="flex cursor-pointer items-center gap-2 rounded border p-2"
                  >
                    <Checkbox
                      checked={selectedTypeKeys.has(typeKey)}
                      onCheckedChange={() => toggleType(typeKey)}
                    />
                    <div>
                      <span className="font-mono text-sm">
                        {def?.label ?? typeKey}
                      </span>
                    </div>
                  </label>
                );
              })}
            </div>
            {watchedTypes.length > 0 && (
              <p className="text-muted-foreground text-xs">
                {watchedTypes.length} type(s) selected — all will use default
                config (50% quorum, 50% threshold, 7d voting)
              </p>
            )}
          </div>
        )}

        {/* Step 5: Funding */}
        {step === 4 && (
          <div className="space-y-4">
            <FormField
              control={form.control}
              name="fundingAmount"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Initial SUI Funding (MIST)</FormLabel>
                  <FormControl>
                    <Input type="number" placeholder="0" {...field} />
                  </FormControl>
                  <FormDescription className="text-xs">
                    Optional. Amount of SUI (in MIST) to transfer from parent
                    treasury to the new SubDAO.
                  </FormDescription>
                  <FormMessage />
                </FormItem>
              )}
            />
          </div>
        )}

        {/* Step 6: Review */}
        {step === 5 && (
          <div className="space-y-4">
            <Card>
              <CardHeader>
                <CardTitle className="text-base">Review SubDAO</CardTitle>
              </CardHeader>
              <CardContent className="space-y-3 text-sm">
                <div>
                  <span className="text-muted-foreground">Name:</span>{" "}
                  {form.getValues("name") || "—"}
                </div>
                <div>
                  <span className="text-muted-foreground">Board:</span>{" "}
                  {(form.getValues("board") as string[]).filter(Boolean)
                    .length}{" "}
                  member(s)
                </div>
                <div>
                  <span className="text-muted-foreground">Charter:</span>{" "}
                  {form.getValues("charterName") || "—"}
                </div>
                <div>
                  <span className="text-muted-foreground">
                    Proposal Types:
                  </span>{" "}
                  {watchedTypes.length} type(s)
                  <div className="mt-1 flex flex-wrap gap-1">
                    {watchedTypes.map((t) => (
                      <Badge key={t.typeKey} variant="outline">
                        {t.typeKey}
                      </Badge>
                    ))}
                  </div>
                </div>
                <div>
                  <span className="text-muted-foreground">Funding:</span>{" "}
                  {form.getValues("fundingAmount") || "0"} MIST
                </div>
              </CardContent>
            </Card>
          </div>
        )}

        {/* Navigation */}
        <div className="flex justify-between">
          <Button
            type="button"
            variant="outline"
            disabled={!canBack}
            onClick={() => setStep((s) => s - 1)}
          >
            Back
          </Button>
          {canNext ? (
            <Button
              type="button"
              onClick={() => setStep((s) => s + 1)}
            >
              Next
            </Button>
          ) : (
            <Button type="submit" disabled={isPending}>
              {isPending ? "Submitting..." : "Create SubDAO Proposal"}
            </Button>
          )}
        </div>
      </form>
    </Form>
  );
}

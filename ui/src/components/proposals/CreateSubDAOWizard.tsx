import { useMemo, useState } from "react";
import { useForm, useFieldArray } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardHeader,
  CardTitle,
  CardContent,
} from "@/components/ui/card";
import { Checkbox } from "@/components/ui/checkbox";
import {
  Form,
  FormField,
  FormItem,
  FormLabel,
  FormControl,
  FormDescription,
  FormMessage,
} from "@/components/ui/form";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { RecipientCombobox } from "@/components/ui/RecipientCombobox";
import { createSubDAOSchema } from "@/lib/schemas";
import { ALL_PROPOSAL_TYPE_KEYS, PROPOSAL_TYPE_MAP } from "@/config/proposal-types";
import { SubmitProposalButton } from "./SubmitProposalButton";
import { useGovernanceDetail, useTreasuryEvents } from "@/hooks/useDao";
import { useCharacterNames } from "@/hooks/useCharacterNames";
import type { CreateSubDAOPayload, ProposalConfigInput } from "@/types/proposal";

interface CreateSubDAOWizardProps {
  daoId: string;
  isPending?: boolean;
  pendingStep?: "creating" | "voting" | null;
  onSubmit: (data: CreateSubDAOPayload) => void;
  onSubmitAndVote?: (data: CreateSubDAOPayload) => void;
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
  quorum: 50,
  approvalThreshold: 50,
  proposeThreshold: 0,
  expiryMs: 168,
  executionDelayMs: 0,
  cooldownMs: 0,
};

const HOURS_TO_MS = 3_600_000;

/** Convert form values (percentages, hours) to on-chain values (basis points, ms). */
function toOnChain(data: CreateSubDAOPayload): CreateSubDAOPayload {
  return {
    ...data,
    proposalTypes: data.proposalTypes.map((pt) => ({
      ...pt,
      config: {
        ...pt.config,
        quorum: Math.round(pt.config.quorum * 100),
        approvalThreshold: Math.round(pt.config.approvalThreshold * 100),
        expiryMs: pt.config.expiryMs * HOURS_TO_MS,
        executionDelayMs: pt.config.executionDelayMs * HOURS_TO_MS,
        cooldownMs: pt.config.cooldownMs * HOURS_TO_MS,
      },
    })),
  };
}

// Types blocked from SubDAOs
const SUBDAO_BLOCKED = new Set(["SpawnDAO", "SpinOutSubDAO", "CreateSubDAO"]);

export function CreateSubDAOWizard({
  daoId,
  isPending,
  pendingStep,
  onSubmit,
  onSubmitAndVote,
}: CreateSubDAOWizardProps) {
  // Prime character-name cache so RecipientCombobox has names even on cold navigation.
  const { data: governance } = useGovernanceDetail(daoId);
  const { data: treasuryEvents } = useTreasuryEvents(daoId);
  const primeAddresses = useMemo(() => {
    const addrs = new Set<string>();
    for (const m of governance?.members ?? []) addrs.add(m.address);
    for (const ev of treasuryEvents ?? []) {
      if (ev.actor) addrs.add(ev.actor);
      if (ev.recipient) addrs.add(ev.recipient);
    }
    return [...addrs];
  }, [governance, treasuryEvents]);
  useCharacterNames(primeAddresses);

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

  // eslint-disable-next-line react-hooks/incompatible-library
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
          onSubmit(toOnChain(data as CreateSubDAOPayload)),
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
                  <FormLabel>Organizational Unit Name</FormLabel>
                  <FormControl>
                    <Input placeholder="Rum Buyers" {...field} />
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
                  <FormLabel>Description</FormLabel>
                  <FormControl>
                    <Textarea
                      placeholder="We buy rum for the crew"
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
                        <RecipientCombobox
                          value={field.value as string}
                          onChange={field.onChange}
                          onBlur={field.onBlur}
                          disabled={isPending}
                        />
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
              Select which proposal types to enable for the organizational unit.
            </p>
            <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
              {ALL_PROPOSAL_TYPE_KEYS.map((typeKey) => {
                const def = PROPOSAL_TYPE_MAP[typeKey];
                const isBlocked = SUBDAO_BLOCKED.has(typeKey);
                return (
                  <label
                    key={typeKey}
                    className={`flex items-center gap-2 rounded border p-2 ${
                      isBlocked
                        ? "cursor-not-allowed opacity-50"
                        : "cursor-pointer"
                    }`}
                  >
                    <Checkbox
                      checked={selectedTypeKeys.has(typeKey)}
                      onCheckedChange={() => toggleType(typeKey)}
                      disabled={isBlocked}
                    />
                    <div className="flex items-center gap-1.5">
                      <span className="font-mono text-sm">
                        {def?.label ?? typeKey}
                      </span>
                      {isBlocked && (
                        <Badge variant="secondary" className="text-[10px] px-1.5 py-0">
                          Organization only
                        </Badge>
                      )}
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
                <CardTitle className="text-base">Review Organizational Unit</CardTitle>
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
                {Object.keys(form.formState.errors).length > 0 && (
                  <div className="mt-4 rounded border border-destructive/50 bg-destructive/10 p-3">
                    <p className="text-destructive text-sm font-medium mb-1">
                      Please fix the following errors:
                    </p>
                    <ul className="list-disc list-inside text-destructive text-xs space-y-0.5">
                      {Object.entries(form.formState.errors).map(
                        ([field, error]) => (
                          <li key={field}>
                            <span className="font-medium">{field}:</span>{" "}
                            {error?.message?.toString() ?? "Invalid value"}
                          </li>
                        ),
                      )}
                    </ul>
                  </div>
                )}
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
            <SubmitProposalButton
              isPending={isPending}
              pendingStep={pendingStep}
              actionType="Create Organizational Unit"
              onSubmit={() => form.handleSubmit((data) => onSubmit(toOnChain(data as CreateSubDAOPayload)))()}
              onSubmitAndVote={() => form.handleSubmit((data) => {
                const d = toOnChain(data as CreateSubDAOPayload);
                if (onSubmitAndVote) onSubmitAndVote(d);
                else onSubmit(d);
              })()}
            />
          )}
        </div>
      </form>
    </Form>
  );
}

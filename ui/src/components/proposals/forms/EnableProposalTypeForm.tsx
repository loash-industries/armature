import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import {
  Form,
  FormField,
  FormItem,
  FormLabel,
  FormControl,
  FormMessage,
} from "@/components/ui/form";
import {
  Select,
  SelectTrigger,
  SelectValue,
  SelectContent,
  SelectItem,
} from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { enableProposalTypeSchema } from "@/lib/schemas";
import { useProposalFormOptions } from "@/hooks/useProposalFormOptions";
import { ProposalConfigForm } from "@/components/proposals/ProposalConfigForm";
import { SubmitProposalButton } from "@/components/proposals/SubmitProposalButton";
import { PROPOSAL_TYPE_DISPLAY_NAME } from "@/config/proposal-types";
import type { EnableProposalTypePayload } from "@/types/proposal";

interface EnableProposalTypeFormProps {
  daoId: string;
  isPending?: boolean;
  defaultTypeKey?: string;
  onSubmit: (data: EnableProposalTypePayload) => void;
  onSubmitAndVote?: (data: EnableProposalTypePayload) => void;
}

export function EnableProposalTypeForm({
  daoId,
  isPending,
  defaultTypeKey = "",
  onSubmit,
  onSubmitAndVote,
}: EnableProposalTypeFormProps) {
  const { disabledTypes } = useProposalFormOptions(daoId);

  const form = useForm({
    resolver: zodResolver(enableProposalTypeSchema),
    defaultValues: {
      typeKey: defaultTypeKey,
      config: {
        quorum: 5000,
        approvalThreshold: 5000,
        proposeThreshold: 0,
        expiryMs: 168,
        executionDelayMs: 0,
        cooldownMs: 0,
      },
      metadataIpfs: "",
    },
  });

  const HOURS_TO_MS = 3_600_000;
  const toMs = (data: EnableProposalTypePayload): EnableProposalTypePayload => ({
    ...data,
    config: {
      ...data.config,
      expiryMs: data.config.expiryMs * HOURS_TO_MS,
      executionDelayMs: data.config.executionDelayMs * HOURS_TO_MS,
      cooldownMs: data.config.cooldownMs * HOURS_TO_MS,
    },
  });

  return (
    <Form {...form}>
      <form
        onSubmit={form.handleSubmit((data) =>
          onSubmit(toMs(data as EnableProposalTypePayload)),
        )}
        className="space-y-4"
      >
        <FormField
          control={form.control}
          name="typeKey"
          render={({ field }) => (
            <FormItem>
              <FormControl>
                <Select value={field.value} onValueChange={field.onChange}>
                  <SelectTrigger>
                    <SelectValue placeholder="Select type...">
                      {field.value
                        ? (PROPOSAL_TYPE_DISPLAY_NAME[field.value as keyof typeof PROPOSAL_TYPE_DISPLAY_NAME] ?? field.value)
                        : undefined}
                    </SelectValue>
                  </SelectTrigger>
                  <SelectContent className="w-[var(--radix-select-trigger-width)]">
                    {disabledTypes.map((t) => (
                      <SelectItem key={t} value={t}>
                        {PROPOSAL_TYPE_DISPLAY_NAME[t as keyof typeof PROPOSAL_TYPE_DISPLAY_NAME] ?? t}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </FormControl>
              <FormLabel>Proposal Type to Enable</FormLabel>
              <FormMessage />
            </FormItem>
          )}
        />

        <div>
          <p className="mb-2 text-sm font-medium">Voting Configuration</p>
          <ProposalConfigForm control={form.control} />
        </div>

        <FormField
          control={form.control}
          name="metadataIpfs"
          render={({ field }) => (
            <FormItem>
              <FormLabel>Proposal Description (optional)</FormLabel>
              <FormControl>
                <Textarea placeholder="Describe this proposal..." {...field} />
              </FormControl>
              <FormMessage />
            </FormItem>
          )}
        />

        <SubmitProposalButton
          isPending={isPending}
          onSubmit={() => form.handleSubmit((data) => onSubmit(toMs(data as EnableProposalTypePayload)))()} 
          onSubmitAndVote={() => form.handleSubmit((data) => {
            const d = toMs(data as EnableProposalTypePayload);
            if (onSubmitAndVote) onSubmitAndVote(d);
            else onSubmit(d);
          })()}
        />
      </form>
    </Form>
  );
}

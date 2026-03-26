import { useEffect } from "react";
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
import { updateProposalConfigSchema } from "@/lib/schemas";
import { useProposalFormOptions } from "@/hooks/useProposalFormOptions";
import { ProposalConfigForm } from "@/components/proposals/ProposalConfigForm";
import { SubmitProposalButton } from "@/components/proposals/SubmitProposalButton";
import type { UpdateProposalConfigPayload } from "@/types/proposal";

interface UpdateProposalConfigFormProps {
  daoId: string;
  isPending?: boolean;
  onSubmit: (data: UpdateProposalConfigPayload) => void;
  onSubmitAndVote?: (data: UpdateProposalConfigPayload) => void;
}

export function UpdateProposalConfigForm({
  daoId,
  isPending,
  onSubmit,
  onSubmitAndVote,
}: UpdateProposalConfigFormProps) {
  const { enabledTypes, govConfig } = useProposalFormOptions(daoId);

  const form = useForm({
    resolver: zodResolver(updateProposalConfigSchema),
    defaultValues: {
      typeKey: "",
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

  const selectedType = form.watch("typeKey");

  const HOURS_TO_MS = 3_600_000;
  const toMs = (data: UpdateProposalConfigPayload): UpdateProposalConfigPayload => ({
    ...data,
    config: {
      ...data.config,
      expiryMs: data.config.expiryMs * HOURS_TO_MS,
      executionDelayMs: data.config.executionDelayMs * HOURS_TO_MS,
      cooldownMs: data.config.cooldownMs * HOURS_TO_MS,
    },
  });

  useEffect(() => {
    if (selectedType) {
      const existing = govConfig.find((t) => t.typeKey === selectedType);
      if (existing?.config) {
        form.setValue("config", {
          ...existing.config,
          expiryMs: existing.config.expiryMs / HOURS_TO_MS,
          executionDelayMs: existing.config.executionDelayMs / HOURS_TO_MS,
          cooldownMs: existing.config.cooldownMs / HOURS_TO_MS,
        });
      }
    }
  }, [selectedType, govConfig, form]);

  return (
    <Form {...form}>
      <form
        onSubmit={form.handleSubmit((data) =>
          onSubmit(toMs(data as UpdateProposalConfigPayload)),
        )}
        className="space-y-4"
      >
        <FormField
          control={form.control}
          name="typeKey"
          render={({ field }) => (
            <FormItem>
              <FormLabel>Proposal Type</FormLabel>
              <FormControl>
                <Select value={field.value} onValueChange={field.onChange}>
                  <SelectTrigger>
                    <SelectValue placeholder="Select type..." />
                  </SelectTrigger>
                  <SelectContent>
                    {enabledTypes.map((t) => (
                      <SelectItem key={t} value={t}>
                        {t}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </FormControl>
              <FormMessage />
            </FormItem>
          )}
        />

        {selectedType && (
          <div>
            <p className="mb-2 text-sm font-medium">
              Voting Configuration for {selectedType}
            </p>
            <ProposalConfigForm control={form.control} />
          </div>
        )}

        <FormField
          control={form.control}
          name="metadataIpfs"
          render={({ field }) => (
            <FormItem>
              <FormLabel>Proposal Description</FormLabel>
              <FormControl>
                <Textarea placeholder="Describe this proposal..." {...field} />
              </FormControl>
              <FormMessage />
            </FormItem>
          )}
        />

        <SubmitProposalButton
          isPending={isPending}
          onSubmit={() => form.handleSubmit((data) => onSubmit(toMs(data as UpdateProposalConfigPayload)))()}
          onSubmitAndVote={() => form.handleSubmit((data) => {
            const d = toMs(data as UpdateProposalConfigPayload);
            if (onSubmitAndVote) onSubmitAndVote(d);
            else onSubmit(d);
          })()}
        />
      </form>
    </Form>
  );
}

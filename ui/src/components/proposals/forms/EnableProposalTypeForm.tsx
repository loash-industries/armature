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

import { ProposalTypeSelect } from "@/components/proposals/ProposalTypeSelect";
import { Textarea } from "@/components/ui/textarea";
import { enableProposalTypeSchema } from "@/lib/schemas";
import { useProposalFormOptions } from "@/hooks/useProposalFormOptions";
import { ProposalConfigForm } from "@/components/proposals/ProposalConfigForm";
import { SubmitProposalButton } from "@/components/proposals/SubmitProposalButton";

import type { EnableProposalTypePayload } from "@/types/proposal";

interface EnableProposalTypeFormProps {
  daoId: string;
  isPending?: boolean;
  pendingStep?: "creating" | "voting" | null;
  defaultTypeKey?: string;
  onSubmit: (data: EnableProposalTypePayload) => void;
  onSubmitAndVote?: (data: EnableProposalTypePayload) => void;
}

export function EnableProposalTypeForm({
  daoId,
  isPending,
  pendingStep,
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
        quorum: 50,
        approvalThreshold: 50,
        proposeThreshold: 0,
        expiryMs: 168,
        executionDelayMs: 0,
        cooldownMs: 0,
      },
      metadataIpfs: "",
    },
  });

  const HOURS_TO_MS = 3_600_000;
  const toMs = (
    data: EnableProposalTypePayload,
  ): EnableProposalTypePayload => ({
    ...data,
    config: {
      ...data.config,
      quorum: Math.round(data.config.quorum * 100),
      approvalThreshold: Math.round(data.config.approvalThreshold * 100),
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
        <ProposalTypeSelect
          control={form.control}
          label="Action to Turn On"
          types={disabledTypes}
        />

        <div>
          <p className="mb-2 text-sm font-medium">Voting Configuration</p>
          <ProposalConfigForm control={form.control} collapseAdvanced />
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
          pendingStep={pendingStep}
          actionType={form.watch("typeKey") || "Enable Action Type"}
          onSubmit={() =>
            form.handleSubmit((data) =>
              onSubmit(toMs(data as EnableProposalTypePayload)),
            )()
          }
          onSubmitAndVote={() =>
            form.handleSubmit((data) => {
              const d = toMs(data as EnableProposalTypePayload);
              if (onSubmitAndVote) onSubmitAndVote(d);
              else onSubmit(d);
            })()
          }
        />
      </form>
    </Form>
  );
}

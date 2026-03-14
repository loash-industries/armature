import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import {
  Form,
  FormField,
  FormItem,
  FormLabel,
  FormControl,
  FormMessage,
  Textarea,
  Select,
  SelectTrigger,
  SelectValue,
  SelectContent,
  SelectItem,
  Button,
} from "@awar.dev/ui";
import { enableProposalTypeSchema } from "@/lib/schemas";
import { useProposalFormOptions } from "@/hooks/useProposalFormOptions";
import { ProposalConfigForm } from "@/components/proposals/ProposalConfigForm";
import type { EnableProposalTypePayload } from "@/types/proposal";

interface EnableProposalTypeFormProps {
  daoId: string;
  isPending?: boolean;
  onSubmit: (data: EnableProposalTypePayload) => void;
}

export function EnableProposalTypeForm({
  daoId,
  isPending,
  onSubmit,
}: EnableProposalTypeFormProps) {
  const { disabledTypes } = useProposalFormOptions(daoId);

  const form = useForm({
    resolver: zodResolver(enableProposalTypeSchema),
    defaultValues: {
      typeKey: "",
      config: {
        quorum: 5000,
        approvalThreshold: 5000,
        proposeThreshold: 0,
        expiryMs: 604800000,
        executionDelayMs: 0,
        cooldownMs: 0,
      },
      metadataIpfs: "",
    },
  });

  return (
    <Form {...form}>
      <form
        onSubmit={form.handleSubmit((data) =>
          onSubmit(data as EnableProposalTypePayload),
        )}
        className="space-y-4"
      >
        <FormField
          control={form.control}
          name="typeKey"
          render={({ field }) => (
            <FormItem>
              <FormLabel>Proposal Type to Enable</FormLabel>
              <FormControl>
                <Select value={field.value} onValueChange={field.onChange}>
                  <SelectTrigger>
                    <SelectValue placeholder="Select type..." />
                  </SelectTrigger>
                  <SelectContent>
                    {disabledTypes.map((t) => (
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

        <div>
          <p className="mb-2 text-sm font-medium">Voting Configuration</p>
          <ProposalConfigForm control={form.control} />
        </div>

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

        <Button type="submit" disabled={isPending}>
          {isPending ? "Submitting..." : "Create Proposal"}
        </Button>
      </form>
    </Form>
  );
}

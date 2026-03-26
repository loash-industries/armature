import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
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
import { charterUpdateSchema } from "@/lib/schemas";
import { useDaoSummary, useCharterDetail } from "@/hooks/useDao";
import { SubmitProposalButton } from "@/components/proposals/SubmitProposalButton";
import type { CharterUpdatePayload } from "@/types/proposal";

interface CharterUpdateFormProps {
  daoId: string;
  isPending?: boolean;
  onSubmit: (data: CharterUpdatePayload) => void;
  onSubmitAndVote?: (data: CharterUpdatePayload) => void;
}

export function CharterUpdateForm({
  daoId,
  isPending,
  onSubmit,
  onSubmitAndVote,
}: CharterUpdateFormProps) {
  const { data: dao } = useDaoSummary(daoId);
  const { data: charter } = useCharterDetail(dao?.charterId);

  const form = useForm<CharterUpdatePayload>({
    resolver: zodResolver(charterUpdateSchema),
    defaultValues: {
      name: charter?.name ?? "",
      description: charter?.description ?? "",
      imageUrl: charter?.imageUrl ?? "",
      metadataIpfs: "",
    },
  });

  return (
    <Form {...form}>
      <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-4">
        <FormField
          control={form.control}
          name="name"
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
          name="description"
          render={({ field }) => (
            <FormItem>
              <FormLabel>Charter Description</FormLabel>
              <FormControl>
                <Textarea rows={6} {...field} />
              </FormControl>
              <FormDescription className="text-xs">
                Supports markdown. For long charters, upload to Walrus and
                paste the blob ID below.
              </FormDescription>
              <FormMessage />
            </FormItem>
          )}
        />

        <FormField
          control={form.control}
          name="imageUrl"
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
          onSubmit={() => form.handleSubmit((data) => onSubmit(data))()}
          onSubmitAndVote={() => form.handleSubmit((data) => {
            if (onSubmitAndVote) onSubmitAndVote(data);
            else onSubmit(data);
          })()}
        />
      </form>
    </Form>
  );
}

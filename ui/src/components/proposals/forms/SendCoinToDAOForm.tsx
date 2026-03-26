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
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectTrigger,
  SelectValue,
  SelectContent,
  SelectItem,
} from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { sendCoinToDAOSchema } from "@/lib/schemas";
import { useTreasuryBalances, useDaoSummary } from "@/hooks/useDao";
import { SubmitProposalButton } from "@/components/proposals/SubmitProposalButton";
import type { SendCoinToDAOPayload } from "@/types/proposal";

interface SendCoinToDAOFormProps {
  daoId: string;
  isPending?: boolean;
  onSubmit: (data: SendCoinToDAOPayload) => void;
  onSubmitAndVote?: (data: SendCoinToDAOPayload) => void;
}

export function SendCoinToDAOForm({
  daoId,
  isPending,
  onSubmit,
  onSubmitAndVote,
}: SendCoinToDAOFormProps) {
  const { data: dao } = useDaoSummary(daoId);
  const { data: balances } = useTreasuryBalances(dao?.treasuryId);

  const form = useForm<SendCoinToDAOPayload>({
    resolver: zodResolver(sendCoinToDAOSchema),
    defaultValues: {
      recipientTreasuryId: "",
      amount: "",
      coinType: "",
      metadataIpfs: "",
    },
  });

  const selectedCoin = form.watch("coinType");
  const maxBalance = balances?.find(
    (b) => b.coinType === selectedCoin,
  )?.balance;

  return (
    <Form {...form}>
      <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-4">
        <FormField
          control={form.control}
          name="coinType"
          render={({ field }) => (
            <FormItem>
              <FormLabel>Coin Type</FormLabel>
              <FormControl>
                <Select value={field.value} onValueChange={field.onChange}>
                  <SelectTrigger>
                    <SelectValue placeholder="Select coin..." />
                  </SelectTrigger>
                  <SelectContent>
                    {balances?.map((b) => (
                      <SelectItem key={b.coinType} value={b.coinType}>
                        {b.coinType} ({b.balance.toString()})
                      </SelectItem>
                    )) ?? (
                      <SelectItem value="" disabled>
                        No coins in treasury
                      </SelectItem>
                    )}
                  </SelectContent>
                </Select>
              </FormControl>
              <FormMessage />
            </FormItem>
          )}
        />

        <FormField
          control={form.control}
          name="amount"
          render={({ field }) => (
            <FormItem>
              <FormLabel>
                Amount
                {maxBalance !== undefined && (
                  <span className="text-muted-foreground ml-2 text-xs">
                    max: {maxBalance.toString()}
                  </span>
                )}
              </FormLabel>
              <FormControl>
                <Input placeholder="0" {...field} />
              </FormControl>
              <FormMessage />
            </FormItem>
          )}
        />

        <FormField
          control={form.control}
          name="recipientTreasuryId"
          render={({ field }) => (
            <FormItem>
              <FormLabel>Recipient Treasury ID</FormLabel>
              <FormControl>
                <Input placeholder="0x..." {...field} />
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

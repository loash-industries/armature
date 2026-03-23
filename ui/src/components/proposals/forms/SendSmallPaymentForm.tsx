import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { Button } from "@/components/ui/button";
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
import { sendSmallPaymentSchema } from "@/lib/schemas";
import { useTreasuryBalances, useDaoSummary } from "@/hooks/useDao";
import type { SendSmallPaymentPayload } from "@/types/proposal";

interface SendSmallPaymentFormProps {
  daoId: string;
  isPending?: boolean;
  onSubmit: (data: SendSmallPaymentPayload) => void;
}

export function SendSmallPaymentForm({
  daoId,
  isPending,
  onSubmit,
}: SendSmallPaymentFormProps) {
  const { data: dao } = useDaoSummary(daoId);
  const { data: balances } = useTreasuryBalances(dao?.treasuryId);

  const form = useForm<SendSmallPaymentPayload>({
    resolver: zodResolver(sendSmallPaymentSchema),
    defaultValues: {
      recipient: "",
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
          name="recipient"
          render={({ field }) => (
            <FormItem>
              <FormLabel>Recipient Address</FormLabel>
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

        <Button type="submit" disabled={isPending}>
          {isPending ? "Submitting..." : "Create Proposal"}
        </Button>
      </form>
    </Form>
  );
}

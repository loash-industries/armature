import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
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
import { useTreasuryBalances, useDaoSummary, useCoinMetadataMap } from "@/hooks/useDao";
import { SubmitProposalButton } from "@/components/proposals/SubmitProposalButton";
import { CoinAmountInput } from "@/components/ui/CoinAmountInput";
import { CoinSelect } from "@/components/ui/CoinSelect";
import { formatBalance, parseAmount } from "@/lib/coins";
import type { TreasuryWithdrawPayload } from "@/types/proposal";
import { useMemo } from "react";

// Internal form schema — amount is human-readable; converted to base units on submit.
const formSchema = z.object({
  coinType: z.string().min(1, "Select a coin type"),
  amount: z.string().min(1, "Amount is required"),
  recipient: z
    .string()
    .regex(/^0x[a-fA-F0-9]{64}$/, "Must be a valid Sui address (0x + 64 hex)"),
  metadataIpfs: z.string().min(1, "Proposal description is required"),
});

type FormValues = z.infer<typeof formSchema>;

interface TreasuryWithdrawFormProps {
  daoId: string;
  isPending?: boolean;
  onSubmit: (data: TreasuryWithdrawPayload) => void;
  onSubmitAndVote?: (data: TreasuryWithdrawPayload) => void;
}

export function TreasuryWithdrawForm({
  daoId,
  isPending,
  onSubmit,
  onSubmitAndVote,
}: TreasuryWithdrawFormProps) {
  const { data: dao } = useDaoSummary(daoId);
  const { data: balances } = useTreasuryBalances(dao?.treasuryId);

  const coinTypes = useMemo(
    () => balances?.map((b) => b.coinType) ?? [],
    [balances],
  );
  const { data: metadataMap } = useCoinMetadataMap(coinTypes);

  const form = useForm<FormValues>({
    resolver: zodResolver(formSchema),
    defaultValues: {
      coinType: "",
      amount: "",
      recipient: "",
      metadataIpfs: "",
    },
  });

  const selectedCoinType = form.watch("coinType");
  const selectedBalance = balances?.find((b) => b.coinType === selectedCoinType);
  const selectedMeta = selectedCoinType ? metadataMap?.[selectedCoinType] : undefined;
  const selectedSymbol =
    selectedMeta?.symbol ??
    (selectedCoinType ? selectedCoinType.split("::").pop() ?? "" : "");
  const selectedDecimals = selectedMeta?.decimals ?? 9;

  function toPayload(values: FormValues): TreasuryWithdrawPayload | null {
    const raw = parseAmount(values.amount, selectedDecimals);
    if (raw === null || raw <= 0n) {
      form.setError("amount", { message: "Enter a valid amount greater than 0" });
      return null;
    }
    if (selectedBalance && raw > selectedBalance.balance) {
      form.setError("amount", {
        message: `Amount exceeds treasury balance (${formatBalance(selectedBalance.balance, selectedDecimals)} ${selectedSymbol})`,
      });
      return null;
    }
    return {
      coinType: values.coinType,
      amount: raw.toString(),
      recipient: values.recipient,
      metadataIpfs: values.metadataIpfs,
    };
  }

  function handleSubmit(values: FormValues) {
    const payload = toPayload(values);
    if (payload) onSubmit(payload);
  }

  function handleSubmitAndVote(values: FormValues) {
    const payload = toPayload(values);
    if (!payload) return;
    if (onSubmitAndVote) onSubmitAndVote(payload);
    else onSubmit(payload);
  }

  return (
    <Form {...form}>
      <form onSubmit={form.handleSubmit(handleSubmit)} className="space-y-4">
        {/* Coin selector */}
        <FormField
          control={form.control}
          name="coinType"
          render={({ field }) => (
            <FormItem>
              <FormLabel>Coin</FormLabel>
              <FormControl>
                <CoinSelect
                  value={field.value}
                  onValueChange={(v) => {
                    field.onChange(v);
                    form.setValue("amount", "");
                  }}
                  balances={balances}
                  metadataMap={metadataMap}
                />
              </FormControl>
              <FormMessage />
            </FormItem>
          )}
        />

        {/* Decimal-aware amount with Max shortcut */}
        <FormField
          control={form.control}
          name="amount"
          render={({ field, fieldState }) => (
            <FormItem>
              <CoinAmountInput
                value={field.value}
                onChange={field.onChange}
                symbol={selectedSymbol}
                decimals={selectedDecimals}
                maxBalance={selectedBalance?.balance}
                disabled={!selectedCoinType || isPending}
                errorMessage={fieldState.error?.message}
              />
            </FormItem>
          )}
        />

        {/* Recipient address */}
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

        <SubmitProposalButton
          isPending={isPending}
          onSubmit={() => form.handleSubmit(handleSubmit)()}
          onSubmitAndVote={() => form.handleSubmit(handleSubmitAndVote)()}
        />
      </form>
    </Form>
  );
}


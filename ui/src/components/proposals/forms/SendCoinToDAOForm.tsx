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
import { formatBalance } from "@/lib/coins";
import type { SendCoinToDAOPayload } from "@/types/proposal";
import { useMemo, useState } from "react";

const formSchema = z.object({
  recipientTreasuryId: z
    .string()
    .regex(/^0x[a-fA-F0-9]{64}$/, "Must be a valid Sui object ID (0x + 64 hex)"),
  coinType: z.string().min(1, "Select a coin type"),
  metadataIpfs: z.string().default(""),
});

type FormValues = z.infer<typeof formSchema>;

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

  const coinTypes = useMemo(
    () => balances?.map((b) => b.coinType) ?? [],
    [balances],
  );
  const { data: metadataMap } = useCoinMetadataMap(coinTypes);

  const [amount, setAmount] = useState<bigint | null>(null);
  const [amountError, setAmountError] = useState<string | undefined>();

  const form = useForm<FormValues>({
    resolver: zodResolver(formSchema),
    defaultValues: {
      recipientTreasuryId: "",
      coinType: "",
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

  /** Convert form values + bigint amount to on-chain payload. */
  function toPayload(values: FormValues): SendCoinToDAOPayload | null {
    setAmountError(undefined);
    if (amount === null || amount <= 0n) {
      setAmountError("Enter a valid amount greater than 0");
      return null;
    }
    if (selectedBalance && amount > selectedBalance.balance) {
      setAmountError(
        `Amount exceeds treasury balance (${formatBalance(selectedBalance.balance, selectedDecimals)} ${selectedSymbol})`,
      );
      return null;
    }
    return {
      recipientTreasuryId: values.recipientTreasuryId,
      amount: amount.toString(),
      coinType: values.coinType,
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
                    setAmount(null);
                    setAmountError(undefined);
                  }}
                  balances={balances}
                  metadataMap={metadataMap}
                />
              </FormControl>
              <FormMessage />
            </FormItem>
          )}
        />

        {/* Amount */}
        <CoinAmountInput
          value={amount}
          onChange={(v) => { setAmount(v); setAmountError(undefined); }}
          symbol={selectedSymbol}
          decimals={selectedDecimals}
          maxBalance={selectedBalance?.balance}
          disabled={!selectedCoinType || isPending}
          errorMessage={amountError}
        />

        {/* Recipient treasury */}
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
          onSubmit={() => form.handleSubmit(handleSubmit)()}
          onSubmitAndVote={() => form.handleSubmit(handleSubmitAndVote)()}
        />
      </form>
    </Form>
  );
}

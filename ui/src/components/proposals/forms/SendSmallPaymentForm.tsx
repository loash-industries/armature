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
import type { SendSmallPaymentPayload } from "@/types/proposal";
import { useMemo, useState } from "react";
import { useCharacterNames } from "@/hooks/useCharacterNames";
import { AddressName } from "@/components/AddressName";

const formSchema = z.object({
  recipient: z
    .string()
    .regex(/^0x[a-fA-F0-9]{64}$/, "Must be a valid Sui address (0x + 64 hex)"),
  coinType: z.string().min(1, "Select a coin type"),
  metadataIpfs: z.string(),
});

type FormValues = z.infer<typeof formSchema>;

interface SendSmallPaymentFormProps {
  daoId: string;
  isPending?: boolean;
  pendingStep?: "creating" | "voting" | null;
  onSubmit: (data: SendSmallPaymentPayload) => void;
  onSubmitAndVote?: (data: SendSmallPaymentPayload) => void;
}

export function SendSmallPaymentForm({
  daoId,
  isPending,
  pendingStep,
  onSubmit,
  onSubmitAndVote,
}: SendSmallPaymentFormProps) {
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
      recipient: "",
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

  const recipientValue = form.watch("recipient");
  const isValidRecipient = /^0x[a-fA-F0-9]{64}$/.test(recipientValue);
  const recipientAddrs = useMemo(
    () => (isValidRecipient ? [recipientValue] : []),
    [isValidRecipient, recipientValue],
  );
  const { data: recipientNameMap } = useCharacterNames(recipientAddrs);

  /** Convert form values + bigint amount to on-chain payload. */
  function toPayload(values: FormValues): SendSmallPaymentPayload | null {
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
      recipient: values.recipient,
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
              {isValidRecipient && (
                <p className="text-xs text-muted-foreground flex items-center gap-1">
                  Resolved: <AddressName address={recipientValue} charName={recipientNameMap?.get(recipientValue)} />
                </p>
              )}
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
          pendingStep={pendingStep}
          actionType={selectedCoinType ? `Send ${selectedSymbol} to Organizational Unit` : "Send Payment"}
          onSubmit={() => form.handleSubmit(handleSubmit)()}
          onSubmitAndVote={() => form.handleSubmit(handleSubmitAndVote)()}
        />
      </form>
    </Form>
  );
}



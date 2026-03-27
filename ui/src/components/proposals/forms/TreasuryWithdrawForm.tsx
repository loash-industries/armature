import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import { TriangleAlert } from "lucide-react";
import { Link } from "@tanstack/react-router";
import {
  Form,
  FormField,
  FormItem,
  FormLabel,
  FormControl,
  FormMessage,
} from "@/components/ui/form";
import { Alert, AlertTitle, AlertDescription } from "@/components/ui/alert";
import { Textarea } from "@/components/ui/textarea";
import { RecipientCombobox } from "@/components/ui/RecipientCombobox";
import { useTreasuryBalances, useDaoSummary, useCoinMetadataMap } from "@/hooks/useDao";
import { SubmitProposalButton } from "@/components/proposals/SubmitProposalButton";
import { CoinAmountInput } from "@/components/ui/CoinAmountInput";
import { CoinSelect } from "@/components/ui/CoinSelect";
import { formatBalance } from "@/lib/coins";
import type { TreasuryWithdrawPayload } from "@/types/proposal";
import { useMemo, useState } from "react";
import { useCharacterNames } from "@/hooks/useCharacterNames";
import { AddressName } from "@/components/AddressName";

const formSchema = z.object({
  coinType: z.string().min(1, "Select a coin type"),
  recipient: z
    .string()
    .regex(/^0x[a-fA-F0-9]{64}$/, "Must be a valid Sui address (0x + 64 hex)"),
  metadataIpfs: z.string().default(""),
});

type FormValues = z.infer<typeof formSchema>;

interface TreasuryWithdrawFormProps {
  daoId: string;
  isPending?: boolean;
  isTypeEnabled?: boolean;
  onSubmit: (data: TreasuryWithdrawPayload) => void;
  onSubmitAndVote?: (data: TreasuryWithdrawPayload) => void;
}

export function TreasuryWithdrawForm({
  daoId,
  isPending,
  isTypeEnabled = true,
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

  const [amount, setAmount] = useState<bigint | null>(null);
  const [amountError, setAmountError] = useState<string | undefined>();

  const form = useForm<FormValues>({
    resolver: zodResolver(formSchema),
    defaultValues: {
      coinType: "",
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

  const recipientValue = form.watch("recipient");
  const isValidRecipient = /^0x[a-fA-F0-9]{64}$/.test(recipientValue);
  const recipientAddrs = useMemo(
    () => (isValidRecipient ? [recipientValue] : []),
    [isValidRecipient, recipientValue],
  );
  const { data: recipientNameMap } = useCharacterNames(recipientAddrs);

  function toPayload(values: FormValues): TreasuryWithdrawPayload | null {
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
      coinType: values.coinType,
      amount: amount.toString(),
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
        {!isTypeEnabled && (
          <Alert className="border-yellow-500/50 text-yellow-700 dark:text-yellow-400 [&>svg]:text-yellow-600 dark:[&>svg]:text-yellow-400">
            <TriangleAlert />
            <AlertTitle>Proposal type disabled</AlertTitle>
            <AlertDescription>
              Treasury Withdraw is not enabled for this DAO. You must{" "}
              <Link
                to="/dao/$daoId/proposals/new"
                params={{ daoId }}
                search={{ type: "EnableProposalType", prefill: "TreasuryWithdraw" }}
                className="font-medium underline underline-offset-2 hover:opacity-80"
              >
                enable treasury withdrawals
              </Link>{" "}
              before creating this proposal.
            </AlertDescription>
          </Alert>
        )}
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
                <RecipientCombobox
                  value={field.value}
                  onChange={field.onChange}
                  onBlur={field.onBlur}
                  disabled={isPending}
                />
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
          isPending={isPending || !isTypeEnabled}
          onSubmit={() => form.handleSubmit(handleSubmit)()}
          onSubmitAndVote={() => form.handleSubmit(handleSubmitAndVote)()}
        />
      </form>
    </Form>
  );
}


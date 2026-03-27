import { useState } from "react";
import { useParams, useNavigate, useSearch, Link } from "@tanstack/react-router";
import { ArrowLeft } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardHeader,
  CardTitle,
  CardDescription,
  CardContent,
} from "@/components/ui/card";
import {
  PROPOSAL_TYPE_MAP,
  PROPOSAL_TYPE_TIER,
} from "@/config/proposal-types";
import { useProposalFormOptions } from "@/hooks/useProposalFormOptions";
import { useSubmitProposal } from "@/hooks/useSubmitProposal";
import { ProposalTypeSelector } from "@/components/proposals/ProposalTypeSelector";
import { GenericProposalForm } from "@/components/proposals/GenericProposalForm";
import { TreasuryWithdrawForm } from "@/components/proposals/forms/TreasuryWithdrawForm";
import { SetBoardForm } from "@/components/proposals/forms/SetBoardForm";
import { EnableProposalTypeForm } from "@/components/proposals/forms/EnableProposalTypeForm";
import { UpdateProposalConfigForm } from "@/components/proposals/forms/UpdateProposalConfigForm";
import { CharterUpdateForm } from "@/components/proposals/forms/CharterUpdateForm";
import { SendCoinToDAOForm } from "@/components/proposals/forms/SendCoinToDAOForm";
import { SendSmallPaymentForm } from "@/components/proposals/forms/SendSmallPaymentForm";
import { CreateSubDAOWizard } from "@/components/proposals/CreateSubDAOWizard";

function BackToProposals({ daoId }: { daoId: string }) {
  return (
    <Link
      to="/dao/$daoId/proposals"
      params={{ daoId }}
      className="text-muted-foreground hover:text-foreground inline-flex items-center gap-1 text-sm transition-colors"
    >
      <ArrowLeft className="h-3.5 w-3.5" />
      Proposals
    </Link>
  );
}

export function NewProposalPage() {
  const { daoId } = useParams({ strict: false });
  const search = useSearch({ strict: false }) as Record<string, string>;
  const navigate = useNavigate();
  const { submitProposal, isPending } = useSubmitProposal(daoId ?? "");
  const typeKey = search.type ?? "";
  const prefill = search.prefill ?? "";
  const [selectorOpen, setSelectorOpen] = useState(!typeKey);

  const { enabledTypes, frozenTypes } = useProposalFormOptions(daoId ?? "");

  const typeDef = typeKey ? PROPOSAL_TYPE_MAP[typeKey] : null;
  const tier = typeKey ? (PROPOSAL_TYPE_TIER[typeKey] ?? "tier1") : null;

  function selectType(key: string) {
    setSelectorOpen(false);
    navigate({
      to: `/dao/$daoId/proposals/new`,
      params: { daoId: daoId ?? "" },
      search: { type: key },
    });
  }

  function handleSelectorOpenChange(open: boolean) {
    setSelectorOpen(open);
    // If the user closes the selector without picking a type, go back to the list.
    if (!open && !typeKey) {
      navigate({ to: "/dao/$daoId/proposals", params: { daoId: daoId ?? "" } });
    }
  }

  if (!typeKey || !typeDef) {
    return (
      <div className="space-y-4">
        <BackToProposals daoId={daoId ?? ""} />
        <ProposalTypeSelector
          open={selectorOpen}
          onOpenChange={handleSelectorOpenChange}
          enabledTypes={enabledTypes}
          frozenTypes={frozenTypes}
          onSelect={selectType}
        />
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <BackToProposals daoId={daoId ?? ""} />
      <Card>
        <CardHeader>
          <div className="flex items-center justify-between">
            <div>
              <CardTitle>{typeDef.label}</CardTitle>
              <CardDescription>{typeDef.description}</CardDescription>
            </div>
            <Button variant="outline" size="sm" onClick={() => navigate({ to: "/dao/$daoId/proposals", params: { daoId: daoId ?? "" } })}>
              Change Type
            </Button>
          </div>
        </CardHeader>
        <CardContent>
          {tier === "tier1" && (
            <GenericProposalForm
              typeKey={typeKey}
              daoId={daoId ?? ""}
              isPending={isPending}
              onSubmit={(data) => submitProposal(typeKey, data)}
              onSubmitAndVote={(data) => submitProposal(typeKey, data, true)}
            />
          )}
          {tier === "tier2" && typeKey === "TreasuryWithdraw" && (
            <TreasuryWithdrawForm
              daoId={daoId ?? ""}
              isPending={isPending}
              isTypeEnabled={enabledTypes.includes("TreasuryWithdraw")}
              onSubmit={(data) => submitProposal("TreasuryWithdraw", data)}
              onSubmitAndVote={(data) => submitProposal("TreasuryWithdraw", data, true)}
            />
          )}
          {tier === "tier2" && typeKey === "SetBoard" && (
            <SetBoardForm
              daoId={daoId ?? ""}
              isPending={isPending}
              onSubmit={(data) => submitProposal("SetBoard", data)}
              onSubmitAndVote={(data) => submitProposal("SetBoard", data, true)}
            />
          )}
          {tier === "tier2" && typeKey === "EnableProposalType" && (
            <EnableProposalTypeForm
              daoId={daoId ?? ""}
              isPending={isPending}
              defaultTypeKey={prefill}
              onSubmit={(data) => submitProposal("EnableProposalType", data)}
              onSubmitAndVote={(data) => submitProposal("EnableProposalType", data, true)}
            />
          )}
          {tier === "tier2" && typeKey === "UpdateProposalConfig" && (
            <UpdateProposalConfigForm
              daoId={daoId ?? ""}
              isPending={isPending}
              onSubmit={(data) => submitProposal("UpdateProposalConfig", data)}
              onSubmitAndVote={(data) => submitProposal("UpdateProposalConfig", data, true)}
            />
          )}
          {tier === "tier2" && typeKey === "CharterUpdate" && (
            <CharterUpdateForm
              daoId={daoId ?? ""}
              isPending={isPending}
              onSubmit={(data) => submitProposal("CharterUpdate", data)}
              onSubmitAndVote={(data) => submitProposal("CharterUpdate", data, true)}
            />
          )}
          {tier === "tier2" && typeKey === "SendCoinToDAO" && (
            <SendCoinToDAOForm
              daoId={daoId ?? ""}
              isPending={isPending}
              onSubmit={(data) => submitProposal("SendCoinToDAO", data)}
              onSubmitAndVote={(data) => submitProposal("SendCoinToDAO", data, true)}
            />
          )}
          {tier === "tier2" && typeKey === "SendSmallPayment" && (
            <SendSmallPaymentForm
              daoId={daoId ?? ""}
              isPending={isPending}
              onSubmit={(data) => submitProposal("SendSmallPayment", data)}
              onSubmitAndVote={(data) => submitProposal("SendSmallPayment", data, true)}
            />
          )}
          {tier === "wizard" && (
            <CreateSubDAOWizard
              daoId={daoId ?? ""}
              isPending={isPending}
              onSubmit={(data) => submitProposal("CreateSubDAO", data)}
              onSubmitAndVote={(data) => submitProposal("CreateSubDAO", data, true)}
            />
          )}
        </CardContent>
      </Card>
    </div>
  );
}

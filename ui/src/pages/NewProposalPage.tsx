import { useState } from "react";
import { useParams, useNavigate, useSearch } from "@tanstack/react-router";
import {
  Card,
  CardHeader,
  CardTitle,
  CardDescription,
  CardContent,
  Button,
} from "@awar.dev/ui";
import {
  PROPOSAL_TYPE_MAP,
  PROPOSAL_TYPE_TIER,
} from "@/config/proposal-types";
import { useProposalFormOptions } from "@/hooks/useProposalFormOptions";
import { ProposalTypeSelector } from "@/components/proposals/ProposalTypeSelector";
import { GenericProposalForm } from "@/components/proposals/GenericProposalForm";
import { TreasuryWithdrawForm } from "@/components/proposals/forms/TreasuryWithdrawForm";
import { SetBoardForm } from "@/components/proposals/forms/SetBoardForm";
import { EnableProposalTypeForm } from "@/components/proposals/forms/EnableProposalTypeForm";
import { UpdateProposalConfigForm } from "@/components/proposals/forms/UpdateProposalConfigForm";
import { CharterUpdateForm } from "@/components/proposals/forms/CharterUpdateForm";
import { CreateSubDAOWizard } from "@/components/proposals/CreateSubDAOWizard";
function handleSubmit(typeKey: string, data: unknown) {
  console.log("Proposal payload:", { typeKey, data });
  alert(`Proposal "${typeKey}" ready. Transaction submission coming soon.`);
}

export function NewProposalPage() {
  const { daoId } = useParams({ strict: false });
  const search = useSearch({ strict: false }) as Record<string, string>;
  const navigate = useNavigate();
  const typeKey = search.type ?? "";
  const [selectorOpen, setSelectorOpen] = useState(!typeKey);

  const { enabledTypes, frozenTypes } = useProposalFormOptions(daoId ?? "");

  const typeDef = typeKey ? PROPOSAL_TYPE_MAP[typeKey] : null;
  const tier = typeKey ? (PROPOSAL_TYPE_TIER[typeKey] ?? "tier1") : null;

  function selectType(key: string) {
    navigate({
      to: `/dao/$daoId/proposals/new`,
      params: { daoId: daoId ?? "" },
      search: { type: key },
    });
  }

  if (!typeKey || !typeDef) {
    return (
      <div className="space-y-4">
        <Card>
          <CardHeader>
            <CardTitle>New Proposal</CardTitle>
            <CardDescription>
              Select a proposal type to get started
            </CardDescription>
          </CardHeader>
          <CardContent>
            <Button onClick={() => setSelectorOpen(true)}>
              Choose Proposal Type
            </Button>
          </CardContent>
        </Card>
        <ProposalTypeSelector
          open={selectorOpen}
          onOpenChange={setSelectorOpen}
          enabledTypes={enabledTypes}
          frozenTypes={frozenTypes}
          onSelect={selectType}
        />
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader>
          <div className="flex items-center justify-between">
            <div>
              <CardTitle>{typeDef.label}</CardTitle>
              <CardDescription>{typeDef.description}</CardDescription>
            </div>
            <Button variant="outline" size="sm" onClick={() => selectType("")}>
              Change Type
            </Button>
          </div>
        </CardHeader>
        <CardContent>
          {tier === "tier1" && (
            <GenericProposalForm
              typeKey={typeKey}
              daoId={daoId ?? ""}
              onSubmit={(data) =>
                handleSubmit(typeKey, data)
              }
            />
          )}
          {tier === "tier2" && typeKey === "TreasuryWithdraw" && (
            <TreasuryWithdrawForm
              daoId={daoId ?? ""}
              onSubmit={(data) =>
                handleSubmit("TreasuryWithdraw", data)
              }
            />
          )}
          {tier === "tier2" && typeKey === "SetBoard" && (
            <SetBoardForm
              daoId={daoId ?? ""}
              onSubmit={(data) =>
                handleSubmit("SetBoard", data)
              }
            />
          )}
          {tier === "tier2" && typeKey === "EnableProposalType" && (
            <EnableProposalTypeForm
              daoId={daoId ?? ""}
              onSubmit={(data) =>
                handleSubmit("EnableProposalType", data)
              }
            />
          )}
          {tier === "tier2" && typeKey === "UpdateProposalConfig" && (
            <UpdateProposalConfigForm
              daoId={daoId ?? ""}
              onSubmit={(data) =>
                handleSubmit("UpdateProposalConfig", data)
              }
            />
          )}
          {tier === "tier2" && typeKey === "CharterUpdate" && (
            <CharterUpdateForm
              daoId={daoId ?? ""}
              onSubmit={(data) =>
                handleSubmit("CharterUpdate", data)
              }
            />
          )}
          {tier === "wizard" && (
            <CreateSubDAOWizard
              daoId={daoId ?? ""}
              onSubmit={(data) =>
                handleSubmit("CreateSubDAO", data)
              }
            />
          )}
        </CardContent>
      </Card>
    </div>
  );
}

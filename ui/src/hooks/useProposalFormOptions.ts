import { useMemo } from "react";
import { useGovernanceConfig, useDaoSummary } from "@/hooks/useDao";
import { ALL_PROPOSAL_TYPE_KEYS } from "@/config/proposal-types";

/** Resolve dynamic select options for proposal forms. */
export function useProposalFormOptions(daoId: string) {
  const { data: govConfig } = useGovernanceConfig(daoId);
  const { data: daoSummary } = useDaoSummary(daoId);

  return useMemo(() => {
    // While governance config is loading, show all types as enabled
    const enabledTypes = govConfig
      ? govConfig.filter((t) => t.enabled).map((t) => t.typeKey)
      : ALL_PROPOSAL_TYPE_KEYS;
    const frozenTypes =
      govConfig?.filter((t) => t.frozen).map((t) => t.typeKey) ?? [];
    const disabledTypes = ALL_PROPOSAL_TYPE_KEYS.filter(
      (k) => !enabledTypes.includes(k),
    );

    const treasuryCoinTypes =
      daoSummary?.enabledProposalTypes ?? [];

    return {
      enabledTypes,
      frozenTypes,
      disabledTypes,
      treasuryCoinTypes,
      govConfig: govConfig ?? [],
    };
  }, [govConfig, daoSummary]);
}

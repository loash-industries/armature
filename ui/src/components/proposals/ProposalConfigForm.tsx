import { useState } from "react";
import {
  FormField,
  FormItem,
  FormLabel,
  FormControl,
  FormDescription,
  FormMessage,
} from "@/components/ui/form";
import { Input } from "@/components/ui/input";
import {
  Collapsible,
  CollapsibleTrigger,
  CollapsibleContent,
} from "@/components/ui/collapsible";
import { ChevronRight } from "lucide-react";
import type { Control, FieldValues, FieldPath } from "react-hook-form";

interface ProposalConfigFormProps<T extends FieldValues = FieldValues> {
  control: Control<T>;
  prefix?: string;
  /** When true, nest Propose Threshold / Voting Period / Execution Delay / Cooldown in a collapsed "Advanced" section. */
  collapseAdvanced?: boolean;
}

const ADVANCED_FIELD_NAMES = new Set(["proposeThreshold", "expiryMs", "executionDelayMs", "cooldownMs"]);

/** Reusable 6-field sub-form for proposal config (quorum, threshold, etc.). */
export function ProposalConfigForm<T extends FieldValues = FieldValues>({
  control,
  prefix = "config",
  collapseAdvanced = false,
}: ProposalConfigFormProps<T>) {
  const [advancedOpen, setAdvancedOpen] = useState(false);

  const fields = [
    {
      name: `${prefix}.quorum`,
      key: "quorum",
      label: "Quorum",
      description: "Percentage of total votes required for quorum",
      placeholder: "50",
      unit: "%",
      step: "0.01",
    },
    {
      name: `${prefix}.approvalThreshold`,
      key: "approvalThreshold",
      label: "Approval Threshold",
      description: "Percentage of votes cast that must be 'Yes'",
      placeholder: "50",
      unit: "%",
      step: "0.01",
    },
    {
      name: `${prefix}.proposeThreshold`,
      key: "proposeThreshold",
      label: "Propose Threshold",
      description: "Minimum weight to create a proposal (0 = anyone)",
      placeholder: "0",
    },
    {
      name: `${prefix}.expiryMs`,
      key: "expiryMs",
      label: "Voting Period (hours)",
      description: "e.g. 168 = 7 days",
      placeholder: "168",
    },
    {
      name: `${prefix}.executionDelayMs`,
      key: "executionDelayMs",
      label: "Execution Delay (hours)",
      description: "Timelock after passing before execution",
      placeholder: "0",
    },
    {
      name: `${prefix}.cooldownMs`,
      key: "cooldownMs",
      label: "Cooldown (hours)",
      description: "Minimum time between executions of this type",
      placeholder: "0",
    },
  ];

  const basicFields = collapseAdvanced ? fields.filter((f) => !ADVANCED_FIELD_NAMES.has(f.key)) : fields;
  const advancedFields = collapseAdvanced ? fields.filter((f) => ADVANCED_FIELD_NAMES.has(f.key)) : [];

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        {basicFields.map((f) => (
          <ConfigField key={f.name} control={control} field={f} />
        ))}
      </div>

      {collapseAdvanced && advancedFields.length > 0 && (
        <Collapsible open={advancedOpen} onOpenChange={setAdvancedOpen}>
          <CollapsibleTrigger className="text-muted-foreground hover:text-foreground flex items-center gap-1 text-sm font-medium transition-colors">
            <ChevronRight
              className={`h-4 w-4 transition-transform ${advancedOpen ? "rotate-90" : ""}`}
            />
            Advanced
          </CollapsibleTrigger>
          <CollapsibleContent>
            <div className="mt-3 grid grid-cols-1 gap-4 sm:grid-cols-2">
              {advancedFields.map((f) => (
                <ConfigField key={f.name} control={control} field={f} />
              ))}
            </div>
          </CollapsibleContent>
        </Collapsible>
      )}
    </div>
  );
}

interface ConfigFieldDef {
  name: string;
  label: string;
  description: string;
  placeholder: string;
  unit?: string;
  step?: string;
}

function ConfigField<T extends FieldValues = FieldValues>({
  control,
  field: f,
}: {
  control: Control<T>;
  field: ConfigFieldDef;
}) {
  return (
    <FormField
      control={control}
      name={f.name as FieldPath<T>}
      render={({ field }) => (
        <FormItem>
          <FormLabel>{f.label}</FormLabel>
          <FormControl>
            {f.unit ? (
              <div className="relative flex items-center">
                <Input
                  type="number"
                  placeholder={f.placeholder}
                  step={f.step}
                  value={String(field.value ?? "")}
                  name={field.name}
                  ref={field.ref}
                  onBlur={field.onBlur}
                  onChange={(e) =>
                    field.onChange(
                      e.target.value ? Number(e.target.value) : "",
                    )
                  }
                  className="pr-8"
                />
                <span className="text-muted-foreground pointer-events-none absolute right-3 text-sm">
                  {f.unit}
                </span>
              </div>
            ) : (
              <Input
                type="number"
                placeholder={f.placeholder}
                value={String(field.value ?? "")}
                name={field.name}
                ref={field.ref}
                onBlur={field.onBlur}
                onChange={(e) =>
                  field.onChange(
                    e.target.value ? Number(e.target.value) : "",
                  )
                }
              />
            )}
          </FormControl>
          <FormDescription className="text-xs">
            {f.description}
          </FormDescription>
          <FormMessage />
        </FormItem>
      )}
    />
  );
}

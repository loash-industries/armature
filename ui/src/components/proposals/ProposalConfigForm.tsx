import {
  FormField,
  FormItem,
  FormLabel,
  FormControl,
  FormDescription,
  FormMessage,
} from "@/components/ui/form";
import { Input } from "@/components/ui/input";
import type { Control } from "react-hook-form";

interface ProposalConfigFormProps {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  control: Control<any>;
  prefix?: string;
}

/** Reusable 6-field sub-form for proposal config (quorum, threshold, etc.). */
export function ProposalConfigForm({
  control,
  prefix = "config",
}: ProposalConfigFormProps) {
  const fields = [
    {
      name: `${prefix}.quorum`,
      label: "Quorum (basis points)",
      description: "e.g. 5000 = 50%",
      placeholder: "5000",
    },
    {
      name: `${prefix}.approvalThreshold`,
      label: "Approval Threshold (basis points)",
      description: "e.g. 5000 = 50%",
      placeholder: "5000",
    },
    {
      name: `${prefix}.proposeThreshold`,
      label: "Propose Threshold",
      description: "Minimum weight to create a proposal (0 = anyone)",
      placeholder: "0",
    },
    {
      name: `${prefix}.expiryMs`,
      label: "Voting Period (hours)",
      description: "e.g. 168 = 7 days",
      placeholder: "168",
    },
    {
      name: `${prefix}.executionDelayMs`,
      label: "Execution Delay (hours)",
      description: "Timelock after passing before execution",
      placeholder: "0",
    },
    {
      name: `${prefix}.cooldownMs`,
      label: "Cooldown (hours)",
      description: "Minimum time between executions of this type",
      placeholder: "0",
    },
  ];

  return (
    <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
      {fields.map((f) => (
        <FormField
          key={f.name}
          control={control}
          name={f.name}
          render={({ field }) => (
            <FormItem>
              <FormLabel>{f.label}</FormLabel>
              <FormControl>
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
              </FormControl>
              <FormDescription className="text-xs">
                {f.description}
              </FormDescription>
              <FormMessage />
            </FormItem>
          )}
        />
      ))}
    </div>
  );
}

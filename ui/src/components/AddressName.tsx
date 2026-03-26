import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip";
import { resolveDisplayName } from "@/lib/address-namer";

interface AddressNameProps {
  address: string;
  charName?: string | null;
}

/**
 * Displays an address as a colored `@Name` label with a tooltip showing the
 * full raw address on hover.
 */
export function AddressName({ address, charName }: AddressNameProps) {
  return (
    <Tooltip>
      <TooltipTrigger asChild>
        <span className="text-sky-500 dark:text-sky-400 font-medium cursor-default">
          {resolveDisplayName(address, charName)}
        </span>
      </TooltipTrigger>
      <TooltipContent>
        <p className="font-mono text-xs break-all">{address}</p>
      </TooltipContent>
    </Tooltip>
  );
}

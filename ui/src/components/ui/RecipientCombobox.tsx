import { forwardRef, useCallback, useEffect, useRef, useState } from "react";
import { cn } from "@/lib/utils";
import { Input } from "@/components/ui/input";
import { useCharacterNameCache } from "@/hooks/useCharacterNameCache";

interface Suggestion {
  address: string;
  name: string;
}

interface RecipientComboboxProps {
  value: string;
  onChange: (address: string) => void;
  onBlur?: () => void;
  disabled?: boolean;
  placeholder?: string;
  /** Forwarded from FormControl / Slot for accessibility */
  id?: string;
  "aria-describedby"?: string;
  "aria-invalid"?: boolean | "true" | "false";
}

const MAX_SUGGESTIONS = 8;
const MIN_QUERY_LENGTH = 2;

/**
 * Address input with character-name autocomplete.
 *
 * As the user types a character name or hex address, suggestions sourced from
 * the React Query `characterNames` cache populate a dropdown.  Selecting a
 * suggestion fills the field with the resolved address.
 *
 * Falls back gracefully when the cache is empty (fresh page load / no prior
 * lookups): the dropdown simply doesn't appear and the user can paste an
 * address directly.
 */
export const RecipientCombobox = forwardRef<
  HTMLInputElement,
  RecipientComboboxProps
>(function RecipientCombobox(
  {
    value,
    onChange,
    onBlur,
    disabled,
    placeholder = "0x... or character name",
    id,
    "aria-describedby": ariaDescribedBy,
    "aria-invalid": ariaInvalid,
  },
  ref,
) {
  const nameCache = useCharacterNameCache();

  const [inputText, setInputText] = useState(value);
  const [open, setOpen] = useState(false);
  const containerRef = useRef<HTMLDivElement>(null);

  // Sync display text when value changes externally (e.g. form reset).
  useEffect(() => {
    setInputText(value);
  }, [value]);

  // Close the dropdown on outside click.
  useEffect(() => {
    function handleMouseDown(e: MouseEvent) {
      if (
        containerRef.current &&
        !containerRef.current.contains(e.target as Node)
      ) {
        setOpen(false);
      }
    }
    document.addEventListener("mousedown", handleMouseDown);
    return () => document.removeEventListener("mousedown", handleMouseDown);
  }, []);

  const query = inputText.trim().toLowerCase();
  const suggestions: Suggestion[] = [];
  if (query.length >= MIN_QUERY_LENGTH) {
    for (const [addr, name] of nameCache) {
      if (
        name.toLowerCase().includes(query) ||
        addr.toLowerCase().includes(query)
      ) {
        suggestions.push({ address: addr, name });
        if (suggestions.length >= MAX_SUGGESTIONS) break;
      }
    }
  }

  const handleInputChange = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      const text = e.target.value;
      setInputText(text);
      setOpen(true);
      onChange(text);
    },
    [onChange],
  );

  const handleSelect = useCallback(
    (suggestion: Suggestion) => {
      setInputText(suggestion.address);
      onChange(suggestion.address);
      setOpen(false);
    },
    [onChange],
  );

  return (
    <div ref={containerRef} className="relative">
      <Input
        ref={ref}
        id={id}
        aria-describedby={ariaDescribedBy}
        aria-invalid={ariaInvalid}
        value={inputText}
        onChange={handleInputChange}
        onFocus={() => {
          if (suggestions.length > 0) setOpen(true);
        }}
        onBlur={onBlur}
        disabled={disabled}
        placeholder={placeholder}
      />
      {open && suggestions.length > 0 && (
        <div className="absolute z-50 mt-1 w-full overflow-hidden rounded-lg border border-border bg-popover shadow-md">
          {suggestions.map(({ address, name }) => (
            <button
              key={address}
              type="button"
              className={cn(
                "flex w-full flex-col gap-0.5 px-3 py-2 text-left text-sm",
                "hover:bg-muted focus:bg-muted focus:outline-none",
              )}
              // mousedown fires before blur so we prevent default to keep focus
              onMouseDown={(e) => {
                e.preventDefault();
                handleSelect({ address, name });
              }}
            >
              <span className="font-medium text-sky-500 dark:text-sky-400">
                @{name}
              </span>
              <span className="truncate font-mono text-xs text-muted-foreground">
                {address}
              </span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
});

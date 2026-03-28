import { clsx, type ClassValue } from "clsx"
import { twMerge } from "tailwind-merge"

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

/**
 * Decode a Move `std::ascii::String` / `std::string::String` that arrives
 * from the relay as `{ bytes: number[] }` (BCS serialisation) into a plain
 * JS string.  If the value is already a string it is returned as-is.
 */
export function decodeMoveString(val: string | { bytes: number[] }): string {
  if (typeof val === 'string') return val
  return String.fromCharCode(...val.bytes)
}

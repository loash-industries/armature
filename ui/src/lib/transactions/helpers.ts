/**
 * Shared helpers for PTB transaction builders.
 */

import {
  PACKAGE_ID,
  PROPOSALS_PACKAGE_ID,
} from "@/config/constants";

export { Transaction } from "@mysten/sui/transactions";
export {
  PACKAGE_ID,
  PROPOSALS_PACKAGE_ID,
  MODULES,
  PROPOSAL_MODULES,
} from "@/config/constants";

export const SUI_CLOCK = "0x6";

export function target(pkg: string, module: string, fn: string): `${string}::${string}::${string}` {
  return `${pkg}::${module}::${fn}`;
}

export function fw(module: string, fn: string) {
  return target(PACKAGE_ID, module, fn);
}

export function prop(module: string, fn: string) {
  return target(PROPOSALS_PACKAGE_ID, module, fn);
}

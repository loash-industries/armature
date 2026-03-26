/**
 * Session-scoped fake name cache.
 *
 * Assigns a human-readable display name to every address the first time it is
 * encountered.  The mapping is kept only in memory — it resets on each page
 * load, which is intentional.  No address ever falls back to a truncated hex.
 */

const DISPLAY_NAMES: readonly string[] = [
  "Amber Fox",      "Azure Wolf",     "Brave Hawk",     "Bright Lynx",
  "Bronze Eagle",   "Calm Raven",     "Coral Bear",     "Crisp Falcon",
  "Dark Otter",     "Dawn Crane",     "Deep Stag",      "Deft Heron",
  "Dusk Badger",    "Ember Drake",    "Fair Mink",      "Fierce Wren",
  "Firm Vixen",     "Fleet Finch",    "Frost Panda",    "Gold Kite",
  "Grand Ibis",     "Grey Stoat",     "Iron Merlin",    "Jade Egret",
  "Just Lark",      "Keen Marten",    "Lithe Puffin",   "Lone Shrike",
  "Misty Quail",    "Noble Swift",    "North Robin",    "Oak Thrush",
  "Pale Pigeon",    "Pine Dove",      "Quick Snipe",    "Quiet Grouse",
  "Red Plover",     "Rich Curlew",    "Rock Bunting",   "Rose Martin",
  "Royal Starling", "Ruby Swallow",   "Sage Harrier",   "Salt Kestrel",
  "Sand Hobby",     "Sharp Osprey",   "Silver Buzzard", "Slim Condor",
  "Smoke Petrel",   "Snow Albatross", "Soft Gannet",    "Solar Tern",
  "Stone Booby",    "Storm Avocet",   "Sunlit Stilt",   "Swift Godwit",
  "Tawny Dunlin",   "Tide Bittern",   "True Snipe",     "Warm Plover",
  "Wild Curlew",    "Wind Sanderling","Wise Redshank",  "Young Turnstone",
];

const cache = new Map<string, string>();
let counter = 0;

/**
 * Returns the `@Name` display string assigned to `address`.  If the address
 * has never been seen before, the next name in the list is assigned and cached.
 * Names cycle if more unique addresses are seen than names in the list.
 */
export function getAddressName(address: string): string {
  const cached = cache.get(address);
  if (cached !== undefined) return `@${cached}`;

  const name = DISPLAY_NAMES[counter % DISPLAY_NAMES.length]!;
  counter++;
  cache.set(address, name);
  return `@${name}`;
}

/**
 * Resolves a Sui address to a display name, always prefixed with `@`.
 * Prefers a resolved character name; falls back to the session-assigned fake name.
 */
export function resolveDisplayName(address: string, charName?: string | null): string {
  if (charName) return `@${charName}`;
  return getAddressName(address);
}

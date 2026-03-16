# 02 — Core Pages

10 pages. Each defines: description, layout (with ASCII wireframe and `@awar.dev/ui` component mapping), data reads, user actions, and role visibility. All proposal interactions reference `01_proposal_lifecycle.md`.

---

## 1. DAO Dashboard (`<DaoDashboard>`)

**Description:** Landing page after selecting a DAO. At-a-glance summary of DAO health and activity.

**Layout (ASCII):**

```
Alert (controller/pause banner — conditional)

Card ×4 (summary row)
┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│CardHeader    │ │CardHeader    │ │CardHeader    │ │CardHeader    │
│ "Treasury"   │ │ "Board"      │ │ "Charter"    │ │ "Active"     │
│CardContent   │ │CardContent   │ │CardContent   │ │CardContent   │
│ 12,450 SUI   │ │ 5 members    │ │ v3           │ │ 3  Badge     │
└──────────────┘ └──────────────┘ └──────────────┘ └──────────────┘

┌───────────────────────────────┐ ┌───────────────────────────────┐
│ Card "Active Proposals"       │ │ Card "SubDAOs"                │
│ CardHeader + CardAction       │ │ CardHeader + CardAction       │
│  Button ghost [View All →]    │ │  Button ghost [View All →]    │
│ CardContent                   │ │ CardContent                   │
│  Table                        │ │  Table                        │
│   ID │ Type │Badge│ Progress  │ │   Name │ Badge │ Balance      │
│   #1   SetBrd Active ████░ 3/5│ │   Mining  Active  500 SUI     │
│   #2   Send   Passed ████ 4/5│ │   Trade   Paused  120 SUI     │
└───────────────────────────────┘ └───────────────────────────────┘

Card "Recent Activity"
┌─────────────────────────────────────────────────────────────────┐
│ Badge "VoteCast"    Alice voted Yes on #1              2m ago   │
│ Badge "Proposal"    Bob created SendCoin #2           15m ago   │
│ Badge "Executed"    TransferCap #0 executed             1h ago  │
└─────────────────────────────────────────────────────────────────┘
```

**Component Mapping:**

| Section | awar.dev/ui Components |
|---------|----------------------|
| Summary Cards | `Card` (×4), `CardHeader`, `CardContent`, `Badge` |
| Controller Banner | `Alert`, `AlertTitle`, `AlertDescription` |
| Status Badge | `Badge` (`variant="default"` for Active, `variant="destructive"` for Migrating) |
| Active Proposals | `Card`, `CardHeader`, `CardAction` → `Button variant="ghost"`, `CardContent`, `Table`, `TableHeader`, `TableHead`, `TableBody`, `TableRow`, `TableCell`, `Badge`, `Progress` |
| SubDAO List | `Card`, `CardHeader`, `CardAction`, `Table`, `TableRow`, `Badge` |
| Recent Activity | `Card`, `CardContent`, `Badge` (event type indicator) |

**Data Reads:**

| Data | Source |
|------|--------|
| DAO object | `sui_getObject(dao_id)` — status, metadata, governance, controller_cap_id, controller_paused |
| Treasury balance | `treasury.coin_types` → `treasury::balance<T>` for each type |
| Active proposals | Query `ProposalCreated` events + filter by status via object reads |
| SubDAO list | Query `SubDAOCreated` events where `parent_id = dao_id`, then read each child DAO |
| Charter version | `charter.version` |
| Recent events | Subscribe/query events by `dao_id` |

**User Actions:**

| Action | Role | Interaction |
|--------|------|-------------|
| Navigate to any page | All | Click sidebar item |
| View proposal detail | All | Click proposal row |
| View SubDAO | All | Click SubDAO card |
| Create proposal | Board Member | "New Proposal" button |

---

## 2. Treasury (`<TreasuryPage>`)

**Description:** View and manage DAO treasury. Multi-coin balances, deposit, and transaction history.

**Layout (ASCII):**

```
Card "Balances"
┌─────────────────────────────────────────────────────────────────┐
│ Table                                                           │
│  TableSortHead      TableSortHead                               │
│  Coin Type ⇅        Balance ⇅                                   │
│  SUI                 12,450.00                                  │
│  USDC                3,200.00                                   │
└─────────────────────────────────────────────────────────────────┘

Collapsible "Deposit"
┌─────────────────────────────────────────────────────────────────┐
│ CollapsibleTrigger  "Deposit to Treasury ▸"                     │
│ CollapsibleContent                                              │
│  Form                                                           │
│   FormField → Select (coin type from wallet)                    │
│   FormField → NumberInput unit="SUI" (amount)                   │
│   Button "Deposit"                                              │
└─────────────────────────────────────────────────────────────────┘

Card "Transaction History"
┌─────────────────────────────────────────────────────────────────┐
│ Table                                                           │
│  Badge "Deposit"  SUI  100   0xA..  2h ago                      │
│  Badge "Send"     SUI   50   0xB..  1d ago                      │
└─────────────────────────────────────────────────────────────────┘
```

**Component Mapping:**

| Section | awar.dev/ui Components |
|---------|----------------------|
| Coin Balances Table | `Card`, `Table`, `TableHeader`, `TableSortHead` (sortable), `TableBody`, `TableRow`, `TableCell` |
| Unclaimed Coins | `Card`, `Table`, `Button variant="outline"` ("Claim" per row) |
| Deposit Form | `Collapsible`, `CollapsibleTrigger`, `CollapsibleContent`, `Form`, `FormField`, `FormItem`, `FormLabel`, `FormControl`, `FormMessage`, `Select` (`SelectTrigger`, `SelectContent`, `SelectItem`), `NumberInput`, `Button` |
| Transaction History | `Card`, `Table`, `TableRow`, `Badge` (type indicator) |

**Data Reads:**

| Data | Source |
|------|--------|
| Coin types | `treasury.coin_types` (VecSet\<TypeName\>) |
| Balance per type | `treasury::balance<T>(vault)` for each type |
| Unclaimed coins | Dynamic field queries on treasury |
| Wallet balances | `sui_getCoins` for connected wallet |
| Transaction history | Query `CoinClaimed`, `ProposalExecuted` events filtered by treasury-related types |

**User Actions:**

| Action | Role | Interaction |
|--------|------|-------------|
| Deposit | All | Fill deposit form → wallet tx |
| Claim unclaimed coin | Board Member | Click "Claim" on unclaimed coin row |
| Propose SendCoin | Board Member | "New Proposal" → SendCoin (redirects to form) |

---

## 3. Capability Vault (`<CapVaultPage>`)

**Description:** Browse capabilities stored in the DAO's vault. View loan status and SubDAO control objects.

**Layout (ASCII):**

```
Card "Capabilities"
┌─────────────────────────────────────────────────────────────────┐
│ Accordion                                                       │
│  AccordionItem "FreezeAdminCap (1)"                             │
│   AccordionContent                                              │
│    Table                                                        │
│     Object ID (Tooltip on hover)  │ Badge "Available"           │
│  AccordionItem "SubDAOControl (2)"                              │
│   AccordionContent                                              │
│    Table                                                        │
│     0x1a…  │ Mining DAO  │ Badge "Active"  │ DropdownMenu ⋮    │
│     0x2b…  │ Trade DAO   │ Badge "Paused"  │ DropdownMenu ⋮    │
└─────────────────────────────────────────────────────────────────┘
```

**Component Mapping:**

| Section | awar.dev/ui Components |
|---------|----------------------|
| Capabilities Table | `Card`, `Accordion`, `AccordionItem`, `AccordionContent`, `Table`, `TableRow`, `Badge` (loan status), `Tooltip` (full object ID on hover) |
| SubDAOControl Section | Same `Accordion` group, `Table`, `Badge` (pause status), `DropdownMenu` (`DropdownMenuTrigger`, `DropdownMenuContent`, `DropdownMenuItem`) for cap actions |
| Loan Status | `Badge variant="secondary"` ("On Loan"), `HoverCard` for borrower details |

**Data Reads:**

| Data | Source |
|------|--------|
| Stored cap types | `capability_vault.cap_types` (VecSet\<TypeName\>) |
| Cap IDs per type | `capability_vault::ids_for_type<T>(vault)` |
| Cap objects | `sui_getObject` for each cap ID |
| Loan status | Check if cap ID has active `CapLoan` |
| SubDAOControl details | Read each SubDAOControl object → `child_dao_id` |

**User Actions:**

| Action | Role | Interaction |
|--------|------|-------------|
| View cap details | All | Expand row |
| Navigate to controlled SubDAO | All | Click SubDAO link in SubDAOControl row |
| Propose TransferCapToSubDAO | Board Member | Action button on cap row → opens form |
| Propose ReclaimCapFromSubDAO | Board Member | Action button on SubDAOControl row → opens form |

---

## 4. Proposals List (`<ProposalsList>`)

**Description:** Filterable, sortable list of all proposals for this DAO.

**Layout (ASCII):**

```
h1 "Proposals"                              Button "+ New"

Tabs variant="underline"
┌─────────┬────────┬────────┬─────────┬──────────┐
│ All     │ Active │ Passed │ Executed│ Expired  │
└─────────┴────────┴────────┴─────────┴──────────┘

TabsContent
┌─────────────────────────────────────────────────────────────────┐
│ Table                                                           │
│  TableSortHead  TableSortHead  TableHead    TableSortHead       │
│  ID ⇅           Type ⇅         Status       Created ⇅          │
│  #3  SetBoard      Badge "Active"    Progress ███░ 3/5          │
│  #2  SendCoin      Badge "Passed"    Progress ████ 4/5          │
│  #1  UpdateMeta    Badge "Executed"  ✓ Complete                 │
└─────────────────────────────────────────────────────────────────┘
```

**Component Mapping:**

| Section | awar.dev/ui Components |
|---------|----------------------|
| Filters Bar | `Tabs`, `TabsList`, `TabsTrigger` (×5 status filters) |
| Sort Controls | `TableSortHead` with `toggleSort()` / `sortRows()` utilities |
| Proposal Rows | `TabsContent`, `Table`, `TableHeader`, `TableSortHead`, `TableHead`, `TableBody`, `TableRow` (clickable → `<ProposalDetail>`), `TableCell`, `Badge` (type + status), `Progress` (vote progress) |
| Empty State | `TabsContent` with centered text |

**Data Reads:**

| Data | Source |
|------|--------|
| Proposal list | Query `ProposalCreated` events for this DAO, then batch-read proposal objects |
| Proposal status | Each proposal object's `status` field |
| Vote tallies | Each proposal's `vote_snapshot` |

**User Actions:**

| Action | Role | Interaction |
|--------|------|-------------|
| Filter / sort | All | Interact with filter/sort controls |
| View proposal | All | Click card → `<ProposalDetail>` |
| Create proposal | Board Member | "New Proposal" button |

---

## 5. Proposal Detail (`<ProposalDetail>`)

**Description:** Full detail view for a single proposal. Specified completely in `01_proposal_lifecycle.md` — the Proposal Detail View section (includes ASCII wireframe). Type-specific payload rendering dispatched per `04_payload_summaries.md`.

**Composition:** `Card` (header with `Badge`), `Alert` (banners), `Card` (payload → `<PayloadSummary>`), `Card` (voting → `Progress` ×2, `Table`, `Badge`), `Card` (actions → `<CountdownTimer>`, `Button` variants).

**Role Visibility:** All can view. Vote/Execute/Expire `Button`s Board Member only. See `01_proposal_lifecycle.md` for complete action rules.

---

## 6. Board Members (`<BoardPage>`)

**Description:** View current board composition. Propose board changes.

**Layout (ASCII):**

```
Card "Board"
┌─────────────────────────────────────────────────────────────────┐
│ CardHeader                                        CardAction    │
│  Badge "Board Governance"   "5 / 7 seats"         Button        │
│                                                  "Propose Change"
│ CardContent                                                     │
│  Table                                                          │
│   TableSortHead    TableHead                                    │
│   Address ⇅        Role                                         │
│   0xA1b2… (Alice)  Badge "You"                                  │
│   0xB3c4… (Bob)                                                 │
│   0xC5d6… (Carol)                                               │
└─────────────────────────────────────────────────────────────────┘
```

**Component Mapping:**

| Section | awar.dev/ui Components |
|---------|----------------------|
| Board Info | `Card`, `CardHeader`, `Badge` ("Board"), text for seat count |
| Member List | `Table`, `TableHeader`, `TableSortHead`, `TableBody`, `TableRow`, `TableCell`, `Badge variant="outline"` ("You"), `Tooltip` (full address on hover) |
| Actions | `CardAction` → `Button` ("Propose Board Change", Member only) |

**Data Reads:**

| Data | Source |
|------|--------|
| Members | `dao.governance.members` (vector\<address\>) |
| Seat count | `dao.governance.seat_count` |
| Governance type | `dao.governance` type tag (always Board in hackathon) |

**User Actions:**

| Action | Role | Interaction |
|--------|------|-------------|
| View members | All | — |
| Propose SetBoard | Board Member | Click "Propose Board Change" → `SetBoard` form |

---

## 7. Charter (`<CharterPage>`)

**Description:** View the DAO's constitutional document. Verify integrity. Browse amendment history.

**Layout (ASCII):**

```
h1 "Charter"                      Badge "v3"   Badge "✓ Verified"

Card "Constitution"
┌─────────────────────────────────────────────────────────────────┐
│ Tabs variant="underline"                                        │
│  TabsTrigger "Document"    TabsTrigger "Integrity"              │
│                                                                 │
│ TabsContent "Document"                                          │
│  ScrollArea (rendered markdown from Walrus)                     │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  # DAO Charter                                            │  │
│  │  ## Article 1: Purpose …                                  │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
│ TabsContent "Integrity"                                         │
│  Table                                                          │
│   Blob ID       │ bafyabc…                                      │
│   On-chain SHA  │ 0x7f3a…                                       │
│   Computed SHA  │ 0x7f3a…   Badge "Match ✓"                     │
│   Storage Exp.  │ <CountdownTimer>                               │
└─────────────────────────────────────────────────────────────────┘

Card "Amendment History"
┌─────────────────────────────────────────────────────────────────┐
│ Accordion                                                       │
│  AccordionItem "v3 — Amended 2h ago by proposal #5"            │
│   AccordionContent (diff view)                                  │
│  AccordionItem "v2 — Amended 3d ago by proposal #2"            │
│  AccordionItem "v1 — Genesis charter"                          │
└─────────────────────────────────────────────────────────────────┘
```

**Component Mapping:**

| Section | awar.dev/ui Components |
|---------|----------------------|
| Current Charter | `Card`, `Tabs`, `TabsList`, `TabsTrigger`, `TabsContent`, `ScrollArea` |
| Integrity Check | `Badge` ("Verified ✓" default / "Mismatch ✗" destructive), `Table` (hash details) |
| Charter Metadata | `Badge` (version), `Tooltip` (blob ID copy) |
| Amendment History | `Card`, `Accordion`, `AccordionItem`, `AccordionContent` (diff view) |
| Actions | `Button` ("Propose Amendment"), `Button variant="outline"` ("Propose Storage Renewal") — Member only |

**Data Reads:**

| Data | Source |
|------|--------|
| Charter object | `sui_getObject(charter_id)` — blob_id, content_hash, version, amendment_history |
| Charter content | Walrus fetch by `current_blob_id` |
| Amendment records | `charter.amendment_history` vector |
| Historical content | Walrus fetch by `previous_blob_id` / `new_blob_id` from amendment records |

**User Actions:**

| Action | Role | Interaction |
|--------|------|-------------|
| Read charter | All | — |
| Verify integrity | All | Automatic on load; manual re-check button |
| View amendment diff | All | Expand amendment history entry |
| Propose amendment | Board Member | "Propose Amendment" button |
| Propose storage renewal | Board Member | "Propose Storage Renewal" button |

---

## 8. Governance Config (`<GovConfigPage>`)

**Description:** View and manage per-type proposal configurations.

**Layout (ASCII):**

```
Card "Enabled Proposal Types"
┌─────────────────────────────────────────────────────────────────┐
│ Table                                                           │
│  TableSortHead  TableHead  TableHead  TableHead  TableHead      │
│  Type ⇅         Quorum     Threshold  Delay      Actions       │
│  UpdateMeta     51%        66%        24h        DropdownMenu ⋮│
│  SetBoard       51%        66%        48h        DropdownMenu ⋮│
│  SendCoin       51%        51% Badge "Protected" DropdownMenu ⋮│
└─────────────────────────────────────────────────────────────────┘

Collapsible "Disabled Types"
┌─────────────────────────────────────────────────────────────────┐
│ CollapsibleTrigger  "Show disabled types (3) ▸"                 │
│ CollapsibleContent                                              │
│  Table                                                          │
│   SpawnDAO          Button "Enable"                             │
│   TransferAssets    Button "Enable"                             │
└─────────────────────────────────────────────────────────────────┘

Alert (info)  "Quorum: 1–10000 bps · Threshold: 5000–10000 bps …"
```

**Component Mapping:**

| Section | awar.dev/ui Components |
|---------|----------------------|
| Enabled Types Table | `Card`, `Table`, `TableHeader`, `TableSortHead`, `TableHead`, `TableBody`, `TableRow`, `TableCell`, `Badge` ("Protected"), `DropdownMenu` (`DropdownMenuTrigger`, `DropdownMenuContent`, `DropdownMenuItem` — Edit / Disable actions) |
| Disabled Types | `Collapsible`, `CollapsibleTrigger`, `CollapsibleContent`, `Table`, `Button variant="outline"` ("Enable") |
| Config Validation Rules | `Alert` (info variant) |

**Data Reads:**

| Data | Source |
|------|--------|
| Enabled types | `dao.enabled_proposals` (VecSet\<TypeName\>) |
| Per-type config | `dao.proposal_configs[TypeName]` → quorum, threshold, execution_delay_ms, cooldown_ms, expiry_ms |
| Protected types | Hardcoded: EnableProposalType, DisableProposalType, TransferFreezeAdmin, UnfreezeProposalType |
| All known types | Hardcoded list of 18 proposal types |

**User Actions:**

| Action | Role | Interaction |
|--------|------|-------------|
| View configs | All | — |
| Propose UpdateProposalConfig | Board Member | "Edit" action on row → opens `UpdateProposalConfig` form |
| Propose EnableProposalType | Board Member | "Enable" action on disabled type → opens `EnableProposalType` form |
| Propose DisableProposalType | Board Member | "Disable" action on enabled (non-protected) type → opens `DisableProposalType` form |

---

## 9. Emergency Freeze (`<EmergencyPage>`)

**Description:** View and manage emergency freeze status for proposal types.

**Layout (ASCII):**

```
Alert variant="destructive" (if any types frozen)
 "⚠ Emergency freeze active on N proposal types"

Card "Freeze Status"
┌─────────────────────────────────────────────────────────────────┐
│ Table                                                           │
│  FreezeAdmin    │ Badge "0xA…"                                  │
│  Freeze Window  │ 72 hours                                      │
│  Frozen Types   │ 2 / 18                                        │
└─────────────────────────────────────────────────────────────────┘

Card "Frozen Types"
┌─────────────────────────────────────────────────────────────────┐
│ Table                                                           │
│  TableSortHead     TableHead          TableHead                 │
│  Type ⇅            Frozen At          Expires In                │
│  SendCoin          2h ago             <CountdownTimer>          │
│  TransferCap       1d ago             <CountdownTimer>          │
│  (loading)         Skeleton ×3                                  │
└─────────────────────────────────────────────────────────────────┘

Card "Freeze Controls" (FreezeAdmin only)
┌─────────────────────────────────────────────────────────────────┐
│ Form                                                            │
│  FormField → Select "Type to freeze"                            │
│  Button variant="destructive" "Freeze Type"                     │
└─────────────────────────────────────────────────────────────────┘
```

**Component Mapping:**

| Section | awar.dev/ui Components |
|---------|----------------------|
| Freeze Status Overview | `Alert variant="destructive"`, or `Badge` ("No active freezes") |
| Frozen Types Table | `Card`, `Table`, `TableSortHead`, `TableHead`, `TableRow`, `TableCell`, `<CountdownTimer>`, `Skeleton` (loading rows) |
| FreezeAdmin Info | `Card`, `Table`, `Badge`, `Button variant="outline"` ("Transfer") |
| Freeze Controls | `Card`, `Form`, `FormField`, `Select`, `Button variant="destructive"` |
| Governance Override | `Button` ("Propose Unfreeze" / "Propose Config Update") — Member only |

**Data Reads:**

| Data | Source |
|------|--------|
| Frozen types | `emergency_freeze.frozen_types` (map TypeName → expiry_ms) |
| FreezeAdminCap | Query objects of type `FreezeAdminCap` matching `dao_id` |
| Freeze config | `emergency_freeze` default duration settings |
| Current time | On-chain clock for expiry calculations |

**User Actions:**

| Action | Role | Interaction |
|--------|------|-------------|
| View freeze status | All | — |
| Freeze a type | FreezeAdmin | Select type + duration → direct tx (no proposal) |
| Unfreeze a type | FreezeAdmin | Click "Unfreeze" → direct tx (no proposal) |
| Propose unfreeze | Board Member | Click "Propose Unfreeze" → `UnfreezeProposalType` form |
| Propose config update | Board Member | Click "Propose Config Update" → `UpdateFreezeConfig` form |
| Propose transfer admin | Board Member | Click "Transfer" → `TransferFreezeAdmin` form |

---

## 10. SubDAO List (`<SubDAOListPage>`)

**Description:** View and manage child DAOs controlled by this DAO.

**Layout (ASCII):**

```
h1 "SubDAOs"                                Button "+ Create SubDAO"

Tabs variant="underline"
 TabsTrigger "List"    TabsTrigger "Graph"

TabsContent "List"
┌──────────────────────────┐  ┌──────────────────────────┐
│ Card                     │  │ Card                     │
│ CardHeader               │  │ CardHeader               │
│  "Mining DAO"  Badge ●   │  │  "Trade DAO"  Badge ⚠   │
│ CardContent              │  │ CardContent              │
│  Treasury: 500 SUI       │  │  Treasury: 120 SUI       │
│  Board: 3 members        │  │  Board: 4 members        │
│  Types: 12 enabled       │  │  Types: 10 enabled       │
│ CardFooter               │  │ CardFooter               │
│  DropdownMenu ⋮          │  │  Badge "Paused"          │
│   Replace Board          │  │  DropdownMenu ⋮          │
│   Pause Execution        │  │   Unpause                │
│   Reclaim Cap            │  │   Reclaim Cap            │
│   Spin Out               │  │   Spin Out               │
└──────────────────────────┘  └──────────────────────────┘

TabsContent "Graph"
┌─────────────────────────────────────────────────────────────────┐
│ GraphCanvas                                                     │
│                                                                 │
│   ┌──────────┐                                                  │
│   │ Root DAO │──GraphEdge──┐                                    │
│   └──────────┘             │                                    │
│        │              ┌────▼─────┐                              │
│   GraphEdge           │ Trade    │                              │
│        │              └──────────┘                              │
│   ┌────▼─────┐                                                  │
│   │ Mining   │──GraphEdge──┐                                    │
│   └──────────┘        ┌────▼─────┐                              │
│                       │ Ops Team │                              │
│                       └──────────┘                              │
│                                                                 │
│   GraphLegend position="bottom-right"                           │
│    ■ Active  ■ Paused  --- Control link                         │
└─────────────────────────────────────────────────────────────────┘
```

**Component Mapping:**

| Section | awar.dev/ui Components |
|---------|----------------------|
| SubDAO Cards | `Card`, `CardHeader`, `CardContent`, `CardFooter`, `Badge` (status), `DropdownMenu` (`DropdownMenuTrigger`, `DropdownMenuContent`, `DropdownMenuItem` — controller actions) |
| Paused Indicator | `Badge variant="destructive"` ("Paused") |
| Controller Actions | `DropdownMenuItem` per action, `AlertDialog` for SpinOut confirmation (`AlertDialogTrigger`, `AlertDialogContent`, `AlertDialogTitle`, `AlertDialogDescription`, `AlertDialogAction`, `AlertDialogCancel`) |
| Graph View | `Tabs`, `TabsTrigger`, `TabsContent`, `GraphCanvas`, `GraphEdge`, `GraphLegend` |
| Create SubDAO | `Button` ("Create SubDAO", Member only) |
| Empty State | Centered text + `Button` CTA |

**Data Reads:**

| Data | Source |
|------|--------|
| SubDAOControl objects | Query parent's `CapabilityVault` for type `SubDAOControl` |
| Child DAO objects | `sui_getObject` for each `SubDAOControl.child_dao_id` |
| Child treasury balances | Read each child's `TreasuryVault` |
| Child board | Read each child's `governance.members` |
| Pause status | Each child's `controller_paused` field |

**User Actions:**

| Action | Role | Interaction |
|--------|------|-------------|
| View SubDAO list | All | — |
| Navigate to SubDAO | All | Click card |
| Create SubDAO | Board Member | "Create SubDAO" button → wizard |
| Replace board | Board Member (parent) | Action menu → privileged_submit SetBoard form |
| Pause | Board Member (parent) | Action menu → PauseSubDAOExecution proposal |
| Unpause | Board Member (parent) | Action menu → UnpauseSubDAOExecution proposal |
| Reclaim cap | Board Member (parent) | Action menu → ReclaimCapFromSubDAO form |
| Spin out | Board Member (parent) | Action menu → SpinOutSubDAO proposal (confirmation dialog) |

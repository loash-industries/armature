# 00 — Overview, Roles & Navigation

## Scope

This document is a **functional specification** for the DAO-framework frontend. It defines every screen, form, data read, and user action needed to surface the on-chain protocol.

**Stack:** React 19 / Vite SPA, desktop-first, wallet connected via `@mysten/dapp-kit`. Routing via `@tanstack/react-router`, server state via `@tanstack/react-query`.

**Component library:** [`@awar.dev/ui`](https://github.com/Algorithmic-Warfare/awar.dev-ui) v2 — a terminal-inspired design system (zero border-radius, monospace-only, warm CRT palette: maroon `#773333` × amber `#FF9944`). Built on Radix primitives + Tailwind CSS v4. All component references in these docs use `@awar.dev/ui` exports unless otherwise noted.

---

## On-Chain Surface — Cheat Sheet

| Object | One-Liner |
|--------|-----------|
| **DAO** | Root shared object — governance config, enabled proposal types, status, metadata CID, links to companion objects. |
| **TreasuryVault** | Multi-coin store using dynamic fields keyed by `TypeName`. Permissionless deposit; governance-gated withdraw. |
| **CapabilityVault** | Typed capability store using dynamic object fields. Governance-gated extract/loan; privileged extract for controllers. |
| **Charter** | Constitutional document on Walrus — blob ID, SHA-256 content hash, version counter, amendment history. |
| **EmergencyFreeze** | Circuit breaker — maps proposal `TypeName` → expiry timestamp. `FreezeAdminCap` is vault-stored; freeze/unfreeze are governance-gated. |
| **SubDAOControl** | Capability stored in controller's `CapabilityVault` — grants board replacement, pause/unpause, cap reclaim, spinout over a child DAO. |
| **Proposal\<P\>** | Typed proposal object — payload, vote snapshot, status (`Active → Passed → Executed \| Expired`), timestamps. |

---

## Roles & Visibility Model

Defined once here; every subsequent document references these role names.

There are two **wallet-level roles** determined by the connected address, and one **contextual scope** determined by the DAO being viewed.

### Wallet Roles

| Role | Detection | Capabilities |
|------|-----------|--------------|
| **Visitor** | Connected wallet address **not** in `governance.members` of the viewed DAO | View all public state, deposit into treasury |
| **Member** | Connected wallet address **in** `governance.members` of the viewed DAO | Everything Visitor can do **+** create proposals, vote, execute passed proposals |

There is no separate "FreezeAdmin" role. `FreezeAdminCap` lives in the DAO's `CapabilityVault` and is exercised through governance proposals (freeze/unfreeze are proposal types, not direct wallet actions). Similarly, `SubDAOControl` is a vault-stored capability — controller operations go through the parent DAO's governance.

### Role Resolution

1. Read `governance.members` from the DAO object → **Visitor** vs **Member**.

That's it. One check.

### Context / Scope

Your role depends on **which DAO you are viewing**, not which DAOs you belong to globally:

| Context | What Happens |
|---------|-------------|
| Open a DAO you are a member of | **Member** view — proposals, voting, execution all available |
| Open a SubDAO you are **not** a member of | **Visitor** view — read-only, deposit only |
| Navigate from parent DAO to its SubDAO | You see the SubDAO in Visitor or Member view based on **that DAO's** membership. Controller actions (pause, reclaim, etc.) are proposals on the **parent** DAO, not buttons on the SubDAO. |

> **Note:** The UI should make it easy to navigate between DAOs the user is a member of (via the DAO Switcher), but the role is always resolved per-DAO.

---

## Navigation Shell

### Layout (ASCII)

```
AWARProvider
└─ SidebarProvider
   ├─ Sidebar                          ┐
   │  ├─ SidebarHeader                 │
   │  │  └─ LogoLockup layout="stacked"│
   │  ├─ SidebarContent                │
   │  │  ├─ SidebarGroup "DAO"         │  fixed
   │  │  │  └─ Select (DAO Switcher)   │  width
   │  │  └─ SidebarGroup "Navigation"  │
   │  │     └─ SidebarMenu             │
   │  │        ├─ SidebarMenuItem …×9   │
   │  │        │  └─ SidebarMenuButton  │
   │  │        │     └─ SidebarMenuBadge│  (active proposal count)
   │  │        └─ …                    │
   │  └─ SidebarFooter                 │
   │     └─ Button "+ New Proposal"    ┘  (Member only)
   │
   └─ SidebarInset (main area)
      ├─ header
      │  ├─ SidebarTrigger (☰ hamburger)
      │  ├─ Breadcrumb → BreadcrumbList → BreadcrumbItem / BreadcrumbLink / BreadcrumbPage
      │  └─ Badge (wallet address + network)
      ├─ Alert (controller / freeze / pause banners — contextual)
      └─ ScrollArea (page content)
```

On mobile (`< 768px`) the `Sidebar` becomes a `Sheet` (slide-in drawer) via `useSidebar().isMobile`.

### Sidebar Items (per-DAO context)

| Nav Item | Target Page | Visible To |
|----------|-------------|------------|
| Dashboard | `<DaoDashboard>` | All |
| Treasury | `<TreasuryPage>` | All |
| Capability Vault | `<CapVaultPage>` | All |
| Proposals | `<ProposalsList>` | All |
| Board | `<BoardPage>` | All |
| Charter | `<CharterPage>` | All |
| Governance Config | `<GovConfigPage>` | All (edit actions Member-only) |
| Emergency | `<EmergencyPage>` | All (freeze/unfreeze via proposals, Member-only) |
| SubDAOs | `<SubDAOListPage>` | All |

### Global Elements

| Element | awar.dev/ui Component(s) | Behaviour |
|---------|------------------------|-----------|
| **SubDAO Breadcrumb** | `Breadcrumb`, `BreadcrumbList`, `BreadcrumbItem`, `BreadcrumbLink`, `BreadcrumbPage`, `BreadcrumbSeparator` | Hierarchy path `Root DAO / Parent / Current`. Each segment is a link. Displayed in the `SidebarInset` header. |
| **"New Proposal" Button** | `Button` in `SidebarFooter` | **Member only** — hidden for Visitors. Opens proposal type selector (see `01_proposal_lifecycle.md` §Type Selection). |
| **DAO Switcher** | `Select` (`SelectTrigger`, `SelectContent`, `SelectItem`) in `SidebarGroup` | Switch between DAOs the user is a member of (query owned objects + known DAO IDs). |
| **Wallet Badge** | `Badge` | Connected address (truncated), network indicator (localnet/devnet/testnet/mainnet). Positioned in `SidebarInset` header. |
| **Controller Banner** | `Alert` (`AlertTitle`, `AlertDescription`) | If `controller_cap_id = Some(...)`: info variant "Controlled by [Parent DAO]". If `controller_paused`: destructive variant "Execution paused by controller". |

### Component Mapping

| App Component | awar.dev/ui Primitives | Responsibility |
|---------------|----------------------|---------------|
| `<AppShell>` | `AWARProvider`, `SidebarProvider`, `Sidebar`, `SidebarInset` | Layout wrapper — sidebar, header, breadcrumb, scrollable content area |
| `<DaoSidebar>` | `Sidebar`, `SidebarHeader`, `SidebarContent`, `SidebarFooter`, `SidebarMenu`, `SidebarMenuItem`, `SidebarMenuButton`, `SidebarMenuBadge`, `LogoLockup` | Navigation items, "New Proposal" button, DAO switcher |
| `<SubDAOBreadcrumb>` | `Breadcrumb`, `BreadcrumbItem`, `BreadcrumbLink`, `BreadcrumbPage` | Hierarchy path rendering from `controller_cap_id` chain |
| `<CountdownTimer>` | `Badge` (custom, app-level) | Reusable countdown — not in awar.dev/ui, built on top |
| `<PayloadSummary>` | `Card`, `Table`, `Badge` (custom, app-level) | Type-dispatched proposal renderers — not in awar.dev/ui, built on top |

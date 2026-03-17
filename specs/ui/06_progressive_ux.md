# 06 — Progressive UX: Wallet Connect → Governance Mastery

> Research-informed breakdown of user flows, progressive disclosure layers,
> and navigation feel.  ASCII layouts show **what the user sees** at each
> stage; prose explains **why**.

---

## Design Principles (drawn from protocol-UI research)

| Principle | Source | Application |
|-----------|--------|-------------|
| **Progressive disclosure** | Nielsen Norman Group | Reveal complexity only when the user reaches for it |
| **Recognition over recall** | Hick's Law | Show actionable options in-context, never force memorization |
| **Information scent** | Pirolli & Card (2005) | Every element must signal what clicking it will reveal |
| **Contextual actions** | Compound v3, Uniswap v4 | Actions appear where data lives, not in global menus |
| **Status visibility** | Nielsen Heuristic #1 | Always show: Where am I? What can I do? What just happened? |
| **Safe exploration** | Krug "Don't Make Me Think" | Read-only by default; mutations require explicit opt-in |
| **Empty states as onboarding** | Material Design | Every zero-state teaches the next step |

---

## Layer Model

The UI has four disclosure layers.  A user who only ever reaches Layer 1
can still understand their DAO.  Power users naturally reach Layer 3–4
through contextual links, never through a buried settings panel.

```
Layer 0  │ Connect ─── "Who are you?"
Layer 1  │ Orient  ─── "What is this DAO?"        (read-only dashboard)
Layer 2  │ Act     ─── "What can I do?"            (vote, propose)
Layer 3  │ Govern  ─── "How do I change the rules?" (config, freeze, subdao)
Layer 4  │ Migrate ─── "How do I evolve the org?"  (spawn, transfer, upgrade)
```

Each layer is **reachable from the previous** via a single click or
contextual prompt — never hidden behind a hamburger menu or docs link.

---

## Flow 0 — Connect & Resolve

**Goal:** Get a wallet connected and land on a DAO with zero protocol jargon.

```
┌─────────────────────────────────────────────────────┐
│                                                     │
│              ╔═══════════════════════╗               │
│              ║   A R M A T U R E    ║               │
│              ║   governance shell    ║               │
│              ╚═══════════════════════╝               │
│                                                     │
│         ┌───────────────────────────┐               │
│         │   Connect Wallet          │               │
│         │   [ Sui Wallet ▾ ]        │               │
│         └───────────────────────────┘               │
│                                                     │
│    "Connect your wallet to view or participate      │
│     in on-chain governance."                        │
│                                                     │
│    ─── or enter a DAO address to browse ───         │
│    ┌──────────────────────────────┐  [Go]           │
│    │ 0x...                        │                 │
│    └──────────────────────────────┘                 │
│                                                     │
└─────────────────────────────────────────────────────┘
```

**Key decisions:**

- **No sign-up, no account creation.** Wallet *is* identity.
- **Browse without connecting.** Visitors can paste a DAO address and
  see everything read-only.  This follows the "safe exploration" principle —
  the protocol is public state; hiding it behind a connect wall is
  anti-pattern.
- **Post-connect routing:** If wallet is a member of exactly one DAO →
  go straight to that dashboard.  If multiple → show DAO picker.
  If none → show "Join or create" empty state.

**After connect, the routing logic:**

```
wallet connected
  ├─ member of 1 DAO ──────→ /dao/:id  (dashboard)
  ├─ member of N DAOs ─────→ /dao-picker
  ├─ member of 0 DAOs ─────→ /dao-picker (empty state + paste address)
  └─ not connected (browse)─→ /dao/:id  (read-only, from pasted address)
```

---

## Flow 0.5 — DAO Picker (multi-DAO users)

```
┌─────────────────────────────────────────────────────┐
│  ┌─ wallet: 0xAb..9f ─────────────────── [switch] ─┤
│  │                                                  │
│  │  Your DAOs                                       │
│  │  ┌───────────────────────────────────────────┐   │
│  │  │ ◆ Protocol Foundation    12 members       │   │
│  │  │   3 active proposals · $482k treasury     │   │
│  │  ├───────────────────────────────────────────┤   │
│  │  │ ◇ Engineering Guild      5 members        │   │
│  │  │   1 active proposal  · $12k treasury      │   │
│  │  │   └─ SubDAO of: Protocol Foundation       │   │
│  │  ├───────────────────────────────────────────┤   │
│  │  │ ◇ Grants Committee       7 members        │   │
│  │  │   0 active proposals · $95k treasury      │   │
│  │  └───────────────────────────────────────────┘   │
│  │                                                  │
│  │  ── or browse another DAO ──                     │
│  │  ┌──────────────────────────┐  [Go]              │
│  │  │ 0x...                    │                    │
│  │  └──────────────────────────┘                    │
│  │                                                  │
│  └──────────────────────────────────────────────────┘
└─────────────────────────────────────────────────────┘
```

**Why this matters:** Protocol power users are often members of parent +
child DAOs.  Showing the hierarchy (SubDAO-of relationship) gives
immediate orientation.  The ◆/◇ glyphs distinguish root vs child DAOs
in the terminal aesthetic.

---

## Flow 1 — Dashboard (Layer 1: Orient)

**Goal:** In 5 seconds, answer: What is this DAO? Is anything happening?
Do I need to act?

```
┌── SIDEBAR ──┬── MAIN ──────────────────────────────────────┐
│             │                                               │
│ ◆ Proto    │  Protocol Foundation                          │
│ Foundation │  ──────────────────────────────────────────── │
│             │                                               │
│ Dashboard ● │  ┌─────────┐ ┌─────────┐ ┌─────────┐       │
│ Treasury    │  │ Treasury │ │  Board  │ │ Active  │       │
│ Proposals   │  │ $482.1k │ │ 12 mbrs │ │ 3 props │       │
│ Board       │  └────┬────┘ └────┬────┘ └────┬────┘       │
│ Charter     │       │           │            │             │
│             │       ▼           ▼            ▼             │
│ ── more ──  │  (click any card to jump to its page)        │
│ Gov Config  │                                               │
│ Emergency   │  Needs Your Vote                    [See All] │
│ SubDAOs     │  ┌────┬──────────────┬────────┬────────────┐ │
│             │  │ #  │ Title        │ Type   │ Deadline   │ │
│             │  ├────┼──────────────┼────────┼────────────┤ │
│             │  │ 14 │ Fund audit   │SendCoin│ 2d 4h left │ │
│             │  │ 15 │ Add member X │SetBoard│ 5d 1h left │ │
│             │  │ 16 │ Freeze swaps │Freeze  │ 12h left   │ │
│             │  └────┴──────────────┴────────┴────────────┘ │
│             │                                               │
│             │  Recent Activity                              │
│             │  · Proposal #13 executed (SendCoin) — 2h ago  │
│             │  · 0xBe..3f voted Yes on #14 — 4h ago         │
│             │  · $5,000 SUI deposited — 1d ago              │
│             │                                               │
└─────────────┴───────────────────────────────────────────────┘
```

**Progressive disclosure on this page:**

| Element | What it shows | What it hides (until clicked) |
|---------|---------------|-------------------------------|
| Treasury card | Total value | Per-coin breakdown, tx history |
| Board card | Member count | Member list, roles |
| Active proposals card | Count | Full proposal list with filters |
| "Needs Your Vote" table | Unvoted active proposals | Full proposal detail, payload, vote breakdown |
| Sidebar "more" divider | Config/Emergency/SubDAOs | Collapsed by default for non-power-users |

**Sidebar design rationale:**

The sidebar is split into two groups with a subtle `── more ──` divider:

- **Top group (Layer 1–2):** Dashboard, Treasury, Proposals, Board, Charter —
  these are the five things 90% of users need 90% of the time.
- **Bottom group (Layer 3–4):** Gov Config, Emergency, SubDAOs —
  governance plumbing.  Visible but de-emphasized.  Power users know
  where to find them; new users aren't overwhelmed.

---

## Flow 2 — Proposal List & Voting (Layer 2: Act)

**Goal:** Find proposals relevant to me.  Vote in one click.  Understand
what a proposal *does* without reading code.

### 2a. Proposal List

```
┌── SIDEBAR ──┬── MAIN ──────────────────────────────────────┐
│             │                                               │
│ Dashboard   │  Proposals                  [+ New Proposal]  │
│ Treasury    │  ──────────────────────────────────────────── │
│ Proposals ● │                                               │
│ Board       │  [All] [Active·3] [Passed·1] [Executed] [Exp] │
│ Charter     │                                               │
│             │  ┌────┬──────────────────┬──────────┬───────┐ │
│             │  │ #  │ Title            │ Status   │ Votes │ │
│             │  ├────┼──────────────────┼──────────┼───────┤ │
│             │  │ 16 │ Freeze swaps     │ ● Active │  8/12 │ │
│             │  │ 15 │ Add member X     │ ● Active │  5/12 │ │
│             │  │ 14 │ Fund audit       │ ● Active │ 10/12 │ │
│             │  │ 13 │ Pay contributor  │ ✓ Exec'd │ 11/12 │ │
│             │  │ 12 │ Update charter   │ ✓ Exec'd │ 12/12 │ │
│             │  └────┴──────────────────┴──────────┴───────┘ │
│             │                                               │
│             │  Showing 5 of 16 proposals          [Load ▾]  │
│             │                                               │
└─────────────┴───────────────────────────────────────────────┘
```

**Design notes:**

- **Tab badges** show counts so the user can scan without clicking.
- **Votes column** shows `cast/total` — instant read on how close to quorum.
- **Status dots** use color coding: amber=active, green=passed/exec, dim=expired.
- **"+ New Proposal" button** only renders for board members (role gating
  happens silently — visitors never see a disabled button, they simply
  don't see the button.  This avoids the "why can't I click this"
  frustration pattern).

### 2b. Proposal Detail — the core interaction surface

This is the **most important screen** in the app.  Every governance action
flows through it.  The layout must answer five questions in visual
scan order:

1. What is this? (header + type badge)
2. What will it *do*? (payload summary)
3. Who supports it? (vote tally)
4. When does it expire/execute? (timers)
5. What can *I* do right now? (action button)

```
┌── SIDEBAR ──┬── MAIN ──────────────────────────────────────┐
│             │                                               │
│             │  ← Back to Proposals                          │
│             │                                               │
│             │  #14 · Fund Security Audit                    │
│             │  Type: SendCoin<SUI>    Status: ● Active      │
│             │  Proposed by 0xAb..9f · 2 days ago            │
│             │                                               │
│             │  ┌─ What This Does ──────────────────────────┐│
│             │  │ Send 15,000 SUI to 0xCd..12              ││
│             │  │                                           ││
│             │  │ Amount:    15,000 SUI ($45,000)           ││
│             │  │ Recipient: 0xCd..12 (hover for full)      ││
│             │  │ From:      Treasury (balance: 160,000 SUI) ││
│             │  └───────────────────────────────────────────┘│
│             │                                               │
│             │  ┌─ Votes ─────────────────── 10/12 voted ──┐│
│             │  │                                           ││
│             │  │ Yes ████████████████░░░░  9  (90%)        ││
│             │  │ No  ██░░░░░░░░░░░░░░░░░░  1  (10%)       ││
│             │  │                                           ││
│             │  │ Quorum:    ████████████████████ 83% ✓     ││
│             │  │ Threshold: ████████████████░░░░ 90%  (need 66%)  ✓ ││
│             │  │                                           ││
│             │  │ ▸ Show voter breakdown                    ││
│             │  └───────────────────────────────────────────┘│
│             │                                               │
│             │  ⏱ Voting closes in 5d 1h 23m                │
│             │                                               │
│             │  ┌──────────────────────────────────────┐     │
│             │  │  [ Vote Yes ]    [ Vote No ]         │     │
│             │  └──────────────────────────────────────┘     │
│             │                                               │
└─────────────┴───────────────────────────────────────────────┘
```

**Progressive disclosure within the detail page:**

- **"What This Does" box** — The `<PayloadSummary>` component renders a
  plain-language description of the mutation.  No raw hex, no struct
  names.  `SendCoin<0x2::sui::SUI>` becomes "Send 15,000 SUI to 0xCd..12".
  Addresses show a truncated form with hover-to-copy full value.
- **Voter breakdown** — Collapsed by default (`▸ Show voter breakdown`).
  Most voters just need the bar chart.  Expanding shows a table of
  each member + their vote + timestamp.
- **Timer** — Single line.  Shows the *most relevant* timer:
  Active → "Voting closes in X"; Passed → "Executable in X" (delay);
  Cooldown → "Cooldown ends in X".
- **Action buttons** — Contextual to status AND role:
  - Active + member + not voted → `[Vote Yes] [Vote No]`
  - Active + member + voted → `You voted Yes ✓` (no re-vote)
  - Passed + delay elapsed → `[Execute]`
  - Passed + delay pending → `Execute available in 2h 14m` (disabled)
  - Visitor → No action buttons shown (read-only)

### 2c. State transitions in the detail view

The detail page is **not a static page** — it's a living view that
transitions as the proposal moves through its lifecycle:

```
             ACTIVE                    PASSED              EXECUTED
  ┌──────────────────────┐  ┌─────────────────────┐  ┌──────────────┐
  │ Vote Yes / Vote No   │→ │ ⏱ Delay: 47h left   │→ │ ✓ Executed    │
  │ ⏱ Expires in 5d      │  │ [ Execute ] (grey)   │  │ Tx: 0xFa..21 │
  │ Quorum: 42%          │  │ Quorum: ✓  Thresh: ✓ │  │ 2h ago        │
  └──────────────────────┘  └─────────────────────┘  └──────────────┘
                                     │
                                     │ delay elapsed
                                     ▼
                            ┌─────────────────────┐
                            │ [ Execute ]  (amber) │
                            │ Ready to execute     │
                            └─────────────────────┘
```

---

## Flow 3 — Creating a Proposal (Layer 2: Act)

**Goal:** Board member creates a proposal.  The form adapts to the
proposal type, revealing only relevant fields.

### 3a. Type Selection (the entry funnel)

Instead of showing all 18 types in a flat list, group them by
**intent** — what the user wants to *accomplish*, not what struct
they're constructing.

```
┌── New Proposal ────────────────────────────────────────────┐
│                                                            │
│  What do you want to do?                                   │
│                                                            │
│  ┌─ Treasury ──────────────────────────────────────────┐   │
│  │  Send funds to an address                           │   │
│  │  Send funds to another DAO                          │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                            │
│  ┌─ Membership ────────────────────────────────────────┐   │
│  │  Change the board                                   │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                            │
│  ┌─ Documents ─────────────────────────────────────────┐   │
│  │  Amend the charter                                  │   │
│  │  Update metadata                                    │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                            │
│  ┌─ Organization ──────────────────────────────────────┐   │
│  │  Create a SubDAO                                    │   │
│  │  Manage a SubDAO (pause, unpause, reclaim, spin out)│   │
│  │  Transfer a capability to a SubDAO                  │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                            │
│  ▸ Advanced: Rules & Security                              │
│  ▸ Advanced: Package Upgrades                              │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

**Progressive disclosure in the type selector:**

- **Top-level categories** use natural language ("Send funds to an address"),
  not protocol jargon ("SendCoin\<T\>").
- **Advanced sections** (Gov Config, Freeze, Upgrades) are collapsed by
  default.  Expanding reveals:

```
  ▾ Advanced: Rules & Security
  ┌──────────────────────────────────────────────────────┐
  │  Enable a proposal type                              │
  │  Disable a proposal type                             │
  │  Update proposal type config                         │
  │  Transfer freeze admin                               │
  │  Unfreeze a proposal type                            │
  │  Update freeze config                                │
  │  Update freeze exempt types                          │
  └──────────────────────────────────────────────────────┘
```

- **Only enabled types are shown.** If a DAO hasn't enabled `SendCoinToDAO`,
  that option doesn't appear.  No disabled/greyed-out items.
- **Cooldown-blocked types** show a small timer:
  `Send funds to an address · available in 4h 12m` — visible but
  non-clickable until cooldown expires.

### 3b. Form Fill (adaptive forms)

After type selection, the form renders fields specific to that type.
Every form shares a common shell:

```
┌── New Proposal: Send Funds ────────────────────────────────┐
│                                                            │
│  Summary *                                                 │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ Fund Q1 security audit                               │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                            │
│  ── type-specific fields here ──                           │
│                                                            │
│  Coin type                                                 │
│  [ SUI ▾ ]                                                 │
│                                                            │
│  Amount                                                    │
│  ┌────────────────────────────────┐                        │
│  │ 15000                          │  [Max: 160,000 SUI]    │
│  └────────────────────────────────┘                        │
│                                                            │
│  Recipient address                                         │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ 0x...                                                │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                            │
│  ▸ Review before submitting                                │
│                                                            │
│  [ Submit Proposal ]                                       │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

**"Review before submitting" — the safety gate:**

Before the transaction fires, expanding this section shows the exact
payload summary the voters will see.  This is the same `<PayloadSummary>`
component used on the detail page — what you see is what they'll see.

```
  ▾ Review before submitting
  ┌──────────────────────────────────────────────────────┐
  │  This proposal will:                                 │
  │  Send 15,000 SUI ($45,000) from the treasury         │
  │  to 0xCd4f...8a12                                   │
  │                                                      │
  │  Current treasury balance: 160,000 SUI               │
  │  Balance after execution:  145,000 SUI               │
  │                                                      │
  │  Voting rules for SendCoin:                          │
  │  · Quorum: 50% (6 of 12 members must vote)           │
  │  · Threshold: 66% (of votes must be Yes)             │
  │  · Voting window: 7 days                             │
  │  · Execution delay: 48 hours after passing           │
  │  · Cooldown: 24 hours between executions             │
  └──────────────────────────────────────────────────────┘
```

### 3c. The CreateSubDAO Wizard (Layer 3 complexity, Layer 2 UX)

The most complex proposal type gets a **step wizard** to break the
cognitive load:

```
  Step:  [1·Name]  [2·Board]  [3·Charter]  [4·Types]  [5·Fund]  [6·Review]
         ════════   ────────   ──────────   ────────   ───────   ────────

  ┌── Step 1: Identity ──────────────────────────────────────┐
  │                                                          │
  │  SubDAO name *                                           │
  │  ┌────────────────────────────────────────────────────┐  │
  │  │ Engineering Guild                                  │  │
  │  └────────────────────────────────────────────────────┘  │
  │                                                          │
  │  Metadata CID (IPFS)                                     │
  │  ┌────────────────────────────────────────────────────┐  │
  │  │ bafk...                                            │  │
  │  └────────────────────────────────────────────────────┘  │
  │                                                          │
  │                              [ Next: Board → ]           │
  └──────────────────────────────────────────────────────────┘
```

Each step validates before allowing "Next".  The step indicator shows
completed steps as solid bars, current as highlighted, future as dashed.
Users can navigate back freely without losing state.

---

## Flow 4 — Treasury (Layer 1–2)

**Goal:** See what the DAO owns.  Deposit permissionlessly.  Propose
withdrawals through governance.

```
┌── SIDEBAR ──┬── MAIN ──────────────────────────────────────┐
│             │                                               │
│ Dashboard   │  Treasury                                     │
│ Treasury  ● │  ──────────────────────────────────────────── │
│ Proposals   │                                               │
│ Board       │  Total Value: $482,100                        │
│ Charter     │                                               │
│             │  ┌────────────┬────────────┬─────────────────┐│
│             │  │ Coin       │ Balance    │ Value           ││
│             │  ├────────────┼────────────┼─────────────────┤│
│             │  │ SUI        │ 160,000    │ $480,000        ││
│             │  │ USDC       │ 2,100      │ $2,100          ││
│             │  └────────────┴────────────┴─────────────────┘│
│             │                                               │
│             │  ▸ Deposit                                    │
│             │  ▸ Transaction History                        │
│             │                                               │
│             │  ┌─ Unclaimed ──────────────────────────────┐ │
│             │  │ 500 SUI sent directly to vault address   │ │
│             │  │ [ Claim ]                                │ │
│             │  └──────────────────────────────────────────┘ │
│             │                                               │
│             │  To withdraw funds, create a SendCoin         │
│             │  proposal →                                   │
│             │                                               │
└─────────────┴───────────────────────────────────────────────┘
```

**Key UX choices:**

- **Deposit is permissionless** — collapsed by default since it's a
  secondary action, but available to *anyone* (visitor or member).
- **Withdraw requires governance** — instead of a "Withdraw" button,
  there's a contextual link to the proposal creation flow.  This
  teaches the governance model without a tutorial.
- **Unclaimed coins** — direct object transfers that need `claim_coin<T>`
  are surfaced proactively with a one-click claim action.

---

## Flow 5 — Board & Charter (Layer 1)

These are **read-heavy, write-rare** pages.  The design reflects this:
large readable content, small action triggers.

### Board

```
┌── Board Members ───────────────────────────────────────────┐
│                                                            │
│  12 members · Quorum requires 6 votes                      │
│                                                            │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ Address          │ Alias        │ Joined (approx)    │  │
│  ├──────────────────┼──────────────┼────────────────────┤  │
│  │ 0xAb..9f         │ alice.sui    │ epoch 142          │  │
│  │ 0xBe..3f         │ bob.sui      │ epoch 142          │  │
│  │ 0xCd..12         │ —            │ epoch 155          │  │
│  │ ...              │              │                    │  │
│  └──────────────────┴──────────────┴────────────────────┘  │
│                                                            │
│  To change the board, create a SetBoard proposal →         │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

### Charter

```
┌── Charter ─────────────────────────────────────────────────┐
│                                                            │
│  [Document]  [Integrity]                                   │
│  ═══════════  ──────────                                   │
│                                                            │
│  Protocol Foundation Charter                               │
│  ──────────────────────────                                │
│  This organization exists to fund public goods...          │
│  (rendered markdown from Walrus)                           │
│                                                            │
│  ...                                                       │
│                                                            │
│  ▸ Amendment History (3 amendments)                        │
│                                                            │
│  To amend, create an AmendCharter proposal →               │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

The **Integrity tab** (progressive disclosure) reveals:

```
  [Document]  [Integrity]
  ──────────  ═══════════

  On-chain hash:  0xfa4b...21ac
  Walrus content: 0xfa4b...21ac
  Status:         ✓ Verified — hashes match

  Storage blob:   bafk...xyz
  Renewal due:    epoch 400 (est. 2026-06-15)

  [ Verify Now ]
```

---

## Flow 6 — Governance Config (Layer 3: Govern)

**Goal:** Understand and modify the rules that govern proposals.
This is complexity that belongs behind the sidebar divider — most
members will never visit it.

```
┌── Governance Config ───────────────────────────────────────┐
│                                                            │
│  Enabled Proposal Types                                    │
│                                                            │
│  ┌──────────────┬────────┬───────┬───────┬────────┬──────┐│
│  │ Type         │Quorum  │Thresh │Delay  │Cooldown│Expiry││
│  ├──────────────┼────────┼───────┼───────┼────────┼──────┤│
│  │ SetBoard     │ 50%    │ 66%   │ 48h   │ 24h    │ 7d   ││
│  │ SendCoin     │ 50%    │ 66%   │ 48h   │ 24h    │ 7d   ││
│  │ AmendCharter │ 66%    │ 80%   │ 72h   │ 48h    │ 14d  ││
│  │ ...          │        │       │       │        │      ││
│  └──────────────┴────────┴───────┴───────┴────────┴──────┘│
│                                                            │
│  Each row has a [▸] to expand with:                        │
│  · Plain-language explanation of what these numbers mean    │
│  · "Propose Config Change →" link                          │
│                                                            │
│  ▸ Disabled Types (3)                                      │
│  ▸ Protected Types (cannot be disabled)                    │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

**Inline education pattern:** When a row is expanded:

```
  ▾ SetBoard
  ┌──────────────────────────────────────────────────────┐
  │ To change the board, at least 50% of members must    │
  │ vote, and 66% of those votes must be Yes.  After     │
  │ passing, there's a 48-hour delay before anyone can   │
  │ execute.  Another SetBoard proposal can't be         │
  │ executed within 24 hours of the last one.  If no     │
  │ one votes within 7 days, the proposal expires.       │
  │                                                      │
  │ Propose Config Change →                              │
  └──────────────────────────────────────────────────────┘
```

This translates governance parameters into **consequences the user can
reason about** — not "quorum = 5000 bps" but "at least 50% of members
must vote."

---

## Flow 7 — Emergency & Freeze (Layer 3: Govern)

**Goal:** Understand and operate the emergency brake.  This page should
feel appropriately urgent — it's the protocol's circuit breaker.

```
┌── Emergency ───────────────────────────────────────────────┐
│                                                            │
│  ┌─ STATUS ───────────────────────────────────────────┐    │
│  │  🔒 1 type currently frozen                        │    │
│  │  Freeze Admin: 0xAb..9f                            │    │
│  │  Max freeze duration: 72 hours                     │    │
│  └────────────────────────────────────────────────────┘    │
│                                                            │
│  Frozen Types                                              │
│  ┌────────────────────┬─────────────────────────────────┐  │
│  │ Type               │ Expires                         │  │
│  ├────────────────────┼─────────────────────────────────┤  │
│  │ SendCoin           │ ⏱ 47h 12m remaining            │  │
│  └────────────────────┴─────────────────────────────────┘  │
│                                                            │
│  ── Freeze Admin Controls ─── (only if you hold the cap)   │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ Freeze a type:  [ Select type ▾ ]  [ Freeze ]       │  │
│  │ Unfreeze:       [ SendCoin ▾    ]  [ Unfreeze ]     │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                            │
│  ── Governance Overrides ──                                │
│  Anyone on the board can propose to:                       │
│  · Unfreeze a type (via governance vote) →                 │
│  · Transfer freeze admin to a new holder →                 │
│  · Update freeze duration limits →                         │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

**Progressive disclosure:**

- The Freeze Admin Controls section **only renders** if the connected
  wallet holds the FreezeAdminCap.  Others see a read-only view of
  who the admin is.
- Governance Overrides are always visible — this teaches that emergency
  actions have democratic escape hatches.

---

## Flow 8 — SubDAOs (Layer 3–4: Govern / Migrate)

**Goal:** Visualize the DAO hierarchy.  Manage child organizations.

```
┌── SubDAOs ─────────────────────────────────────────────────┐
│                                                            │
│  [List]  [Graph]                                           │
│  ═══════  ──────                                           │
│                                                            │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ ◇ Engineering Guild                                 │   │
│  │   5 members · $12k treasury · 8 types enabled       │   │
│  │   Status: Active                                    │   │
│  │   [ Enter DAO → ]  [ ▾ Actions ]                    │   │
│  ├─────────────────────────────────────────────────────┤   │
│  │ ◇ Grants Committee                                  │   │
│  │   7 members · $95k treasury · 6 types enabled       │   │
│  │   Status: Paused by parent                          │   │
│  │   [ Enter DAO → ]  [ ▾ Actions ]                    │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                            │
│  [ Create SubDAO → ]                                       │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

**The "Actions" dropdown** is the Layer 4 power tool:

```
  ▾ Actions
  ┌────────────────────────────────┐
  │ Replace Board (privileged)     │
  │ Pause Execution                │
  │ Reclaim Capability             │
  │ ────────────────────────────── │
  │ Spin Out (grant independence)  │
  └────────────────────────────────┘
```

Each action links to a pre-filled proposal form — "Pause Execution"
goes to `/proposals/new?type=PauseSubDAOExecution&subdao=0x...`.

### Graph View (alternate tab)

```
  [List]  [Graph]
  ──────  ═══════

         ◆ Protocol Foundation
        ╱                      ╲
  ◇ Engineering            ◇ Grants
     Guild                 Committee
       │
  ◇ Frontend
     Team

  Legend:  ◆ Root DAO   ◇ SubDAO   ── control link
           Red border = paused     Dashed = spun out
```

---

## Navigation Feel — How the Pieces Connect

The navigation model follows a **hub-and-spoke with contextual bridges**
pattern:

```
                    ┌──────────┐
                    │DAO Picker│
                    └────┬─────┘
                         │
                    ┌────▼─────┐
              ┌─────┤Dashboard ├─────┐
              │     └────┬─────┘     │
              │          │           │
         ┌────▼───┐ ┌───▼────┐ ┌────▼────┐
         │Treasury│ │Proposals│ │  Board  │
         └────┬───┘ └───┬────┘ └────┬────┘
              │         │           │
              │    ┌────▼─────┐    │
              └───→│ Proposal │←───┘
                   │  Detail  │
                   └────┬─────┘
                        │
             ┌──────────┼──────────┐
             ▼          ▼          ▼
         (vote)    (execute)  (create new
                               from context)
```

**Key navigation principles:**

1. **Dashboard is always home.** One click from anywhere.
2. **Proposal Detail is the action hub.** Vote, execute, and inspect all
   happen here.  Other pages *link to* relevant proposals.
3. **Contextual creation links.** "To withdraw funds, create a SendCoin
   proposal →" beats a generic "New Proposal" button because it carries
   intent.  The user arrives at the form with context.
4. **Breadcrumbs for SubDAOs.** When inside a SubDAO, the breadcrumb
   `Protocol Foundation > Engineering Guild > Dashboard` always shows
   the hierarchy.  Clicking any ancestor navigates to that DAO.
5. **Sidebar stays stable.** No dynamic sidebar items.  The same 9 items
   always exist in the same order.  Stability builds spatial memory.

---

## Visitor vs Member Experience

Rather than two separate UIs, the same interface renders with
**subtractive disclosure** — members see action affordances, visitors
see the same data without them:

```
                        VISITOR                 MEMBER
  ─────────────────────────────────────────────────────────
  Dashboard             ✓ read-only             ✓ + "Needs Your Vote"
  Proposal List         ✓ read-only             ✓ + [New Proposal]
  Proposal Detail       ✓ payload + votes       ✓ + vote/execute btns
  Treasury              ✓ balances              ✓ + deposit + withdraw→
  Board                 ✓ member list           ✓ + "Propose Change →"
  Charter               ✓ document              ✓ + "Amend →"
  Gov Config            ✓ read-only table       ✓ + config change links
  Emergency             ✓ freeze status         ✓ + admin controls (if cap)
  SubDAOs               ✓ list + graph          ✓ + action dropdown
```

**Why subtractive, not additive:** Visitors learn the full data model.
When they become members, the interface gains affordances but the
layout stays identical.  Zero re-learning cost.

---

## Empty States as Onboarding

Every page must handle the zero-state gracefully.  Empty states
should teach, not just say "nothing here."

```
  ┌─ No Active Proposals ───────────────────────────────┐
  │                                                     │
  │  No proposals are currently up for vote.            │
  │                                                     │
  │  Proposals are how this DAO makes decisions —       │
  │  any board member can propose changes to the        │
  │  treasury, board, charter, or governance rules.     │
  │                                                     │
  │  [ Create First Proposal ]   (member only)          │
  │                                                     │
  └─────────────────────────────────────────────────────┘

  ┌─ Empty Treasury ────────────────────────────────────┐
  │                                                     │
  │  This DAO's treasury has no funds yet.              │
  │                                                     │
  │  Anyone can deposit coins directly to the vault.    │
  │  Withdrawals require a governance proposal.         │
  │                                                     │
  │  [ Deposit ]                                        │
  │                                                     │
  └─────────────────────────────────────────────────────┘

  ┌─ No SubDAOs ────────────────────────────────────────┐
  │                                                     │
  │  This DAO has no child organizations yet.           │
  │                                                     │
  │  SubDAOs let you delegate authority to focused      │
  │  teams while the parent retains oversight.          │
  │                                                     │
  │  [ Create SubDAO → ]   (member only)                │
  │                                                     │
  └─────────────────────────────────────────────────────┘
```

---

## Banner System (persistent alerts)

Certain DAO states require persistent visibility.  These render as
full-width banners below the top bar, above page content:

```
  ┌─────────────────────────────────────────────────────────┐
  │ ⚠ This DAO is paused by its parent. Proposals cannot   │
  │   be executed until the parent unpauses.                │
  ├─────────────────────────────────────────────────────────┤
  │ ⚠ This DAO is migrating to a successor.  Only asset    │
  │   transfer proposals can be executed.                   │
  ├─────────────────────────────────────────────────────────┤
  │ 🔒 1 proposal type is currently frozen. View details →  │
  └─────────────────────────────────────────────────────────┘
```

Banners stack.  They're dismissible per-session but return on reload
as long as the condition holds.

---

## Summary: Disclosure Layers Mapped to Sidebar

```
  ┌── SIDEBAR ──────────────────────────┐
  │                                     │
  │  Layer 1 — Orient                   │
  │  ├─ Dashboard                       │
  │  ├─ Treasury                        │
  │  ├─ Board                           │
  │  └─ Charter                         │
  │                                     │
  │  Layer 2 — Act                      │
  │  └─ Proposals (list + detail + new) │
  │                                     │
  │  ── more ──────────────────────     │
  │                                     │
  │  Layer 3 — Govern                   │
  │  ├─ Gov Config                      │
  │  └─ Emergency                       │
  │                                     │
  │  Layer 4 — Evolve                   │
  │  └─ SubDAOs                         │
  │                                     │
  └─────────────────────────────────────┘
```

The user's journey through these layers is **self-directed and
non-linear**.  A new board member might spend weeks at Layer 1–2 before
curiosity (or necessity) pulls them into Layer 3.  The UI never gates
access — it just de-emphasizes complexity until it's needed.

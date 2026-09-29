# Demo Flows

Three live Testnet demos, each chosen to highlight a distinct axis of the protocol's value:

| Demo | Axis | What It Proves |
|------|------|----------------|
| **A — One Vision, One Tribe** | Scaling | One person's vision becomes a structured tribe — the OU scales from founder to organization |
| **B — The Gate Builders** | Emergence | Bottom-up initiative creates a funded sub-OU whose revenue flows back to the parent |
| **C — Gate Network Franchise** | Integration | OUs plug directly into EVE Frontier smart assemblies (SSUs, Gates, Turrets) |

All PTBs below use the current API. Proposal types other than the defaults (`SetBoard`, the member types, `UpdateMetadata`, the type-admin and freeze meta-types, `Composite`) are opt-in: an OU enables each one with an `EnableProposalType` vote (80%), which also sets the permission bits the type's handler needs (`armature_proposals::type_permissions`). Configs holding `TREASURY_WITHDRAW`, `VAULT_BORROW` or `VAULT_EXTRACT` need an 80% approval threshold.

---

## Flow A — One Vision, One Tribe (Scaling)

### Context

Alice is a solo miner with a vision: build the largest hauling operation in the sector. She doesn't start by recruiting — she starts by **codifying her intent**. She creates an OU with a charter document that describes what "Iron Haulers" stands for, how decisions will be made, and what kind of people she wants on board. The OU is her civilizational seed — a structure that can grow from one person to many without ever being rewritten.

As she recruits Bob and Carol, they join the board and contribute to the treasury. As the tribe grows further, they spin up specialized sub-OUs and delegate authority downward. The same `OU` object that started as Alice's solo venture now governs a multi-department tribe — no migrations, no restructuring. The primitive scales because it was designed to.

(For a tribe that starts with its full structure, `tribe::create_tribe` builds a Tribe OU, an Officers SubOU and a Members SubOU in one transaction; see [`docs/tribe-creation.md`](../docs/tribe-creation.md).)

### Steps

```
Step 1: Alice Plants the Seed
─────────────────────────────────────────────────────────────
Alice creates "Iron Haulers" — an OU with herself as the
sole board member. She publishes a charter document to IPFS
describing her vision: a hauling tribe that shares profits,
votes on strategy, and scales by delegating to sub-OUs.

  PTB: ou::create(
         gov_init:     governance::init_board(vector[Alice]),
         name:         "Iron Haulers",
         metadata_uri: "ipfs://<ironhaulers charter CID>",
       )

  Charter excerpt (at metadata_uri):
    "Iron Haulers is a mining and logistics tribe.
     Membership is by board invitation. Treasury funds
     are spent only through proposals. Sub-OUs may be
     created for specialized operations. The founder
     retains no special privileges beyond her board seat."

  On-chain result:
    OU #0xOU1 (Iron Haulers)
    ├── TreasuryVault #0xTV1
    ├── CapabilityVault #0xCV1
    ├── Charter #0xCH1 (name, metadata_uri)
    ├── EmergencyFreeze #0xEF1
    ├── Board: [Alice]
    └── default proposal types seeded (SetBoard, AddMember,
        …, EnableProposalType, UpdateProposalConfig, Composite)
    FreezeAdminCap → Alice's wallet
```

```
Step 2: Recruit the Right People
─────────────────────────────────────────────────────────────
Alice finds Bob (a logistics pilot) and Carol (a combat
escort). She proposes adding them to the board — even as
sole member, she goes through governance. This sets the
precedent: everything happens through proposals.

  Proposal #P1 (on Iron Haulers): SetBoard
    to_add:    [Bob, Carol]
    to_remove: []

  As the only member, Alice's single YES passes, so she can
  submit, vote and execute in one PTB:
    1. board_voting::submit_vote_execute<SetBoard>(OU1, …)
         → ExecutionTicket<SetBoard>
    2. board_ops::execute_set_board(OU1, ticket)

  Board is now [Alice, Bob, Carol].
  Alice has no more voting power than Bob or Carol — by design.
  (She holds the FreezeAdminCap, which can pause proposal
  types but never act; the board can move it with
  TransferFreezeAdmin.)
```

```
Step 3: Pool Resources
─────────────────────────────────────────────────────────────
All three members deposit SUI into the shared treasury.
No proposal needed — deposits are permissionless. Anyone
can contribute to a cause they believe in.

  PTB: treasury_vault::deposit<SUI>(#0xTV1, coin: 100 SUI, ctx)
       × 3 (one per member)

  Treasury balance: 300 SUI
```

```
Step 4: First Real Decision — Create a Logistics Sub-OU
─────────────────────────────────────────────────────────────
The tribe is growing. Bob proposes a Logistics department
to manage hauling routes. This is the first structural
decision the tribe makes together.

  CreateSubOU and SendCoinToOU are opt-in, so the board
  first expands its proposal set (80% votes):
    EnableProposalType { type_key: "CreateSubOU", … }
    EnableProposalType { type_key: "SendCoinToOU<SUI>",
      config: … .with_permissions(TREASURY_WITHDRAW) }

  Proposal #P2: CreateSubOU
    name:          "Logistics Dept"
    initial_board: [Bob, Dave]
    metadata_uri:  "ipfs://<logistics charter CID>"

  Voting (quorum: 50%, threshold: 80%):
    Alice: YES    Bob: YES    Carol: (does not vote)
    Result: 2 of 3 voted (quorum met), 2/2 = 100% YES → PASSED

  Proposal #P3: SendCoinToOU<SUI>
    recipient_treasury: <Logistics treasury>
    amount: 50 SUI
    (submitted once #P2 has executed and the SubOU's
     treasury ID is known)
```

```
Step 5: The Tribe Takes Shape
─────────────────────────────────────────────────────────────
Executing #P2 (lifecycle_ops::execute_create_subou) produces
a new sub-OU. The parent keeps oversight through
SubOUControl, but the sub-OU governs its own day-to-day
operations. Executing #P3 funds it.

  OU #0xOU1 (Iron Haulers)
  ├── TreasuryVault: 250 SUI
  ├── CapabilityVault: [SubOUControl(#0xOU2),
  │                     FreezeAdminCap(#0xOU2)]
  └── Board: [Alice, Bob, Carol]
       │
       └──► OU #0xOU2 (Logistics Dept)   [CONTROLLED]
            ├── TreasuryVault: 50 SUI
            ├── Board: [Bob, Dave]  (parent can override)
            └── controller_cap_id: Some(SubOUControl in #0xCV1)
```

```
Step 6: Sub-OU Operates Autonomously
─────────────────────────────────────────────────────────────
Bob proposes a SendCoin from the Logistics treasury to pay
a hauler (Eve) for a delivery. The sub-OU votes and
executes on its own — no parent approval needed. (Logistics
enabled SendCoin<SUI> with TREASURY_WITHDRAW by its own
80% vote.)

  Proposal #P4 (on OU #0xOU2): SendCoin<SUI>
    recipient: Eve
    amount: 10 SUI

  Voting (on Logistics board):
    Bob: YES    Dave: YES
    Result: PASSED → treasury_ops::execute_send_coin
            → Eve receives 10 SUI

  Alice didn't need to approve this. She trusted the
  structure she built. That's the point.
```

```
Step 7: Parent Overrides — Accountability Preserved
─────────────────────────────────────────────────────────────
Dave goes inactive. The parent tribe replaces him on the
Logistics board. The controller acts through its
SubOUControl — no vote on the sub-OU.
Delegation doesn't mean abandonment.

  Proposal #P5 (on Iron Haulers): a composite of
    ControllerBatchRemoveMembers { control_id, members: [Dave] }
    ControllerBatchAddMembers    { control_id, members: [Frank] }
  (both enabled with VAULT_BORROW scoped to SubOUControl,
   80%, composable)

  PTB (by Alice, after the parent board passes #P5):
    1. board_voting::ticket_from_vote(OU1, #P5, …)
         → ExecutionTicket<CompositePayload>
    2. composite::begin_pipeline → advance_step per step, each
       ticket passed to its handler
       (subou_ops::execute_controller_batch_remove_members, then
       subou_ops::execute_controller_batch_add_members), which
       loans the SubOUControl, calls
       controller::privileged_submit on OU#2, and changes the
       board with the privileged request
    3. composite::finalize_pipeline

  Logistics board is now [Bob, Frank] — instant effect.
```

### Interface Mockups

```
┌─────────────────────────────────────────────────────────────┐
│  IRON HAULERS                          OU #0xOU1          │
│  ═══════════                                                │
│                                                             │
│  Board Members          Treasury             Charter        │
│  ┌───────────┐         ┌──────────┐         ┌───────────┐  │
│  │ ★ Alice   │         │ 250 SUI  │         │ View      │  │
│  │   Bob     │         │          │         │ document ↗│  │
│  │   Carol   │         └──────────┘         └───────────┘  │
│  └───────────┘                                              │
│                                                             │
│  SubOUs                                                    │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  📁 Logistics Dept        Board: Bob, Frank         │    │
│  │     Treasury: 40 SUI      Status: ACTIVE            │    │
│  │     [Manage]  [Reclaim Caps]  [Change Board]        │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
│  Active Proposals                                           │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  #P6  Expand Proposal Set         2 of 3 voted      │    │
│  │       Threshold: 80%              Expires: 18h       │    │
│  │       [Vote YES]  [Vote NO]  [Details]               │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
│  [+ New Proposal]                                           │
└─────────────────────────────────────────────────────────────┘
```

```
┌─────────────────────────────────────────────────────────────┐
│  CREATE SUBOU PROPOSAL                                     │
│  ═════════════════════                                      │
│                                                             │
│  SubOU Name:    [ Logistics Dept_____________ ]            │
│  Charter (URI):  [ ipfs://..._________________ ]            │
│                                                             │
│  Initial Board:                                             │
│    [ 0xBob...  ] [+]                                        │
│    [ 0xDave... ] [+]                                        │
│    [___________] [Add Member]                               │
│                                                             │
│  Initial Funding (follow-up SendCoinToOU proposal):        │
│    Amount: [ 50    ] SUI                                    │
│    Source: Parent Treasury (250 SUI available)               │
│                                                             │
│  Approval required: 80% (CreateSubOU floor)                │
│                                                             │
│  ┌────────────────────────────────────────────┐             │
│  │ This will create a controlled sub-OU.     │             │
│  │ The parent OU retains:                    │             │
│  │  • Board membership override               │             │
│  │  • Capability reclaim rights               │             │
│  │  • Execution pause/unpause                 │             │
│  │  • Custody of the sub-OU's FreezeAdminCap │             │
│  └────────────────────────────────────────────┘             │
│                                                             │
│  [Cancel]                           [Submit Proposal]       │
└─────────────────────────────────────────────────────────────┘
```

---

## Flow B — The Gate Builders (Emergence)

### Context

Iron Haulers has a funded treasury and a working governance structure (established in Flow A). Dave, a new recruit, sees an opportunity: three star systems nearby have no jump gates. He proposes a **gate-building project** to the parent OU. The OU votes to create a "Gate Builders" sub-OU, seeds it with treasury funds, and delegates it the authority to deploy and manage gates. Once the gates go live and collect tolls, **revenue flows back up** to the parent treasury.

This is **emergent gameplay**: the protocol doesn't hardcode "ventures," "projects," or "revenue-sharing agreements." Players use the existing OU/sub-OU primitives — proposals, treasury funding, capability delegation, charter updates — to **invent project-based organizations** from the bottom up. The gate-building venture was never designed into the protocol; it emerged from a player's initiative and the composability of the governance primitives.

The gate types in this flow (`AdoptGateCaps`, `ConfigureGateAccess`) come from a mocked gate integration package (see the Flow C note). Like any third-party type, each is enabled by an 80% vote with only the bits its handler needs, and only its own module can spend its tickets.

### Steps

```
Step 1: Dave Pitches the Gate Project
─────────────────────────────────────────────────────────────
Dave proposes a CreateSubOU to the Iron Haulers board.
Its charter document describes the project: build 3 gates,
charge tolls, return revenue to parent.

  Proposal #P7 (on Iron Haulers): CreateSubOU
    name:          "Gate Builders"
    initial_board: [Dave, Eve]
    metadata_uri:  "ipfs://<gateproject v1 CID>"
  followed by SendCoinToOU<SUI> for 100 SUI of seed funding

  Charter excerpt (at metadata_uri):
    "Gate Builders is a project sub-OU of Iron Haulers.
     Mission: deploy jump gates connecting Systems A, B, C.
     Revenue policy: 80% of toll revenue flows to parent
     treasury; 20% retained for maintenance and ops.
     Dissolution: parent may reclaim all caps at any time."

  Voting (quorum: 50%, threshold: 80%):
    Alice: YES    Bob: YES    Carol: YES
    Result: 3/3 = 100% → PASSED
```

```
Step 2: Gate Builders Sub-OU Materializes
─────────────────────────────────────────────────────────────
Execution produces:
  - A new OU #0xOU3 (Gate Builders)
  - SubOUControl and the sub-OU's FreezeAdminCap stored in
    the parent's CapabilityVault
  - 100 SUI sent to the Gate Builders treasury (SendCoinToOU)

  OU #0xOU1 (Iron Haulers)
  ├── TreasuryVault: 150 SUI  (was 250, minus 100 funding)
  ├── CapabilityVault: [SubOUControl(Logistics), SubOUControl(Gate Builders), …]
  └── Board: [Alice, Bob, Carol]
       │
       ├──► OU #0xOU2 (Logistics Dept)    [CONTROLLED]
       │    └── ...
       │
       └──► OU #0xOU3 (Gate Builders)     [CONTROLLED]
            ├── TreasuryVault: 100 SUI
            ├── CapabilityVault: empty (no caps yet)
            ├── Board: [Dave, Eve]
            └── Charter: "ipfs://<gateproject v1 CID>"
```

```
Step 3: Gate Builders Deploy Infrastructure  [MOCKED — see Flow C note]
─────────────────────────────────────────────────────────────
Dave deploys three Smart Gates. A vault accepts capabilities
only through a governed request carrying VAULT_STORE, so the
Gate Builders board passes an AdoptGateCaps proposal (a
mocked type holding VAULT_STORE, like AdoptCurrency) whose
handler stores the caps.

  PTB:
    1. gate::deploy(system_a, system_b) → GateOwnerCap #0xG1
    2. gate::deploy(system_b, system_c) → GateOwnerCap #0xG2
    3. gate::deploy(system_c, system_a) → GateOwnerCap #0xG3
    4. ticket_from_vote(OU3, AdoptGateCaps proposal, …)
    5. gate_ops::execute_adopt_gate_caps(#0xCV3, caps, ticket)
         → capability_vault::store_cap × 3

  Gate Builders CapabilityVault now holds:
    [GateOwnerCap(#0xG1), GateOwnerCap(#0xG2), GateOwnerCap(#0xG3)]
```

```
Step 4: Configure Gates — Tolls Go Live
─────────────────────────────────────────────────────────────
Dave proposes on the Gate Builders sub-OU to configure
all gates with toll pricing. The sub-OU votes and executes
autonomously — no parent approval needed.

  Proposal #P8 (on Gate Builders): ConfigureGateAccess
    gates: [#0xG1, #0xG2, #0xG3]
    access_policy:
      iron_haulers_members: FREE
      public: 1 SUI toll per jump
  (enabled with VAULT_BORROW, borrow scope [GateOwnerCap], 80%)

  Voting (on Gate Builders board):
    Dave: YES    Eve: YES → PASSED

  Execution loans each GateOwnerCap from the vault,
  calls gate::set_access_hook, and returns the cap.

  All three gates are now live and charging tolls.
```

```
Step 5: Revenue Flows — Tolls Accumulate
─────────────────────────────────────────────────────────────
Ships start jumping through the gates. The gate contract
deposits toll payments into the Gate Builders treasury
(treasury_vault::deposit is permissionless).

  Event stream:
    gate_jump { gate: #0xG1, jumper: Frank, toll: 1 SUI }
    gate_jump { gate: #0xG2, jumper: Grace, toll: 1 SUI }
    gate_jump { gate: #0xG1, jumper: Bob,   toll: 0 SUI (member) }
    ... over time ...

  Gate Builders treasury: 150 SUI (100 seed + 50 tolls)

  The project is profitable. Time to pay it forward.
```

```
Step 6: Revenue Share — Pay the Parent Back
─────────────────────────────────────────────────────────────
Per the charter, 80% of toll revenue goes to the parent.
Eve proposes sending 40 SUI (80% of 50) to the Iron Haulers
treasury.

  Proposal #P9 (on Gate Builders): SendCoinToOU<SUI>
    recipient_treasury: Iron Haulers Treasury (#0xTV1)
    amount: 40 SUI

  Voting:
    Dave: YES    Eve: YES → PASSED

  Iron Haulers treasury: 190 SUI (150 + 40 revenue)
  Gate Builders treasury: 110 SUI (150 - 40 paid up)

  The split is a charter term, paid by vote. Enforcing it
  on-chain is not implemented — see "Revenue Enforcement
  Options" below. The parent can override the sub-OU board
  if terms are violated.
```

```
Step 7: Emergent Self-Modification — Charter Update
─────────────────────────────────────────────────────────────
The gate network is thriving. Dave proposes updating the
Gate Builders charter to adjust the revenue split from
80/20 to 70/30 (more retained for expansion).

  Proposal #P10 (on Gate Builders): UpdateMetadata
    new_ipfs_cid: "ipfs://<gateproject v2 CID>"
    (metadata: "Reduce parent share to 70% to fund
                expansion into Systems D and E")

  Voting:
    Dave: YES    Eve: YES → PASSED

  But wait — the parent OU may not agree. Alice proposes a
  parent override that restores the v1 charter on the
  sub-OU through its SubOUControl (a custom controller type:
  loan the control, privileged_submit on Gate Builders,
  charter::update_metadata with the privileged request).
  It holds VAULT_BORROW, so it needs 80%:

  Voting on Iron Haulers board:
    Alice: YES    Bob: NO    Carol: (does not vote)
    Result: 1 YES / 2 cast = 50% < 80% → does not pass

  The parent board is split. The update stands — for now.
  This is emergent negotiation: governance tensions resolved
  through the protocol's own mechanisms, not hardcoded rules.
```

### Revenue Enforcement Options

> **Status:** not implemented. None of these options exists in the packages. The options are kept as design notes.

Three approaches were considered for enforcing revenue-sharing on-chain between a sub-OU and its parent. All rely on a `RevenuePolicy` object created at sub-OU inception, controlled by the parent via `SubOUControl`.

```
struct RevenuePolicy has key, store {
    id: UID,
    parent_treasury: ID,       // where the parent's share goes
    parent_share_bps: u16,     // 8000 = 80%, basis points
    child_treasury: ID,        // where the retained share goes
}
```

**Option A — Split-on-Deposit**

The sub-OU's `treasury_vault::deposit` checks for an attached `RevenuePolicy`. If present, incoming `Coin<T>` is split *before* it enters the sub-OU treasury — the parent's share is forwarded immediately, and only the retained portion is deposited.

- Simplest implementation, no accounting state
- Tamper-proof: the sub-OU never touches the parent's share
- Tradeoff: the sub-OU cannot batch or defer payments — every deposit triggers a split
- Requires a hook in the framework's `deposit`, which is not upgraded after a release: it would ship only with a fresh framework publish

**Option B — Split-on-Withdrawal with Accounting**

All revenue accumulates in the sub-OU treasury. A `RevenuePolicy` tracks an `owed_to_parent` counter. Treasury-spending handlers check the policy and require the parent's share to be settled first (or settled as part of the same PTB).

- More flexible: sub-OU can manage cash flow
- Requires accounting state (`owed_to_parent`, `total_revenue_received`)
- Enforcement point is at withdrawal, not deposit — sub-OU holds funds in the interim
- Risk: if the sub-OU's treasury is drained by other proposals before settling, the parent share could be underfunded. Mitigation: reserve a portion of treasury as "encumbered" and block withdrawals that would breach the reserve
- Can live in an extension package: its own spend types would enforce it, but any other type holding `TREASURY_WITHDRAW` on the sub-OU bypasses it

**Option C — Revenue Escrow**

Revenue goes into a shared `RevenueSplitEscrow` object (not directly into either treasury). Either party can call `escrow::release()` which splits and distributes to both treasuries according to the policy. No party can extract funds without triggering the split.

- Most trustless — neither party has custody of unsplit funds
- Adds an extra object and interaction step
- Clean separation of concerns: the escrow is a standalone primitive that needs no framework change
- Tradeoff: requires the revenue source (e.g., gate tolls) to target the escrow address instead of a treasury directly

Renegotiation (e.g., the 80/20 → 70/30 change in Step 7) would require the parent to update the policy through its `SubOUControl`. This turns the charter's revenue terms into an on-chain enforceable constraint while preserving the governance negotiation narrative.

### Interface Mockups

```
┌─────────────────────────────────────────────────────────────┐
│  GATE BUILDERS                         OU #0xOU3          │
│  ═════════════                     (SubOU of Iron Haulers) │
│                                                             │
│  Board Members          Treasury             Charter        │
│  ┌───────────┐         ┌──────────┐         ┌───────────┐  │
│  │ ★ Dave    │         │ 110 SUI  │         │ View      │  │
│  │   Eve     │         │          │         │ document ↗│  │
│  └───────────┘         └──────────┘         └───────────┘  │
│                                                             │
│  Parent: Iron Haulers (#0xOU1)    [View Parent]            │
│  Revenue terms: 80% to parent (charter v1)                  │
│                                                             │
│  Infrastructure Assets (from CapabilityVault)               │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  Gate  System A ↔ B    Status: ●  Jumps: 47         │    │
│  │  Gate  System B ↔ C    Status: ●  Jumps: 23         │    │
│  │  Gate  System C ↔ A    Status: ●  Jumps: 12         │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
│  Revenue Summary                                            │
│  ┌──────────────────────────────────────┐                   │
│  │  Total tolls collected:   50 SUI     │                   │
│  │  Paid to parent (80%):   40 SUI     │                   │
│  │  Retained (20%):         10 SUI     │                   │
│  └──────────────────────────────────────┘                   │
│                                                             │
│  Recent Proposals                                           │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  #P10 Update Charter (70/30 split)  EXECUTED        │    │
│  │       ⚠ Parent override proposed — see Iron Haulers │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
│  [+ New Proposal]  [Configure Gates]  [Pay Parent]          │
└─────────────────────────────────────────────────────────────┘
```

```
┌─────────────────────────────────────────────────────────────┐
│  PROJECT PROPOSAL — CREATE SUBOU                           │
│  ════════════════════════════════                            │
│                                                             │
│  Project Name:   [ Gate Builders________________ ]          │
│                                                             │
│  Project Charter (published to IPFS):                       │
│  ┌────────────────────────────────────────────────┐         │
│  │  Mission: Deploy jump gates connecting         │         │
│  │  Systems A, B, C.                              │         │
│  │                                                │         │
│  │  Revenue: 80% to parent, 20% retained.         │         │
│  │                                                │         │
│  │  Dissolution: Parent may reclaim all caps.     │         │
│  └────────────────────────────────────────────────┘         │
│  [Edit document ↗]                                          │
│                                                             │
│  Initial Board:                                             │
│    [ 0xDave... ] [+]                                        │
│    [ 0xEve...  ] [+]                                        │
│    [___________] [Add Member]                               │
│                                                             │
│  Initial Funding (follow-up SendCoinToOU proposal):        │
│    Amount: [ 100   ] SUI                                    │
│    Source: Parent Treasury (250 SUI available)               │
│                                                             │
│  ┌────────────────────────────────────────────┐             │
│  │ This creates a controlled project sub-OU. │             │
│  │ The parent OU retains:                    │             │
│  │  • Board membership override               │             │
│  │  • Capability reclaim rights               │             │
│  │  • Execution pause/unpause                 │             │
│  └────────────────────────────────────────────┘             │
│                                                             │
│  [Cancel]                           [Submit Proposal]       │
└─────────────────────────────────────────────────────────────┘
```

---

## Flow C — Gate Network Franchise (Integration)

### Context

Iron Haulers decides to build a toll gate network connecting three star systems. The OU holds the **Smart Gate ownership capabilities** in its CapabilityVault. Gate access logic calls back to on-chain OU state to check membership. Toll revenue flows into the OU treasury. A third-party logistics DApp reads OU membership to offer route planning through the gate network.

This demonstrates direct integration with EVE Frontier's **Smart Assemblies** (Gates, SSUs) — the OU protocol isn't a standalone governance toy but a **composable primitive** that plugs into the game world.

> **Note — Mocked Integration**: The EVE Frontier world contracts currently only
> allow `Character` objects (not arbitrary Sui objects like OUs) to hold Smart
> Assembly `OwnerCap`s. Object-based custody is flagged as future work by CCP.
>
> For the demo, we **mock the Smart Assembly modules** (`gate::`, `ssu::`)
> with simplified contracts that allow object-based custody. This lets us demonstrate
> the full OU-holds-caps-and-loans-them-via-proposals architecture without being
> blocked by the current world contract limitation.
>
> The capability names below (`GateOwnerCap`, `SSUOwnerCap`) are illustrative.
> The pattern — OU holds caps, proposals loan them for configuration — is
> architecture-stable regardless of final naming or custody model.
>
> The integration that ships today is `armature_world_bridge`: a Members OU can
> let players self-join by proving, through their world `Character`, that they
> belong to an allowlisted in-game tribe (`AutojoinOU`, a bypass type).

### Steps

```
Step 1: OU Acquires Gate Ownership Capabilities
─────────────────────────────────────────────────────────────
Alice deploys three Smart Gates and the board stores their
ownership capabilities in the Iron Haulers CapabilityVault
through an AdoptGateCaps proposal (VAULT_STORE).

  PTB:
    1. gate::deploy(system_a, system_b) → GateOwnerCap #0xG1
    2. gate::deploy(system_b, system_c) → GateOwnerCap #0xG2
    3. gate::deploy(system_c, system_a) → GateOwnerCap #0xG3
    4. ticket_from_vote(OU1, AdoptGateCaps proposal, …)
    5. gate_ops::execute_adopt_gate_caps(#0xCV1, caps, ticket)

  CapabilityVault #0xCV1 now holds:
    [SubOUControl(Logistics), SubOUControl(Gate Builders),
     GateOwnerCap(#0xG1), GateOwnerCap(#0xG2), GateOwnerCap(#0xG3), …]
```

```
Step 2: Proposal — Configure Gate Access Policy
─────────────────────────────────────────────────────────────
Bob proposes configuring all gates to allow only OU members
and charge 1 SUI toll per jump for non-members.

  This uses a custom proposal type that loans the GateOwnerCap
  from the vault and calls the gate's configuration function.
  The OU enabled it with VAULT_BORROW and a borrow scope of
  [GateOwnerCap], so its requests can reach no other cap in
  the vault (not the SubOUControls, not an UpgradeCap).

  Proposal #P11: ConfigureGateAccess
    gates: [#0xG1, #0xG2, #0xG3]
    access_policy:
      members: FREE
      non_members: 1 SUI toll
      blacklist: [known pirates]

  Voting (threshold 80%):
    Alice: YES    Bob: YES    Carol: YES → PASSED
```

```
Step 3: Execute — Gate Access Logic Set On-Chain
─────────────────────────────────────────────────────────────
  PTB (execution):
    1. board_voting::ticket_from_vote(OU1, #P11, freeze, clock)
         → ExecutionTicket<ConfigureGateAccess>
    2. gate_ops::execute_configure_gate_access(#0xCV1, gates, ticket):
         for each gate:
           capability_vault::loan_cap<GateOwnerCap, ConfigureGateAccess>(
             #0xCV1, gate_cap_id, ticket.ticket_request(permit))
             → (GateOwnerCap, CapLoan)
           gate::set_access_hook(cap, policy)  // EVE world contract call
           capability_vault::return_cap(#0xCV1, cap, loan)
         ticket.discharge(permit)

  Only gate_ops (the module defining ConfigureGateAccess) can
  spend the ticket, so the policy applied is the one voted on.

  The gate's canJump hook now queries:
    fn can_jump(character):
      if ou::is_governance_member(&OU1, character.character_address())
                                               → allow (free)
      if has_toll_ticket(character)            → allow (paid)
      if blacklisted(character)                → deny
      else                                     → charge toll
```

```
Step 4: Toll Revenue Flows Into Treasury
─────────────────────────────────────────────────────────────
As ships jump through the gates, toll payments accumulate.
The gate contract deposits toll revenue into the OU's
treasury (treasury_vault::deposit, permissionless).

  Event stream:
    gate_jump { gate: #0xG1, jumper: Eve, toll: 1 SUI }
    gate_jump { gate: #0xG2, jumper: Frank, toll: 1 SUI }
    gate_jump { gate: #0xG1, jumper: Grace, toll: 0 SUI (member) }

  Treasury balance: 252 SUI (250 + 2 tolls)

  Revenue is visible on the OU dashboard and auditable
  on-chain — every deposit emits CoinDeposited.
```

```
Step 5: Third-Party DApp Integration — Route Planner
─────────────────────────────────────────────────────────────
A logistics DApp ("StarRoutes") queries on-chain state to
offer route planning through OU-governed gate networks.

  StarRoutes reads:
    1. ou::is_governance_member(&OU1, user) → member?
       (the full roster comes from the indexer or the
        members table; see 06 Data Layer)
    2. gate::get_access_policy(#0xG1) → toll/free for user
    3. gate::get_connections() → system graph

  StarRoutes UI:
  ┌──────────────────────────────────────────────┐
  │  Route: System A → System C                  │
  │                                               │
  │  Option 1: A → B → C (2 jumps)               │
  │    Gate: Iron Haulers Network                 │
  │    Cost: FREE (you are a member)              │
  │    [Jump Now]                                 │
  │                                               │
  │  Option 2: A → C (1 jump, direct)             │
  │    Gate: Iron Haulers Network                 │
  │    Cost: 1 SUI toll                           │
  │    [Buy Toll Ticket + Jump]                   │
  └──────────────────────────────────────────────┘
```

```
Step 6: Delegate Gate Ops to Logistics SubOU
─────────────────────────────────────────────────────────────
The parent OU delegates one gate's ownership to the
Logistics SubOU, letting them manage it independently.

  Proposal #P12 (on Iron Haulers): TransferCapToSubOU
    cap_id:        GateOwnerCap(#0xG2)
    target_subou: #0xOU2 (Logistics Dept)
  (VAULT_EXTRACT, 80%)

  Voting: PASSED

  Execution (subou_ops::execute_transfer_cap<GateOwnerCap>):
    1. Extract GateOwnerCap(#0xG2) from parent vault
    2. Receive it into Logistics SubOU's CapabilityVault

  Once Logistics enables ConfigureGateAccess on its own OU,
  it can reconfigure Gate #0xG2 autonomously.
  Parent retains reclaim rights (ReclaimCapFromSubOU).
```

```
Step 7: SSU Integration — Tribe Supply Depot
─────────────────────────────────────────────────────────────
Iron Haulers deploys a Smart Storage Unit (SSU) at their
base station. The SSU ownership cap is held in the OU's
CapabilityVault. Access is governed by OU membership.

  PTB:
    1. ssu::deploy(station_id) → SSUOwnerCap #0xSSU1
    2. store it via an adopt proposal (VAULT_STORE), as in Step 1

  SSU access hook:
    fn can_access(character):
      if ou::is_governance_member(&OU1, character.character_address())
                                               → allow
      → deny

  Only Iron Haulers members can deposit/withdraw from
  the tribe supply depot. The same cap vault pattern
  used for gates works for any Smart Assembly type.
```

### Interface Mockups

```
┌─────────────────────────────────────────────────────────────┐
│  GATE NETWORK MANAGEMENT              Iron Haulers OU      │
│  ═══════════════════════                                    │
│                                                             │
│  Infrastructure Assets (from CapabilityVault)               │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  Gate  System A ↔ B    Owner: This OU    Status: ● │    │
│  │  #0xG1                 Toll: 1 SUI        Jumps: 47 │    │
│  │  [Configure]  [Delegate to SubOU]  [View Revenue]  │    │
│  ├─────────────────────────────────────────────────────┤    │
│  │  Gate  System B ↔ C    Owner: Logistics   Status: ● │    │
│  │  #0xG2                 Toll: 1 SUI        Jumps: 23 │    │
│  │  [Reclaim from SubOU]  [View Revenue]              │    │
│  ├─────────────────────────────────────────────────────┤    │
│  │  Gate  System C ↔ A    Owner: This OU    Status: ● │    │
│  │  #0xG3                 Toll: 2 SUI        Jumps: 12 │    │
│  │  [Configure]  [Delegate to SubOU]  [View Revenue]  │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
│  Revenue Summary (last 7 days)                              │
│  ┌──────────────────────────────────────┐                   │
│  │  Gate #0xG1:  47 SUI  ████████████  │                   │
│  │  Gate #0xG2:  23 SUI  ██████        │                   │
│  │  Gate #0xG3:  24 SUI  ██████        │                   │
│  │  ─────────────────────              │                   │
│  │  Total:       94 SUI               │                   │
│  └──────────────────────────────────────┘                   │
│                                                             │
│  [+ Deploy New Gate]  [Bulk Configure]                      │
└─────────────────────────────────────────────────────────────┘
```

```
┌─────────────────────────────────────────────────────────────┐
│  CONFIGURE GATE ACCESS                                      │
│  ═════════════════════                                      │
│                                                             │
│  Gate: #0xG1 (System A ↔ System B)                          │
│                                                             │
│  Access Rules:                                              │
│  ┌────────────────────────────────────────────────┐         │
│  │  OU Members (Iron Haulers)                    │         │
│  │    Access: [✓ Allowed]    Toll: [ FREE       ] │         │
│  ├────────────────────────────────────────────────┤         │
│  │  Public                                        │         │
│  │    Access: [✓ Allowed]    Toll: [ 1 SUI      ] │         │
│  ├────────────────────────────────────────────────┤         │
│  │  Blacklist                                     │         │
│  │    Access: [✗ Denied ]                         │         │
│  │    [ 0xPirate1... ] [×]                        │         │
│  │    [ 0xPirate2... ] [×]                        │         │
│  │    [______________ ] [Add]                     │         │
│  └────────────────────────────────────────────────┘         │
│                                                             │
│  Revenue Destination: [ OU Treasury (#0xTV1)      ▼ ]      │
│                                                             │
│  ┌────────────────────────────────────────────┐             │
│  │ This creates a ConfigureGateAccess proposal │             │
│  │ requiring board approval (80% threshold).   │             │
│  └────────────────────────────────────────────┘             │
│                                                             │
│  [Cancel]                        [Submit Proposal]          │
└─────────────────────────────────────────────────────────────┘
```

```
┌─────────────────────────────────────────────────────────────┐
│  STARROUTES (Third-Party DApp)                              │
│  ════════════════════════════                               │
│                                                             │
│  Plan your route through player-built gate networks         │
│                                                             │
│  From: [ System Alpha  ▼ ]    To: [ System Gamma  ▼ ]      │
│                                                             │
│  Your Identity: 0xAlice...  (Iron Haulers member)           │
│                                                             │
│  Available Routes:                                          │
│  ┌──────────────────────────────────────────────────┐      │
│  │  ★ Route 1: Alpha → Beta → Gamma                 │      │
│  │    Network: Iron Haulers Gate Network             │      │
│  │    Jumps: 2       Cost: FREE (member)             │      │
│  │    Est. time: ~30s                                │      │
│  │    [Select Route]                                 │      │
│  ├──────────────────────────────────────────────────┤      │
│  │    Route 2: Alpha → Gamma (direct)                │      │
│  │    Network: Iron Haulers Gate Network             │      │
│  │    Jumps: 1       Cost: FREE (member)             │      │
│  │    Est. time: ~15s                                │      │
│  │    [Select Route]                                 │      │
│  ├──────────────────────────────────────────────────┤      │
│  │    Route 3: Alpha → Delta → Gamma                 │      │
│  │    Network: Star Weavers Express                  │      │
│  │    Jumps: 2       Cost: 2 SUI (non-member)        │      │
│  │    Est. time: ~30s                                │      │
│  │    [Select Route]                                 │      │
│  └──────────────────────────────────────────────────┘      │
│                                                             │
│  ┌─────────── Network Map ──────────────┐                  │
│  │                                       │                  │
│  │    [Alpha] ──G1── [Beta]              │                  │
│  │       \              |                │                  │
│  │       G3           G2                 │                  │
│  │         \            |                │                  │
│  │         [Gamma]──────┘                │                  │
│  │                                       │                  │
│  │  ── Iron Haulers (free for members)   │                  │
│  │                                       │                  │
│  └───────────────────────────────────────┘                  │
└─────────────────────────────────────────────────────────────┘
```

---

## Contract Features Required Across All Flows

| Feature | Flow A | Flow B | Flow C |
|---------|--------|--------|--------|
| `ou::create` (or `tribe::create_tribe`) | ✓ | | |
| `treasury_vault::deposit` | ✓ | ✓ | ✓ |
| `board_voting::submit_proposal` / `vote` / `ticket_from_vote` | ✓ | ✓ | ✓ |
| `board_voting::submit_vote_execute` (sole-member board) | ✓ | | |
| `admin_ops::execute_enable_proposal_type` (opt-in types, with bits) | ✓ | ✓ | ✓ |
| `board_ops::execute_set_board` (SetBoard) | ✓ | | |
| `lifecycle_ops::execute_create_subou` (CreateSubOU) | ✓ | ✓ | |
| `treasury_ops::execute_send_coin` / `execute_send_coin_to_ou` | ✓ | ✓ | |
| `subou_ops::execute_controller_batch_add_members` / `execute_controller_batch_remove_members` | ✓ | | |
| `composite` (bundle controller steps) | ✓ | | |
| `admin_ops::execute_update_metadata` (charter update) | | ✓ | |
| `capability_vault::store_cap` (through a VAULT_STORE adopt type) | | ✓ | ✓ |
| `capability_vault::loan_cap` / `return_cap` (VAULT_BORROW + scope) | | ✓ | ✓ |
| Custom: `AdoptGateCaps`, `ConfigureGateAccess` types and handlers | | ✓ | ✓ |
| `controller::privileged_submit` (parent override) | ✓ | ✓ | |
| `subou_ops::execute_transfer_cap` (TransferCapToSubOU) | | | ✓ |
| `RevenuePolicy` (not implemented) | | ✓ | |
| Charter document at `metadata_uri` (IPFS) | ✓ | ✓ | |
| Smart Gate integration hooks (mocked) | | ✓ | ✓ |
| Smart SSU integration hooks (mocked) | | | ✓ |
| Third-party DApp read queries (`ou::is_governance_member`, indexer) | | | ✓ |

# Demo Flows

Three live Testnet demos, each chosen to highlight a distinct axis of the protocol's value:

| Demo | Axis | What It Proves |
|------|------|----------------|
| **A — One Vision, One Tribe** | Scaling | One person's vision becomes a structured tribe — the DAO scales from founder to organization |
| **B — The Gate Builders** | Emergence | Bottom-up initiative creates a funded sub-DAO whose revenue flows back to the parent |
| **C — Gate Network Franchise** | Integration | DAOs plug directly into EVE Frontier smart assemblies (SSUs, Gates, Turrets) |

---

## Flow A — One Vision, One Tribe (Scaling)

### Context

Alice is a solo miner with a vision: build the largest hauling operation in the sector. She doesn't start by recruiting — she starts by **codifying her intent**. She creates a DAO with a charter that describes what "Iron Haulers" stands for, how decisions will be made, and what kind of people she wants on board. The DAO is her civilizational seed — a structure that can grow from one person to many without ever being rewritten.

As she recruits Bob and Carol, they join the board and contribute to the treasury. As the tribe grows further, they spin up specialized sub-DAOs and delegate authority downward. The same `DAO` object that started as Alice's solo venture now governs a multi-department tribe — no migrations, no restructuring. The primitive scales because it was designed to.

### Steps

```
Step 1: Alice Plants the Seed
─────────────────────────────────────────────────────────────
Alice creates "Iron Haulers" — a DAO with herself as the
sole board member. She writes a charter describing her
vision: a hauling tribe that shares profits, votes on
strategy, and scales by delegating to sub-DAOs.

  PTB: dao::create_dao(
         name: "Iron Haulers",
         governance: Board { members: [Alice] },
         charter_blob_id: "walrus://ironhaulers_v1..."
       )

  Charter excerpt (on Walrus):
    "Iron Haulers is a mining and logistics tribe.
     Membership is by board invitation. Treasury funds
     are spent only through proposals. Sub-DAOs may be
     created for specialized operations. The founder
     retains no special privileges beyond her board seat."

  On-chain result:
    DAO #0xDAO1 (Iron Haulers)
    ├── TreasuryVault #0xTV1
    ├── CapabilityVault #0xCV1
    ├── Charter #0xCH1 (v1, blob: walrus://ironhaulers_v1)
    └── Board: [Alice]
```

```
Step 2: Recruit the Right People
─────────────────────────────────────────────────────────────
Alice finds Bob (a logistics pilot) and Carol (a combat
escort). She proposes adding them to the board — even as
sole member, she goes through governance. This sets the
precedent: everything happens through proposals.

  Proposal #P1 (on Iron Haulers): SetBoard
    new_board: [Alice, Bob, Carol]

  Voting (sole member):
    Alice: YES → PASSED

  Board is now [Alice, Bob, Carol].
  Alice has no more power than Bob or Carol — by design.
```

```
Step 3: Pool Resources
─────────────────────────────────────────────────────────────
All three members deposit SUI into the shared treasury.
No proposal needed — deposits are permissionless. Anyone
can contribute to a cause they believe in.

  PTB: treasury::deposit<SUI>(vault: #0xTV1, coin: 100 SUI)
       × 3 (one per member)

  Treasury balance: 300 SUI
```

```
Step 4: First Real Decision — Create a Logistics Sub-DAO
─────────────────────────────────────────────────────────────
The tribe is growing. Bob proposes a Logistics department
to manage hauling routes. This is the first structural
decision the tribe makes together.

  Proposal #P2: CreateSubDAO
    name: "Logistics Dept"
    initial_board: [Bob, Dave]
    funding: 50 SUI from parent treasury

  Voting (quorum: 2, threshold: 66%):
    Alice: YES    Bob: YES    Carol: ABSTAIN
    Result: 2/2 = 100% → PASSED
```

```
Step 5: The Tribe Takes Shape
─────────────────────────────────────────────────────────────
Execution produces a new sub-DAO. The parent retains
oversight through SubDAOControl, but the sub-DAO governs
its own day-to-day operations.

  DAO #0xDAO1 (Iron Haulers)
  ├── TreasuryVault: 250 SUI
  ├── CapabilityVault: [SubDAOControl(#0xDAO2)]
  └── Board: [Alice, Bob, Carol]
       │
       └──► DAO #0xDAO2 (Logistics Dept)   [CONTROLLED]
            ├── TreasuryVault: 50 SUI
            ├── Board: [Bob, Dave]  (managed by parent)
            └── controller_cap_id: Some(SubDAOControl in #0xCV1)
```

```
Step 6: Sub-DAO Operates Autonomously
─────────────────────────────────────────────────────────────
Bob proposes a SendCoin from the Logistics treasury to pay
a hauler (Eve) for a delivery. The sub-DAO votes and
executes on its own — no parent approval needed.

  Proposal #P3 (on DAO #0xDAO2): SendCoin<SUI>
    recipient: Eve
    amount: 10 SUI

  Voting (on Logistics board):
    Bob: YES    Dave: YES
    Result: PASSED → Eve receives 10 SUI

  Alice didn't need to approve this. She trusted the
  structure she built. That's the point.
```

```
Step 7: Parent Overrides — Accountability Preserved
─────────────────────────────────────────────────────────────
Dave goes inactive. The parent tribe replaces the Logistics
board using privileged_submit (instant, no vote on sub-DAO).
Delegation doesn't mean abandonment.

  PTB (by Alice, authorized by parent board vote):
    1. proposal::execute(#P4)         → ExecutionRequest<SetBoard>
    2. board_ops::handle(req, DAO#2)  → Board set to [Bob, Frank]

  Logistics board is now [Bob, Frank] — instant effect.
```

### Interface Mockups

```
┌─────────────────────────────────────────────────────────────┐
│  IRON HAULERS                          DAO #0xDAO1          │
│  ═══════════                                                │
│                                                             │
│  Board Members          Treasury             Charter v1     │
│  ┌───────────┐         ┌──────────┐         ┌───────────┐  │
│  │ ★ Alice   │         │ 250 SUI  │         │ View on   │  │
│  │   Bob     │         │          │         │ Walrus ↗  │  │
│  │   Carol   │         └──────────┘         └───────────┘  │
│  └───────────┘                                              │
│                                                             │
│  SubDAOs                                                    │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  📁 Logistics Dept        Board: Bob, Frank         │    │
│  │     Treasury: 40 SUI      Status: ACTIVE            │    │
│  │     [Manage]  [Reclaim Caps]  [Replace Board]       │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
│  Active Proposals                                           │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  #P5  Expand Proposal Set         2 of 3 voted      │    │
│  │       Threshold: 66%              Expires: 18h       │    │
│  │       [Vote YES]  [Vote NO]  [Details]               │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
│  [+ New Proposal]                                           │
└─────────────────────────────────────────────────────────────┘
```

```
┌─────────────────────────────────────────────────────────────┐
│  CREATE SUBDAO PROPOSAL                                     │
│  ═════════════════════                                      │
│                                                             │
│  SubDAO Name:    [ Logistics Dept_____________ ]            │
│                                                             │
│  Initial Board:                                             │
│    [ 0xBob...  ] [+]                                        │
│    [ 0xDave... ] [+]                                        │
│    [___________] [Add Member]                               │
│                                                             │
│  Initial Funding:                                           │
│    Amount: [ 50    ] SUI                                    │
│    Source: Parent Treasury (250 SUI available)               │
│                                                             │
│  Proposal Config:                                           │
│    Voting window:  [ 72h ]                                  │
│    Approval:       [ 66% ]                                  │
│                                                             │
│  ┌────────────────────────────────────────────┐             │
│  │ This will create a controlled sub-DAO.     │             │
│  │ The parent DAO retains:                    │             │
│  │  • Board replacement authority             │             │
│  │  • Capability reclaim rights               │             │
│  │  • Execution pause/unpause                 │             │
│  └────────────────────────────────────────────┘             │
│                                                             │
│  [Cancel]                           [Submit Proposal]       │
└─────────────────────────────────────────────────────────────┘
```

---

## Flow B — The Gate Builders (Emergence)

### Context

Iron Haulers has a funded treasury and a working governance structure (established in Flow A). Dave, a new recruit, sees an opportunity: three star systems nearby have no jump gates. He proposes a **gate-building project** to the parent DAO. The DAO votes to create a "Gate Builders" sub-DAO, seeds it with treasury funds, and delegates it the authority to deploy and manage gates. Once the gates go live and collect tolls, **revenue flows back up** to the parent treasury.

This is **emergent gameplay**: the protocol doesn't hardcode "ventures," "projects," or "revenue-sharing agreements." Players use the existing DAO/sub-DAO primitives — proposals, treasury funding, capability delegation, charter amendments — to **invent project-based organizations** from the bottom up. The gate-building venture was never designed into the protocol; it emerged from a player's initiative and the composability of the governance primitives.

### Steps

```
Step 1: Dave Pitches the Gate Project
─────────────────────────────────────────────────────────────
Dave proposes a CreateSubDAO to the Iron Haulers board.
The proposal includes a charter describing the project:
build 3 gates, charge tolls, return revenue to parent.

  Proposal #P5 (on Iron Haulers): CreateSubDAO
    name: "Gate Builders"
    initial_board: [Dave, Eve]
    funding: 100 SUI from parent treasury
    charter_blob_id: "walrus://gateproject_v1..."

  Charter excerpt (on Walrus):
    "Gate Builders is a project sub-DAO of Iron Haulers.
     Mission: deploy jump gates connecting Systems A, B, C.
     Revenue policy: 80% of toll revenue flows to parent
     treasury; 20% retained for maintenance and ops.
     Dissolution: parent may reclaim all caps at any time."

  Voting (quorum: 2, threshold: 66%):
    Alice: YES    Bob: YES    Carol: YES
    Result: 3/3 = 100% → PASSED
```

```
Step 2: Gate Builders Sub-DAO Materializes
─────────────────────────────────────────────────────────────
Execution produces:
  - A new DAO #0xDAO3 (Gate Builders)
  - SubDAOControl cap stored in parent's CapabilityVault
  - 100 SUI transferred to Gate Builders treasury

  DAO #0xDAO1 (Iron Haulers)
  ├── TreasuryVault: 150 SUI  (was 250, minus 100 funding)
  ├── CapabilityVault: [SubDAOControl(Logistics), SubDAOControl(Gate Builders)]
  └── Board: [Alice, Bob, Carol]
       │
       ├──► DAO #0xDAO2 (Logistics Dept)    [CONTROLLED]
       │    └── ...
       │
       └──► DAO #0xDAO3 (Gate Builders)     [CONTROLLED]
            ├── TreasuryVault: 100 SUI
            ├── CapabilityVault: empty (no caps yet)
            ├── Board: [Dave, Eve]
            └── Charter: "walrus://gateproject_v1..."
```

```
Step 3: Gate Builders Deploy Infrastructure  [MOCKED — see Flow C note]
─────────────────────────────────────────────────────────────
Dave deploys three Smart Gates and deposits their ownership
caps into the Gate Builders' CapabilityVault.
(Uses mocked gate contracts — see Flow C integration note.)

  PTB:
    1. gate::deploy(system_a, system_b) → GateOwnerCap #0xG1
    2. gate::deploy(system_b, system_c) → GateOwnerCap #0xG2
    3. gate::deploy(system_c, system_a) → GateOwnerCap #0xG3
    4. capability_vault::deposit(#0xCV3, #0xG1)
    5. capability_vault::deposit(#0xCV3, #0xG2)
    6. capability_vault::deposit(#0xCV3, #0xG3)

  Gate Builders CapabilityVault now holds:
    [GateOwnerCap(#0xG1), GateOwnerCap(#0xG2), GateOwnerCap(#0xG3)]
```

```
Step 4: Configure Gates — Tolls Go Live
─────────────────────────────────────────────────────────────
Dave proposes on the Gate Builders sub-DAO to configure
all gates with toll pricing. The sub-DAO votes and executes
autonomously — no parent approval needed.

  Proposal #P6 (on Gate Builders): ConfigureGateAccess
    gates: [#0xG1, #0xG2, #0xG3]
    access_policy:
      iron_haulers_members: FREE
      public: 1 SUI toll per jump

  Voting (on Gate Builders board):
    Dave: YES    Eve: YES → PASSED

  Execution loans each GateOwnerCap from the vault,
  calls gate::set_access_hook, and returns the cap.

  All three gates are now live and charging tolls.
```

```
Step 5: Revenue Flows — Tolls Accumulate
─────────────────────────────────────────────────────────────
Ships start jumping through the gates. Toll payments
accumulate in the Gate Builders treasury.

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
Eve proposes a SendCoin to transfer 40 SUI (80% of 50)
to the Iron Haulers treasury.

  Proposal #P7 (on Gate Builders): SendCoin<SUI>
    recipient: Iron Haulers Treasury (#0xTV1)
    amount: 40 SUI

  Voting:
    Dave: YES    Eve: YES → PASSED

  Iron Haulers treasury: 190 SUI (150 + 40 revenue)
  Gate Builders treasury: 110 SUI (150 - 40 paid up)

  Revenue sharing can be enforced on-chain via a RevenuePolicy
  object — see "Revenue Enforcement Options" below. For the
  demo, we use the split-on-deposit approach. The parent can
  also override the sub-DAO board if terms are violated.
```

```
Step 7: Emergent Self-Modification — Charter Amendment
─────────────────────────────────────────────────────────────
The gate network is thriving. Dave proposes amending the
Gate Builders charter to adjust the revenue split from
80/20 to 70/30 (more retained for expansion).

  Proposal #P8 (on Gate Builders): AmendCharter
    new_charter_blob_id: "walrus://gateproject_v2..."
    description: "Reduce parent share to 70% to fund
                  expansion into Systems D and E"

  Voting:
    Dave: YES    Eve: YES → PASSED

  But wait — the parent DAO may not agree. Alice notices
  the amendment and proposes a parent override:

  Proposal #P9 (on Iron Haulers): privileged_submit
    target: Gate Builders
    action: AmendCharter (revert to 80/20)

  Voting on Iron Haulers board:
    Alice: YES    Bob: NO    Carol: ABSTAIN
    Result: 1/1 = 100% of YES votes... but below quorum?

  The parent board is split. The amendment stands — for now.
  This is emergent negotiation: governance tensions resolved
  through the protocol's own mechanisms, not hardcoded rules.
```

### Revenue Enforcement Options

Three approaches were considered for enforcing revenue-sharing on-chain between a sub-DAO and its parent. All rely on a `RevenuePolicy` object created at sub-DAO inception, controlled by the parent via `SubDAOControl`.

```
struct RevenuePolicy has key, store {
    id: UID,
    parent_treasury: ID,       // where the parent's share goes
    parent_share_bps: u16,     // 8000 = 80%, basis points
    child_treasury: ID,        // where the retained share goes
}
```

**Option A — Split-on-Deposit (Recommended for hackathon)**

The sub-DAO's `treasury::deposit` checks for an attached `RevenuePolicy`. If present, incoming `Coin<T>` is split *before* it enters the sub-DAO treasury — the parent's share is forwarded immediately, and only the retained portion is deposited.

- Simplest implementation, no accounting state
- Tamper-proof: the sub-DAO never touches the parent's share
- Enforcement is transparent and obvious to judges
- Tradeoff: the sub-DAO cannot batch or defer payments — every deposit triggers a split

**Option B — Split-on-Withdrawal with Accounting**

All revenue accumulates in the sub-DAO treasury. A `RevenuePolicy` tracks an `owed_to_parent` counter. Any `SendCoin` proposal execution checks the policy and requires the parent's share to be settled first (or settled as part of the same PTB).

- More flexible: sub-DAO can manage cash flow
- Requires accounting state (`owed_to_parent`, `total_revenue_received`)
- Enforcement point is at withdrawal, not deposit — sub-DAO holds funds in the interim
- Risk: if the sub-DAO's treasury is drained by other proposals before settling, the parent share could be underfunded. Mitigation: reserve a portion of treasury as "encumbered" and block withdrawals that would breach the reserve

**Option C — Revenue Escrow**

Revenue goes into a shared `RevenueSplitEscrow` object (not directly into either treasury). Either party can call `escrow::release()` which splits and distributes to both treasuries according to the policy. No party can extract funds without triggering the split.

- Most trustless — neither party has custody of unsplit funds
- Adds an extra object and interaction step
- Clean separation of concerns: the escrow is a standalone primitive
- Tradeoff: requires the revenue source (e.g., gate tolls) to target the escrow address instead of a treasury directly

**Decision**: Option A (split-on-deposit) for the hackathon demo. Option B or C may be more appropriate for production use where sub-DAOs need cash flow flexibility or where trust assumptions differ.

The `RevenuePolicy` is created during `CreateSubDAO` execution and is immutable from the sub-DAO's perspective. Renegotiation (e.g., the 80/20 → 70/30 amendment in Step 7) requires the parent to update the policy via `privileged_submit`. This turns the charter's revenue terms into an on-chain enforceable constraint while preserving the governance negotiation narrative.

### Interface Mockups

```
┌─────────────────────────────────────────────────────────────┐
│  GATE BUILDERS                         DAO #0xDAO3          │
│  ═════════════                     (SubDAO of Iron Haulers) │
│                                                             │
│  Board Members          Treasury             Charter v2     │
│  ┌───────────┐         ┌──────────┐         ┌───────────┐  │
│  │ ★ Dave    │         │ 110 SUI  │         │ View on   │  │
│  │   Eve     │         │          │         │ Walrus ↗  │  │
│  └───────────┘         └──────────┘         └───────────┘  │
│                                                             │
│  Parent: Iron Haulers (#0xDAO1)    [View Parent]            │
│  Revenue Policy: 80% to parent (charter v1 terms)           │
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
│  Active Proposals                                           │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  #P8  Amend Charter (70/30 split)  PASSED           │    │
│  │       ⚠ Parent override pending — see Iron Haulers  │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
│  [+ New Proposal]  [Configure Gates]  [Pay Parent]          │
└─────────────────────────────────────────────────────────────┘
```

```
┌─────────────────────────────────────────────────────────────┐
│  PROJECT PROPOSAL — CREATE SUBDAO                           │
│  ════════════════════════════════                            │
│                                                             │
│  Project Name:   [ Gate Builders________________ ]          │
│                                                             │
│  Project Charter (uploaded to Walrus):                      │
│  ┌────────────────────────────────────────────────┐         │
│  │  Mission: Deploy jump gates connecting         │         │
│  │  Systems A, B, C.                              │         │
│  │                                                │         │
│  │  Revenue: 80% to parent, 20% retained.         │         │
│  │                                                │         │
│  │  Dissolution: Parent may reclaim all caps.     │         │
│  └────────────────────────────────────────────────┘         │
│  [Edit on Walrus ↗]                                         │
│                                                             │
│  Initial Board:                                             │
│    [ 0xDave... ] [+]                                        │
│    [ 0xEve...  ] [+]                                        │
│    [___________] [Add Member]                               │
│                                                             │
│  Initial Funding:                                           │
│    Amount: [ 100   ] SUI                                    │
│    Source: Parent Treasury (250 SUI available)               │
│                                                             │
│  ┌────────────────────────────────────────────┐             │
│  │ This creates a controlled project sub-DAO. │             │
│  │ The parent DAO retains:                    │             │
│  │  • Board replacement authority             │             │
│  │  • Capability reclaim rights               │             │
│  │  • Charter override via privileged_submit  │             │
│  └────────────────────────────────────────────┘             │
│                                                             │
│  [Cancel]                           [Submit Proposal]       │
└─────────────────────────────────────────────────────────────┘
```

---

## Flow C — Gate Network Franchise (Integration)

### Context

Iron Haulers decides to build a toll gate network connecting three star systems. The DAO holds the **Smart Gate ownership capabilities** in its CapabilityVault. Gate access logic calls back to on-chain DAO state to check membership. Toll revenue flows into the DAO treasury. A third-party logistics DApp reads DAO membership to offer route planning through the gate network.

This demonstrates direct integration with EVE Frontier's **Smart Assemblies** (Gates, SSUs) — the DAO protocol isn't a standalone governance toy but a **composable primitive** that plugs into the game world.

> **Note — Mocked Integration**: The EVE Frontier world contracts currently only
> allow `Character` objects (not arbitrary Sui objects like DAOs) to hold Smart
> Assembly `OwnerCap`s. Object-based custody is flagged as future work by CCP.
>
> For the hackathon demo, we **mock the Smart Assembly modules** (`gate::`, `ssu::`)
> with simplified contracts that allow object-based custody. This lets us demonstrate
> the full DAO-holds-caps-and-loans-them-via-proposals architecture without being
> blocked by the current world contract limitation.
>
> The capability names below (`GateOwnerCap`, `SSUOwnerCap`) are illustrative.
> The pattern — DAO holds caps, proposals loan them for configuration — is
> architecture-stable regardless of final naming or custody model.

### Steps

```
Step 1: DAO Acquires Gate Ownership Capabilities
─────────────────────────────────────────────────────────────
Alice deploys three Smart Gates and transfers their ownership
capabilities into the Iron Haulers CapabilityVault.

  PTB:
    1. gate::deploy(system_a, system_b) → GateOwnerCap #0xG1
    2. gate::deploy(system_b, system_c) → GateOwnerCap #0xG2
    3. gate::deploy(system_c, system_a) → GateOwnerCap #0xG3
    4. capability_vault::deposit(#0xCV1, #0xG1)
    5. capability_vault::deposit(#0xCV1, #0xG2)
    6. capability_vault::deposit(#0xCV1, #0xG3)

  CapabilityVault #0xCV1 now holds:
    [SubDAOControl(Logistics), SubDAOControl(Gate Builders),
     GateOwnerCap(#0xG1), GateOwnerCap(#0xG2), GateOwnerCap(#0xG3)]
```

```
Step 2: Proposal — Configure Gate Access Policy
─────────────────────────────────────────────────────────────
Bob proposes configuring all gates to allow only DAO members
and charge 1 SUI toll per jump for non-members.

  This uses a custom proposal type that loans the GateOwnerCap
  from the vault and calls the gate's configuration function.

  Proposal #P10: ConfigureGateAccess
    gates: [#0xG1, #0xG2, #0xG3]
    access_policy:
      members: FREE
      non_members: 1 SUI toll
      blacklist: [known pirates]

  Voting:
    Alice: YES    Bob: YES    Carol: YES → PASSED
```

```
Step 3: Execute — Gate Access Logic Set On-Chain
─────────────────────────────────────────────────────────────
  PTB (execution):
    1. proposal::execute(#P10)      → ExecutionRequest<ConfigureGateAccess>
    2. cap_vault::loan_cap(#0xCV1, #0xG1) → (GateOwnerCap, CapLoan)
    3. gate::set_access_hook(cap, policy)  // EVE world contract call
    4. cap_vault::return_cap(#0xCV1, cap, loan)
    ... repeat for #0xG2, #0xG3

  The gate's canJump hook now queries:
    fn can_jump(character_id):
      if dao::is_member(#0xDAO1, character_id) → allow (free)
      if has_toll_ticket(character_id)         → allow (paid)
      if blacklisted(character_id)             → deny
      else                                     → charge toll
```

```
Step 4: Toll Revenue Flows Into Treasury
─────────────────────────────────────────────────────────────
As ships jump through the gates, toll payments accumulate.
The gate contract sends toll revenue to the DAO's treasury.

  Event stream:
    gate_jump { gate: #0xG1, jumper: Eve, toll: 1 SUI }
    gate_jump { gate: #0xG2, jumper: Frank, toll: 1 SUI }
    gate_jump { gate: #0xG1, jumper: Grace, toll: 0 SUI (member) }

  Treasury balance: 252 SUI (250 + 2 tolls)

  Revenue is visible on the DAO dashboard and auditable
  on-chain — every toll is a traceable transaction.
```

```
Step 5: Third-Party DApp Integration — Route Planner
─────────────────────────────────────────────────────────────
A logistics DApp ("StarRoutes") queries on-chain state to
offer route planning through DAO-governed gate networks.

  StarRoutes reads:
    1. dao::get_members(#0xDAO1) → membership list
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
Step 6: Delegate Gate Ops to Logistics SubDAO
─────────────────────────────────────────────────────────────
The parent DAO delegates one gate's ownership to the
Logistics SubDAO, letting them manage it independently.

  Proposal #P11 (on Iron Haulers): TransferCapToSubDAO
    capability: GateOwnerCap(#0xG2)
    target_subdao: #0xDAO2 (Logistics Dept)

  Voting: PASSED

  Execution:
    1. Extract GateOwnerCap(#0xG2) from parent vault
    2. Deposit into Logistics SubDAO's CapabilityVault

  Now Logistics can reconfigure Gate #0xG2 autonomously.
  Parent retains reclaim rights via SubDAOControl.
```

```
Step 7: SSU Integration — Tribe Supply Depot
─────────────────────────────────────────────────────────────
Iron Haulers deploys a Smart Storage Unit (SSU) at their
base station. The SSU ownership cap is held in the DAO's
CapabilityVault. Access is governed by DAO membership.

  PTB:
    1. ssu::deploy(station_id) → SSUOwnerCap #0xSSU1
    2. capability_vault::deposit(#0xCV1, #0xSSU1)

  SSU access hook:
    fn can_access(character_id):
      if dao::is_member(#0xDAO1, character_id) → allow
      → deny

  Only Iron Haulers members can deposit/withdraw from
  the tribe supply depot. The same cap vault pattern
  used for gates works for any Smart Assembly type.
```

### Interface Mockups

```
┌─────────────────────────────────────────────────────────────┐
│  GATE NETWORK MANAGEMENT              Iron Haulers DAO      │
│  ═══════════════════════                                    │
│                                                             │
│  Infrastructure Assets (from CapabilityVault)               │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  Gate  System A ↔ B    Owner: This DAO    Status: ● │    │
│  │  #0xG1                 Toll: 1 SUI        Jumps: 47 │    │
│  │  [Configure]  [Delegate to SubDAO]  [View Revenue]  │    │
│  ├─────────────────────────────────────────────────────┤    │
│  │  Gate  System B ↔ C    Owner: Logistics   Status: ● │    │
│  │  #0xG2                 Toll: 1 SUI        Jumps: 23 │    │
│  │  [Reclaim from SubDAO]  [View Revenue]              │    │
│  ├─────────────────────────────────────────────────────┤    │
│  │  Gate  System C ↔ A    Owner: This DAO    Status: ● │    │
│  │  #0xG3                 Toll: 2 SUI        Jumps: 12 │    │
│  │  [Configure]  [Delegate to SubDAO]  [View Revenue]  │    │
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
│  │  DAO Members (Iron Haulers)                    │         │
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
│  Revenue Destination: [ DAO Treasury (#0xTV1)      ▼ ]      │
│                                                             │
│  ┌────────────────────────────────────────────┐             │
│  │ This creates a ConfigureGateAccess proposal │             │
│  │ requiring board approval (66% threshold).   │             │
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
| `dao::create_dao` | ✓ | | |
| `treasury::deposit` | ✓ | | |
| `proposal::create` / `vote` / `execute` | ✓ | ✓ | ✓ |
| `board_ops::handle (SetBoard)` | ✓ | | |
| `subdao_ops::handle (CreateSubDAO)` | ✓ | ✓ | |
| `treasury_ops::handle (SendCoin)` | ✓ | ✓ | |
| `charter_ops::handle (AmendCharter)` | | ✓ | |
| `capability_vault::deposit` | | ✓ | ✓ |
| `capability_vault::loan_cap / return_cap` | | ✓ | ✓ |
| Custom: `ConfigureGateAccess` handler | | ✓ | ✓ |
| `privileged_submit` (parent override) | ✓ | ✓ | |
| `subdao_ops::handle (TransferCapToSubDAO)` | | | ✓ |
| `RevenuePolicy` (split-on-deposit) | | ✓ | |
| Walrus charter upload/read | ✓ | ✓ | |
| Smart Gate integration hooks (mocked) | | ✓ | ✓ |
| Smart SSU integration hooks (mocked) | | | ✓ |
| Third-party DApp read queries | | | ✓ |

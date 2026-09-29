# Tribe Configuration: Proposals Config

This document covers how to pre-configure proposal types for a standard tribe and which types should use the single-vote-execute path for each role.

**Role terminology:**
- **Owners** = the Tribe OU board. Responsible for administering officers, cold-storage of treasury/packages, and all coin creation/mint/burn.
- **Officers** = the Officers SubOU board. Responsible for adding/removing players from the Members role and creating buy/sell orders from the officer treasury.

**Start from `armature_proposals::tribe_setup`.** Its `create_tribe` / `create_tribe_configured` already apply the controller policy in §8 to the Tribe OU and the Officers SubOU (see §3). You only add overrides for the types it does not cover.

---

## 1. How single-vote-execute works

### The `submit_vote_execute` path

`board_voting::submit_vote_execute` (or `submit_vote_execute_readonly`, for
handlers that take `&OU`) bundles proposal creation, a YES vote, and execution
into one PTB. The proposer's YES must pass on its own:

| Condition | Abort if not met |
|-----------|------------------|
| the type is enabled on the OU | `board_voting::ETypeNotEnabled` |
| `execution_delay_ms == 0` in the type's config | `board_voting::EDelayForbidsAtomicExecution` |
| quorum and approval threshold met by the proposer's vote alone | `board_voting::EInsufficientVotingWeight` |

### Voting math (basis points, 1 bps = 0.01%)

```
quorum_met     = (total_voted * 10_000) >= quorum * total_snapshot_weight
threshold_met  = (yes_weight  * 10_000) >= approval_threshold * total_voted
```

For a single owner or officer voting YES on a board of N (weight 1 each):

- `total_voted = 1`, `yes_weight = 1`, `total_snapshot_weight = N`
- quorum passes when `quorum ≤ floor(10_000 / N)`
- threshold always passes because `10_000 ≥ approval_threshold × 1` for any
  `approval_threshold ≤ 10_000`

So **quorum decides whether a type is single-vote**. With the default 50%
quorum, one YES only passes on a board of 1 or 2.

### Canonical single-vote-execute config

```move
proposal::new_config(
    1,            // quorum: 1 bps — any single member reaches quorum
    5000,         // approval_threshold: raise to 8000 for types with an 80% floor (below)
    0,            // propose_threshold: any board member may submit
    3_600_000,    // expiry_ms: 1 hour (framework minimum)
    0,            // execution_delay_ms: REQUIRED for submit_vote_execute
    0,            // cooldown_ms
)
```

> **Floor note.** The framework enforces minimum `approval_threshold` values
> regardless of what you pass in a config override:
>
> | Type | Floor | Impact on single-vote |
> |------|-------|-----------------------|
> | `EnableProposalType` | 8000 (80%), and `quorum × approval_threshold ≥ 8000 × 10000` | Not single-vote except on a 1-member board (§6c) |
> | `UpdateProposalConfig` | 8000 (80%), and `quorum × approval_threshold ≥ 8000 × 10000` | Not single-vote except on a 1-member board |
> | `EnableBypassType` | 8000 (80%), and `quorum × approval_threshold ≥ 8000 × 10000` | Not single-vote except on a 1-member board (see below) |
> | Types holding `TYPE_ADMIN`, `MIGRATE`, `TREASURY_WITHDRAW`, `VAULT_BORROW` or `VAULT_EXTRACT` | 8000 (80%) | Use 8000+; still passes with 1 YES, 0 NO |
> | all others | none | Use 5000 |
>
> An override below its floor makes `create_tribe_configured` abort with
> `EThresholdBelowMinimum`. An `EnableBypassType`, `EnableProposalType` or
> `UpdateProposalConfig` config whose `quorum × approval_threshold` is below
> `8000 × 10000` aborts with `ou::EBypassQuorumTooLow` /
> `ou::EEnableQuorumTooLow` / `ou::EUpdateConfigQuorumTooLow`; all three
> default to quorum 8000, threshold 10000.
>
> A single YES voter with no NO voters always passes a threshold check, so the
> threshold floors only matter when multiple members vote and some vote NO.
> The quorum rule on `EnableBypassType`, `EnableProposalType` and
> `UpdateProposalConfig` is the exception: it forces quorum ≥ 8000, so one YES
> reaches quorum only on a 1-member board (§6c).

### Permission bits

A type from `armature_proposals` or a third-party package only does what its
config's permission bits allow; without them its handler aborts with
`proposal::EPermissionDenied`. Set them with `.with_permissions(bits)` (and
`.with_borrow_scope(scope)` for types that borrow a capability), using the
values in `armature_proposals::type_permissions`. Framework types
(`armature::*`) carry fixed bits; leave their permissions at 0 and the
framework fills them in.

---

## 2. Organizational hierarchy

`create_tribe_configured` wires up three OUs in a fixed parent-controls-child chain:

```
Tribe OU  (Owners board — governs officers, holds treasury/package cold storage)
└── Officers SubOU  (Officers board — manages members, runs trading)
    └── Members SubOU  (Members board — the player roster)
```

- The **Tribe OU (Owners)** board governs the Tribe OU and can add/remove officers via
  `ControllerBatchAddMembers` / `ControllerBatchRemoveMembers`.
- The **Officers SubOU** board governs the Officers SubOU and can add/remove
  members via `ControllerBatchAddMembers` / `ControllerBatchRemoveMembers`.
- A controller type on the Officers OU acts on the Members SubOU by loaning
  the `SubOUControl` stored in the Officers vault; on the Tribe OU, the one
  for the Officers SubOU. Its config needs `type_permissions::subou_control()`
  bits and `subou_control_scope()`.

---

## 3. `create_tribe_configured` call

Overrides are a `vector<ProposalTypeInit>`, one per type, built with
`ou::new_type_init<T>(display_key, config)`. The Move type `T` is what the
OU keys the slot by; the display key is a label for events and UIs. To
override a type the OU enables by default, pass its default display key
(§9) or the call aborts with `EDisplayKeyMismatch`.

`tribe_setup::create_tribe_configured` puts these presets on the Tribe OU and
the Officers SubOU, then applies your overrides after them:

| Type | Preset (threshold 8000 on all) |
|---|---|
| `ControllerBatchAddMembers` | single-vote (quorum 1) |
| `ControllerBatchRemoveMembers` | single-vote (quorum 1) |
| `PauseSubOUExecution` | single-vote (quorum 1) |
| `UnpauseSubOUExecution` | consensus (quorum 5000) |
| `ReclaimCapFromSubOU` | consensus (quorum 5000) |
| `TransferCapToSubOU` | consensus (quorum 5000) |

The controller types carry their bits and borrow scope from `type_permissions`.
An override of a preset type replaces its config but keeps those bits and scope.

```move
use armature::ou::{Self, ProposalTypeInit};
use armature::proposal::{Self, ProposalConfig};
use armature_proposals::tribe_setup;

fun single_vote_config(): ProposalConfig {
    proposal::new_config(1, 5000, 0, 3_600_000, 0, 0)
}

fun single_vote_config_high(approval_threshold: u16): ProposalConfig {
    proposal::new_config(1, approval_threshold, 0, 3_600_000, 0, 0)
}

/// Build the override lists and create the tribe.
public fun deploy_tribe(
    tribe_board: vector<address>,
    officers:    vector<address>,
    members:     vector<address>,
    officer_freeze_admin: address,
    member_freeze_admin:  address,
    ctx: &mut TxContext,
): (ID, ID, ID) {
    tribe_setup::create_tribe_configured(
        tribe_board,
        officers,
        members,
        b"Tribe".to_string(),
        b"Officers".to_string(),
        b"Members".to_string(),
        b"ipfs://<tribe-metadata>".to_string(),    // tribe_metadata_uri
        b"ipfs://<officer-metadata>".to_string(),  // officer_metadata_uri
        b"ipfs://<member-metadata>".to_string(),   // member_metadata_uri
        officer_freeze_admin,
        member_freeze_admin,
        tribe_config_overrides(),
        officer_config_overrides(),
        member_config_overrides(),
        ctx,
    )
}
```

### 3a. Tribe OU (Owners) config overrides

Owners hold governance over officers, coin issuance, package upgrades, and cold treasury. Most actions require owner consensus — single-vote is reserved for low-stakes operational items only.

```move
use armature::transfer_freeze_admin::TransferFreezeAdmin;
use armature::update_metadata::UpdateMetadata;

fun tribe_config_overrides(): vector<ProposalTypeInit> {
    vector[
        // ── Officer management and emergency pause ────────────────────────
        // Preset by tribe_setup: ControllerBatchAdd/RemoveMembers and
        // PauseSubOUExecution single-vote (one owner can seat or remove an
        // officer, or halt the Officers SubOU); UnpauseSubOUExecution needs
        // owner consensus, so a single owner cannot reverse a pause.

        // ── SubOU capability delegation ───────────────────────────────────
        // Preset by tribe_setup: TransferCapToSubOU / ReclaimCapFromSubOU
        // need owner consensus.

        // ── Treasury seeding (owners → officers) ──────────────────────────
        // Coin types registered separately in §4. Owner consensus — not single-vote.

        // ── Metadata ──────────────────────────────────────────────────────
        // Single-vote: cosmetic, low-stakes. Default display key is "CharterUpdate".
        ou::new_type_init<UpdateMetadata>(
            b"CharterUpdate".to_ascii_string(),
            single_vote_config(),
        ),

        // ── Currency (owners are sole mint/burn authority) ────────────────
        // MintAllowance: delegated minting is a bypass (no vote per mint). It is
        // gated by ConfigureMintAllowance<T>: the minter allowlist, a per-call cap
        // enforced by currency_ops::mint_allowance_bypass, and a kill-switch. The
        // governance question is therefore who may change that allowlist.
        // ConfigureMintAllowance must NOT be single-vote: one owner could add
        // themselves as a minter with an unbounded per-call cap. Leave it at
        // default quorum, and enable MintAllowance itself only via EnableBypassType
        // (YES from 80% of the whole Owners board, §6c) with type_permissions::mint()
        // and currency_scope<T>().
        //
        // MintCoin, BurnCoin, AdoptCurrency, ReturnCurrencyCap, ConfigureMintAllowance
        // need owner consensus.

        // ── Security ──────────────────────────────────────────────────────
        // Freeze config changes require owner consensus (default quorum).
        // UnfreezeProposalType also requires consensus: a single owner must not be
        // able to unilaterally reverse an emergency freeze issued by FreezeAdminCap.
        // TransferFreezeAdmin holds only the FREEZE bit (no floor); 6600 is a
        // recommendation, not a requirement.
        ou::new_type_init<TransferFreezeAdmin>(
            b"TransferFreezeAdmin".to_ascii_string(),
            single_vote_config_high(6600),
        ),

        // ── Governance meta ───────────────────────────────────────────────
        // EnableProposalType keeps its default (quorum 8000, threshold 10000):
        // enabling a type needs YES from 80% of the whole Owners board (§6c).
        //
        // EnableBypassType keeps its default (quorum 8000, threshold 10000):
        // it needs YES from 80% of the whole Owners board (§6c).
        //
        // UpdateProposalConfig keeps its default (quorum 8000, threshold 10000):
        // it needs YES from 80% of the whole Owners board. A passed update can
        // reclassify MintCoin, SendCoin, or any other consensus-required type
        // into single-vote, so it is a grant of power like enabling a type.
    ]
}
```

**Owners: what requires consensus (no single-vote)**

| Type | Reason |
|---|---|
| `MintCoin<T>` | Coin issuance — high blast radius |
| `BurnCoin<T>` | Supply contraction — high blast radius |
| `AdoptCurrency<T>` | Takes custody of TreasuryCap — one-time, irreversible direction |
| `ReturnCurrencyCap<T>` | Relinquishes mint/burn authority |
| `ProposeUpgrade` | Package upgrade — high stakes |
| `SendCoin<T>` / `SendCoinToOU<T>` | Large treasury transfers (seeding officers) |
| `UpdateFreezeConfig` | Controls emergency freeze duration |
| `UpdateFreezeExemptTypes` | Controls which types survive a freeze |
| `TransferCapToSubOU` / `ReclaimCapFromSubOU` | Capability delegation |
| `UnpauseSubOUExecution` | Reverses an emergency pause — must not be unilateral |
| `TransferAssets` | Bulk asset movement |
| `SetBoard` | Full board replacement |
| `UnfreezeProposalType` | Reverses out-of-band emergency freeze — must not be unilateral |
| `UpdateProposalConfig` | Can reclassify any type's governance config — needs 80% of the whole board |

> **Why `EnableProposalType` is never single-vote.** Enabling a type can
> grant it any permission bit, including `TREASURY_WITHDRAW` and
> `VAULT_EXTRACT`. An 80% threshold alone counts votes cast, which one YES
> meets on any board, so the framework also requires
> `quorum × approval_threshold ≥ 80%` of the board (§6c). Enable the types an
> OU needs from day one as construction-time overrides instead.

---

### 3b. Officers SubOU config overrides

Officers are an operational hot-path. Single-vote-execute applies to all trading operations (market conditions don't wait for quorum) and routine member management.

```move
fun officer_config_overrides(): vector<ProposalTypeInit> {
    vector[
        // ── Members SubOU management ──────────────────────────────────────
        // Preset by tribe_setup: ControllerBatchAdd/RemoveMembers single-vote.
        // They act on the Members SubOU through the SubOUControl in the
        // Officers vault — the role officers are responsible for managing.
        // AddMember / RemoveMember / BatchAdd* / BatchRemove* act on the
        // Officers board itself and keep default quorum (officer consensus).

        // ── Emergency: pause / unpause the Members SubOU ──────────────────
        // Preset by tribe_setup: PauseSubOUExecution single-vote (fast
        // emergency response); UnpauseSubOUExecution needs officer consensus.

        // ── Officers' own treasury ────────────────────────────────────────
        // SendSmallPayment: rate-limited, safe for single-vote. Coin-specific
        // entries in §4. SendCoin / SendBatchMulticoin: officer consensus.

        // ── Governance meta ───────────────────────────────────────────────
        // EnableProposalType and UpdateProposalConfig keep their defaults: YES
        // from 80% of the whole Officers board. UnfreezeProposalType keeps
        // default quorum (officer consensus).

        // ── Trading proposals (single-vote-execute) ───────────────────────
        // See §6.
    ]
}
```

**Officers: what requires consensus (no single-vote)**

| Type | Reason |
|---|---|
| `AddMember` / `RemoveMember` | Manages the Officers board itself — a single officer must not unilaterally change officer membership |
| `BatchAddMembers` / `BatchRemoveMembers` | Same: bulk changes to the Officers board require officer consensus |
| `UnpauseSubOUExecution` | Reverses an emergency pause — must not be unilateral |
| `SetupTradingAccount` | One-time infrastructure setup — should be deliberate |
| `CreateMulticoinPool` | Creates persistent on-chain pool |
| `SendCoin<T>` / `SendCoinToOU<T>` | Non-trivial treasury transfers |
| `SendBatchMulticoinToAddress` / `SendBatchMulticoinToOU` | Bulk asset movement |
| `SetBoard` | Full board replacement — higher threshold recommended |
| `UnfreezeProposalType` | Reverses an emergency freeze — must not be unilateral |
| `UpdateProposalConfig` | Can reclassify proposal governance — needs 80% of the whole board |

---

### 3c. Members SubOU config overrides

Members manage their own board via standard majority — no single-vote. `tribe_setup` adds nothing to the Members SubOU; it controls no SubOU.

```move
fun member_config_overrides(): vector<ProposalTypeInit> {
    // Standard majority for self-governance; adjust as needed.
    // AddMember and RemoveMember keep the default 50/50 config.
    vector[]
}
```

---

## 4. Treasury proposal configs (coin management)

Treasury types are **generic over coin type** (`SendCoin<T>`, etc.). Each coin
variant is its own proposal type: enable it with its own `ProposalTypeInit`
(or an `EnableProposalType` vote later). All of them withdraw from the
treasury, so their configs need `type_permissions::treasury_spend()` and the
80% threshold floor.

For the Officers SubOU treasury, add each coin to `officer_config_overrides()`:

```move
use armature_proposals::send_small_payment::SendSmallPayment;
use armature_proposals::type_permissions;
use sui::sui::SUI;

// SendSmallPayment: single-vote ok (rate-limited by SmallPaymentState, which
// the handler creates on first use).
ou::new_type_init<SendSmallPayment<SUI>>(
    b"SendSmallPayment<SUI>".to_ascii_string(),
    single_vote_config_high(8000).with_permissions(type_permissions::treasury_spend()),
),

// SendCoin<T> / SendCoinToOU<T>: officer consensus, e.g.
// proposal::new_config(5000, 8000, 0, 604_800_000, 0, 0)
//     .with_permissions(type_permissions::treasury_spend())

// Multicoin batch types are not generic — one entry covers all coins.
// Officer consensus, same bits.
```

> **Summary of treasury proposal types:**
>
> | Type | Generic? | Bits | Single-vote? |
> |------|----------|------|---|
> | `SendCoin<T>` | yes — per coin | `treasury_spend()` | No — officer consensus |
> | `SendCoinToOU<T>` | yes — per coin | `treasury_spend()` | No — officer consensus |
> | `SendSmallPayment<T>` | yes — per coin | `treasury_spend()` | Yes — rate-limited |
> | `SendBatchMulticoinToAddress` | no | `treasury_spend()` | No — officer consensus |
> | `SendBatchMulticoinToOU` | no | `treasury_spend()` | No — officer consensus |

---

## 5. Emergency freeze config (Members SubOU)

Two complementary mechanisms protect the Members SubOU:

### 5a. PauseSubOUExecution (recommended for day-to-day emergencies)

Preset on the Officers SubOU by `tribe_setup` (§3). A single officer can pause
the Members SubOU in one transaction by loaning the `SubOUControl` in the
Officers vault; this sets the Members SubOU's `controller_paused` flag, which
blocks its proposal execution. Unpausing requires officer consensus.

### 5b. Type-level freezing via FreezeAdminCap

The `member_freeze_admin` address passed to `create_tribe_configured` receives
the `FreezeAdminCap` for the Members SubOU. The freeze admin can call
`emergency::freeze_type<P>` to freeze individual proposal types without a vote.

To **transfer** that freeze admin cap via governance (e.g., to a multisig or
different officer), configure `TransferFreezeAdmin` on the Members SubOU:

```move
ou::new_type_init<TransferFreezeAdmin>(
    b"TransferFreezeAdmin".to_ascii_string(),
    // Higher threshold recommended — this transfers permanent freeze authority.
    proposal::new_config(1, 6600, 0, 3_600_000, 0, 0),
),
```

`UnfreezeProposalType` (governance-path unfreeze) and `UpdateFreezeConfig`
(adjust automatic-freeze parameters) can also be pre-configured if needed:

```move
// UnfreezeProposalType must NOT be single-vote: a single member must not
// be able to unilaterally reverse an emergency freeze. Leave it at default
// quorum (consensus required).

// UpdateFreezeConfig must NOT be single-vote. The framework enforces no
// minimum on max_freeze_duration_ms — a value of 0 is accepted, which makes
// every subsequent freeze expire instantly and silently disables the
// FreezeAdminCap circuit breaker. A single compromised member could execute
// this in one PTB, stripping all future freeze protection before anyone can
// react. Leave it at default quorum (consensus required).
```

---

## 6. Trading proposals (armature-trading)

All armature-trading proposal types should be registered on the **Officers SubOU** — trading is an officer responsibility, not an owner one. A type must be enabled before `submit_vote_execute` can use it. Enable the trading types as `officer_config_overrides` at construction: enabling one later takes an `EnableProposalType` vote with YES from 80% of the whole Officers board (§6c).

Each trading type's config needs the permission bits its handler uses — take
them from armature-trading, not from this repo. A type holding an 80%-floor
bit (e.g. `TREASURY_WITHDRAW` for deposits) needs `approval_threshold ≥ 8000`;
with quorum 1 it is still single-vote.

### 6a. Single-vote trading types (all market operations)

All order placement, cancellation, deposit, and sweep operations are single-vote on the Officers SubOU. Market conditions don't wait for quorum.

```move
// T = the trading payload type from armature-trading; BITS = the permission
// bits armature-trading documents for it.
ou::new_type_init<T>(
    b"<DisplayKey>".to_ascii_string(),
    single_vote_config_high(8000).with_permissions(BITS),
),
```

| Type | Kind |
|---|---|
| `DepositCoinToBook<T>` / `DepositMulticoinToBook` | Deposits (treasury → DEX) |
| `PlaceLimitOrder<QuoteAsset>` / `PlaceLimitOrderCoin<Base, Quote>` | Order placement |
| `CancelOrder<QuoteAsset>` / `CancelOrderCoin<Base, Quote>` | Order cancellation |
| `SweepCoinToTreasury<T>` / `SweepMulticoinToTreasury` | Sweeps (DEX → treasury) |

### 6b. Officer-consensus trading types (infrastructure)

These create persistent on-chain state and should not be single-vote. Use
quorum 5000 (e.g. `proposal::new_config(5000, 8000, 0, 604_800_000, 0, 0)`
plus their bits):

- `SetupTradingAccount` — one-time BalanceManager setup, deliberate.
- `CreateMulticoinPool` — creates a persistent pool, deliberate.

### 6c. Registration note

`EnableProposalType` needs YES from 80% of the **whole board**, not 80% of
votes cast. Its threshold floor is 8000, checked on its config at submission
(`board_voting::assert_enable_floor`) and whenever the config is stored. Every
stored config must also satisfy `quorum × approval_threshold ≥ 8000 × 10000`
(else `ou::EEnableQuorumTooLow`), and the default is quorum 8000, threshold
10000. A vote that meets quorum and threshold then has YES from at least 80% of
all board weight.

With the default, the proposal passes as soon as 80% of the board has voted
and every vote is YES; the remaining members need not vote. The trade-off of
the 100% threshold: **a single NO vote means the proposal can never pass.** It
stays Active until it expires, and must then be resubmitted. An OU that would
rather tolerate dissent can override with e.g. quorum 9000, threshold 9000
(81%), at the cost of needing 90% of the board to vote.

Because the threshold is at most 10000, the rule forces quorum ≥ 8000. One YES
on a board of N reaches quorum only if `10 000 ≥ quorum × N`, which holds only
for **N = 1**. On a larger board `submit_vote_execute` on `EnableProposalType`
aborts at submission with `EInsufficientVotingWeight`, and a normal vote with
fewer than 80% of the board voting YES never passes. With the default config on
a board of 3 or 4, every member must vote YES; on a board of 5, four.

This is why trading types belong in the construction-time overrides: once
enabled, any single officer can use a single-vote trading type in one PTB.
`armature_external_type_tests::tribe_e2e_tests` covers both halves with a
stand-in type on three-member boards: one officer, or two of three, cannot
enable a type; the whole board can, and then one officer trades.

**`EnableBypassType` is different.** `external_execution::execute_enable_bypass_type`
checks its 80% floor at execution against the **whole board**:
`yes_weight × 10 000 ≥ 8000 × total_snapshot_weight`. So that no vote can pass
and then fail that check, every `EnableBypassType` config must also satisfy
`quorum × approval_threshold ≥ 8000 × 10000` (else `ou::EBypassQuorumTooLow`),
and the default is quorum 8000, threshold 10000. Any vote that meets quorum and
threshold then has YES from at least 80% of all board weight, not just 80% of
votes cast.

Because the threshold is at most 10000, the rule forces quorum ≥ 8000. One YES
on a board of N reaches quorum only if `10 000 ≥ quorum × N`, which holds only
for **N = 1**. On a larger board `submit_vote_execute` on `EnableBypassType`
aborts at submission with `EInsufficientVotingWeight`; use the normal vote path.
`EnableBypassType` is blocked on SubOUs, so this only affects the Tribe OU.

---

## 7. Types officers should NOT have

| Type | Reason |
|------|-------------------|
| `MintCoin<T>` / `BurnCoin<T>` | Coin issuance is owners-only |
| `AdoptCurrency<T>` / `ReturnCurrencyCap<T>` | TreasuryCap custody is owners-only |
| `MintAllowance<T>` | Delegated mint authority is owners-only |
| `ProposeUpgrade` | Package upgrade authority is owners-only |
| `SpawnOU` | Hierarchy-altering; blocked for SubOUs anyway |
| `SpinOutSubOU` | Makes Officers independent; removes tribe oversight |
| `CreateSubOU` | Blocked for SubOUs |
| `EnableBypassType` | Blocked for SubOUs; bypass authorisation is governance-sensitive |
| `DisableBypassType` | Blocked for SubOUs |
| `TransferAssets` | Migration primitive; should require full tribe vote |

---

## 8. Quick-reference: single-vote eligibility by role

"Preset" means `tribe_setup` configures it; the rest are overrides you add.

| Type | Owners | Officers |
|---|---|---|
| `UpdateMetadata` | Yes | — |
| `MintAllowance<T>` | n/a: bypass type, gated by `ConfigureMintAllowance<T>` (consensus) | No (owners only) |
| `ControllerBatchAddMembers` | Yes (preset, 8000) | Yes (preset, 8000) |
| `ControllerBatchRemoveMembers` | Yes (preset, 8000) | Yes (preset, 8000) |
| `PauseSubOUExecution` | Yes (preset, 8000) | Yes (preset, 8000) |
| `UnpauseSubOUExecution` | No — consensus (preset) | No — consensus (preset) |
| `TransferCapToSubOU` / `ReclaimCapFromSubOU` | No — consensus (preset) | No — consensus (preset) |
| `TransferFreezeAdmin` | Yes (6600) | Yes (6600) |
| `UnfreezeProposalType` | No — consensus | No — consensus |
| `EnableProposalType` | No — 80% of whole board | No — 80% of whole board |
| `UpdateProposalConfig` | No — 80% of whole board | No — 80% of whole board |
| `AddMember` / `RemoveMember` | — | No — manages Officers board itself |
| `BatchAddMembers` / `BatchRemoveMembers` | — | No — manages Officers board itself |
| `SendSmallPayment<T>` | — | Yes (8000) |
| `DepositCoinToBook<T>` | — | Yes |
| `DepositMulticoinToBook` | — | Yes |
| `PlaceLimitOrder<QuoteAsset>` | — | Yes |
| `PlaceLimitOrderCoin<Base, Quote>` | — | Yes |
| `CancelOrder<QuoteAsset>` | — | Yes |
| `CancelOrderCoin<Base, Quote>` | — | Yes |
| `SweepCoinToTreasury<T>` | — | Yes |
| `SweepMulticoinToTreasury` | — | Yes |
| Everything else | No | No |

---

## 9. Display keys

Every OU is created with these types enabled, under these display keys. An
override of one of them must use the same key (`EDisplayKeyMismatch`
otherwise). SubOUs omit `EnableBypassType` and `DisableBypassType`.

```
SetBoard              AddMember             RemoveMember
BatchAddMembers       BatchRemoveMembers    CharterUpdate  (UpdateMetadata)
EnableProposalType    DisableProposalType   UpdateProposalConfig
EnableBypassType      DisableBypassType
TransferFreezeAdmin   UnfreezeProposalType  Composite      (CompositePayload)
```

`tribe_setup` adds these on the Tribe OU and Officers SubOU:

```
ControllerBatchAddMembers     ControllerBatchRemoveMembers
PauseSubOUExecution           UnpauseSubOUExecution
ReclaimCapFromSubOU           TransferCapToSubOU
```

For any other type, you choose the display key when you enable it; it must be
unique per OU (`EDisplayKeyTaken`). The OU keys the slot by the Move type
(`type_name::with_defining_ids<T>()`), so the display key carries no authority
and does not need a package prefix. Use one key per generic instantiation, e.g.
`SendSmallPayment<SUI>`.

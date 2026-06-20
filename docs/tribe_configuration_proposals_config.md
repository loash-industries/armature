P# Tribe Configuration: Proposals Config

This document covers how to pre-configure proposal types for a standard tribe and which types should use the single-vote-execute path for each role.

**Role terminology:**
- **Owners** = the Tribe DAO board. Responsible for administering officers, cold-storage of treasury/packages, and all coin creation/mint/burn.
- **Officers** = the Officers SubDAO board. Responsible for adding/removing players from the Members role and creating buy/sell orders from the officer treasury.

---

## 1. How single-vote-execute works

### The `submit_vote_execute` path

`board_voting::submit_vote_execute` bundles proposal creation, a YES vote, and
execution into one PTB.  Three conditions must hold for it to succeed:

| Condition | Source |
|-----------|--------|
| `execution_delay_ms == 0` in the type's config | enforced at execution time |
| quorum is met by the single voter's weight | `proposal.move:442-445` |
| approval threshold is met (yes% of voters) | `proposal.move:451-455` |

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

### Canonical single-vote-execute config

```move
proposal::new_config(
    1,            // quorum: 1 bps — any single member reaches quorum
    5000,         // approval_threshold: 50% of actual voters (min allowed)
    0,            // propose_threshold: any board member may submit
    3_600_000,    // expiry_ms: 1 hour (framework minimum)
    0,            // execution_delay_ms: REQUIRED for submit_vote_execute
    0,            // cooldown_ms
)
```

> **Floor note.** The framework enforces minimum `approval_threshold` values for
> certain built-in types regardless of what you pass in a config override:
>
> | Type | Floor | Impact on single-vote |
> |------|-------|-----------------------|
> | `EnableProposalType` | 6600 (66%) | Use 6600+; still passes with 1 YES, 0 NO |
> | `UpdateProposalConfig` (self) | 8000 (80%) | Use 8000+; still passes with 1 YES, 0 NO |
> | `EnableBypassType` | 8000 (80%) | Use 8000+; still passes with 1 YES, 0 NO |
> | all others | 5000 (50%) | Use 5000 |
>
> A single YES voter with no NO voters always passes a threshold check, so these
> floors only matter when multiple members vote and some vote NO.

---

## 2. Organizational hierarchy

`create_tribe_configured` wires up three DAOs in a fixed parent-controls-child chain:

```
Tribe DAO  (Owners board — governs officers, holds treasury/package cold storage)
└── Officers SubDAO  (Officers board — manages members, runs trading)
    └── Members SubDAO  (Members board — the player roster)
```

- The **Tribe DAO (Owners)** board governs the Tribe DAO and can add/remove officers via
  `ControllerBatchAddMembers` / `ControllerBatchRemoveMembers`.
- The **Officers SubDAO** board governs the Officers SubDAO and can add/remove
  members via `ControllerBatchAddMembers` / `ControllerBatchRemoveMembers`.
- `ControllerBatch*` on the Officers DAO targets the Members SubDAO by
  presenting the MemberControl cap stored in the Officers vault.

---

## 3. `create_tribe_configured` call

```move
use sui::vec_map::{Self, VecMap};
use std::ascii::String;
use armature_framework::proposal::{Self, ProposalConfig};

fun single_vote_config(): ProposalConfig {
    proposal::new_config(1, 5000, 0, 3_600_000, 0, 0)
}

fun single_vote_config_high(approval_threshold: u16): ProposalConfig {
    proposal::new_config(1, approval_threshold, 0, 3_600_000, 0, 0)
}

/// Build config override maps and call create_tribe_configured.
public fun deploy_tribe(
    tribe_board: vector<address>,
    officers:    vector<address>,
    members:     vector<address>,
    officer_freeze_admin: address,
    member_freeze_admin:  address,
    ctx: &mut TxContext,
): (ID, ID, ID) {
    tribe::create_tribe_configured(
        tribe_board,
        officers,
        members,
        b"Tribe".to_string(),
        b"Officers".to_string(),
        b"Members".to_string(),
        b"Top-level tribe DAO".to_string(),
        b"Officer sub-DAO".to_string(),
        b"Member sub-DAO".to_string(),
        b"".to_string(),  // tribe_image_url
        b"".to_string(),  // officer_image_url
        b"".to_string(),  // member_image_url
        officer_freeze_admin,
        member_freeze_admin,
        tribe_config_overrides(),
        officer_config_overrides(),
        member_config_overrides(),
        ctx,
    )
}
```

### 3a. Tribe DAO (Owners) config overrides

Owners hold governance over officers, coin issuance, package upgrades, and cold treasury. Most actions require owner consensus — single-vote is reserved for low-stakes operational items only.

```move
fun tribe_config_overrides(): VecMap<String, ProposalConfig> {
    let mut m = vec_map::empty();

    // ── Officer management ────────────────────────────────────────────────
    // Add / remove officers board members via the OfficerControl cap.
    // Single-vote: routine operational — one owner should be able to act.
    vec_map::insert(&mut m,
        b"ControllerBatchAddMembers".to_ascii_string(),
        single_vote_config());

    vec_map::insert(&mut m,
        b"ControllerBatchRemoveMembers".to_ascii_string(),
        single_vote_config());

    // ── Emergency: pause / unpause the Officers SubDAO ────────────────────
    // PauseSubDAOExecution: single-vote — fast emergency response should not
    // require quorum. Any one owner can halt officers immediately.
    vec_map::insert(&mut m,
        b"PauseSubDAOExecution".to_ascii_string(),
        single_vote_config());

    // UnpauseSubDAOExecution: requires owner consensus — inherits default quorum.
    // A single owner must not be able to unilaterally reverse an emergency pause
    // (same rationale as UnfreezeProposalType requiring consensus). If any owner
    // could unilaterally unpause, a colluding owner defeats the emergency measure
    // the moment it is applied. Omit from map so it uses default 50/50 quorum.

    // ── SubDAO capability delegation ──────────────────────────────────────
    // Moving caps to/from the officer vault — requires owner consensus.
    // Not single-vote (omit from map; inherits default quorum).
    // Include here only if you want an explicit non-default config:
    // vec_map::insert(&mut m, b"TransferCapToSubDAO".to_ascii_string(), ...);
    // vec_map::insert(&mut m, b"ReclaimCapFromSubDAO".to_ascii_string(), ...);

    // ── Treasury seeding (owners → officers) ─────────────────────────────
    // Coin type keys registered separately in §4.
    // These should require owner consensus — not single-vote.

    // ── Metadata ──────────────────────────────────────────────────────────
    // Single-vote: cosmetic, low-stakes.
    vec_map::insert(&mut m,
        b"UpdateMetadata".to_ascii_string(),
        single_vote_config());

    // ── Currency (owners are sole mint/burn authority) ─────────────────────
    // MintAllowance: single-vote is ONLY safe if the framework enforces a
    // per-grant size ceiling (e.g. MaxMintAllowance in MintAllowanceConfig).
    // Without that ceiling a single owner can issue MintAllowance(u64::MAX),
    // granting unlimited delegated mint authority and bypassing the MintCoin
    // multi-owner consensus requirement entirely.
    //
    // PREREQUISITE: confirm that armature_framework rejects MintAllowance
    // grants exceeding the configured ceiling before enabling single-vote here.
    // Until confirmed, use a consensus config (inherit default quorum by
    // omitting this entry) and add it back once the cap is verified.
    //
    // If the ceiling is confirmed:
    // vec_map::insert(&mut m,
    //     b"<armature_proposals_pkg>::mint_allowance::MintAllowance".to_ascii_string(),
    //     single_vote_config());
    //
    // MintCoin, BurnCoin, AdoptCurrency, ReturnCurrencyCap inherit default quorum.

    // ── Security ──────────────────────────────────────────────────────────
    // Freeze config changes require owner consensus — inherit default quorum.
    // UnfreezeProposalType also requires consensus: a single owner must not be
    // able to unilaterally reverse an emergency freeze issued by FreezeAdminCap.
    vec_map::insert(&mut m,
        b"TransferFreezeAdmin".to_ascii_string(),
        single_vote_config_high(6600));
    // UnfreezeProposalType inherits default quorum (requires owner consensus).

    // ── Governance meta ───────────────────────────────────────────────────
    vec_map::insert(&mut m,
        b"EnableProposalType".to_ascii_string(),
        single_vote_config_high(6600));  // floor-required minimum

    // UpdateProposalConfig inherits default quorum (requires owner consensus).
    // Single-vote would let any one owner reclassify MintCoin, SendCoin, or any
    // other consensus-required type into single-vote, defeating the multi-tier
    // governance design. The 8000 self-update floor is irrelevant here — the
    // risk is updating *other* types' configs, which has only the 5000 floor.

    m
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
| `SendCoin<T>` / `SendCoinToDAO<T>` | Large treasury transfers (seeding officers) |
| `UpdateFreezeConfig` | Controls emergency freeze duration |
| `UpdateFreezeExemptTypes` | Controls which types survive a freeze |
| `TransferCapToSubDAO` / `ReclaimCapFromSubDAO` | Capability delegation |
| `TransferAssets` | Bulk asset movement |
| `SetBoard` | Full board replacement |
| `UnfreezeProposalType` | Reverses out-of-band emergency freeze — must not be unilateral |
| `UpdateProposalConfig` | Can reclassify any type's governance config — single-vote allows downgrading consensus-required types |

---

### 3b. Officers SubDAO config overrides

Officers are an operational hot-path. Single-vote-execute applies to all trading operations (market conditions don't wait for quorum) and routine member management.

```move
fun officer_config_overrides(): VecMap<String, ProposalConfig> {
    let mut m = vec_map::empty();

    // ── Members SubDAO management (single-vote-execute) ───────────────────
    // ControllerBatch* targets the Members SubDAO via the MemberControl cap
    // stored in the Officers vault — this is the role officers are responsible
    // for managing, so single-vote is appropriate.
    // AddMember / RemoveMember / BatchAdd* / BatchRemove* target the Officers
    // board itself and require officer consensus — omitted from this map.
    vec_map::insert(&mut m,
        b"ControllerBatchAddMembers".to_ascii_string(),
        single_vote_config());

    vec_map::insert(&mut m,
        b"ControllerBatchRemoveMembers".to_ascii_string(),
        single_vote_config());

    // ── Emergency: pause / unpause the Members SubDAO ─────────────────────
    // PauseSubDAOExecution: single-vote — fast emergency response.
    vec_map::insert(&mut m,
        b"PauseSubDAOExecution".to_ascii_string(),
        single_vote_config());

    // UnpauseSubDAOExecution: requires officer consensus — inherits default quorum.
    // A single officer must not be able to unilaterally reverse an emergency pause
    // (same rationale as UnfreezeProposalType requiring consensus). Omit from map.

    // ── Officers' own treasury (single-vote-execute) ──────────────────────
    // SendSmallPayment: already rate-limited, safe for single-vote.
    // SendCoin / SendBatchMulticoin: require officer consensus — not single-vote.
    // Coin-type-specific keys registered below in §4.

    // ── Governance meta ───────────────────────────────────────────────────
    vec_map::insert(&mut m,
        b"EnableProposalType".to_ascii_string(),
        single_vote_config_high(6600));

    // UpdateProposalConfig inherits default quorum (requires officer consensus).
    // UnfreezeProposalType inherits default quorum (requires officer consensus).

    // ── Trading proposals (single-vote-execute) ───────────────────────────
    // See §6 for full trading type key registration.

    m
}
```

**Officers: what requires consensus (no single-vote)**

| Type | Reason |
|---|---|
| `AddMember` / `RemoveMember` | Manages the Officers board itself — a single officer must not unilaterally change officer membership |
| `BatchAddMembers` / `BatchRemoveMembers` | Same: bulk changes to the Officers board require officer consensus |
| `SetupTradingAccount` | One-time infrastructure setup — should be deliberate |
| `CreateMulticoinPool` | Creates persistent on-chain pool |
| `SendCoin<T>` / `SendCoinToDAO<T>` | Non-trivial treasury transfers |
| `SendBatchMulticoinToAddress` / `SendBatchMulticoinToDAO` | Bulk asset movement |
| `SetBoard` | Full board replacement — higher threshold recommended |
| `UnfreezeProposalType` | Reverses an emergency freeze — must not be unilateral |
| `UpdateProposalConfig` | Can reclassify proposal governance — single-vote allows downgrading consensus-required types |

---

### 3c. Members SubDAO config overrides

Members manage their own board via standard majority — no single-vote.

```move
fun member_config_overrides(): VecMap<String, ProposalConfig> {
    let mut m = vec_map::empty();
    // Standard majority for self-governance; adjust as needed.
    // AddMember and RemoveMember inherit the default 50/50 config.
    m
}
```

---

## 4. Treasury proposal configs (coin management)

Treasury types are **generic over coin type** (`SendCoin<T>`, etc.).  Each coin
variant must be registered as a separate proposal type via `EnableProposalType`
or included as a config override.  The type key is the full Move type name
string: `<pkg_id>::send_coin::SendCoin<<coin_pkg>::<module>::<COIN>`.

For the Officers SubDAO treasury, insert each required coin key into
`officer_config_overrides()`:

```move
// Example: SUI coin key — replace with actual package-id-qualified name.
// The key is produced by std::type_name::with_defining_ids<SendCoin<SUI>>().
// Typically obtained offline and pasted as a constant.

const SEND_COIN_SUI_KEY: vector<u8> =
    b"<armature_proposals_pkg>::send_coin::SendCoin<0x2::sui::SUI>";

// SendSmallPayment: single-vote ok (rate-limited by SmallPaymentState).
vec_map::insert(&mut m,
    b"<armature_proposals_pkg>::send_small_payment::SendSmallPayment<0x2::sui::SUI>"
        .to_ascii_string(),
    single_vote_config());

// SendCoin: officer consensus required (not single-vote).
// SendBatchMulticoin: officer consensus required (not single-vote).

// Multicoin batch (type key is NOT generic — single entry covers all coins):
// These require officer consensus; include with default or explicit quorum config.
```

> **Summary of treasury proposal types and their type-key patterns:**
>
> | Type | Generic? | Key pattern | Single-vote? |
> |------|----------|-------------|---|
> | `SendCoin<T>` | yes — per coin | `<pkg>::send_coin::SendCoin<<coin_pkg>::<mod>::<COIN>` | No — officer consensus |
> | `SendCoinToDAO<T>` | yes — per coin | `<pkg>::send_coin_to_dao::SendCoinToDAO<...>` | No — officer consensus |
> | `SendSmallPayment<T>` | yes — per coin | `<pkg>::send_small_payment::SendSmallPayment<...>` | Yes — rate-limited |
> | `SendBatchMulticoinToAddress` | no | `<pkg>::send_batch_multicoin_to_address::SendBatchMulticoinToAddress` | No — officer consensus |
> | `SendBatchMulticoinToDAO` | no | `<pkg>::send_batch_multicoin_to_dao::SendBatchMulticoinToDAO` | No — officer consensus |

---

## 5. Emergency freeze config (Members SubDAO)

Two complementary mechanisms protect the Members SubDAO:

### 5a. PauseSubDAOExecution (recommended for day-to-day emergencies)

Added to `officer_config_overrides()` in §3b.  A single officer can pause all
execution on the Members SubDAO in one transaction.  Unpausing requires a
separate call.  The `PauseControl` cap must be in the Officers vault.

### 5b. Type-level freezing via FreezeAdminCap

The `member_freeze_admin` address passed to `create_tribe_configured` receives
the `FreezeAdminCap` for the Members SubDAO.  The freeze admin can call
`emergency::freeze_proposal_type` off-chain to freeze individual proposal types
without a vote.

To **transfer** that freeze admin cap via governance (e.g., to a multisig or
different officer), configure `TransferFreezeAdmin` on the Officers SubDAO:

```move
vec_map::insert(&mut m,
    b"TransferFreezeAdmin".to_ascii_string(),
    // Higher threshold recommended — this transfers permanent freeze authority.
    proposal::new_config(1, 6600, 0, 3_600_000, 0, 0));
```

`UnfreezeProposalType` (governance-path unfreeze) and `UpdateFreezeConfig`
(adjust automatic-freeze parameters) can also be pre-configured if officers
need that control:

```move
// UnfreezeProposalType must NOT be single-vote: a single officer must not
// be able to unilaterally reverse an emergency freeze. Omit from this map
// so it inherits default quorum (officer consensus required).

// UpdateFreezeConfig must NOT be single-vote. The framework enforces no
// minimum on max_freeze_duration_ms — a value of 0 is accepted, which makes
// every subsequent freeze expire instantly and silently disables the
// FreezeAdminCap circuit breaker for the Officers SubDAO. A single
// compromised officer could execute this in one PTB, stripping all future
// freeze protection before anyone can react. Omit from this map so it
// inherits default quorum (officer consensus required).
```

---

## 6. Trading proposals (armature-trading)

All armature-trading proposal types should be registered on the **Officers SubDAO** — trading is an officer responsibility, not an owner one. Types must be enabled via `EnableProposalType` before `submit_vote_execute` can use them.

### 6a. Single-vote trading types (all market operations)

All order placement, cancellation, deposit, and sweep operations are single-vote on the Officers SubDAO. Market conditions don't wait for quorum.

```move
// Replace <trading_pkg> with the actual armature-trading package address.

// ── Deposits (treasury → DEX) ─────────────────────────────────────────
vec_map::insert(&mut m,
    b"<trading_pkg>::deposit_coin_to_book::DepositCoinToBook".to_ascii_string(),
    single_vote_config());

vec_map::insert(&mut m,
    b"<trading_pkg>::deposit_multicoin_to_book::DepositMulticoinToBook".to_ascii_string(),
    single_vote_config());

// ── Order placement ───────────────────────────────────────────────────
vec_map::insert(&mut m,
    b"<trading_pkg>::place_limit_order::PlaceLimitOrder".to_ascii_string(),
    single_vote_config());

vec_map::insert(&mut m,
    b"<trading_pkg>::place_limit_order_coin::PlaceLimitOrderCoin".to_ascii_string(),
    single_vote_config());

// ── Order cancellation ────────────────────────────────────────────────
vec_map::insert(&mut m,
    b"<trading_pkg>::cancel_order::CancelOrder".to_ascii_string(),
    single_vote_config());

vec_map::insert(&mut m,
    b"<trading_pkg>::cancel_order_coin::CancelOrderCoin".to_ascii_string(),
    single_vote_config());

// ── Sweeps (DEX → treasury) ───────────────────────────────────────────
vec_map::insert(&mut m,
    b"<trading_pkg>::sweep_coin_to_treasury::SweepCoinToTreasury".to_ascii_string(),
    single_vote_config());

vec_map::insert(&mut m,
    b"<trading_pkg>::sweep_multicoin_to_treasury::SweepMulticoinToTreasury".to_ascii_string(),
    single_vote_config());
```

### 6b. Officer-consensus trading types (infrastructure)

These create persistent on-chain state and should not be single-vote:

```move
// SetupTradingAccount: one-time BalanceManager setup — deliberate.
// vec_map::insert(&mut m,
//     b"<trading_pkg>::setup_trading_account::SetupTradingAccount".to_ascii_string(),
//     <officer-consensus config>);

// CreateMulticoinPool: creates a persistent pool — deliberate.
// vec_map::insert(&mut m,
//     b"<trading_pkg>::create_multicoin_pool::CreateMulticoinPool".to_ascii_string(),
//     <officer-consensus config>);
```

### 6c. Registration note

`EnableProposalType` has two separate checks that both must pass:

1. **Stored `approval_threshold` check** — `yes_weight × 10 000 ≥ approval_threshold × total_voted`.
   With 1 YES, 0 NO (`total_voted = 1`): `10 000 ≥ 6600 × 1`. Passes for any board size. ✓

2. **Hardcoded handler floor** — `yes_weight × 10 000 ≥ 6 600 × total_snapshot_weight`
   (fraction of **all** eligible voters, not votes cast). For a board of N officers where 1 votes YES:
   `10 000 ≥ 6 600 × N`. This only holds for **N = 1**. For N ≥ 2 the proposal passes voting
   (check 1 ✓) but aborts at execution time when the floor fires. ✗

**Consequence:** `submit_vote_execute` on `EnableProposalType` only works for a 1-person board. On a multi-member board the proposal is created, the single vote passes the quorum and approval-threshold checks, but `ticket_from_vote` → `execute_enable_proposal_type` aborts on the floor check. Use a normal multi-member governance vote for initial trading type registration on any board with 2+ members.

---

## 7. Types officers should NOT have

| Type | Reason |
|------|-------------------|
| `MintCoin<T>` / `BurnCoin<T>` | Coin issuance is owners-only |
| `AdoptCurrency<T>` / `ReturnCurrencyCap<T>` | TreasuryCap custody is owners-only |
| `MintAllowance<T>` | Delegated mint authority is owners-only |
| `ProposeUpgrade` | Package upgrade authority is owners-only |
| `SpawnDAO` | Hierarchy-altering; blocked for SubDAOs anyway |
| `SpinOutSubDAO` | Makes Officers independent; removes tribe oversight |
| `CreateSubDAO` | Blocked for SubDAOs |
| `EnableBypassType` | Blocked for SubDAOs; bypass authorisation is governance-sensitive |
| `DisableBypassType` | Blocked for SubDAOs |
| `TransferAssets` | Migration primitive; should require full tribe vote |

---

## 8. Quick-reference: single-vote eligibility by role

| Type | Owners | Officers |
|---|---|---|
| `UpdateMetadata` | Yes | — |
| `MintAllowance<T>` | Only after per-grant cap verified (see §3a) | No (owners only) |
| `ControllerBatchAddMembers` | Yes | Yes |
| `ControllerBatchRemoveMembers` | Yes | Yes |
| `PauseSubDAOExecution` | Yes | Yes |
| `UnpauseSubDAOExecution` | No — consensus | No — consensus |
| `TransferFreezeAdmin` | Yes (6600) | Yes (6600) |
| `UnfreezeProposalType` | No — consensus | No — consensus |
| `EnableProposalType` | Yes (6600) | Yes (6600) |
| `UpdateProposalConfig` | No — consensus | No — consensus |
| `AddMember` / `RemoveMember` | — | No — manages Officers board itself |
| `BatchAddMembers` / `BatchRemoveMembers` | — | No — manages Officers board itself |
| `SendSmallPayment<T>` | — | Yes |
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

## 9. Built-in type key reference

```
// Short keys (built-in, no package prefix needed):
SetBoard                    RemoveMember               AddMember
BatchAddMembers             BatchRemoveMembers
EnableProposalType          DisableProposalType         UpdateProposalConfig
TransferFreezeAdmin         UnfreezeProposalType        UpdateMetadata
ControllerBatchAddMembers   ControllerBatchRemoveMembers
PauseSubDAOExecution        UnpauseSubDAOExecution
TransferCapToSubDAO         ReclaimCapFromSubDAO
CreateSubDAO                SpawnDAO                    SpinOutSubDAO
TransferAssets

// Full qualified keys (external packages — use actual pkg address):
<armature_proposals_pkg>::send_coin::SendCoin<...>
<armature_proposals_pkg>::send_coin_to_dao::SendCoinToDAO<...>
<armature_proposals_pkg>::send_small_payment::SendSmallPayment<...>
<armature_proposals_pkg>::send_batch_multicoin_to_address::SendBatchMulticoinToAddress
<armature_proposals_pkg>::send_batch_multicoin_to_dao::SendBatchMulticoinToDAO
<armature_proposals_pkg>::mint_coin::MintCoin<...>
<armature_proposals_pkg>::mint_allowance::MintAllowance<...>
<armature_proposals_pkg>::burn_coin::BurnCoin<...>
<armature_proposals_pkg>::adopt_currency::AdoptCurrency<...>
<armature_proposals_pkg>::return_currency_cap::ReturnCurrencyCap<...>
<armature_proposals_pkg>::propose_upgrade::ProposeUpgrade
<armature_proposals_pkg>::update_freeze_config::UpdateFreezeConfig
<trading_pkg>::setup_trading_account::SetupTradingAccount
<trading_pkg>::deposit_coin_to_book::DepositCoinToBook<...>
<trading_pkg>::deposit_multicoin_to_book::DepositMulticoinToBook
<trading_pkg>::place_limit_order::PlaceLimitOrder<...>
<trading_pkg>::place_limit_order_coin::PlaceLimitOrderCoin<...>
<trading_pkg>::cancel_order::CancelOrder<...>
<trading_pkg>::cancel_order_coin::CancelOrderCoin<...>
<trading_pkg>::sweep_coin_to_treasury::SweepCoinToTreasury<...>
<trading_pkg>::sweep_multicoin_to_treasury::SweepMulticoinToTreasury
<trading_pkg>::create_multicoin_pool::CreateMulticoinPool<...>
```

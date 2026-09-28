# Package Boundaries: Which Proposal Types Live Where

Armature ships three Move packages that define proposal types, plus one fixture
that stands in for a third party:

| Package | Role | Upgrade cadence |
|---|---|---|
| `armature_framework` | The kernel: DAO objects, the execution engine, and the types that change who may do what | Never touched after a release |
| `armature_proposals` | First-party extension: asset operations on the treasury and capability vault, SubDAO control, upgrades | Frequent |
| `armature_world_bridge` | First-party extension: EVE Frontier world integration (autojoin) | Frequent |
| `armature_external_type_tests` | Test-only fixture shaped like a third-party integrator (`Rebalance<T>`) | Never published |

This page is the rule for deciding where a new proposal type goes, and why the
current inventory sits where it does. It exists because a type's package is a
one-way door: a type's identity is its defining package, so moving a type later
creates a new type that every DAO must re-enable and the indexer must re-key.

## Why the package boundary is the trust boundary

An `ExecutionTicket<P>` can be spent or closed only by the package that
defines `P`: `proposal::ticket_request`, `discharge` and
`external_execution::ticket_from_cap` take `std::internal::Permit<P>`, which
only `P`'s module can mint. A request also carries only the permission bits
and borrow scope `P`'s slot held when it was minted, and every framework
mutator checks them. Three things follow.

- **The framework gives no package special treatment.** Nothing in the
  framework is `public(package)` for another package's benefit.
  `armature_proposals` is, mechanically, a third-party package that Trinary
  happens to author; `Rebalance<T>` has the identical shape. The framework's
  security argument never mentions another package, and that is the property
  every change must preserve.
- **Bits and scopes are the blast radius of a package, not a handler.** Each
  package keeps an `UpgradeCap`. An upgrade can rewrite how every type defined
  in that package spends its request, and a DAO cannot pin a package version.
  Whoever holds the `armature_proposals` upgrade cap can therefore use every
  bit and scope any DAO has granted a proposals-defined type. Keep that cap in
  a DAO vault governed by `ProposeUpgrade`, or make the package immutable per
  release.
- **What "shopping around" now means.** A PTB author cannot shop across types:
  the permit stops them spending another type's ticket, and bits stop a ticket
  reaching resources its type was never granted. Inside a bit, the borrow
  scope stops a `VAULT_BORROW` type reaching caps it was not scoped to. What
  remains is the package-level risk above, and `TREASURY_WITHDRAW`, which still
  covers every coin at any amount (bounded only by handler logic such as
  `spend_guard`).

## The placement rule

Ask these in order. The first "yes" decides.

1. **Does the framework name the type?** The fixed-bits table
   (`dao::framework_permissions`), the fixed borrow scope
   (`dao::framework_borrow_scope`), the undisableable and SubDAO-blocked sets,
   the migration-allowed set, the mandatory freeze exemptions, default seeded
   slots, and the typed composite steps all name types. Anything they name is a
   framework type. No choice.
2. **Does the handler need a package-private framework internal?** Minting an
   `ExternalExecutionCap`, creating DAO objects, constructing a
   `SubDAOControl`. Framework.
3. **Does the type reconfigure the framework's own safety machinery?** The
   emergency freeze is the framework's last line of defence, and its exempt set
   decides which types keep executing while everything else is stopped. That
   must not be editable by a package whose handler might be the thing being
   frozen. All four freeze-governance types are framework types for this
   reason.
4. **Is the handler's own logic the only bound on a high-floor bit?**
   `SendSmallPayment` holds `TREASURY_WITHDRAW` but is rate-limited;
   `MintAllowance` holds `VAULT_BORROW` but is meant to be per-call bounded.
   The framework cannot express such bounds, so the bound is only as
   trustworthy as that package's upgrade key. The *type* stays outside; the
   *bound* becomes a framework primitive (`spend_guard`, the borrow scope).
5. **Otherwise it is an extension type.** First-party versus third-party
   differs only in who holds the upgrade cap and who reviews. The DAO's 80%
   enable vote is the sole trust decision in both cases.

Two standing constraints sit on top of the rule:

- A type's package is a one-way door (see above). Decide placement before the
  fresh publish, not after.
- The framework should be as small as questions 1 to 3 force it to be. Every
  type added to it is code that will not be touched again.

## The inventory

| Types | Bits (scope) | Package | Rule |
|---|---|---|---|
| EnableProposalType, DisableProposalType, UpdateProposalConfig, EnableBypassType, DisableBypassType | TYPE_ADMIN (+ vault) | framework | 1, 2 |
| AddMember, RemoveMember, BatchAddMembers, BatchRemoveMembers, SetBoard, UpdateMetadata | BOARD_*, METADATA | framework | 1 |
| SpawnDAO, CreateSubDAO, SpinOutSubDAO, TransferAssets | MIGRATE, VAULT_*, TREASURY_WITHDRAW; SpinOutSubDAO scoped to `SubDAOControl` | framework | 1 |
| TransferFreezeAdmin, UnfreezeProposalType, UpdateFreezeConfig, UpdateFreezeExemptTypes | FREEZE | framework | 1, 3 |
| AdoptCurrency, MintCoin, MintAllowance, BurnCoin, ReturnCurrencyCap | vault bits, TREASURY_WITHDRAW; borrowers scoped to `TreasuryCap<T>` | proposals | 4, 5 |
| SendCoin, SendCoinToDAO, SendSmallPayment, SendBatchMulticoin* | TREASURY_WITHDRAW | proposals | 4, 5 |
| TransferCapToSubDAO, ReclaimCapFromSubDAO, ControllerBatch*, PauseSubDAOExecution, UnpauseSubDAOExecution | VAULT_EXTRACT / VAULT_BORROW scoped to `SubDAOControl` | proposals | 5 |
| ProposeUpgrade | VAULT_BORROW scoped to `UpgradeCap` | proposals | 5 |
| ConfigureMintAllowance | none (own type-state) | proposals | 5 |
| AutojoinDAO, ConfigureAutojoin | BOARD_ADD / none | world_bridge | 5 |
| Rebalance | none | external tests | third-party template |

## Bypass types

A bypass-capable type is a triple in one module: the payload, a mint entry
that authenticates the caller before calling `external_execution::ticket_from_cap`,
and the handler. The framework enforces "one module" through the permit. The
`ExternalExecutionCap` in the vault is the DAO's opt-in, not a bearer
credential, so the mint entry's check is the whole authorization. The
constructor's visibility is irrelevant: `Rebalance::new` is public and the type
is still safe from outsiders, because nobody outside its module can reach the
mint. An `EnableBypassType` vote is a vote on that module's code.

Two framework rules make this safe by construction rather than by review:

- **Bypass-safe bits.** A bypass-enabled type may never hold TYPE_ADMIN,
  MIGRATE, VAULT_EXTRACT or FREEZE (`external_execution::bypass_forbidden_bits`).
  A path that executes without a vote must not change the authority graph.
  Checked when the bypass is enabled and again on every mint, so a later
  `UpdateProposalConfig` grant cannot open it either.
- **Borrow scope.** A `VAULT_BORROW` type reaches only the cap types in its
  `borrow_scope`, whatever its handler does. `MintAllowance<T>` is scoped to
  `TreasuryCap<T>` and cannot reach the `UpgradeCap` or a `SubDAOControl` in
  the same vault.

First-party reference implementations: `autojoin_ops::autojoin` (world bridge,
authenticates by character ownership and a tribe allowlist) and
`currency_ops::mint_allowance_bypass` (proposals, authenticates by a minter
allowlist and a per-call cap held in `ConfigureMintAllowance` type-state).

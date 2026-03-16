# Stretch: Federation System

> Part of the [stretch features index](00_index.md). Not in hackathon scope.

Federations model peer associations — alliances, trade agreements, mutual defense pacts. Unlike SubDAOs, no member controls another. Membership is voluntary. Authority is collective.

---

## 1. Design Principles

- **Sovereignty preserved.** A federation cannot modify a member's board, access a member's treasury, or override a member's governance.
- **Consent required.** Joining a federation requires a governance decision within the prospective member DAO.
- **Inverse of SubDAO.** Where `SubDAOControl` sits in the *controller's* vault (authority flows down), `FederationSeat` sits in the *member's* vault (membership claims flow up).

## 2. `FederationSeat`

```rust
struct FederationSeat has key, store {
    id:            UID,
    federation_id: ID,
    member_dao_id: ID,
    joined_at_ms:  u64,
}
```

Stored in *member*'s `CapabilityVault`. Non-transferable (`member_dao_id` checked at use).

## 3. Federation Formation (Two-Phase)

**Phase 1: Propose** — One DAO passes `FormFederation`. Creates federation DAO + `FederationInvite` objects + auto-joins.

```rust
struct FormFederation has store {
    federation_metadata:  String,
    federation_charter:   vector<u8>,
    invited_dao_ids:      vector<ID>,
    representative_addrs: vector<address>,
    own_representative:   address,
}

struct FederationInvite has key, store {
    id:             UID,
    federation_id:  ID,
    invited_dao:    ID,
    representative: address,
    expires_at_ms:  u64,
}
```

**Phase 2: Accept** — Each invited DAO passes `JoinFederation` through its own governance.

## 4. Leaving

`LeaveFederation` — extracts and destroys `FederationSeat`, removes representative. No federation approval needed.

## 5. Two-Layer Governance

- **Layer 1:** Representatives vote directly on federation proposals (fast, routine).
- **Layer 2:** `CastFederationVote` — member DAOs pass internal proposals to authorize their representative's vote on high-stakes federation decisions.

```rust
struct CastFederationVote has store {
    federation_id: ID,
    proposal_id:   ID,
    vote:          bool,
    seat_id:       ID,
}
```

## 6. Federation Treasury

The federation DAO has its own `TreasuryVault`. Members fund it through `SendCoinToDAO<T>` proposals.

## 7. Federation Charter

Federation charters carry additional sections: Member Rights, Member Obligations, Admission Criteria, Exit Provisions, Dispute Resolution. High amendment thresholds recommended.

## 8. Invariants

| ID | Invariant |
|---|---|
| F-1 | Managed SubDAOs (`controller_cap_id.is_some()`) cannot join federations |
| F-2 | `FederationSeat` is non-transferable (`member_dao_id` checked at use) |
| F-3 | Federation cannot hold `SubDAOControl` over a member |
| F-4 | SubDAOControl graph must be acyclic |
| F-5 | At most one `FederationSeat` per federation per member |

## 9. Federation-Specific Threats

- **Seat Forgery:** Fails — `FederationSeat` is module-internal, created only by `JoinFederation` handler.
- **Hostile Takeover:** Mitigated by sovereignty (exit right), charter thresholds, two-layer voting.
- **Voting Deadlock:** Mitigated by odd-member design, proposal expiry, charter provisions.
- **Invite Spam:** Mitigated by invite expiry, accepting requires governance.
- **Rogue Representative:** Replaceable via `SetBoard`; critical decisions use `CastFederationVote`.

---

**See also:** [Lateral Composition](07_lateral_composition.md) for how federation membership composes with SubDAO hierarchy.

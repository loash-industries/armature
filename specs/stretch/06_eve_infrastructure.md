# Stretch: EVE Infrastructure Integration

> Part of the [stretch features index](00_index.md). Not in hackathon scope.

These are application-layer patterns built on the DAO framework:

- **Gate Network Ticketing** — Revenue integration with project funding
- **Minehaul** — Logistics coordination as DAO-governed infrastructure
- **Market Infrastructure** — Trade marketplace operated as DAO-governed project
- **Inventory Management** — Storage depot systems with DAO-governed access control
- **ZK Voting** — Anonymous voting via zero-knowledge proofs

Each of these can be implemented as custom proposal types using the [Open Proposal Type Set](11_open_proposal_type_set.md) pattern — third-party packages defining domain-specific proposal payloads and handlers that interact with DAO treasury/vaults via hot-potato-gated public APIs.

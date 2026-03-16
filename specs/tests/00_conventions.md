# Test Conventions

## Naming

```
test_{descriptive_name}
```

- Suffix `_aborts` for expected-failure tests
- Use descriptive names that convey the invariant being tested

Examples:
- `test_governance_type_immutable_after_creation`
- `test_withdraw_exact_balance_removes_field`
- `test_subdao_cannot_enable_spinout_aborts`

## Standard Addresses

```move
const ALICE: address = @0xA;
const BOB:   address = @0xB;
const CAROL: address = @0xC;
const DAVE:  address = @0xD;
const EVE:   address = @0xE;
const FRANK: address = @0xF;
```

## Abort Code Convention

Modules define error constants prefixed by module name:

```move
// governance.move
const EGovernanceTypeImmutable: u64 = 1;

// proposal.move
const ETypeNotEnabled: u64 = 100;
const ENotEligible: u64 = 101;
const EAlreadyVoted: u64 = 102;
const EProposalExpired: u64 = 103;
const ENotPassed: u64 = 104;
const EFrozen: u64 = 105;
const EDelayNotElapsed: u64 = 106;
const ECooldownActive: u64 = 107;
const EControllerPaused: u64 = 108;

// treasury.move
const EInsufficientBalance: u64 = 200;

// capability_vault.move
const ECapNotFound: u64 = 300;
const ECapLoanMismatch: u64 = 301;
const ENotController: u64 = 302;

// dao.move
const ENotActive: u64 = 400;
const ENotMigrating: u64 = 401;
const EVaultsNotEmpty: u64 = 402;

// admin.move
const ESelfReferentialFloor: u64 = 500;
const EEnableFloor: u64 = 501;
const ECannotDisable: u64 = 502;

// subdao_ops.move
const EBlockedType: u64 = 600;
```

## Helper Module Catalog

All tests share a `test_helpers` module (see `01_test_helpers.md`) providing:

| Helper | Purpose |
|--------|---------|
| `setup_dao(scenario, members) → ID` | Create a Board DAO with given members, all defaults enabled |
| `setup_funded_dao(scenario, amount) → ID` | `setup_dao` + deposit `amount` SUI |
| `setup_dao_with_subdao(scenario) → (parent_id, child_id)` | Parent with Alice/Bob/Carol, child with Dave/Eve |
| `create_proposal<P>(scenario, dao_id, payload) → ID` | Submit proposal as first board member |
| `pass_proposal<P>(scenario, proposal_id, voters)` | All voters vote YES, assert Passed |
| `execute_proposal<P>(scenario, proposal_id, dao_id) → ExecutionRequest<P>` | Execute after passage |
| `advance_clock(scenario, ms)` | Fast-forward test clock |
| `assert_balance<T>(scenario, vault_id, expected)` | Check treasury balance |
| `enable_proposal_type<P>(scenario, dao_id, config)` | Enable an opt-in proposal type via full proposal cycle |

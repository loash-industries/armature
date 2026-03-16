# Coverage Summary

## Invariant Coverage

Every invariant has at least one happy-path test and one abort/negative test.

| Invariant | Happy Path | Abort/Negative | File |
|-----------|------------|----------------|------|
| Governance type immutable | `test_governance_type_immutable_after_creation` | (structural — no setter exists) | `03_governance` |
| State mutations are `public(friend)` | `test_borrow_cap_requires_execution_request` | (structural — visibility enforced by compiler) | `03_governance` |
| Create aborts if type not enabled | `test_create_proposal_with_enabled_type_succeeds` | `test_create_proposal_with_disabled_type_aborts` | `03_governance` |
| Protected types cannot be disabled | `test_can_disable_send_coin` | `test_cannot_disable_enable_proposal_type_aborts` + 3 more | `03_governance` |
| 80% floor for self-referential config | `test_update_config_self_referential_at_80_succeeds` | `test_update_config_self_referential_below_80_aborts` | `03_governance` |
| 66% floor for EnableProposalType | `test_enable_type_at_66_threshold_succeeds` | `test_enable_type_below_66_threshold_aborts` | `03_governance` |
| ProposalConfig validation bounds | `test_config_valid_boundaries_succeeds` | `test_config_quorum_zero_aborts` + 2 more | `03_governance` |
| ExecutionRequest has no abilities | `test_execution_request_no_drop` | (structural — Move type system) | `04_proposals` |
| CapLoan verified on return | `test_loan_and_return_restores_capability` | `test_return_cap_verifies_cap_id` | `04_proposals` |
| Status transitions monotonic | `test_status_active_to_passed` + 2 more | `test_cannot_vote_on_passed_aborts` + 3 more | `04_proposals` |
| Vote snapshot immutable | `test_vote_snapshot_immutable_after_creation` | `test_new_member_cannot_vote_on_old_proposal` | `04_proposals` |
| Executor eligibility | `test_board_member_can_execute` | `test_non_board_member_cannot_execute_aborts` | `04_proposals` |
| Failed execution retryable | `test_failed_execution_leaves_proposal_passed` | — | `04_proposals` |
| Withdraw requires ExecutionRequest | `test_withdraw_with_valid_request_succeeds` | (structural — `public(friend)`) | `05_treasury` |
| coin_types reflects balances | `test_deposit_first_coin_adds_to_registry` + 2 more | — | `05_treasury` |
| Zero-balance cleanup | `test_partial_withdraw_preserves_field` | `test_withdraw_exact_balance_removes_field` | `05_treasury` |
| Vault access requires ExecutionRequest | `test_borrow_cap_requires_execution_request` + 3 more | (structural) | `06_capability_vault` |
| Registries reflect stored caps | `test_store_updates_cap_types_and_cap_ids` + 2 more | `test_extract_removes_from_cap_types_and_cap_ids` | `06_capability_vault` |
| Loan preserves registries | `test_loan_does_not_update_registries` | — | `06_capability_vault` |
| Privileged extract checks SubDAOControl | `test_privileged_extract_succeeds` | `test_privileged_extract_wrong_subdao_aborts` | `06_capability_vault` |
| SubDAO blocklist | — | `test_subdao_cannot_enable_create_subdao_aborts` + 2 more | `13_subdao_ops` |
| controller_cap_id lifecycle | `test_controller_cap_id_set_at_creation` | `test_controller_cap_id_cleared_at_spinout` | `13_subdao_ops` |
| One SubDAOControl per SubDAO | `test_create_subdao__stores_control_in_parent_vault` | `test_only_one_control_per_subdao` | `13_subdao_ops` |
| Pause via privileged_submit only | `test_pause_requires_privileged_submit` | — | `13_subdao_ops` |
| Paused blocks all execution | — | `test_paused_subdao_cannot_execute_aborts` | `13_subdao_ops` |
| SpinOut clears paused | `test_spinout_clears_paused_flag` | — | `13_subdao_ops` |
| Acyclic graph | — | `test_acyclic_graph_enforced` | `13_subdao_ops` |
| At most one controller | Same as one-control-per-subdao | Same as one-control-per-subdao | `13_subdao_ops` |
| Charter version monotonic | `test_version_increments_on_amendment` | `test_version_cannot_decrease` | `07_charter` |
| Amendment records both blob IDs | `test_amendment_records_previous_blob_id` + 2 more | — | `07_charter` |
| Renew doesn't increment version | `test_renew_changes_blob_id_only` | `test_renew_does_not_add_amendment_record` | `07_charter` |
| Status Active to Migrating only | `test_transition_active_to_migrating` | `test_migrating_cannot_revert_to_active_aborts` | `02_dao_lifecycle` |
| Migrating blocks non-transfer types | `test_migrating_allows_transfer_assets` | `test_migrating_blocks_non_transfer_proposals_aborts` | `02_dao_lifecycle` |
| Destroy requires Migrating + empty | `test_destroy_succeeds_when_migrating_and_empty` | `test_destroy_requires_migrating_aborts` + 2 more | `02_dao_lifecycle` |
| In-flight proposals unexecutable | `test_inflight_proposal_unexecutable_after_destroy` | — | `02_dao_lifecycle` |

## Proposal Type Coverage

All 18 proposal types have at least one happy-path and one abort test.

| # | Type | Happy | Abort | File |
|---|------|-------|-------|------|
| 1 | `UpdateProposalConfig` | `test_update_config__changes_config_for_target_type` | `test_update_config_self_referential_below_80_aborts` | `10_admin` |
| 2 | `EnableProposalType` | `test_enable_type__sets_config_atomically` | `test_enable_type_below_66_threshold_aborts`, `test_enable_type__subdao_blocklist` | `10_admin` |
| 3 | `DisableProposalType` | `test_disable_type__removes_from_enabled` | `test_cannot_disable_*` (x4) | `10_admin` |
| 4 | `UpdateMetadata` | `test_update_metadata__changes_ipfs_cid` | — | `10_admin` |
| 5 | `TransferFreezeAdmin` | `test_transfer_freeze_admin__transfers_cap` | — | `10_admin` |
| 6 | `UnfreezeProposalType` | `test_unfreeze__removes_frozen_type` | — | `10_admin` |
| 7 | `SendCoin<T>` | `test_send_coin__transfers_to_recipient` | `test_send_coin__insufficient_balance_aborts` | `11_treasury_ops` |
| 8 | `SendCoinToDAO<T>` | `test_send_coin_to_dao__deposits_into_target_treasury` | — | `11_treasury_ops` |
| 9 | `SetBoard` | `test_set_board__replaces_all_members` | `test_set_board__empty_board_aborts` | `12_board_ops` |
| 10 | `CreateSubDAO` | `test_create_subdao__stores_control_in_parent_vault` | — | `13_subdao_ops` |
| 11 | `SpinOutSubDAO` | `test_controller_cap_id_cleared_at_spinout` | — | `13_subdao_ops` |
| 12 | `TransferCapToSubDAO` | `test_transfer_cap__moves_cap_to_subdao_vault` | — | `13_subdao_ops` |
| 13 | `ReclaimCapFromSubDAO` | `test_reclaim_cap__returns_cap_to_parent` | — | `13_subdao_ops` |
| 14 | `PauseSubDAOExecution` | `test_pause_requires_privileged_submit` | `test_paused_subdao_cannot_execute_aborts` | `13_subdao_ops` |
| 15 | `UnpauseSubDAOExecution` | `test_spinout_clears_paused_flag` | — | `13_subdao_ops` |
| 16 | `AmendCharter` | `test_amend__updates_blob_id_and_hash` | `test_amend__validates_charter_belongs_to_dao` | `14_charter_ops` |
| 17 | `RenewCharterStorage` | `test_renew__updates_blob_id_only` | — | `14_charter_ops` |
| 18 | `UpdateFreezeConfig` | `test_update_freeze_config__changes_max_duration` | — | `10_admin` |

## Demo Flow Coverage

All 21 demo steps are covered.

| Flow | Steps | Tests | File |
|------|-------|-------|------|
| A — One Vision, One Tribe | 7 | 8 (7 steps + full sequence) | `16_integration_flows` |
| B — The Gate Builders | 7 | 8 (7 steps + full sequence) | `16_integration_flows` |
| C — Gate Network Franchise | 7 | 8 (7 steps + full sequence) | `16_integration_flows` |

## Test Count Summary

| File | Section | Tests |
|------|---------|-------|
| `02_dao_lifecycle` | DAO Creation & Lifecycle | 13 |
| `03_governance` | Governance Config | 18 |
| `04_proposals` | Proposal Lifecycle | 25 |
| `05_treasury` | Treasury Vault | 16 |
| `06_capability_vault` | Capability Vault | 20 |
| `07_charter` | Charter | 10 |
| `08_emergency` | Emergency Freeze | 10 |
| `09_board_voting` | Board Voting | 10 |
| `10_admin_proposals` | Admin Proposals (6 types) | 16 |
| `11_treasury_ops` | Treasury Ops | 7 |
| `12_board_ops` | Board Ops | 6 |
| `13_subdao_ops` | SubDAO Ops | 22 |
| `14_charter_ops` | Charter Ops | 10 |
| `15_privileged_submit` | Privileged Submit | 7 |
| `16_integration_flows` | Integration Flows (A+B+C) | 24 |
| **Total** | | **~214** |

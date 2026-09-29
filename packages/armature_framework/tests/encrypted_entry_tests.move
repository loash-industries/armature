#[test_only]
module armature::encrypted_entry_tests;

use armature::ou::{Self, OU};
use armature::encrypted_entry::{Self, EncryptedEntry};
use armature::governance;
use armature::proposal;
use std::string;
use sui::test_scenario;

// === Test addresses ===

const ALICE: address = @0xA; // initial board member
const BOB: address = @0xB; // initial board member
const CAROL: address = @0xC; // non-member

// === Dummy proposal type for crafting ExecutionRequests in board-change helpers ===

public struct SetBoardWitness has drop, store {}

// === Helpers ===

#[test_only]
fun create_ou(scenario: &mut test_scenario::Scenario) {
    scenario.next_tx(ALICE);
    let init = governance::init_board(vector[ALICE, BOB]);
    ou::create(
        &init,
        string::utf8(b"Tribe"),
        string::utf8(b"https://example.com/img.png"),
        scenario.ctx(),
    );
}

/// Create two single-member OUs (both ALICE) and return their IDs.
#[test_only]
fun create_two_ous(scenario: &mut test_scenario::Scenario): (ID, ID) {
    scenario.next_tx(ALICE);
    let id1 = {
        let init = governance::init_board(vector[ALICE]);
        ou::create(
            &init,
            string::utf8(b"OU One"),
            string::utf8(b"https://one.example"),
            scenario.ctx(),
        )
    };
    scenario.next_tx(ALICE);
    let id2 = {
        let init = governance::init_board(vector[ALICE]);
        ou::create(
            &init,
            string::utf8(b"OU Two"),
            string::utf8(b"https://two.example"),
            scenario.ctx(),
        )
    };
    (id1, id2)
}

/// Drive a board update through set_board_governance without the full proposal cycle.
/// Crafts an ExecutionRequest with the correct ou_id so the mismatch assert passes.
#[test_only]
fun do_set_board(ou: &mut OU, to_add: vector<address>, to_remove: vector<address>) {
    let req = proposal::new_execution_request_for_testing<SetBoardWitness>(
        ou.id(),
        object::id_from_address(@0xDEAD),
    );
    ou.set_board_governance(to_add, to_remove, &req);
    proposal::consume(req);
}

// ─────────────────────────────────────────────────────────────────────────────
// OU initialisation
// ─────────────────────────────────────────────────────────────────────────────

#[test]
/// New OU initialises encrypt_epoch at 0.
fun test_ou_starts_with_zero_epoch() {
    let mut scenario = test_scenario::begin(ALICE);
    create_ou(&mut scenario);
    scenario.next_tx(ALICE);
    {
        let ou = scenario.take_shared<OU>();
        assert!(ou.encrypt_epoch() == 0);
        test_scenario::return_shared(ou);
    };
    scenario.end();
}

#[test]
/// New OU initialises with an empty entries vector.
fun test_ou_starts_with_empty_entries() {
    let mut scenario = test_scenario::begin(ALICE);
    create_ou(&mut scenario);
    scenario.next_tx(ALICE);
    {
        let ou = scenario.take_shared<OU>();
        assert!(ou.entries().is_empty());
        test_scenario::return_shared(ou);
    };
    scenario.end();
}

// ─────────────────────────────────────────────────────────────────────────────
// is_governance_member
// ─────────────────────────────────────────────────────────────────────────────

#[test]
/// Board members return true; non-members return false.
fun test_is_governance_member_distinguishes_members() {
    let mut scenario = test_scenario::begin(ALICE);
    create_ou(&mut scenario);
    scenario.next_tx(ALICE);
    {
        let ou = scenario.take_shared<OU>();
        assert!(ou.is_governance_member(ALICE));
        assert!(ou.is_governance_member(BOB));
        assert!(!ou.is_governance_member(CAROL));
        test_scenario::return_shared(ou);
    };
    scenario.end();
}

// ─────────────────────────────────────────────────────────────────────────────
// publish_entry
// ─────────────────────────────────────────────────────────────────────────────

#[test]
/// publish_entry shares an EncryptedEntry and appends its ID to ou.entries.
fun test_publish_entry_succeeds() {
    let mut scenario = test_scenario::begin(ALICE);
    create_ou(&mut scenario);

    scenario.next_tx(ALICE);
    {
        let mut ou = scenario.take_shared<OU>();
        encrypted_entry::publish_entry(
            &mut ou,
            string::utf8(b"ipfs://QmExample"),
            string::utf8(b"Secret doc"),
            scenario.ctx(),
        );
        assert!(ou.entries().length() == 1);
        assert!(ou.encrypt_epoch() == 0);
        test_scenario::return_shared(ou);
    };

    // Entry object is shared and fields are correct.
    scenario.next_tx(ALICE);
    {
        let entry = scenario.take_shared<EncryptedEntry>();
        assert!(encrypted_entry::entry_created_by(&entry) == ALICE);
        assert!(encrypted_entry::entry_encrypt_epoch(&entry) == 0);
        assert!(encrypted_entry::entry_location(&entry) == &string::utf8(b"ipfs://QmExample"));
        assert!(encrypted_entry::entry_description(&entry) == &string::utf8(b"Secret doc"));
        test_scenario::return_shared(entry);
    };

    scenario.end();
}

#[test]
/// Any board member can publish an entry.
fun test_publish_entry_any_board_member_can_publish() {
    let mut scenario = test_scenario::begin(ALICE);
    create_ou(&mut scenario);

    scenario.next_tx(BOB);
    {
        let mut ou = scenario.take_shared<OU>();
        encrypted_entry::publish_entry(
            &mut ou,
            string::utf8(b"ipfs://QmBob"),
            string::utf8(b"Bob's doc"),
            scenario.ctx(),
        );
        assert!(ou.entries().length() == 1);
        test_scenario::return_shared(ou);
    };

    scenario.next_tx(BOB);
    {
        let entry = scenario.take_shared<EncryptedEntry>();
        assert!(encrypted_entry::entry_created_by(&entry) == BOB);
        test_scenario::return_shared(entry);
    };

    scenario.end();
}

#[test]
/// Multiple board members can publish; each adds to the entries count.
fun test_publish_entry_multiple_entries_tracked() {
    let mut scenario = test_scenario::begin(ALICE);
    create_ou(&mut scenario);

    scenario.next_tx(ALICE);
    {
        let mut ou = scenario.take_shared<OU>();
        encrypted_entry::publish_entry(
            &mut ou,
            string::utf8(b"ipfs://Qm1"),
            string::utf8(b"Doc 1"),
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    scenario.next_tx(BOB);
    {
        let mut ou = scenario.take_shared<OU>();
        encrypted_entry::publish_entry(
            &mut ou,
            string::utf8(b"ipfs://Qm2"),
            string::utf8(b"Doc 2"),
            scenario.ctx(),
        );
        assert!(ou.entries().length() == 2);
        test_scenario::return_shared(ou);
    };

    scenario.end();
}

#[test]
/// Published entry's ID is stored in ou.entries at index 0.
fun test_publish_entry_id_stored_in_ou_entries() {
    let mut scenario = test_scenario::begin(ALICE);
    create_ou(&mut scenario);

    scenario.next_tx(ALICE);
    {
        let mut ou = scenario.take_shared<OU>();
        encrypted_entry::publish_entry(
            &mut ou,
            string::utf8(b"ipfs://QmA"),
            string::utf8(b"A"),
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    scenario.next_tx(ALICE);
    {
        let ou = scenario.take_shared<OU>();
        let entry = scenario.take_shared<EncryptedEntry>();
        let entry_id = object::id(&entry);
        assert!(ou.entries()[0] == entry_id);
        test_scenario::return_shared(ou);
        test_scenario::return_shared(entry);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = encrypted_entry::ENotMember)]
/// A non-member cannot publish.
fun test_publish_entry_non_member_aborts() {
    let mut scenario = test_scenario::begin(ALICE);
    create_ou(&mut scenario);

    scenario.next_tx(CAROL);
    {
        let mut ou = scenario.take_shared<OU>();
        encrypted_entry::publish_entry(
            &mut ou,
            string::utf8(b"ipfs://QmEvil"),
            string::utf8(b"Unauthorized"),
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = encrypted_entry::EEntriesCapReached)]
/// Publishing a 33rd entry aborts with EEntriesCapReached.
fun test_publish_entry_cap_at_32_aborts() {
    let mut scenario = test_scenario::begin(ALICE);
    create_ou(&mut scenario);

    let mut i = 0u64;
    while (i < 32) {
        scenario.next_tx(ALICE);
        {
            let mut ou = scenario.take_shared<OU>();
            encrypted_entry::publish_entry(
                &mut ou,
                string::utf8(b"ipfs://QmFill"),
                string::utf8(b"Filler"),
                scenario.ctx(),
            );
            test_scenario::return_shared(ou);
        };
        i = i + 1;
    };

    // 33rd publish should abort.
    scenario.next_tx(ALICE);
    {
        let mut ou = scenario.take_shared<OU>();
        encrypted_entry::publish_entry(
            &mut ou,
            string::utf8(b"ipfs://QmOver"),
            string::utf8(b"Over the cap"),
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    scenario.end();
}

// ─────────────────────────────────────────────────────────────────────────────
// edit_entry
// ─────────────────────────────────────────────────────────────────────────────

#[test]
/// edit_entry updates the blob location within the same epoch.
fun test_edit_entry_updates_location() {
    let mut scenario = test_scenario::begin(ALICE);
    create_ou(&mut scenario);

    scenario.next_tx(ALICE);
    {
        let mut ou = scenario.take_shared<OU>();
        encrypted_entry::publish_entry(
            &mut ou,
            string::utf8(b"ipfs://QmOld"),
            string::utf8(b"Doc"),
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    scenario.next_tx(ALICE);
    {
        let ou = scenario.take_shared<OU>();
        let mut entry = scenario.take_shared<EncryptedEntry>();
        encrypted_entry::edit_entry(
            &ou,
            &mut entry,
            string::utf8(b"ipfs://QmNew"),
            scenario.ctx(),
        );
        assert!(encrypted_entry::entry_location(&entry) == &string::utf8(b"ipfs://QmNew"));
        // Epoch is unchanged.
        assert!(encrypted_entry::entry_encrypt_epoch(&entry) == 0);
        test_scenario::return_shared(ou);
        test_scenario::return_shared(entry);
    };

    scenario.end();
}

#[test]
/// Any board member (not just the author) can edit an entry.
fun test_edit_entry_any_board_member_can_edit() {
    let mut scenario = test_scenario::begin(ALICE);
    create_ou(&mut scenario);

    scenario.next_tx(ALICE);
    {
        let mut ou = scenario.take_shared<OU>();
        encrypted_entry::publish_entry(
            &mut ou,
            string::utf8(b"ipfs://QmA"),
            string::utf8(b"Doc"),
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    scenario.next_tx(BOB);
    {
        let ou = scenario.take_shared<OU>();
        let mut entry = scenario.take_shared<EncryptedEntry>();
        encrypted_entry::edit_entry(&ou, &mut entry, string::utf8(b"ipfs://QmB"), scenario.ctx());
        assert!(encrypted_entry::entry_location(&entry) == &string::utf8(b"ipfs://QmB"));
        test_scenario::return_shared(ou);
        test_scenario::return_shared(entry);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = encrypted_entry::ENotMember)]
/// A non-member cannot edit an entry.
fun test_edit_entry_non_member_aborts() {
    let mut scenario = test_scenario::begin(ALICE);
    create_ou(&mut scenario);

    scenario.next_tx(ALICE);
    {
        let mut ou = scenario.take_shared<OU>();
        encrypted_entry::publish_entry(
            &mut ou,
            string::utf8(b"ipfs://QmDoc"),
            string::utf8(b"Doc"),
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    scenario.next_tx(CAROL);
    {
        let ou = scenario.take_shared<OU>();
        let mut entry = scenario.take_shared<EncryptedEntry>();
        encrypted_entry::edit_entry(
            &ou,
            &mut entry,
            string::utf8(b"ipfs://QmEvil"),
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
        test_scenario::return_shared(entry);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = encrypted_entry::EOuMismatch)]
/// edit_entry rejects an entry whose ou_id does not match the OU passed in.
fun test_edit_entry_wrong_ou_aborts() {
    let mut scenario = test_scenario::begin(ALICE);
    let (ou1_id, ou2_id) = create_two_ous(&mut scenario);

    // Publish an entry on OU1.
    scenario.next_tx(ALICE);
    {
        let mut ou1 = scenario.take_shared_by_id<OU>(ou1_id);
        encrypted_entry::publish_entry(
            &mut ou1,
            string::utf8(b"ipfs://QmA"),
            string::utf8(b"Doc"),
            scenario.ctx(),
        );
        test_scenario::return_shared(ou1);
    };

    // Try to edit the OU1 entry using OU2 — should abort with EOuMismatch.
    scenario.next_tx(ALICE);
    {
        let ou2 = scenario.take_shared_by_id<OU>(ou2_id);
        let mut entry = scenario.take_shared<EncryptedEntry>();
        encrypted_entry::edit_entry(&ou2, &mut entry, string::utf8(b"ipfs://QmB"), scenario.ctx());
        test_scenario::return_shared(ou2);
        test_scenario::return_shared(entry);
    };

    scenario.end();
}

// ─────────────────────────────────────────────────────────────────────────────
// update_entry (re-encrypt after epoch rotation)
// ─────────────────────────────────────────────────────────────────────────────

#[test]
/// update_entry succeeds on a stale entry, advancing its epoch to the current one.
fun test_update_entry_succeeds_on_stale_entry() {
    let mut scenario = test_scenario::begin(ALICE);
    create_ou(&mut scenario);

    // Publish at epoch 0.
    scenario.next_tx(ALICE);
    {
        let mut ou = scenario.take_shared<OU>();
        encrypted_entry::publish_entry(
            &mut ou,
            string::utf8(b"ipfs://QmV0"),
            string::utf8(b"Doc"),
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    // Rotate epoch to 1 — entry is now stale.
    scenario.next_tx(ALICE);
    {
        let mut ou = scenario.take_shared<OU>();
        encrypted_entry::rotate_encryption_epoch(&mut ou, scenario.ctx());
        assert!(ou.encrypt_epoch() == 1);
        test_scenario::return_shared(ou);
    };

    // Re-encrypt: update_entry stamps current epoch onto the entry.
    scenario.next_tx(ALICE);
    {
        let ou = scenario.take_shared<OU>();
        let mut entry = scenario.take_shared<EncryptedEntry>();
        assert!(encrypted_entry::entry_encrypt_epoch(&entry) == 0); // stale
        encrypted_entry::update_entry(
            &ou,
            &mut entry,
            string::utf8(b"ipfs://QmV1"),
            scenario.ctx(),
        );
        assert!(encrypted_entry::entry_location(&entry) == &string::utf8(b"ipfs://QmV1"));
        assert!(encrypted_entry::entry_encrypt_epoch(&entry) == 1); // current
        test_scenario::return_shared(ou);
        test_scenario::return_shared(entry);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = encrypted_entry::EEntryNotStale)]
/// update_entry aborts when the entry epoch already matches the OU epoch.
fun test_update_entry_not_stale_aborts() {
    let mut scenario = test_scenario::begin(ALICE);
    create_ou(&mut scenario);

    scenario.next_tx(ALICE);
    {
        let mut ou = scenario.take_shared<OU>();
        encrypted_entry::publish_entry(
            &mut ou,
            string::utf8(b"ipfs://QmA"),
            string::utf8(b"Doc"),
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    // Entry is at epoch 0; OU is also at epoch 0 — not stale.
    scenario.next_tx(ALICE);
    {
        let ou = scenario.take_shared<OU>();
        let mut entry = scenario.take_shared<EncryptedEntry>();
        encrypted_entry::update_entry(
            &ou,
            &mut entry,
            string::utf8(b"ipfs://QmB"),
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
        test_scenario::return_shared(entry);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = encrypted_entry::ENotMember)]
/// A non-member cannot call update_entry.
fun test_update_entry_non_member_aborts() {
    let mut scenario = test_scenario::begin(ALICE);
    create_ou(&mut scenario);

    scenario.next_tx(ALICE);
    {
        let mut ou = scenario.take_shared<OU>();
        encrypted_entry::publish_entry(
            &mut ou,
            string::utf8(b"ipfs://QmA"),
            string::utf8(b"Doc"),
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    scenario.next_tx(ALICE);
    {
        let mut ou = scenario.take_shared<OU>();
        encrypted_entry::rotate_encryption_epoch(&mut ou, scenario.ctx());
        test_scenario::return_shared(ou);
    };

    scenario.next_tx(CAROL);
    {
        let ou = scenario.take_shared<OU>();
        let mut entry = scenario.take_shared<EncryptedEntry>();
        encrypted_entry::update_entry(
            &ou,
            &mut entry,
            string::utf8(b"ipfs://QmEvil"),
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
        test_scenario::return_shared(entry);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = encrypted_entry::EOuMismatch)]
/// update_entry rejects an entry whose ou_id does not match the OU passed in.
fun test_update_entry_wrong_ou_aborts() {
    let mut scenario = test_scenario::begin(ALICE);
    let (ou1_id, ou2_id) = create_two_ous(&mut scenario);

    // Publish on OU1; OU1 epoch is 0.
    scenario.next_tx(ALICE);
    {
        let mut ou1 = scenario.take_shared_by_id<OU>(ou1_id);
        encrypted_entry::publish_entry(
            &mut ou1,
            string::utf8(b"ipfs://QmA"),
            string::utf8(b"Doc"),
            scenario.ctx(),
        );
        test_scenario::return_shared(ou1);
    };

    // EOuMismatch is checked before EEntryNotStale, so no rotation needed.
    // Pass OU2 with the entry from OU1.
    scenario.next_tx(ALICE);
    {
        let ou2 = scenario.take_shared_by_id<OU>(ou2_id);
        let mut entry = scenario.take_shared<EncryptedEntry>();
        encrypted_entry::update_entry(
            &ou2,
            &mut entry,
            string::utf8(b"ipfs://QmB"),
            scenario.ctx(),
        );
        test_scenario::return_shared(ou2);
        test_scenario::return_shared(entry);
    };

    scenario.end();
}

// ─────────────────────────────────────────────────────────────────────────────
// rotate_encryption_epoch (explicit / out-of-band)
// ─────────────────────────────────────────────────────────────────────────────

#[test]
/// rotate_encryption_epoch increments the epoch by exactly 1.
fun test_rotate_encryption_epoch_increments_epoch() {
    let mut scenario = test_scenario::begin(ALICE);
    create_ou(&mut scenario);

    scenario.next_tx(ALICE);
    {
        let mut ou = scenario.take_shared<OU>();
        assert!(ou.encrypt_epoch() == 0);
        encrypted_entry::rotate_encryption_epoch(&mut ou, scenario.ctx());
        assert!(ou.encrypt_epoch() == 1);
        test_scenario::return_shared(ou);
    };

    scenario.end();
}

#[test]
/// Sequential rotations accumulate: 0 → 1 → 2 → 3.
fun test_rotate_encryption_epoch_sequential_increments() {
    let mut scenario = test_scenario::begin(ALICE);
    create_ou(&mut scenario);

    let mut i = 1u64;
    while (i <= 3) {
        scenario.next_tx(ALICE);
        {
            let mut ou = scenario.take_shared<OU>();
            encrypted_entry::rotate_encryption_epoch(&mut ou, scenario.ctx());
            assert!(ou.encrypt_epoch() == i);
            test_scenario::return_shared(ou);
        };
        i = i + 1;
    };

    scenario.end();
}

#[test]
/// Any board member can trigger an explicit epoch rotation.
fun test_rotate_encryption_epoch_any_board_member() {
    let mut scenario = test_scenario::begin(ALICE);
    create_ou(&mut scenario);

    scenario.next_tx(BOB);
    {
        let mut ou = scenario.take_shared<OU>();
        encrypted_entry::rotate_encryption_epoch(&mut ou, scenario.ctx());
        assert!(ou.encrypt_epoch() == 1);
        test_scenario::return_shared(ou);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = encrypted_entry::ENotMember)]
/// A non-member cannot rotate the encryption epoch.
fun test_rotate_encryption_epoch_non_member_aborts() {
    let mut scenario = test_scenario::begin(ALICE);
    create_ou(&mut scenario);

    scenario.next_tx(CAROL);
    {
        let mut ou = scenario.take_shared<OU>();
        encrypted_entry::rotate_encryption_epoch(&mut ou, scenario.ctx());
        test_scenario::return_shared(ou);
    };

    scenario.end();
}

// ─────────────────────────────────────────────────────────────────────────────
// remove_entry
// ─────────────────────────────────────────────────────────────────────────────

#[test]
/// remove_entry deletes the EncryptedEntry and removes its ID from ou.entries.
fun test_remove_entry_succeeds() {
    let mut scenario = test_scenario::begin(ALICE);
    create_ou(&mut scenario);

    scenario.next_tx(ALICE);
    {
        let mut ou = scenario.take_shared<OU>();
        encrypted_entry::publish_entry(
            &mut ou,
            string::utf8(b"ipfs://QmA"),
            string::utf8(b"Doc"),
            scenario.ctx(),
        );
        assert!(ou.entries().length() == 1);
        test_scenario::return_shared(ou);
    };

    scenario.next_tx(ALICE);
    {
        let mut ou = scenario.take_shared<OU>();
        let entry = scenario.take_shared<EncryptedEntry>();
        encrypted_entry::remove_entry(&mut ou, entry, scenario.ctx());
        assert!(ou.entries().is_empty());
        test_scenario::return_shared(ou);
    };

    scenario.end();
}

#[test]
/// After remove, a new publish fills the freed slot (cap is back below 32).
fun test_remove_entry_frees_cap_slot() {
    let mut scenario = test_scenario::begin(ALICE);
    create_ou(&mut scenario);

    // Fill to cap.
    let mut i = 0u64;
    while (i < 32) {
        scenario.next_tx(ALICE);
        {
            let mut ou = scenario.take_shared<OU>();
            encrypted_entry::publish_entry(
                &mut ou,
                string::utf8(b"ipfs://QmFill"),
                string::utf8(b"Filler"),
                scenario.ctx(),
            );
            test_scenario::return_shared(ou);
        };
        i = i + 1;
    };

    // Remove the first entry.
    scenario.next_tx(ALICE);
    {
        let mut ou = scenario.take_shared<OU>();
        // Can only take one entry at a time; take any.
        let entry = scenario.take_shared<EncryptedEntry>();
        encrypted_entry::remove_entry(&mut ou, entry, scenario.ctx());
        assert!(ou.entries().length() == 31);
        test_scenario::return_shared(ou);
    };

    // Now the 32nd publish should succeed.
    scenario.next_tx(ALICE);
    {
        let mut ou = scenario.take_shared<OU>();
        encrypted_entry::publish_entry(
            &mut ou,
            string::utf8(b"ipfs://QmNew"),
            string::utf8(b"New"),
            scenario.ctx(),
        );
        assert!(ou.entries().length() == 32);
        test_scenario::return_shared(ou);
    };

    scenario.end();
}

#[test]
/// Remove one of two entries; the remaining entry's ID stays in ou.entries.
fun test_remove_entry_partial_removal() {
    let mut scenario = test_scenario::begin(ALICE);
    create_ou(&mut scenario);

    let entry1_id: ID;
    let entry2_id: ID;

    scenario.next_tx(ALICE);
    {
        let mut ou = scenario.take_shared<OU>();
        encrypted_entry::publish_entry(
            &mut ou,
            string::utf8(b"ipfs://Qm1"),
            string::utf8(b"Doc 1"),
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };
    scenario.next_tx(ALICE);
    {
        let mut ou = scenario.take_shared<OU>();
        encrypted_entry::publish_entry(
            &mut ou,
            string::utf8(b"ipfs://Qm2"),
            string::utf8(b"Doc 2"),
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    // Capture entry IDs from the shared objects.
    scenario.next_tx(ALICE);
    {
        let e1 = scenario.take_shared<EncryptedEntry>();
        let e2 = scenario.take_shared<EncryptedEntry>();
        entry1_id = object::id(&e1);
        entry2_id = object::id(&e2);
        test_scenario::return_shared(e1);
        test_scenario::return_shared(e2);
    };

    // Remove entry1.
    scenario.next_tx(ALICE);
    {
        let mut ou = scenario.take_shared<OU>();
        let e1 = scenario.take_shared_by_id<EncryptedEntry>(entry1_id);
        encrypted_entry::remove_entry(&mut ou, e1, scenario.ctx());
        assert!(ou.entries().length() == 1);
        // entry2 should still be tracked.
        assert!(ou.entries()[0] == entry2_id);
        test_scenario::return_shared(ou);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = encrypted_entry::ENotMember)]
/// A non-member cannot remove an entry.
fun test_remove_entry_non_member_aborts() {
    let mut scenario = test_scenario::begin(ALICE);
    create_ou(&mut scenario);

    scenario.next_tx(ALICE);
    {
        let mut ou = scenario.take_shared<OU>();
        encrypted_entry::publish_entry(
            &mut ou,
            string::utf8(b"ipfs://QmA"),
            string::utf8(b"Doc"),
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    scenario.next_tx(CAROL);
    {
        let mut ou = scenario.take_shared<OU>();
        let entry = scenario.take_shared<EncryptedEntry>();
        encrypted_entry::remove_entry(&mut ou, entry, scenario.ctx());
        test_scenario::return_shared(ou);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = encrypted_entry::EOuMismatch)]
/// remove_entry rejects an entry belonging to a different OU.
fun test_remove_entry_wrong_ou_aborts() {
    let mut scenario = test_scenario::begin(ALICE);
    let (ou1_id, ou2_id) = create_two_ous(&mut scenario);

    scenario.next_tx(ALICE);
    {
        let mut ou1 = scenario.take_shared_by_id<OU>(ou1_id);
        encrypted_entry::publish_entry(
            &mut ou1,
            string::utf8(b"ipfs://QmA"),
            string::utf8(b"Doc"),
            scenario.ctx(),
        );
        test_scenario::return_shared(ou1);
    };

    scenario.next_tx(ALICE);
    {
        let mut ou2 = scenario.take_shared_by_id<OU>(ou2_id);
        let entry = scenario.take_shared<EncryptedEntry>();
        encrypted_entry::remove_entry(&mut ou2, entry, scenario.ctx());
        test_scenario::return_shared(ou2);
    };

    scenario.end();
}

// ─────────────────────────────────────────────────────────────────────────────
// SetBoard auto-epoch rotation
// ─────────────────────────────────────────────────────────────────────────────

#[test]
/// Removing a board member via SetBoard automatically increments encrypt_epoch.
fun test_setboard_member_removal_auto_rotates_epoch() {
    let mut scenario = test_scenario::begin(ALICE);
    create_ou(&mut scenario);

    // Remove BOB from the board.
    scenario.next_tx(ALICE);
    {
        let mut ou = scenario.take_shared<OU>();
        assert!(ou.encrypt_epoch() == 0);
        do_set_board(&mut ou, vector[], vector[BOB]);
        assert!(ou.encrypt_epoch() == 1);
        test_scenario::return_shared(ou);
    };

    scenario.end();
}

#[test]
/// Adding a new member without removing any does not rotate the epoch.
fun test_setboard_member_addition_does_not_rotate_epoch() {
    let mut scenario = test_scenario::begin(ALICE);
    create_ou(&mut scenario);

    // Add CAROL without removing ALICE or BOB.
    scenario.next_tx(ALICE);
    {
        let mut ou = scenario.take_shared<OU>();
        do_set_board(&mut ou, vector[CAROL], vector[]);
        assert!(ou.encrypt_epoch() == 0);
        test_scenario::return_shared(ou);
    };

    scenario.end();
}

#[test]
/// Replacing the entire board (add + remove) still rotates the epoch.
fun test_setboard_full_replacement_rotates_epoch() {
    let mut scenario = test_scenario::begin(ALICE);
    create_ou(&mut scenario);

    // Replace ALICE + BOB with CAROL only.
    scenario.next_tx(ALICE);
    {
        let mut ou = scenario.take_shared<OU>();
        do_set_board(&mut ou, vector[CAROL], vector[ALICE, BOB]);
        assert!(ou.encrypt_epoch() == 1);
        test_scenario::return_shared(ou);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = governance::ENoBoardChange)]
/// A SetBoard that adds and removes nothing aborts.
fun test_setboard_empty_change_aborts() {
    let mut scenario = test_scenario::begin(ALICE);
    create_ou(&mut scenario);

    scenario.next_tx(ALICE);
    {
        let mut ou = scenario.take_shared<OU>();
        do_set_board(&mut ou, vector[], vector[]);
        test_scenario::return_shared(ou);
    };

    scenario.end();
}

#[test]
/// Multiple sequential removals each increment the epoch by 1.
fun test_setboard_multiple_removals_each_rotate_epoch() {
    let mut scenario = test_scenario::begin(ALICE);

    scenario.next_tx(ALICE);
    {
        let init = governance::init_board(vector[ALICE, BOB, CAROL]);
        ou::create(
            &init,
            string::utf8(b"Multi-member"),
            string::utf8(b"https://example.com"),
            scenario.ctx(),
        );
    };

    // Remove CAROL → epoch 1.
    scenario.next_tx(ALICE);
    {
        let mut ou = scenario.take_shared<OU>();
        do_set_board(&mut ou, vector[], vector[CAROL]);
        assert!(ou.encrypt_epoch() == 1);
        test_scenario::return_shared(ou);
    };

    // Remove BOB → epoch 2.
    scenario.next_tx(ALICE);
    {
        let mut ou = scenario.take_shared<OU>();
        do_set_board(&mut ou, vector[], vector[BOB]);
        assert!(ou.encrypt_epoch() == 2);
        test_scenario::return_shared(ou);
    };

    scenario.end();
}

#[test]
/// After a SetBoard auto-rotation, entries published before the rotation are stale.
fun test_setboard_removal_makes_existing_entries_stale() {
    let mut scenario = test_scenario::begin(ALICE);
    create_ou(&mut scenario);

    // Publish at epoch 0.
    scenario.next_tx(ALICE);
    {
        let mut ou = scenario.take_shared<OU>();
        encrypted_entry::publish_entry(
            &mut ou,
            string::utf8(b"ipfs://QmA"),
            string::utf8(b"Doc"),
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    // Remove BOB — epoch auto-rotates to 1.
    scenario.next_tx(ALICE);
    {
        let mut ou = scenario.take_shared<OU>();
        do_set_board(&mut ou, vector[], vector[BOB]);
        assert!(ou.encrypt_epoch() == 1);
        test_scenario::return_shared(ou);
    };

    // Entry is stale: its epoch (0) != ou epoch (1).
    scenario.next_tx(ALICE);
    {
        let ou = scenario.take_shared<OU>();
        let entry = scenario.take_shared<EncryptedEntry>();
        assert!(encrypted_entry::entry_encrypt_epoch(&entry) == 0);
        assert!(ou.encrypt_epoch() == 1);
        // update_entry should now succeed (entry is stale).
        test_scenario::return_shared(ou);
        test_scenario::return_shared(entry);
    };

    scenario.end();
}

// ─────────────────────────────────────────────────────────────────────────────
// seal_approve
// ─────────────────────────────────────────────────────────────────────────────

#[test]
/// seal_approve succeeds when a board member presents a valid 32-byte OU ID prefix.
fun test_seal_approve_valid_member_and_id() {
    let mut scenario = test_scenario::begin(ALICE);
    create_ou(&mut scenario);

    scenario.next_tx(ALICE);
    {
        let ou = scenario.take_shared<OU>();
        // Build seal ID: ou object ID bytes (32) + zero nonce (32).
        let mut seal_id = object::id_to_bytes(&ou.id());
        let mut i = 0u64;
        while (i < 32) {
            seal_id.push_back(0u8);
            i = i + 1;
        };
        encrypted_entry::seal_approve(seal_id, &ou, scenario.ctx());
        test_scenario::return_shared(ou);
    };

    scenario.end();
}

#[test]
/// Any board member can call seal_approve with a valid ID.
fun test_seal_approve_any_board_member_succeeds() {
    let mut scenario = test_scenario::begin(ALICE);
    create_ou(&mut scenario);

    scenario.next_tx(BOB);
    {
        let ou = scenario.take_shared<OU>();
        let mut seal_id = object::id_to_bytes(&ou.id());
        let mut i = 0u64;
        while (i < 32) { seal_id.push_back(0u8); i = i + 1; };
        encrypted_entry::seal_approve(seal_id, &ou, scenario.ctx());
        test_scenario::return_shared(ou);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = encrypted_entry::EIdTooShort)]
/// seal_approve aborts when the ID vector is shorter than 32 bytes.
fun test_seal_approve_id_too_short_aborts() {
    let mut scenario = test_scenario::begin(ALICE);
    create_ou(&mut scenario);

    scenario.next_tx(ALICE);
    {
        let ou = scenario.take_shared<OU>();
        encrypted_entry::seal_approve(vector[0u8, 1u8, 2u8], &ou, scenario.ctx());
        test_scenario::return_shared(ou);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = encrypted_entry::EOuMismatch)]
/// seal_approve aborts when the first 32 bytes do not match the OU's object ID.
fun test_seal_approve_wrong_prefix_aborts() {
    let mut scenario = test_scenario::begin(ALICE);
    create_ou(&mut scenario);

    scenario.next_tx(ALICE);
    {
        let ou = scenario.take_shared<OU>();
        // 64 zero bytes — will never match the real OU object ID.
        let wrong_id = vector[
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
            0u8,
        ];
        encrypted_entry::seal_approve(wrong_id, &ou, scenario.ctx());
        test_scenario::return_shared(ou);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = encrypted_entry::ENotMember)]
/// seal_approve aborts for a non-member even with a valid ID prefix.
fun test_seal_approve_non_member_aborts() {
    let mut scenario = test_scenario::begin(ALICE);
    create_ou(&mut scenario);

    scenario.next_tx(CAROL);
    {
        let ou = scenario.take_shared<OU>();
        let mut seal_id = object::id_to_bytes(&ou.id());
        let mut i = 0u64;
        while (i < 32) { seal_id.push_back(0u8); i = i + 1; };
        encrypted_entry::seal_approve(seal_id, &ou, scenario.ctx());
        test_scenario::return_shared(ou);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = encrypted_entry::ENotMember)]
/// seal_approve aborts for a removed board member (forward security).
fun test_seal_approve_removed_member_aborts() {
    let mut scenario = test_scenario::begin(ALICE);
    create_ou(&mut scenario);

    // Remove BOB from the board.
    scenario.next_tx(ALICE);
    {
        let mut ou = scenario.take_shared<OU>();
        do_set_board(&mut ou, vector[], vector[BOB]);
        test_scenario::return_shared(ou);
    };

    // BOB now tries to call seal_approve — should abort.
    scenario.next_tx(BOB);
    {
        let ou = scenario.take_shared<OU>();
        let mut seal_id = object::id_to_bytes(&ou.id());
        let mut i = 0u64;
        while (i < 32) { seal_id.push_back(0u8); i = i + 1; };
        encrypted_entry::seal_approve(seal_id, &ou, scenario.ctx());
        test_scenario::return_shared(ou);
    };

    scenario.end();
}

// ─────────────────────────────────────────────────────────────────────────────
// Migration guard
// ─────────────────────────────────────────────────────────────────────────────

#[test, expected_failure(abort_code = ou::EEntriesNotEmpty)]
/// ou::destroy aborts if the OU still has entries — they must be cleared first.
fun test_destroy_with_entries_aborts() {
    use armature::capability_vault::CapabilityVault;
    use armature::charter::Charter;
    use armature::emergency::EmergencyFreeze;
    use armature::treasury_vault::TreasuryVault;

    let mut scenario = test_scenario::begin(ALICE);
    create_ou(&mut scenario);

    // Publish an entry so ou.entries is non-empty.
    scenario.next_tx(ALICE);
    {
        let mut ou = scenario.take_shared<OU>();
        encrypted_entry::publish_entry(
            &mut ou,
            string::utf8(b"ipfs://QmA"),
            string::utf8(b"Doc"),
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    // Transition to Migrating status via a crafted ExecutionRequest.
    scenario.next_tx(ALICE);
    {
        let mut ou = scenario.take_shared<OU>();
        let successor_id = object::id_from_address(@0xBEEF);
        let req = proposal::new_execution_request_for_testing<SetBoardWitness>(
            ou.id(),
            object::id_from_address(@0xDEAD),
        );
        ou.set_migrating(successor_id, &req);
        proposal::consume(req);
        test_scenario::return_shared(ou);
    };

    // Attempt to destroy — should abort because entries is non-empty.
    scenario.next_tx(ALICE);
    {
        let ou = scenario.take_shared<OU>();
        let treasury = scenario.take_shared<TreasuryVault>();
        let vault = scenario.take_shared<CapabilityVault>();
        let charter = scenario.take_shared<Charter>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        ou::destroy(ou, treasury, vault, charter, freeze);
    };

    scenario.end();
}

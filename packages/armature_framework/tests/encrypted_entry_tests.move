#[test_only]
module armature::encrypted_entry_tests;

use armature::dao::{Self, DAO};
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
fun create_dao(scenario: &mut test_scenario::Scenario) {
    scenario.next_tx(ALICE);
    let init = governance::init_board(vector[ALICE, BOB]);
    dao::create(
        &init,
        string::utf8(b"Tribe"),
        string::utf8(b"Test tribe"),
        string::utf8(b"https://example.com/img.png"),
        scenario.ctx(),
    );
}

/// Create two single-member DAOs (both ALICE) and return their IDs.
#[test_only]
fun create_two_daos(scenario: &mut test_scenario::Scenario): (ID, ID) {
    scenario.next_tx(ALICE);
    let id1 = {
        let init = governance::init_board(vector[ALICE]);
        dao::create(
            &init,
            string::utf8(b"DAO One"),
            string::utf8(b"First"),
            string::utf8(b"https://one.example"),
            scenario.ctx(),
        )
    };
    scenario.next_tx(ALICE);
    let id2 = {
        let init = governance::init_board(vector[ALICE]);
        dao::create(
            &init,
            string::utf8(b"DAO Two"),
            string::utf8(b"Second"),
            string::utf8(b"https://two.example"),
            scenario.ctx(),
        )
    };
    (id1, id2)
}

/// Drive a board update through set_board_governance without the full proposal cycle.
/// Crafts an ExecutionRequest with the correct dao_id so the mismatch assert passes.
#[test_only]
fun do_set_board(dao: &mut DAO, new_members: vector<address>) {
    let req = proposal::new_execution_request<SetBoardWitness>(
        dao.id(),
        object::id_from_address(@0xDEAD),
    );
    dao.set_board_governance(new_members, &req);
    proposal::consume(req);
}

// ─────────────────────────────────────────────────────────────────────────────
// DAO initialisation
// ─────────────────────────────────────────────────────────────────────────────

#[test]
/// New DAO initialises encrypt_epoch at 0.
fun test_dao_starts_with_zero_epoch() {
    let mut scenario = test_scenario::begin(ALICE);
    create_dao(&mut scenario);
    scenario.next_tx(ALICE);
    {
        let dao = scenario.take_shared<DAO>();
        assert!(dao.encrypt_epoch() == 0);
        test_scenario::return_shared(dao);
    };
    scenario.end();
}

#[test]
/// New DAO initialises with an empty entries vector.
fun test_dao_starts_with_empty_entries() {
    let mut scenario = test_scenario::begin(ALICE);
    create_dao(&mut scenario);
    scenario.next_tx(ALICE);
    {
        let dao = scenario.take_shared<DAO>();
        assert!(dao.entries().is_empty());
        test_scenario::return_shared(dao);
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
    create_dao(&mut scenario);
    scenario.next_tx(ALICE);
    {
        let dao = scenario.take_shared<DAO>();
        assert!(dao.is_governance_member(ALICE));
        assert!(dao.is_governance_member(BOB));
        assert!(!dao.is_governance_member(CAROL));
        test_scenario::return_shared(dao);
    };
    scenario.end();
}

// ─────────────────────────────────────────────────────────────────────────────
// publish_entry
// ─────────────────────────────────────────────────────────────────────────────

#[test]
/// publish_entry shares an EncryptedEntry and appends its ID to dao.entries.
fun test_publish_entry_succeeds() {
    let mut scenario = test_scenario::begin(ALICE);
    create_dao(&mut scenario);

    scenario.next_tx(ALICE);
    {
        let mut dao = scenario.take_shared<DAO>();
        encrypted_entry::publish_entry(
            &mut dao,
            string::utf8(b"ipfs://QmExample"),
            string::utf8(b"Secret doc"),
            scenario.ctx(),
        );
        assert!(dao.entries().length() == 1);
        assert!(dao.encrypt_epoch() == 0);
        test_scenario::return_shared(dao);
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
    create_dao(&mut scenario);

    scenario.next_tx(BOB);
    {
        let mut dao = scenario.take_shared<DAO>();
        encrypted_entry::publish_entry(
            &mut dao,
            string::utf8(b"ipfs://QmBob"),
            string::utf8(b"Bob's doc"),
            scenario.ctx(),
        );
        assert!(dao.entries().length() == 1);
        test_scenario::return_shared(dao);
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
    create_dao(&mut scenario);

    scenario.next_tx(ALICE);
    {
        let mut dao = scenario.take_shared<DAO>();
        encrypted_entry::publish_entry(
            &mut dao,
            string::utf8(b"ipfs://Qm1"),
            string::utf8(b"Doc 1"),
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(BOB);
    {
        let mut dao = scenario.take_shared<DAO>();
        encrypted_entry::publish_entry(
            &mut dao,
            string::utf8(b"ipfs://Qm2"),
            string::utf8(b"Doc 2"),
            scenario.ctx(),
        );
        assert!(dao.entries().length() == 2);
        test_scenario::return_shared(dao);
    };

    scenario.end();
}

#[test]
/// Published entry's ID is stored in dao.entries at index 0.
fun test_publish_entry_id_stored_in_dao_entries() {
    let mut scenario = test_scenario::begin(ALICE);
    create_dao(&mut scenario);

    scenario.next_tx(ALICE);
    {
        let mut dao = scenario.take_shared<DAO>();
        encrypted_entry::publish_entry(
            &mut dao,
            string::utf8(b"ipfs://QmA"),
            string::utf8(b"A"),
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(ALICE);
    {
        let dao = scenario.take_shared<DAO>();
        let entry = scenario.take_shared<EncryptedEntry>();
        let entry_id = object::id(&entry);
        assert!(dao.entries()[0] == entry_id);
        test_scenario::return_shared(dao);
        test_scenario::return_shared(entry);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = encrypted_entry::ENotMember)]
/// A non-member cannot publish.
fun test_publish_entry_non_member_aborts() {
    let mut scenario = test_scenario::begin(ALICE);
    create_dao(&mut scenario);

    scenario.next_tx(CAROL);
    {
        let mut dao = scenario.take_shared<DAO>();
        encrypted_entry::publish_entry(
            &mut dao,
            string::utf8(b"ipfs://QmEvil"),
            string::utf8(b"Unauthorized"),
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = encrypted_entry::EEntriesCapReached)]
/// Publishing a 33rd entry aborts with EEntriesCapReached.
fun test_publish_entry_cap_at_32_aborts() {
    let mut scenario = test_scenario::begin(ALICE);
    create_dao(&mut scenario);

    let mut i = 0u64;
    while (i < 32) {
        scenario.next_tx(ALICE);
        {
            let mut dao = scenario.take_shared<DAO>();
            encrypted_entry::publish_entry(
                &mut dao,
                string::utf8(b"ipfs://QmFill"),
                string::utf8(b"Filler"),
                scenario.ctx(),
            );
            test_scenario::return_shared(dao);
        };
        i = i + 1;
    };

    // 33rd publish should abort.
    scenario.next_tx(ALICE);
    {
        let mut dao = scenario.take_shared<DAO>();
        encrypted_entry::publish_entry(
            &mut dao,
            string::utf8(b"ipfs://QmOver"),
            string::utf8(b"Over the cap"),
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
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
    create_dao(&mut scenario);

    scenario.next_tx(ALICE);
    {
        let mut dao = scenario.take_shared<DAO>();
        encrypted_entry::publish_entry(
            &mut dao,
            string::utf8(b"ipfs://QmOld"),
            string::utf8(b"Doc"),
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(ALICE);
    {
        let dao = scenario.take_shared<DAO>();
        let mut entry = scenario.take_shared<EncryptedEntry>();
        encrypted_entry::edit_entry(
            &dao,
            &mut entry,
            string::utf8(b"ipfs://QmNew"),
            scenario.ctx(),
        );
        assert!(encrypted_entry::entry_location(&entry) == &string::utf8(b"ipfs://QmNew"));
        // Epoch is unchanged.
        assert!(encrypted_entry::entry_encrypt_epoch(&entry) == 0);
        test_scenario::return_shared(dao);
        test_scenario::return_shared(entry);
    };

    scenario.end();
}

#[test]
/// Any board member (not just the author) can edit an entry.
fun test_edit_entry_any_board_member_can_edit() {
    let mut scenario = test_scenario::begin(ALICE);
    create_dao(&mut scenario);

    scenario.next_tx(ALICE);
    {
        let mut dao = scenario.take_shared<DAO>();
        encrypted_entry::publish_entry(
            &mut dao,
            string::utf8(b"ipfs://QmA"),
            string::utf8(b"Doc"),
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(BOB);
    {
        let dao = scenario.take_shared<DAO>();
        let mut entry = scenario.take_shared<EncryptedEntry>();
        encrypted_entry::edit_entry(&dao, &mut entry, string::utf8(b"ipfs://QmB"), scenario.ctx());
        assert!(encrypted_entry::entry_location(&entry) == &string::utf8(b"ipfs://QmB"));
        test_scenario::return_shared(dao);
        test_scenario::return_shared(entry);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = encrypted_entry::ENotMember)]
/// A non-member cannot edit an entry.
fun test_edit_entry_non_member_aborts() {
    let mut scenario = test_scenario::begin(ALICE);
    create_dao(&mut scenario);

    scenario.next_tx(ALICE);
    {
        let mut dao = scenario.take_shared<DAO>();
        encrypted_entry::publish_entry(
            &mut dao,
            string::utf8(b"ipfs://QmDoc"),
            string::utf8(b"Doc"),
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CAROL);
    {
        let dao = scenario.take_shared<DAO>();
        let mut entry = scenario.take_shared<EncryptedEntry>();
        encrypted_entry::edit_entry(
            &dao,
            &mut entry,
            string::utf8(b"ipfs://QmEvil"),
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
        test_scenario::return_shared(entry);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = encrypted_entry::EDaoMismatch)]
/// edit_entry rejects an entry whose dao_id does not match the DAO passed in.
fun test_edit_entry_wrong_dao_aborts() {
    let mut scenario = test_scenario::begin(ALICE);
    let (dao1_id, dao2_id) = create_two_daos(&mut scenario);

    // Publish an entry on DAO1.
    scenario.next_tx(ALICE);
    {
        let mut dao1 = scenario.take_shared_by_id<DAO>(dao1_id);
        encrypted_entry::publish_entry(
            &mut dao1,
            string::utf8(b"ipfs://QmA"),
            string::utf8(b"Doc"),
            scenario.ctx(),
        );
        test_scenario::return_shared(dao1);
    };

    // Try to edit the DAO1 entry using DAO2 — should abort with EDaoMismatch.
    scenario.next_tx(ALICE);
    {
        let dao2 = scenario.take_shared_by_id<DAO>(dao2_id);
        let mut entry = scenario.take_shared<EncryptedEntry>();
        encrypted_entry::edit_entry(&dao2, &mut entry, string::utf8(b"ipfs://QmB"), scenario.ctx());
        test_scenario::return_shared(dao2);
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
    create_dao(&mut scenario);

    // Publish at epoch 0.
    scenario.next_tx(ALICE);
    {
        let mut dao = scenario.take_shared<DAO>();
        encrypted_entry::publish_entry(
            &mut dao,
            string::utf8(b"ipfs://QmV0"),
            string::utf8(b"Doc"),
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    // Rotate epoch to 1 — entry is now stale.
    scenario.next_tx(ALICE);
    {
        let mut dao = scenario.take_shared<DAO>();
        encrypted_entry::rotate_encryption_epoch(&mut dao, scenario.ctx());
        assert!(dao.encrypt_epoch() == 1);
        test_scenario::return_shared(dao);
    };

    // Re-encrypt: update_entry stamps current epoch onto the entry.
    scenario.next_tx(ALICE);
    {
        let dao = scenario.take_shared<DAO>();
        let mut entry = scenario.take_shared<EncryptedEntry>();
        assert!(encrypted_entry::entry_encrypt_epoch(&entry) == 0); // stale
        encrypted_entry::update_entry(
            &dao,
            &mut entry,
            string::utf8(b"ipfs://QmV1"),
            scenario.ctx(),
        );
        assert!(encrypted_entry::entry_location(&entry) == &string::utf8(b"ipfs://QmV1"));
        assert!(encrypted_entry::entry_encrypt_epoch(&entry) == 1); // current
        test_scenario::return_shared(dao);
        test_scenario::return_shared(entry);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = encrypted_entry::EEntryNotStale)]
/// update_entry aborts when the entry epoch already matches the DAO epoch.
fun test_update_entry_not_stale_aborts() {
    let mut scenario = test_scenario::begin(ALICE);
    create_dao(&mut scenario);

    scenario.next_tx(ALICE);
    {
        let mut dao = scenario.take_shared<DAO>();
        encrypted_entry::publish_entry(
            &mut dao,
            string::utf8(b"ipfs://QmA"),
            string::utf8(b"Doc"),
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    // Entry is at epoch 0; DAO is also at epoch 0 — not stale.
    scenario.next_tx(ALICE);
    {
        let dao = scenario.take_shared<DAO>();
        let mut entry = scenario.take_shared<EncryptedEntry>();
        encrypted_entry::update_entry(
            &dao,
            &mut entry,
            string::utf8(b"ipfs://QmB"),
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
        test_scenario::return_shared(entry);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = encrypted_entry::ENotMember)]
/// A non-member cannot call update_entry.
fun test_update_entry_non_member_aborts() {
    let mut scenario = test_scenario::begin(ALICE);
    create_dao(&mut scenario);

    scenario.next_tx(ALICE);
    {
        let mut dao = scenario.take_shared<DAO>();
        encrypted_entry::publish_entry(
            &mut dao,
            string::utf8(b"ipfs://QmA"),
            string::utf8(b"Doc"),
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(ALICE);
    {
        let mut dao = scenario.take_shared<DAO>();
        encrypted_entry::rotate_encryption_epoch(&mut dao, scenario.ctx());
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CAROL);
    {
        let dao = scenario.take_shared<DAO>();
        let mut entry = scenario.take_shared<EncryptedEntry>();
        encrypted_entry::update_entry(
            &dao,
            &mut entry,
            string::utf8(b"ipfs://QmEvil"),
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
        test_scenario::return_shared(entry);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = encrypted_entry::EDaoMismatch)]
/// update_entry rejects an entry whose dao_id does not match the DAO passed in.
fun test_update_entry_wrong_dao_aborts() {
    let mut scenario = test_scenario::begin(ALICE);
    let (dao1_id, dao2_id) = create_two_daos(&mut scenario);

    // Publish on DAO1; DAO1 epoch is 0.
    scenario.next_tx(ALICE);
    {
        let mut dao1 = scenario.take_shared_by_id<DAO>(dao1_id);
        encrypted_entry::publish_entry(
            &mut dao1,
            string::utf8(b"ipfs://QmA"),
            string::utf8(b"Doc"),
            scenario.ctx(),
        );
        test_scenario::return_shared(dao1);
    };

    // EDaoMismatch is checked before EEntryNotStale, so no rotation needed.
    // Pass DAO2 with the entry from DAO1.
    scenario.next_tx(ALICE);
    {
        let dao2 = scenario.take_shared_by_id<DAO>(dao2_id);
        let mut entry = scenario.take_shared<EncryptedEntry>();
        encrypted_entry::update_entry(
            &dao2,
            &mut entry,
            string::utf8(b"ipfs://QmB"),
            scenario.ctx(),
        );
        test_scenario::return_shared(dao2);
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
    create_dao(&mut scenario);

    scenario.next_tx(ALICE);
    {
        let mut dao = scenario.take_shared<DAO>();
        assert!(dao.encrypt_epoch() == 0);
        encrypted_entry::rotate_encryption_epoch(&mut dao, scenario.ctx());
        assert!(dao.encrypt_epoch() == 1);
        test_scenario::return_shared(dao);
    };

    scenario.end();
}

#[test]
/// Sequential rotations accumulate: 0 → 1 → 2 → 3.
fun test_rotate_encryption_epoch_sequential_increments() {
    let mut scenario = test_scenario::begin(ALICE);
    create_dao(&mut scenario);

    let mut i = 1u64;
    while (i <= 3) {
        scenario.next_tx(ALICE);
        {
            let mut dao = scenario.take_shared<DAO>();
            encrypted_entry::rotate_encryption_epoch(&mut dao, scenario.ctx());
            assert!(dao.encrypt_epoch() == i);
            test_scenario::return_shared(dao);
        };
        i = i + 1;
    };

    scenario.end();
}

#[test]
/// Any board member can trigger an explicit epoch rotation.
fun test_rotate_encryption_epoch_any_board_member() {
    let mut scenario = test_scenario::begin(ALICE);
    create_dao(&mut scenario);

    scenario.next_tx(BOB);
    {
        let mut dao = scenario.take_shared<DAO>();
        encrypted_entry::rotate_encryption_epoch(&mut dao, scenario.ctx());
        assert!(dao.encrypt_epoch() == 1);
        test_scenario::return_shared(dao);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = encrypted_entry::ENotMember)]
/// A non-member cannot rotate the encryption epoch.
fun test_rotate_encryption_epoch_non_member_aborts() {
    let mut scenario = test_scenario::begin(ALICE);
    create_dao(&mut scenario);

    scenario.next_tx(CAROL);
    {
        let mut dao = scenario.take_shared<DAO>();
        encrypted_entry::rotate_encryption_epoch(&mut dao, scenario.ctx());
        test_scenario::return_shared(dao);
    };

    scenario.end();
}

// ─────────────────────────────────────────────────────────────────────────────
// remove_entry
// ─────────────────────────────────────────────────────────────────────────────

#[test]
/// remove_entry deletes the EncryptedEntry and removes its ID from dao.entries.
fun test_remove_entry_succeeds() {
    let mut scenario = test_scenario::begin(ALICE);
    create_dao(&mut scenario);

    scenario.next_tx(ALICE);
    {
        let mut dao = scenario.take_shared<DAO>();
        encrypted_entry::publish_entry(
            &mut dao,
            string::utf8(b"ipfs://QmA"),
            string::utf8(b"Doc"),
            scenario.ctx(),
        );
        assert!(dao.entries().length() == 1);
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(ALICE);
    {
        let mut dao = scenario.take_shared<DAO>();
        let entry = scenario.take_shared<EncryptedEntry>();
        encrypted_entry::remove_entry(&mut dao, entry, scenario.ctx());
        assert!(dao.entries().is_empty());
        test_scenario::return_shared(dao);
    };

    scenario.end();
}

#[test]
/// After remove, a new publish fills the freed slot (cap is back below 32).
fun test_remove_entry_frees_cap_slot() {
    let mut scenario = test_scenario::begin(ALICE);
    create_dao(&mut scenario);

    // Fill to cap.
    let mut i = 0u64;
    while (i < 32) {
        scenario.next_tx(ALICE);
        {
            let mut dao = scenario.take_shared<DAO>();
            encrypted_entry::publish_entry(
                &mut dao,
                string::utf8(b"ipfs://QmFill"),
                string::utf8(b"Filler"),
                scenario.ctx(),
            );
            test_scenario::return_shared(dao);
        };
        i = i + 1;
    };

    // Remove the first entry.
    scenario.next_tx(ALICE);
    {
        let mut dao = scenario.take_shared<DAO>();
        // Can only take one entry at a time; take any.
        let entry = scenario.take_shared<EncryptedEntry>();
        encrypted_entry::remove_entry(&mut dao, entry, scenario.ctx());
        assert!(dao.entries().length() == 31);
        test_scenario::return_shared(dao);
    };

    // Now the 32nd publish should succeed.
    scenario.next_tx(ALICE);
    {
        let mut dao = scenario.take_shared<DAO>();
        encrypted_entry::publish_entry(
            &mut dao,
            string::utf8(b"ipfs://QmNew"),
            string::utf8(b"New"),
            scenario.ctx(),
        );
        assert!(dao.entries().length() == 32);
        test_scenario::return_shared(dao);
    };

    scenario.end();
}

#[test]
/// Remove one of two entries; the remaining entry's ID stays in dao.entries.
fun test_remove_entry_partial_removal() {
    let mut scenario = test_scenario::begin(ALICE);
    create_dao(&mut scenario);

    let entry1_id: ID;
    let entry2_id: ID;

    scenario.next_tx(ALICE);
    {
        let mut dao = scenario.take_shared<DAO>();
        encrypted_entry::publish_entry(
            &mut dao,
            string::utf8(b"ipfs://Qm1"),
            string::utf8(b"Doc 1"),
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };
    scenario.next_tx(ALICE);
    {
        let mut dao = scenario.take_shared<DAO>();
        encrypted_entry::publish_entry(
            &mut dao,
            string::utf8(b"ipfs://Qm2"),
            string::utf8(b"Doc 2"),
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
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
        let mut dao = scenario.take_shared<DAO>();
        let e1 = scenario.take_shared_by_id<EncryptedEntry>(entry1_id);
        encrypted_entry::remove_entry(&mut dao, e1, scenario.ctx());
        assert!(dao.entries().length() == 1);
        // entry2 should still be tracked.
        assert!(dao.entries()[0] == entry2_id);
        test_scenario::return_shared(dao);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = encrypted_entry::ENotMember)]
/// A non-member cannot remove an entry.
fun test_remove_entry_non_member_aborts() {
    let mut scenario = test_scenario::begin(ALICE);
    create_dao(&mut scenario);

    scenario.next_tx(ALICE);
    {
        let mut dao = scenario.take_shared<DAO>();
        encrypted_entry::publish_entry(
            &mut dao,
            string::utf8(b"ipfs://QmA"),
            string::utf8(b"Doc"),
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CAROL);
    {
        let mut dao = scenario.take_shared<DAO>();
        let entry = scenario.take_shared<EncryptedEntry>();
        encrypted_entry::remove_entry(&mut dao, entry, scenario.ctx());
        test_scenario::return_shared(dao);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = encrypted_entry::EDaoMismatch)]
/// remove_entry rejects an entry belonging to a different DAO.
fun test_remove_entry_wrong_dao_aborts() {
    let mut scenario = test_scenario::begin(ALICE);
    let (dao1_id, dao2_id) = create_two_daos(&mut scenario);

    scenario.next_tx(ALICE);
    {
        let mut dao1 = scenario.take_shared_by_id<DAO>(dao1_id);
        encrypted_entry::publish_entry(
            &mut dao1,
            string::utf8(b"ipfs://QmA"),
            string::utf8(b"Doc"),
            scenario.ctx(),
        );
        test_scenario::return_shared(dao1);
    };

    scenario.next_tx(ALICE);
    {
        let mut dao2 = scenario.take_shared_by_id<DAO>(dao2_id);
        let entry = scenario.take_shared<EncryptedEntry>();
        encrypted_entry::remove_entry(&mut dao2, entry, scenario.ctx());
        test_scenario::return_shared(dao2);
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
    create_dao(&mut scenario);

    // Remove BOB from the board.
    scenario.next_tx(ALICE);
    {
        let mut dao = scenario.take_shared<DAO>();
        assert!(dao.encrypt_epoch() == 0);
        do_set_board(&mut dao, vector[ALICE]);
        assert!(dao.encrypt_epoch() == 1);
        test_scenario::return_shared(dao);
    };

    scenario.end();
}

#[test]
/// Adding a new member without removing any does not rotate the epoch.
fun test_setboard_member_addition_does_not_rotate_epoch() {
    let mut scenario = test_scenario::begin(ALICE);
    create_dao(&mut scenario);

    // Add CAROL without removing ALICE or BOB.
    scenario.next_tx(ALICE);
    {
        let mut dao = scenario.take_shared<DAO>();
        do_set_board(&mut dao, vector[ALICE, BOB, CAROL]);
        assert!(dao.encrypt_epoch() == 0);
        test_scenario::return_shared(dao);
    };

    scenario.end();
}

#[test]
/// Replacing the entire board (add + remove) still rotates the epoch.
fun test_setboard_full_replacement_rotates_epoch() {
    let mut scenario = test_scenario::begin(ALICE);
    create_dao(&mut scenario);

    // Replace ALICE + BOB with CAROL only.
    scenario.next_tx(ALICE);
    {
        let mut dao = scenario.take_shared<DAO>();
        do_set_board(&mut dao, vector[CAROL]);
        assert!(dao.encrypt_epoch() == 1);
        test_scenario::return_shared(dao);
    };

    scenario.end();
}

#[test]
/// Re-setting the board with the exact same members does not rotate the epoch.
fun test_setboard_same_members_no_rotation() {
    let mut scenario = test_scenario::begin(ALICE);
    create_dao(&mut scenario);

    // Re-set with same members.
    scenario.next_tx(ALICE);
    {
        let mut dao = scenario.take_shared<DAO>();
        do_set_board(&mut dao, vector[ALICE, BOB]);
        assert!(dao.encrypt_epoch() == 0);
        test_scenario::return_shared(dao);
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
        dao::create(
            &init,
            string::utf8(b"Multi-member"),
            string::utf8(b"Three members"),
            string::utf8(b"https://example.com"),
            scenario.ctx(),
        );
    };

    // Remove CAROL → epoch 1.
    scenario.next_tx(ALICE);
    {
        let mut dao = scenario.take_shared<DAO>();
        do_set_board(&mut dao, vector[ALICE, BOB]);
        assert!(dao.encrypt_epoch() == 1);
        test_scenario::return_shared(dao);
    };

    // Remove BOB → epoch 2.
    scenario.next_tx(ALICE);
    {
        let mut dao = scenario.take_shared<DAO>();
        do_set_board(&mut dao, vector[ALICE]);
        assert!(dao.encrypt_epoch() == 2);
        test_scenario::return_shared(dao);
    };

    scenario.end();
}

#[test]
/// After a SetBoard auto-rotation, entries published before the rotation are stale.
fun test_setboard_removal_makes_existing_entries_stale() {
    let mut scenario = test_scenario::begin(ALICE);
    create_dao(&mut scenario);

    // Publish at epoch 0.
    scenario.next_tx(ALICE);
    {
        let mut dao = scenario.take_shared<DAO>();
        encrypted_entry::publish_entry(
            &mut dao,
            string::utf8(b"ipfs://QmA"),
            string::utf8(b"Doc"),
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    // Remove BOB — epoch auto-rotates to 1.
    scenario.next_tx(ALICE);
    {
        let mut dao = scenario.take_shared<DAO>();
        do_set_board(&mut dao, vector[ALICE]);
        assert!(dao.encrypt_epoch() == 1);
        test_scenario::return_shared(dao);
    };

    // Entry is stale: its epoch (0) != dao epoch (1).
    scenario.next_tx(ALICE);
    {
        let dao = scenario.take_shared<DAO>();
        let entry = scenario.take_shared<EncryptedEntry>();
        assert!(encrypted_entry::entry_encrypt_epoch(&entry) == 0);
        assert!(dao.encrypt_epoch() == 1);
        // update_entry should now succeed (entry is stale).
        test_scenario::return_shared(dao);
        test_scenario::return_shared(entry);
    };

    scenario.end();
}

// ─────────────────────────────────────────────────────────────────────────────
// seal_approve
// ─────────────────────────────────────────────────────────────────────────────

#[test]
/// seal_approve succeeds when a board member presents a valid 32-byte DAO ID prefix.
fun test_seal_approve_valid_member_and_id() {
    let mut scenario = test_scenario::begin(ALICE);
    create_dao(&mut scenario);

    scenario.next_tx(ALICE);
    {
        let dao = scenario.take_shared<DAO>();
        // Build seal ID: dao object ID bytes (32) + zero nonce (32).
        let mut seal_id = object::id_to_bytes(&dao.id());
        let mut i = 0u64;
        while (i < 32) {
            seal_id.push_back(0u8);
            i = i + 1;
        };
        encrypted_entry::seal_approve(seal_id, &dao, scenario.ctx());
        test_scenario::return_shared(dao);
    };

    scenario.end();
}

#[test]
/// Any board member can call seal_approve with a valid ID.
fun test_seal_approve_any_board_member_succeeds() {
    let mut scenario = test_scenario::begin(ALICE);
    create_dao(&mut scenario);

    scenario.next_tx(BOB);
    {
        let dao = scenario.take_shared<DAO>();
        let mut seal_id = object::id_to_bytes(&dao.id());
        let mut i = 0u64;
        while (i < 32) { seal_id.push_back(0u8); i = i + 1; };
        encrypted_entry::seal_approve(seal_id, &dao, scenario.ctx());
        test_scenario::return_shared(dao);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = encrypted_entry::EIdTooShort)]
/// seal_approve aborts when the ID vector is shorter than 32 bytes.
fun test_seal_approve_id_too_short_aborts() {
    let mut scenario = test_scenario::begin(ALICE);
    create_dao(&mut scenario);

    scenario.next_tx(ALICE);
    {
        let dao = scenario.take_shared<DAO>();
        encrypted_entry::seal_approve(vector[0u8, 1u8, 2u8], &dao, scenario.ctx());
        test_scenario::return_shared(dao);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = encrypted_entry::EDaoMismatch)]
/// seal_approve aborts when the first 32 bytes do not match the DAO's object ID.
fun test_seal_approve_wrong_prefix_aborts() {
    let mut scenario = test_scenario::begin(ALICE);
    create_dao(&mut scenario);

    scenario.next_tx(ALICE);
    {
        let dao = scenario.take_shared<DAO>();
        // 64 zero bytes — will never match the real DAO object ID.
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
        encrypted_entry::seal_approve(wrong_id, &dao, scenario.ctx());
        test_scenario::return_shared(dao);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = encrypted_entry::ENotMember)]
/// seal_approve aborts for a non-member even with a valid ID prefix.
fun test_seal_approve_non_member_aborts() {
    let mut scenario = test_scenario::begin(ALICE);
    create_dao(&mut scenario);

    scenario.next_tx(CAROL);
    {
        let dao = scenario.take_shared<DAO>();
        let mut seal_id = object::id_to_bytes(&dao.id());
        let mut i = 0u64;
        while (i < 32) { seal_id.push_back(0u8); i = i + 1; };
        encrypted_entry::seal_approve(seal_id, &dao, scenario.ctx());
        test_scenario::return_shared(dao);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = encrypted_entry::ENotMember)]
/// seal_approve aborts for a removed board member (forward security).
fun test_seal_approve_removed_member_aborts() {
    let mut scenario = test_scenario::begin(ALICE);
    create_dao(&mut scenario);

    // Remove BOB from the board.
    scenario.next_tx(ALICE);
    {
        let mut dao = scenario.take_shared<DAO>();
        do_set_board(&mut dao, vector[ALICE]);
        test_scenario::return_shared(dao);
    };

    // BOB now tries to call seal_approve — should abort.
    scenario.next_tx(BOB);
    {
        let dao = scenario.take_shared<DAO>();
        let mut seal_id = object::id_to_bytes(&dao.id());
        let mut i = 0u64;
        while (i < 32) { seal_id.push_back(0u8); i = i + 1; };
        encrypted_entry::seal_approve(seal_id, &dao, scenario.ctx());
        test_scenario::return_shared(dao);
    };

    scenario.end();
}

// ─────────────────────────────────────────────────────────────────────────────
// Migration guard
// ─────────────────────────────────────────────────────────────────────────────

#[test, expected_failure(abort_code = dao::EEntriesNotEmpty)]
/// dao::destroy aborts if the DAO still has entries — they must be cleared first.
fun test_destroy_with_entries_aborts() {
    use armature::capability_vault::CapabilityVault;
    use armature::charter::Charter;
    use armature::emergency::EmergencyFreeze;
    use armature::treasury_vault::TreasuryVault;

    let mut scenario = test_scenario::begin(ALICE);
    create_dao(&mut scenario);

    // Publish an entry so dao.entries is non-empty.
    scenario.next_tx(ALICE);
    {
        let mut dao = scenario.take_shared<DAO>();
        encrypted_entry::publish_entry(
            &mut dao,
            string::utf8(b"ipfs://QmA"),
            string::utf8(b"Doc"),
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    // Transition to Migrating status via a crafted ExecutionRequest.
    scenario.next_tx(ALICE);
    {
        let mut dao = scenario.take_shared<DAO>();
        let successor_id = object::id_from_address(@0xBEEF);
        let req = proposal::new_execution_request<SetBoardWitness>(
            dao.id(),
            object::id_from_address(@0xDEAD),
        );
        dao.set_migrating(successor_id, &req);
        proposal::consume(req);
        test_scenario::return_shared(dao);
    };

    // Attempt to destroy — should abort because entries is non-empty.
    scenario.next_tx(ALICE);
    {
        let dao = scenario.take_shared<DAO>();
        let treasury = scenario.take_shared<TreasuryVault>();
        let vault = scenario.take_shared<CapabilityVault>();
        let charter = scenario.take_shared<Charter>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        dao::destroy(dao, treasury, vault, charter, freeze);
    };

    scenario.end();
}

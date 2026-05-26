module armature_proposals::upgrade_ops;

use armature::capability_vault::{CapabilityVault, CapLoan};
use armature::proposal::ExecutionTicket;
use armature_proposals::propose_upgrade::ProposeUpgrade;
use sui::event;
use sui::package::{Self, UpgradeCap, UpgradeTicket, UpgradeReceipt};

// === Errors ===

const EVaultDaoMismatch: u64 = 0;

// === Events ===

public struct UpgradeAuthorized has copy, drop {
    dao_id: ID,
    cap_id: ID,
    package_id: ID,
    policy: u8,
}

// === Handlers ===

/// Step 1: Authorize a package upgrade.
/// Loans the UpgradeCap from the vault, calls `package::authorize_upgrade`,
/// and returns the ticket, cap, and loan.
/// The caller must follow with `commit_upgrade` in the same PTB
/// after the PTB `Upgrade` command.
public fun execute_propose_upgrade(
    vault: &mut CapabilityVault,
    ticket: ExecutionTicket<ProposeUpgrade>,
): (UpgradeTicket, UpgradeCap, CapLoan) {
    assert!(vault.dao_id() == ticket.ticket_dao_id(), EVaultDaoMismatch);

    let payload = ticket.ticket_payload();

    let (mut cap, loan) = vault.loan_cap<UpgradeCap, ProposeUpgrade>(
        payload.cap_id(),
        ticket.ticket_request(),
    );

    let upgrade_ticket = package::authorize_upgrade(
        &mut cap,
        payload.policy(),
        *payload.digest(),
    );

    event::emit(UpgradeAuthorized {
        dao_id: vault.dao_id(),
        cap_id: payload.cap_id(),
        package_id: payload.package_id(),
        policy: payload.policy(),
    });

    ticket.discharge();

    (upgrade_ticket, cap, loan)
}

/// Step 2: Commit the upgrade and return the UpgradeCap to the vault.
/// Called after the PTB `Upgrade` command produces an UpgradeReceipt.
public fun commit_upgrade(
    vault: &mut CapabilityVault,
    mut cap: UpgradeCap,
    receipt: UpgradeReceipt,
    loan: CapLoan,
) {
    package::commit_upgrade(&mut cap, receipt);
    vault.return_cap(cap, loan);
}

module armature::spend_guard;

/// Reusable rolling-epoch spend-limit building block for third-party treasury handlers.
///
/// Store one of these as proposal type state on the DAO via `dao::init_type_state<P, SpendWindow>`
/// and update it each execution via `dao::borrow_type_state_mut<P, SpendWindow>`.
/// See `armature_proposals::send_small_payment` for a full worked example.
///
/// Example handler skeleton:
///
///   public fun execute_my_payment<T>(
///       dao: &mut DAO,
///       vault: &mut TreasuryVault,
///       proposal: &Proposal<MyPayload>,
///       req: ExecutionRequest<MyPayload>,
///       clock: &Clock,
///       ctx: &mut TxContext,
///   ) {
///       let now = clock.timestamp_ms();
///       if (!dao.has_type_state<MyPayload>()) {
///           dao.init_type_state(
///               spend_guard::new(now, MAX_EPOCH_SPEND, EPOCH_MS),
///               &req,
///           );
///       };
///       let window: &mut SpendWindow = dao.borrow_type_state_mut(&req);
///       window.charge(proposal.payload().amount(), now);
///       let coin = vault.withdraw<T, MyPayload>(proposal.payload().amount(), &req, ctx);
///       transfer::public_transfer(coin, proposal.payload().recipient());
///       proposal::finalize(req, proposal);
///   }
public struct SpendWindow has drop, store {
    epoch_start_ms: u64,
    epoch_spend: u64,
    max_epoch_spend: u64,
    epoch_duration_ms: u64,
}

// === Errors ===

const EExceedsEpochLimit: u64 = 0;

// === Constructor ===

/// Create a SpendWindow with a fixed max spend per rolling epoch.
public fun new(epoch_start_ms: u64, max_epoch_spend: u64, epoch_duration_ms: u64): SpendWindow {
    SpendWindow {
        epoch_start_ms,
        epoch_spend: 0,
        max_epoch_spend,
        epoch_duration_ms,
    }
}

// === Mutators ===

/// Record a spend of `amount` at `now_ms`, rolling the epoch forward if needed.
/// Aborts if `amount` would push cumulative epoch spend past `max_epoch_spend`.
public fun charge(self: &mut SpendWindow, amount: u64, now_ms: u64) {
    if (now_ms >= self.epoch_start_ms + self.epoch_duration_ms) {
        let periods = (now_ms - self.epoch_start_ms) / self.epoch_duration_ms;
        self.epoch_start_ms = self.epoch_start_ms + periods * self.epoch_duration_ms;
        self.epoch_spend = 0;
    };
    assert!(self.epoch_spend + amount <= self.max_epoch_spend, EExceedsEpochLimit);
    self.epoch_spend = self.epoch_spend + amount;
}

/// Update the per-epoch cap, e.g. after recalculating from current treasury balance.
public fun set_max(self: &mut SpendWindow, max_epoch_spend: u64) {
    self.max_epoch_spend = max_epoch_spend;
}

// === Accessors ===

public fun epoch_spend(self: &SpendWindow): u64 { self.epoch_spend }

public fun max_epoch_spend(self: &SpendWindow): u64 { self.max_epoch_spend }

public fun epoch_start_ms(self: &SpendWindow): u64 { self.epoch_start_ms }

public fun epoch_duration_ms(self: &SpendWindow): u64 { self.epoch_duration_ms }

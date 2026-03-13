module armature_proposals::send_small_payment;

/// Rate-limited small payment from treasury. Uses ProposalTypeState
/// to enforce a cumulative spend cap within rolling time epochs.
public struct SendSmallPayment<phantom T> has store {
    recipient: address,
    amount: u64,
}

/// Handler-owned persistent state stored as a dynamic field on the DAO.
/// Each coin type T gets its own state (keyed by TypeName of SendSmallPayment<T>).
public struct SmallPaymentState has drop, store {
    epoch_start_ms: u64,
    epoch_spend: u64,
    max_epoch_spend: u64,
    epoch_duration_ms: u64,
    spend_limit_bps: u64,
}

// === Constants ===

const DEFAULT_EPOCH_DURATION_MS: u64 = 86_400_000; // 24 hours
const DEFAULT_SPEND_LIMIT_BPS: u64 = 100; // 1% of treasury balance (100 basis points)

// === SendSmallPayment Constructor + Accessors ===

public fun new<T>(recipient: address, amount: u64): SendSmallPayment<T> {
    SendSmallPayment { recipient, amount }
}

public fun recipient<T>(self: &SendSmallPayment<T>): address { self.recipient }

public fun amount<T>(self: &SendSmallPayment<T>): u64 { self.amount }

// === SmallPaymentState Constructor + Accessors ===

public fun new_state(
    epoch_start_ms: u64,
    epoch_spend: u64,
    max_epoch_spend: u64,
    epoch_duration_ms: u64,
    spend_limit_bps: u64,
): SmallPaymentState {
    SmallPaymentState {
        epoch_start_ms,
        epoch_spend,
        max_epoch_spend,
        epoch_duration_ms,
        spend_limit_bps,
    }
}

public fun epoch_start_ms(self: &SmallPaymentState): u64 { self.epoch_start_ms }

public fun epoch_spend(self: &SmallPaymentState): u64 { self.epoch_spend }

public fun max_epoch_spend(self: &SmallPaymentState): u64 { self.max_epoch_spend }

public fun epoch_duration_ms(self: &SmallPaymentState): u64 { self.epoch_duration_ms }

public fun spend_limit_bps(self: &SmallPaymentState): u64 { self.spend_limit_bps }

// === SmallPaymentState Mutators ===

/// Add to the cumulative epoch spend.
public fun add_epoch_spend(self: &mut SmallPaymentState, amount: u64) {
    self.epoch_spend = self.epoch_spend + amount;
}

/// Reset state for a new epoch with a recalculated spend cap.
public fun reset_epoch(self: &mut SmallPaymentState, epoch_start_ms: u64, max_epoch_spend: u64) {
    self.epoch_start_ms = epoch_start_ms;
    self.epoch_spend = 0;
    self.max_epoch_spend = max_epoch_spend;
}

// === Default Accessors ===

public fun default_epoch_duration_ms(): u64 { DEFAULT_EPOCH_DURATION_MS }

public fun default_spend_limit_bps(): u64 { DEFAULT_SPEND_LIMIT_BPS }

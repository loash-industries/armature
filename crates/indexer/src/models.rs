use serde::Deserialize;

/// Define your Move event structs here.
/// Each struct should mirror the on-chain event layout for BCS deserialization.
///
/// Example:
/// ```ignore
/// #[derive(Debug, Deserialize)]
/// pub struct MyEvent {
///     pub pool_id: Vec<u8>,
///     pub amount: u64,
/// }
/// ```
#[derive(Debug, Deserialize)]
pub struct PlaceholderEvent {
    pub id: Vec<u8>,
}

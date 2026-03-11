// @generated automatically by Diesel CLI.

diesel::table! {
    events (event_digest) {
        event_digest -> Text,
        digest -> Text,
        sender -> Text,
        checkpoint -> Int8,
        checkpoint_timestamp_ms -> Int8,
        package -> Text,
    }
}

//! Axum REST API served alongside the indexer.
//!
//! Endpoints:
//!   GET /dao/:id                      — DAO companion IDs
//!   GET /dao/:id/proposals?status=    — Proposal list (optionally filtered by status)
//!   GET /dao/:id/treasury             — Treasury balances
//!   GET /dao/:id/activity?limit=      — Recent activity events
//!   GET /health                       — Liveness (200 OK)

use std::net::SocketAddr;
use std::sync::Arc;

use anyhow::Result;
use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::response::IntoResponse;
use axum::routing::get;
use axum::{Json, Router};
use diesel::prelude::*;
use diesel_async::pooled_connection::bb8::Pool;
use diesel_async::pooled_connection::AsyncDieselConnectionManager;
use diesel_async::{AsyncPgConnection, RunQueryDsl};
use serde::{Deserialize, Serialize};
use tower_http::cors::CorsLayer;

use armature_schema::models::{Dao, Proposal, TreasuryBalance};
use armature_schema::schema::{daos, events, proposals, treasury_balances};

type DbPool = Arc<Pool<AsyncPgConnection>>;

// ── Request / response types ─────────────────────────────────────────────────

#[derive(Deserialize)]
struct ProposalQuery {
    status: Option<String>,
}

#[derive(Deserialize)]
struct ActivityQuery {
    limit: Option<i64>,
}

#[derive(Serialize)]
struct ActivityRow {
    event_type: String,
    dao_id: Option<String>,
    timestamp_ms: i64,
    tx_digest: String,
    payload: Option<serde_json::Value>,
}

// ── Handlers ─────────────────────────────────────────────────────────────────

async fn health() -> impl IntoResponse {
    (StatusCode::OK, "OK")
}

async fn get_dao(
    Path(dao_id): Path<String>,
    State(pool): State<DbPool>,
) -> Result<Json<Dao>, StatusCode> {
    let mut conn = pool
        .get()
        .await
        .map_err(|_| StatusCode::SERVICE_UNAVAILABLE)?;
    daos::table
        .filter(daos::dao_id.eq(&dao_id))
        .first::<Dao>(&mut conn)
        .await
        .map(Json)
        .map_err(|_| StatusCode::NOT_FOUND)
}

async fn get_proposals(
    Path(dao_id): Path<String>,
    Query(q): Query<ProposalQuery>,
    State(pool): State<DbPool>,
) -> Result<Json<Vec<Proposal>>, StatusCode> {
    let mut conn = pool
        .get()
        .await
        .map_err(|_| StatusCode::SERVICE_UNAVAILABLE)?;

    let rows = if let Some(status) = q.status {
        proposals::table
            .filter(proposals::dao_id.eq(&dao_id))
            .filter(proposals::status.eq(status))
            .order(proposals::created_at_ms.desc())
            .load::<Proposal>(&mut conn)
            .await
    } else {
        proposals::table
            .filter(proposals::dao_id.eq(&dao_id))
            .order(proposals::created_at_ms.desc())
            .load::<Proposal>(&mut conn)
            .await
    };

    rows.map(Json)
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)
}

async fn get_treasury(
    Path(dao_id): Path<String>,
    State(pool): State<DbPool>,
) -> Result<Json<Vec<TreasuryBalance>>, StatusCode> {
    let mut conn = pool
        .get()
        .await
        .map_err(|_| StatusCode::SERVICE_UNAVAILABLE)?;

    // Look up the treasury_id for this DAO first.
    let dao = daos::table
        .filter(daos::dao_id.eq(&dao_id))
        .first::<Dao>(&mut conn)
        .await
        .map_err(|_| StatusCode::NOT_FOUND)?;

    treasury_balances::table
        .filter(treasury_balances::treasury_id.eq(&dao.treasury_id))
        .load::<TreasuryBalance>(&mut conn)
        .await
        .map(Json)
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)
}

async fn get_activity(
    Path(dao_id): Path<String>,
    Query(q): Query<ActivityQuery>,
    State(pool): State<DbPool>,
) -> Result<Json<Vec<ActivityRow>>, StatusCode> {
    let mut conn = pool
        .get()
        .await
        .map_err(|_| StatusCode::SERVICE_UNAVAILABLE)?;
    let limit = q.limit.unwrap_or(50).min(200);

    let rows = events::table
        .filter(events::dao_id.eq(&dao_id))
        .order(events::checkpoint_timestamp_ms.desc())
        .limit(limit)
        .select((
            events::event_type,
            events::dao_id,
            events::checkpoint_timestamp_ms,
            events::digest,
            events::payload_json,
        ))
        .load::<(
            String,
            Option<String>,
            i64,
            String,
            Option<serde_json::Value>,
        )>(&mut conn)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let activity = rows
        .into_iter()
        .map(
            |(event_type, dao_id, timestamp_ms, tx_digest, payload)| ActivityRow {
                event_type,
                dao_id,
                timestamp_ms,
                tx_digest,
                payload,
            },
        )
        .collect();

    Ok(Json(activity))
}

// ── Server ───────────────────────────────────────────────────────────────────

pub async fn serve(database_url: String, addr: SocketAddr) -> Result<()> {
    let manager = AsyncDieselConnectionManager::<AsyncPgConnection>::new(&database_url);
    let pool = Pool::builder()
        .max_size(10)
        .build(manager)
        .await
        .map_err(|e| anyhow::anyhow!("Failed to build API DB pool: {e}"))?;

    let pool = Arc::new(pool);

    let app = Router::new()
        .route("/health", get(health))
        .route("/dao/:id", get(get_dao))
        .route("/dao/:id/proposals", get(get_proposals))
        .route("/dao/:id/treasury", get(get_treasury))
        .route("/dao/:id/activity", get(get_activity))
        // Permissive CORS is intentional for local dev; restrict origins before production.
        .layer(CorsLayer::permissive())
        .with_state(pool);

    tracing::info!("REST API listening on {addr}");
    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
}

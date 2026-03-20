//! Axum REST API served alongside the indexer.
//!
//! Endpoints:
//!   GET /dao/:id                             — DAO companion IDs
//!   GET /dao/:id/proposals                   — Proposals (status, type_key, limit, offset)
//!   GET /dao/:id/treasury                    — Treasury balances
//!   GET /dao/:id/activity                    — Recent activity events (limit, offset)
//!   GET /dao/:id/frozen                      — Currently frozen proposal types
//!   GET /proposal/:id/votes                  — Votes for a specific proposal (limit, offset)
//!   GET /health                              — Liveness (200 OK)

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

use armature_schema::models::{Dao, FrozenType, Proposal, TreasuryBalance, Vote};
use armature_schema::schema::{daos, events, frozen_types, proposals, treasury_balances, votes};

type DbPool = Arc<Pool<AsyncPgConnection>>;

// ── Request / response types ─────────────────────────────────────────────────

#[derive(Deserialize)]
struct ProposalQuery {
    status: Option<String>,
    type_key: Option<String>,
    limit: Option<i64>,
    offset: Option<i64>,
}

#[derive(Deserialize)]
struct PageQuery {
    limit: Option<i64>,
    offset: Option<i64>,
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

    let limit = q.limit.unwrap_or(50).clamp(1, 200);
    let offset = q.offset.unwrap_or(0).max(0);

    let mut query = proposals::table
        .filter(proposals::dao_id.eq(&dao_id))
        .into_boxed();

    if let Some(status) = q.status {
        query = query.filter(proposals::status.eq(status));
    }
    if let Some(type_key) = q.type_key {
        query = query.filter(proposals::type_key.eq(type_key));
    }

    query
        .order(proposals::created_at_ms.desc())
        .limit(limit)
        .offset(offset)
        .load::<Proposal>(&mut conn)
        .await
        .map(Json)
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
    Query(q): Query<PageQuery>,
    State(pool): State<DbPool>,
) -> Result<Json<Vec<ActivityRow>>, StatusCode> {
    let mut conn = pool
        .get()
        .await
        .map_err(|_| StatusCode::SERVICE_UNAVAILABLE)?;
    let limit = q.limit.unwrap_or(50).clamp(1, 200);
    let offset = q.offset.unwrap_or(0).max(0);

    let rows = events::table
        .filter(events::dao_id.eq(&dao_id))
        .order(events::checkpoint_timestamp_ms.desc())
        .limit(limit)
        .offset(offset)
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

async fn get_frozen(
    Path(dao_id): Path<String>,
    State(pool): State<DbPool>,
) -> Result<Json<Vec<FrozenType>>, StatusCode> {
    let mut conn = pool
        .get()
        .await
        .map_err(|_| StatusCode::SERVICE_UNAVAILABLE)?;

    frozen_types::table
        .filter(frozen_types::dao_id.eq(&dao_id))
        .load::<FrozenType>(&mut conn)
        .await
        .map(Json)
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)
}

async fn get_proposal_votes(
    Path(proposal_id): Path<String>,
    Query(q): Query<PageQuery>,
    State(pool): State<DbPool>,
) -> Result<Json<Vec<Vote>>, StatusCode> {
    let mut conn = pool
        .get()
        .await
        .map_err(|_| StatusCode::SERVICE_UNAVAILABLE)?;

    let limit = q.limit.unwrap_or(50).clamp(1, 200);
    let offset = q.offset.unwrap_or(0).max(0);

    votes::table
        .filter(votes::proposal_id.eq(&proposal_id))
        .order(votes::timestamp_ms.asc())
        .limit(limit)
        .offset(offset)
        .load::<Vote>(&mut conn)
        .await
        .map(Json)
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)
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
        .route("/dao/:id/frozen", get(get_frozen))
        .route("/proposal/:id/votes", get(get_proposal_votes))
        // Permissive CORS is intentional for local dev; restrict origins before production.
        .layer(CorsLayer::permissive())
        .with_state(pool);

    tracing::info!("REST API listening on {addr}");
    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
}

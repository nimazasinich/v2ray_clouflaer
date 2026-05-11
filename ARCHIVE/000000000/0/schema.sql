-- ============================================================
-- DreamMaker — D1 Database Schema
-- Run once: wrangler d1 execute DM_DB --file=schema.sql
-- ============================================================

-- ── Helpers (endpoint configurations for TIER 1 prober) ────
CREATE TABLE IF NOT EXISTS helpers (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    edge_id      TEXT    NOT NULL UNIQUE,
    url          TEXT    NOT NULL,
    method       TEXT    NOT NULL DEFAULT 'GET',
    timeout      INTEGER NOT NULL DEFAULT 5000,
    enabled      INTEGER NOT NULL DEFAULT 1,      -- 0 = disabled
    created_at   INTEGER NOT NULL DEFAULT (unixepoch() * 1000)
);

-- ── Edge metrics history (written by TIER 1, read by TIER 2) ─
CREATE TABLE IF NOT EXISTS edge_metrics (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    edge_id          TEXT    NOT NULL,
    latency_ms       INTEGER,
    disconnect_rate  REAL,
    dpi_suspicion    REAL,
    mobile_stability REAL,
    tls_failure_rate REAL,
    timestamp        INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_edge_metrics_edge_id   ON edge_metrics (edge_id);
CREATE INDEX IF NOT EXISTS idx_edge_metrics_timestamp ON edge_metrics (timestamp);

-- ── Request logs (sampled 1%, written by TIER 0 waitUntil) ──
CREATE TABLE IF NOT EXISTS request_logs (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    path        TEXT    NOT NULL,
    status      INTEGER NOT NULL,
    duration_ms INTEGER,
    method      TEXT,
    cf_country  TEXT,
    timestamp   INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_request_logs_timestamp ON request_logs (timestamp);

-- ── Audit log (written by TIER 2 admin operations) ──────────
CREATE TABLE IF NOT EXISTS audit_logs (
    id        INTEGER PRIMARY KEY AUTOINCREMENT,
    action    TEXT    NOT NULL,
    details   TEXT,
    timestamp INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_timestamp ON audit_logs (timestamp);

-- ── Global configuration (single row) ───────────────────────
CREATE TABLE IF NOT EXISTS config (
    id                    INTEGER PRIMARY KEY DEFAULT 1,
    site_title            TEXT    NOT NULL DEFAULT 'DreamMaker Control Plane',
    version               INTEGER NOT NULL DEFAULT 2,
    notification_email    TEXT,
    max_helpers           INTEGER NOT NULL DEFAULT 20,
    metrics_retention     INTEGER NOT NULL DEFAULT 2592000,  -- 30 days in seconds
    alert_thresholds_json TEXT    NOT NULL DEFAULT '{"highLatency":500,"highDpi":0.6,"highDisconnect":0.15}',
    updated_at            INTEGER NOT NULL DEFAULT (unixepoch() * 1000),
    -- Enforce single-row constraint
    CHECK (id = 1)
);

-- Insert default config row
INSERT OR IGNORE INTO config (id) VALUES (1);

-- ── Default helpers (real DreamMaker endpoints) ──────────────
INSERT OR IGNORE INTO helpers (edge_id, url, method, timeout) VALUES
    ('cdn-primary', 'https://cdn.dreammaker-groupsoft.ir/health', 'GET', 5000),
    ('cdn-clean',   'https://clean.dreammaker-groupsoft.ir/health', 'GET', 5000),
    ('cdn-main',    'https://dreammaker-groupsoft.ir/health',     'GET', 5000),
    ('tier-starter','https://cdn.dreammaker-groupsoft.ir/api/v1/ping', 'GET', 5000),
    ('tier-basic',  'https://cdn.dreammaker-groupsoft.ir/cdn/init',    'GET', 5000);

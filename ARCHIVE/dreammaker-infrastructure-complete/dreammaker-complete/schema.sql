-- ============================================================
-- DreamMaker D1 Database Schema
-- 
-- Purpose: Store configuration, metrics, and audit logs
-- Version: 1.0.0
-- Last Updated: 2026-05-09
-- 
-- Migration Path:
--   1. Create tables in order (config → metrics → audit_log)
--   2. Run initialization to populate defaults
--   3. Enable foreign keys (if needed)
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- Table: config
-- Purpose: Store site-wide configuration and settings
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS config (
  id INTEGER PRIMARY KEY,
  site_title TEXT NOT NULL DEFAULT 'DreamMaker Infrastructure',
  version INTEGER NOT NULL DEFAULT 1,
  notification_email TEXT,
  max_helpers INTEGER NOT NULL DEFAULT 100,
  metrics_retention INTEGER NOT NULL DEFAULT 86400,
  alert_thresholds_json TEXT,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Add index for faster lookups (though id=1 is primary)
CREATE INDEX IF NOT EXISTS idx_config_updated ON config(updated_at);

-- ────────────────────────────────────────────────────────────
-- Table: metrics
-- Purpose: Store health and performance metrics per tier
-- 
-- Fields:
--   timestamp: When metric was recorded
--   tier: Tier name (starter, basic, standard, plus, pro, elite, unlimited)
--   status: 'healthy', 'degraded', 'offline'
--   latency_ms: Measured latency in milliseconds
--   success_count: Number of successful requests
--   failure_count: Number of failed requests
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS metrics (
  id INTEGER PRIMARY KEY,
  timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
  tier TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'healthy',
  latency_ms INTEGER,
  success_count INTEGER DEFAULT 0,
  failure_count INTEGER DEFAULT 0,
  probe_endpoint TEXT,
  error_message TEXT,
  CONSTRAINT valid_status CHECK (status IN ('healthy', 'degraded', 'offline', 'unknown'))
);

-- Create indexes for efficient querying
CREATE INDEX IF NOT EXISTS idx_metrics_timestamp ON metrics(timestamp);
CREATE INDEX IF NOT EXISTS idx_metrics_tier ON metrics(tier);
CREATE INDEX IF NOT EXISTS idx_metrics_status ON metrics(status);
CREATE INDEX IF NOT EXISTS idx_metrics_tier_timestamp ON metrics(tier, timestamp);

-- ────────────────────────────────────────────────────────────
-- Table: audit_log
-- Purpose: Track all admin actions for compliance and debugging
-- 
-- Fields:
--   action: Type of action (login, config_change, worker_deploy, etc)
--   admin_jwt: Hashed JWT identifier
--   ip_address: IP address of requester (anonymized)
--   details: JSON details of the action
--   result: 'success' or 'failure'
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS audit_log (
  id INTEGER PRIMARY KEY,
  timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
  action TEXT NOT NULL,
  admin_jwt TEXT,
  ip_address TEXT,
  details TEXT,
  result TEXT NOT NULL DEFAULT 'success',
  CONSTRAINT valid_action CHECK (action IN (
    'login', 'logout', 'config_read', 'config_write',
    'worker_deploy', 'worker_test', 'tier_modify',
    'backup_create', 'backup_restore', 'health_check',
    'telegram_test', 'settings_change', 'emergency_mode'
  ))
);

-- Create indexes for efficient querying
CREATE INDEX IF NOT EXISTS idx_audit_timestamp ON audit_log(timestamp);
CREATE INDEX IF NOT EXISTS idx_audit_action ON audit_log(action);
CREATE INDEX IF NOT EXISTS idx_audit_result ON audit_log(result);
CREATE INDEX IF NOT EXISTS idx_audit_admin ON audit_log(admin_jwt);

-- ────────────────────────────────────────────────────────────
-- Table: health_checks
-- Purpose: Track health check history for trend analysis
-- 
-- Used by Tier 1 (helper ecosystem) to record probe results
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS health_checks (
  id INTEGER PRIMARY KEY,
  timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
  check_type TEXT NOT NULL,
  target TEXT NOT NULL,
  status_code INTEGER,
  response_time_ms INTEGER,
  success BOOLEAN DEFAULT 1,
  error_detail TEXT
);

CREATE INDEX IF NOT EXISTS idx_health_timestamp ON health_checks(timestamp);
CREATE INDEX IF NOT EXISTS idx_health_target ON health_checks(target);
CREATE INDEX IF NOT EXISTS idx_health_success ON health_checks(success);

-- ────────────────────────────────────────────────────────────
-- Table: subscriptions (Optional - for future use)
-- Purpose: Track active subscriptions if needed
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS subscriptions (
  id INTEGER PRIMARY KEY,
  uuid TEXT NOT NULL UNIQUE,
  tier TEXT NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  expires_at DATETIME,
  is_active BOOLEAN DEFAULT 1,
  last_accessed DATETIME,
  access_count INTEGER DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_subscriptions_uuid ON subscriptions(uuid);
CREATE INDEX IF NOT EXISTS idx_subscriptions_tier ON subscriptions(tier);
CREATE INDEX IF NOT EXISTS idx_subscriptions_active ON subscriptions(is_active);

-- ────────────────────────────────────────────────────────────
-- Initialization Data
-- ────────────────────────────────────────────────────────────

-- Insert default configuration
INSERT OR IGNORE INTO config (id, site_title, version) VALUES (
  1,
  'DreamMaker Infrastructure Control Plane',
  1
);

-- ────────────────────────────────────────────────────────────
-- Views for easier querying
-- ────────────────────────────────────────────────────────────

-- View: Latest health status per tier
CREATE VIEW IF NOT EXISTS v_latest_health_per_tier AS
SELECT 
  tier,
  MAX(timestamp) as last_check,
  status,
  AVG(latency_ms) as avg_latency
FROM metrics
WHERE timestamp > datetime('now', '-1 hour')
GROUP BY tier;

-- View: Recent audit activity
CREATE VIEW IF NOT EXISTS v_recent_audits AS
SELECT 
  timestamp,
  action,
  result,
  ip_address
FROM audit_log
WHERE timestamp > datetime('now', '-7 days')
ORDER BY timestamp DESC;

-- View: Health check success rate (last 24 hours)
CREATE VIEW IF NOT EXISTS v_health_check_success_rate AS
SELECT 
  check_type,
  target,
  COUNT(*) as total_checks,
  SUM(CASE WHEN success = 1 THEN 1 ELSE 0 END) as successful_checks,
  ROUND(100.0 * SUM(CASE WHEN success = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) as success_percentage
FROM health_checks
WHERE timestamp > datetime('now', '-24 hours')
GROUP BY check_type, target;

-- ────────────────────────────────────────────────────────────
-- Cleanup Procedure (for retention policy)
-- 
-- Execute periodically to maintain retention policy:
-- DELETE FROM metrics WHERE timestamp < datetime('now', '-7 days');
-- DELETE FROM audit_log WHERE timestamp < datetime('now', '-30 days');
-- DELETE FROM health_checks WHERE timestamp < datetime('now', '-14 days');
--
-- Consider scheduling via cron or Cloudflare scheduled worker
-- ────────────────────────────────────────────────────────────

-- Verify schema
-- SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;
-- SELECT name FROM sqlite_master WHERE type='view' ORDER BY name;

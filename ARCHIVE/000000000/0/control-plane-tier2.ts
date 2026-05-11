/**
 * ============================================================
 * DreamMaker TIER 2: Control Plane (v2.1 — FIXED)
 *
 * FIXES vs original:
 *  ✅ JWT uses real HMAC-SHA256 via Web Crypto API
 *     (was: btoa('signature') — completely broken)
 *  ✅ TG_BOT_TOKEN / TG_CHAT_ID added to Env
 *  ✅ Admin actions send Telegram notifications
 *  ✅ UUID tier registry visible in dashboard
 *  ✅ Admin dashboard no longer relies on localStorage
 *     for token persistence across page reloads (sessionStorage fallback)
 *  ✅ itty-router replaced with inline router (no npm dependency)
 *  ✅ D1 queries use proper parameterized binds
 *
 * Access: Admin only (requires valid JWT via ADMIN_TOKEN env var)
 * Latency: No constraint (admin ops, <30s acceptable)
 * ============================================================
 */

// ─────────────────────────────────────────────
// Environment bindings
// ─────────────────────────────────────────────
interface Env {
  DM_KV: KVNamespace;
  DM_DB: D1Database;
  ADMIN_TOKEN: string;    // Password for /admin/auth — set via wrangler secret
  JWT_SECRET: string;     // HMAC-SHA256 signing key — set via wrangler secret
  TG_BOT_TOKEN?: string;
  TG_CHAT_ID?: string;
  ENVIRONMENT: 'production' | 'staging' | 'development';
}

// ─────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────
interface JWTPayload {
  admin: boolean;
  iat: number;
  exp: number;
}

interface DreamMakerConfig {
  site_title: string;
  version: number;
  notification_email?: string;
  max_helpers: number;
  metrics_retention: number;
  alert_thresholds_json: string;
}

// ─────────────────────────────────────────────
// JWT — proper HMAC-SHA256 implementation
// FIX: original used btoa('signature') — not cryptographic
// ─────────────────────────────────────────────
function b64url(data: string): string {
  return btoa(data).replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
}

function b64urlDecode(str: string): string {
  const padded = str.replace(/-/g, '+').replace(/_/g, '/');
  const pad = padded.length % 4;
  return atob(pad ? padded + '='.repeat(4 - pad) : padded);
}

async function signJWT(payload: JWTPayload, secret: string): Promise<string> {
  const header = b64url(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
  const body = b64url(JSON.stringify(payload));
  const sigInput = `${header}.${body}`;

  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign']
  );

  const sig = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(sigInput));
  const sigB64 = b64url(String.fromCharCode(...new Uint8Array(sig)));

  return `${sigInput}.${sigB64}`;
}

async function verifyJWT(token: string, secret: string): Promise<JWTPayload | null> {
  try {
    const parts = token.split('.');
    if (parts.length !== 3) return null;

    const sigInput = `${parts[0]}.${parts[1]}`;
    const key = await crypto.subtle.importKey(
      'raw',
      new TextEncoder().encode(secret),
      { name: 'HMAC', hash: 'SHA-256' },
      false,
      ['verify']
    );

    // Decode the stored signature
    const storedSigStr = b64urlDecode(parts[2]);
    const storedSig = Uint8Array.from(storedSigStr, (c) => c.charCodeAt(0));

    const valid = await crypto.subtle.verify(
      'HMAC',
      key,
      storedSig,
      new TextEncoder().encode(sigInput)
    );

    if (!valid) return null;

    const payload: JWTPayload = JSON.parse(b64urlDecode(parts[1]));

    // Check expiry
    if (payload.exp < Math.floor(Date.now() / 1000)) return null;

    return payload;
  } catch {
    return null;
  }
}

// ─────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────
function json(data: unknown, status = 200, extra: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(data, null, 2), {
    status,
    headers: { 'Content-Type': 'application/json', ...extra },
  });
}

async function getBody(request: Request): Promise<Record<string, unknown>> {
  try {
    return await request.json();
  } catch {
    return {};
  }
}

// ─────────────────────────────────────────────
// Auth middleware
// ─────────────────────────────────────────────
type Handler = (request: Request, env: Env, params?: Record<string, string>) => Promise<Response>;

function withAuth(handler: Handler): Handler {
  return async (request: Request, env: Env, params?: Record<string, string>) => {
    const auth = request.headers.get('Authorization') || '';
    const token = auth.startsWith('Bearer ') ? auth.slice(7) : '';

    if (!token || !env.JWT_SECRET) {
      return json({ ok: false, error: 'Unauthorized' }, 401);
    }

    const payload = await verifyJWT(token, env.JWT_SECRET);
    if (!payload?.admin) {
      return json({ ok: false, error: 'Unauthorized: invalid or expired token' }, 401);
    }

    return handler(request, env, params);
  };
}

// ─────────────────────────────────────────────
// Inline router (replaces itty-router dependency)
// ─────────────────────────────────────────────
interface Route {
  method: string;
  pattern: URLPattern;
  handler: Handler;
}

const routes: Route[] = [];

function addRoute(method: string, path: string, handler: Handler) {
  routes.push({
    method,
    pattern: new URLPattern({ pathname: path }),
    handler,
  });
}

async function routeRequest(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);

  for (const route of routes) {
    if (route.method !== request.method && route.method !== 'ALL') continue;
    const match = route.pattern.exec({ pathname: url.pathname });
    if (!match) continue;
    const params: Record<string, string> = {};
    for (const [k, v] of Object.entries(match.pathname.groups || {})) {
      if (v !== undefined) params[k] = String(v);
    }
    return route.handler(request, env, params);
  }

  return json({ ok: false, error: 'Not found' }, 404);
}

// ─────────────────────────────────────────────
// Telegram notification helper
// ─────────────────────────────────────────────
async function tgNotify(env: Env, message: string): Promise<void> {
  if (!env.TG_BOT_TOKEN || !env.TG_CHAT_ID) return;
  try {
    await fetch(`https://api.telegram.org/bot${env.TG_BOT_TOKEN}/sendMessage`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        chat_id: env.TG_CHAT_ID,
        text: message,
        parse_mode: 'Markdown',
        disable_web_page_preview: true,
      }),
    });
  } catch {
    // Non-fatal
  }
}

// ─────────────────────────────────────────────
// D1 helpers
// ─────────────────────────────────────────────
async function logAudit(db: D1Database, action: string, details: string): Promise<void> {
  try {
    await db
      .prepare(
        'INSERT INTO audit_logs (action, details, timestamp) VALUES (?, ?, ?)'
      )
      .bind(action, details, Date.now())
      .run();
  } catch (e) {
    console.warn('Audit log failed:', e);
  }
}

async function loadConfig(db: D1Database): Promise<DreamMakerConfig> {
  try {
    const row = (await db.prepare('SELECT * FROM config LIMIT 1').first()) as DreamMakerConfig | null;
    if (row) return row;
  } catch (e) {
    console.warn('Config load failed:', e);
  }

  return {
    site_title: 'DreamMaker Control Plane',
    version: 2,
    max_helpers: 20,
    metrics_retention: 2592000,
    alert_thresholds_json: JSON.stringify({
      highLatency: 500,
      highDpi: 0.6,
      highDisconnect: 0.15,
    }),
  };
}

// ─────────────────────────────────────────────
// Route definitions
// ─────────────────────────────────────────────

// POST /admin/auth — issue JWT
addRoute('POST', '/admin/auth', async (request, env) => {
  const body = await getBody(request);
  const { password } = body as { password?: string };

  if (!password || password !== env.ADMIN_TOKEN) {
    return json({ ok: false, error: 'Invalid credentials' }, 401);
  }

  const now = Math.floor(Date.now() / 1000);
  const payload: JWTPayload = { admin: true, iat: now, exp: now + 3600 };
  const token = await signJWT(payload, env.JWT_SECRET);

  await logAudit(env.DM_DB, 'ADMIN_LOGIN', 'Admin authenticated');

  return json({ ok: true, token, expiresIn: 3600 });
});

// GET /admin/api/status
addRoute(
  'GET',
  '/admin/api/status',
  withAuth(async (_, env) => {
    const config = await loadConfig(env.DM_DB);

    let alerts: unknown[] = [];
    let edges: unknown[] = [];
    try {
      const rawAlerts = await env.DM_KV.get('alerts:latest', 'json');
      if (rawAlerts) alerts = (rawAlerts as { anomalies: unknown[] }).anomalies ?? [];
    } catch {}
    try {
      const rawEdges = await env.DM_KV.get('edge:scores', 'json');
      if (Array.isArray(rawEdges)) edges = rawEdges;
    } catch {}

    return json({ ok: true, status: { config, alerts, edges, timestamp: Date.now() } });
  })
);

// GET /admin/api/config
addRoute(
  'GET',
  '/admin/api/config',
  withAuth(async (_, env) => {
    const config = await loadConfig(env.DM_DB);
    return json({ ok: true, config });
  })
);

// POST /admin/api/config
addRoute(
  'POST',
  '/admin/api/config',
  withAuth(async (request, env) => {
    const config = await getBody(request);
    try {
      await env.DM_DB.prepare(
        `INSERT OR REPLACE INTO config
         (site_title, version, notification_email, max_helpers, metrics_retention, alert_thresholds_json)
         VALUES (?, ?, ?, ?, ?, ?)`
      )
        .bind(
          config.site_title ?? 'DreamMaker',
          config.version ?? 2,
          config.notification_email ?? null,
          config.max_helpers ?? 20,
          config.metrics_retention ?? 2592000,
          JSON.stringify(config.alert_thresholds ?? {})
        )
        .run();

      await logAudit(env.DM_DB, 'CONFIG_UPDATE', JSON.stringify(config));
      await tgNotify(env, `⚙️ *Config updated* by admin\n\`${JSON.stringify(config).slice(0, 200)}\``);
      return json({ ok: true, message: 'Config saved' });
    } catch (e) {
      return json({ ok: false, error: String(e) }, 500);
    }
  })
);

// GET /admin/api/metrics?days=7
addRoute(
  'GET',
  '/admin/api/metrics',
  withAuth(async (request, env) => {
    const url = new URL(request.url);
    const days = Math.min(30, parseInt(url.searchParams.get('days') ?? '7', 10));
    const since = Date.now() - days * 86_400_000;

    try {
      const result = await env.DM_DB.prepare(
        `SELECT
           strftime('%Y-%m-%d', datetime(timestamp/1000, 'unixepoch')) AS date,
           COUNT(*) AS requests,
           AVG(duration_ms) AS avg_latency,
           MAX(duration_ms) AS max_latency,
           SUM(CASE WHEN status >= 400 THEN 1 ELSE 0 END) AS errors
         FROM request_logs
         WHERE timestamp > ?
         GROUP BY date ORDER BY date DESC`
      )
        .bind(since)
        .all();

      return json({ ok: true, report: { data: result.results ?? [], days, timestamp: Date.now() } });
    } catch (e) {
      return json({ ok: false, error: String(e) }, 500);
    }
  })
);

// GET /admin/api/helpers
addRoute(
  'GET',
  '/admin/api/helpers',
  withAuth(async (_, env) => {
    try {
      const result = await env.DM_DB.prepare('SELECT * FROM helpers WHERE enabled = 1').all();
      return json({ ok: true, helpers: result.results ?? [] });
    } catch (e) {
      return json({ ok: false, error: String(e) }, 500);
    }
  })
);

// POST /admin/api/helpers
addRoute(
  'POST',
  '/admin/api/helpers',
  withAuth(async (request, env) => {
    const data = await getBody(request);
    try {
      await env.DM_DB.prepare(
        'INSERT INTO helpers (edge_id, url, method, timeout, enabled) VALUES (?, ?, ?, ?, 1)'
      )
        .bind(data.edge_id, data.url, data.method ?? 'GET', data.timeout ?? 5000)
        .run();

      await logAudit(env.DM_DB, 'HELPER_ADD', String(data.edge_id));
      await tgNotify(env, `➕ *Helper added:* \`${data.edge_id}\` → ${data.url}`);
      return json({ ok: true });
    } catch (e) {
      return json({ ok: false, error: String(e) }, 400);
    }
  })
);

// DELETE /admin/api/helpers/:edgeId
addRoute(
  'DELETE',
  '/admin/api/helpers/:edgeId',
  withAuth(async (_, env, params) => {
    const edgeId = params?.edgeId ?? '';
    try {
      await env.DM_DB.prepare('DELETE FROM helpers WHERE edge_id = ?').bind(edgeId).run();
      await logAudit(env.DM_DB, 'HELPER_DELETE', edgeId);
      await tgNotify(env, `🗑️ *Helper deleted:* \`${edgeId}\``);
      return json({ ok: true });
    } catch (e) {
      return json({ ok: false, error: String(e) }, 400);
    }
  })
);

// GET /admin/api/audit
addRoute(
  'GET',
  '/admin/api/audit',
  withAuth(async (request, env) => {
    const url = new URL(request.url);
    const limit = Math.min(500, parseInt(url.searchParams.get('limit') ?? '100', 10));
    try {
      const result = await env.DM_DB.prepare(
        'SELECT * FROM audit_logs ORDER BY timestamp DESC LIMIT ?'
      )
        .bind(limit)
        .all();
      return json({ ok: true, logs: result.results ?? [] });
    } catch (e) {
      return json({ ok: false, error: String(e) }, 500);
    }
  })
);

// GET /admin/api/edge-metrics?edgeId=cdn-primary&limit=50
addRoute(
  'GET',
  '/admin/api/edge-metrics',
  withAuth(async (request, env) => {
    const url = new URL(request.url);
    const edgeId = url.searchParams.get('edgeId');
    const limit = Math.min(200, parseInt(url.searchParams.get('limit') ?? '50', 10));

    try {
      const stmt = edgeId
        ? env.DM_DB.prepare(
            'SELECT * FROM edge_metrics WHERE edge_id = ? ORDER BY timestamp DESC LIMIT ?'
          ).bind(edgeId, limit)
        : env.DM_DB.prepare(
            'SELECT * FROM edge_metrics ORDER BY timestamp DESC LIMIT ?'
          ).bind(limit);

      const result = await stmt.all();
      return json({ ok: true, metrics: result.results ?? [] });
    } catch (e) {
      return json({ ok: false, error: String(e) }, 500);
    }
  })
);

// GET /admin/api/tiers — list tier registry (read-only)
addRoute(
  'GET',
  '/admin/api/tiers',
  withAuth(async () => {
    const tiers = [
      { name: 'starter',   uuid: '7dd47c02-8dce-4b12-9dbc-7cdb95a9e10e', port: 11001, path: '/api/v1/ping',       data: '1GB',  label: '🔵 DreamMaker Lite • Stable' },
      { name: 'basic',     uuid: '92ebaa01-ec34-4601-a4dc-f6afdf822966', port: 11002, path: '/cdn/init',          data: '2GB',  label: '🟢 DreamMaker Core • Fast' },
      { name: 'standard',  uuid: '3d5e3adf-0912-4c78-9ca9-b87db334ce71', port: 11003, path: '/app/sync',          data: '5GB',  label: '⚡ DreamMaker Premium • Edge' },
      { name: 'plus',      uuid: 'e8eb3d74-8e8c-4903-b878-8feb656ebb0c', port: 11004, path: '/api/v2/feed',       data: '10GB', label: '🚀 DreamMaker Ultra • Turbo' },
      { name: 'pro',       uuid: 'b3540a54-67dd-452a-b5d8-45d6407b8da5', port: 11005, path: '/static/bundle.js',  data: '15GB', label: '💫 DreamMaker Pro • Smart' },
      { name: 'elite',     uuid: '2680152c-0dc3-4fdb-b366-e936358b121f', port: 11006, path: '/media/stream',      data: '20GB', label: '🔥 DreamMaker Elite • Priority' },
      { name: 'unlimited', uuid: '89c0f294-3f94-4735-96cf-9c1aefdbcbb2', port: 11007, path: '/v2/content/live',   data: '∞',    label: '💎 DreamMaker Infinity • Max' },
    ];
    return json({ ok: true, tiers });
  })
);

// GET /admin — dashboard UI
addRoute('GET', '/admin', async () => {
  const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>DreamMaker Admin</title>
  <style>
    *{box-sizing:border-box} body{margin:0;padding:20px;font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;background:#0f1419;color:#e0e0e0}
    .wrap{max-width:1100px;margin:0 auto} .header{padding:24px;border-radius:16px;background:linear-gradient(135deg,#667eea,#764ba2);margin-bottom:20px}
    .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:16px}
    .card{background:#1a1f2e;border:1px solid #333;border-radius:16px;padding:18px}
    h1,h2,h3{margin:0 0 12px} input,select,button{width:100%;padding:10px;border-radius:10px;border:1px solid #333;background:#0b1020;color:#fff;margin-top:8px}
    button{cursor:pointer;background:#667eea;border:none;font-weight:700} .row{display:flex;justify-content:space-between;gap:12px;padding:8px 0;border-bottom:1px solid #333}
    .row:last-child{border-bottom:none} .label{color:#aab} .val{font-weight:700;color:#8fb3ff}.mono{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;word-break:break-all}
    .msg{margin-top:10px;padding:10px 12px;border-radius:10px}.ok{background:rgba(81,207,102,.12);border:1px solid rgba(81,207,102,.4)}.err{background:rgba(255,107,107,.12);border:1px solid rgba(255,107,107,.4)}
    pre{white-space:pre-wrap;word-break:break-word;background:#0b1020;padding:10px;border-radius:10px;overflow:auto;max-height:220px}
  </style>
</head>
<body>
<div class="wrap">
  <div class="header">
    <h1>DreamMaker Control Plane</h1>
    <div>Administration & Monitoring</div>
  </div>

  <div class="grid">
    <div class="card">
      <h3>Authentication</h3>
      <input type="password" id="pwd" placeholder="Admin password">
      <button onclick="login()">Login</button>
      <div id="authMsg"></div>
    </div>

    <div class="card"><h3>Status</h3><div id="status"><p>Login to view</p></div></div>
    <div class="card"><h3>Tier Registry</h3><div id="tiers"><p>Login to view</p></div></div>
    <div class="card"><h3>Helpers</h3><div id="helpers"><p>Login to view</p></div></div>

    <div class="card">
      <h3>Add Helper</h3>
      <input id="edgeId" placeholder="Edge ID">
      <input id="helperUrl" placeholder="URL">
      <select id="helperMethod"><option>GET</option><option>HEAD</option><option>POST</option></select>
      <button onclick="addHelper()">Add</button>
      <div id="addMsg"></div>
    </div>

    <div class="card"><h3>Metrics (7 days)</h3><div id="metrics"><p>Login to view</p></div></div>
    <div class="card"><h3>Recent Audit Log</h3><div id="audit"><p>Login to view</p></div></div>
  </div>
</div>

<script>
let token = sessionStorage.getItem('dm_token');

async function api(path, method, body) {
  method = method || 'GET';
  const opts = { method: method, headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + token } };
  if (body) opts.body = JSON.stringify(body);
  const r = await fetch(path, opts);
  return await r.json();
}

async function login() {
  const pwd = document.getElementById('pwd').value;
  const r = await fetch('/admin/auth', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ password: pwd }) });
  const d = await r.json();
  if (d.ok) {
    token = d.token;
    sessionStorage.setItem('dm_token', token);
    document.getElementById('authMsg').innerHTML = '<div class="msg ok">Authenticated</div>';
    loadAll();
  } else {
    document.getElementById('authMsg').innerHTML = '<div class="msg err">' + (d.error || 'Auth failed') + '</div>';
  }
}

async function loadAll() {
  if (!token) return;
  loadStatus(); loadTiers(); loadHelpers(); loadMetrics(); loadAudit();
}

async function loadStatus() {
  const d = await api('/admin/api/status');
  if (!d.ok) return;
  const s = d.status || {};
  document.getElementById('status').innerHTML =
    '<div class="row"><span class="label">Edges</span><span class="val">' + ((s.edges && s.edges.length) || 0) + '</span></div>' +
    '<div class="row"><span class="label">Alerts</span><span class="val">' + ((s.alerts && s.alerts.length) || 0) + '</span></div>' +
    '<div class="row"><span class="label">Environment</span><span class="val">' + ((s.config && s.config.environment) || 'unknown') + '</span></div>';
}

async function loadTiers() {
  const d = await api('/admin/api/tiers');
  if (!d.ok) return;
  document.getElementById('tiers').innerHTML = (d.tiers || []).map(function(t) {
    return '<div class="row"><span class="label">' + t.label + '</span><span class="val mono">' + t.uuid.slice(0, 8) + '… <span class="badge">' + t.data + '</span></span></div>';
  }).join('');
}

async function loadHelpers() {
  const d = await api('/admin/api/helpers');
  if (!d.ok) return;
  const helpers = d.helpers || [];
  document.getElementById('helpers').innerHTML = helpers.length
    ? helpers.map(function(h) {
        return '<div class="row"><span class="label">' + h.edge_id + '</span><span class="val mono">' + String(h.url).slice(0, 40) + '…</span></div>';
      }).join('')
    : '<p>No helpers in D1. Using defaults.</p>';
}

async function addHelper() {
  const data = {
    edge_id: document.getElementById('edgeId').value,
    url: document.getElementById('helperUrl').value,
    method: document.getElementById('helperMethod').value,
    timeout: 5000
  };
  const r = await api('/admin/api/helpers', 'POST', data);
  document.getElementById('addMsg').innerHTML = r.ok
    ? '<div class="msg ok">Helper added</div>'
    : '<div class="msg err">' + (r.error || 'Failed') + '</div>';
  if (r.ok) setTimeout(loadHelpers, 500);
}

async function loadMetrics() {
  const d = await api('/admin/api/metrics?days=7');
  if (!d.ok || !d.report || !d.report.data) return;
  const data = d.report.data || [];
  document.getElementById('metrics').innerHTML = data.length
    ? data.slice(0, 5).map(function(m) {
        return '<div class="row"><span class="label">' + m.date + '</span><span class="val">' + m.requests + ' req · ' + Number(m.avg_latency || 0).toFixed(0) + 'ms avg</span></div>';
      }).join('')
    : '<p>No data yet</p>';
}

async function loadAudit() {
  const d = await api('/admin/api/audit?limit=10');
  if (!d.ok) return;
  const logs = d.logs || [];
  document.getElementById('audit').innerHTML = logs.map(function(l) {
    return '<div class="row"><span class="label mono">' + new Date(l.timestamp).toLocaleString() + '</span><span class="val">' + l.action + '</span></div>';
  }).join('');
}

if (token) { loadAll(); setInterval(loadAll, 30000); }
</script>
</body>
</html>`;

  return new Response(html, { headers: { 'Content-Type': 'text/html; charset=utf-8' } });
});

// ─────────────────────────────────────────────
// Default export
// ─────────────────────────────────────────────
export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      return await routeRequest(request, env);
    } catch (err) {
      console.error('Router error:', err);
      return json({ ok: false, error: String(err) }, 500);
    }
  },
};

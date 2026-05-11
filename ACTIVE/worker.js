// ============================================================
// DreamMaker VPN — edge-ws-relay-v4 (PATCHED v7.1)
// FIX: CDN loop error 1003 — backend must be IP:port directly
// FIX: WS backend changed from https://direct1... to http://IP:port
// ============================================================

// ─── Configuration ───────────────────────────────────────────
// CRITICAL FIX: Use IP:port directly — NOT hostname subdomains
// Subdomains are orange-cloud and match *.dreammaker-groupsoft.ir/*
// which routes BACK to this worker → CDN loop → error 1003
const GERMANY_BACKEND_IP  = "82.115.26.105";
const GERMANY_BACKEND_PORT = 2053;

// WS paths on the xray backend
const WS_PATH             = "/ws-vless";

// Host headers to send to xray (so xray can route by SNI/host)
const GERMANY_WS_HOST1    = "direct1.dreammaker-groupsoft.ir";
const GERMANY_WS_HOST2    = "direct2.dreammaker-groupsoft.ir";

// Full backend WS URLs — HTTP to IP directly, bypasses CF orange-cloud loop
const GERMANY_ORIGIN_WS   = `http://${GERMANY_BACKEND_IP}:${GERMANY_BACKEND_PORT}${WS_PATH}`;
const GERMANY_BACKUP_WS   = `http://${GERMANY_BACKEND_IP}:${GERMANY_BACKEND_PORT}${WS_PATH}`;

// ─── TIMEOUTS ─────────────────────────────────────────────
const DE_HEALTH_TIMEOUT     = 8_000;
const PANEL_TIMEOUT         = 30_000;
const FORCE_DE_ONLY         = true;
const WS_CONNECTION_TIMEOUT = 6_000;

// ─── CACHE & STATE ─────────────────────────────────────────
const STATE_CACHE_TTL       = 10;
const KV_STATE_TTL          = 300;
const KV_PREV_TTL           = 3_600;
const HEALTH_CHECK_INTERVAL = 120_000;
const ENABLE_DNS_CHECKS     = false;

// ─── UUID & Domain ────────────────────────────────────────
const UUID   = "a959df86-fce5-474f-a94c-049e24746713";
const DOMAIN = "dreammaker-groupsoft.ir";

// ─── KV Keys ──────────────────────────────────────────────
const KV_KEYS = {
  DE_ALIVE:           "de_alive",
  DE_PREV:            "de_prev_state",
  STATE_CACHE:        "state_cache_v7",
  TG_COOLDOWN:        "tg_cooldown",
  CLEAN_IPS:          "clean_ips",
  LAST_HEALTH_CHECK:  "last_health_check",
};

const CF_RANGES = [
  "173.245.48.0/20","103.21.244.0/22","103.22.200.0/22","103.31.4.0/22",
  "141.101.64.0/18","108.162.192.0/18","190.93.240.0/20","188.114.96.0/20",
  "197.234.240.0/22","198.41.128.0/17","162.158.0.0/15","104.16.0.0/13",
  "172.64.0.0/13","131.0.72.0/22",
].map(parseCidr).filter(Boolean);

const EDGES = [
  `cdn.${DOMAIN}`,
  ...Array.from({ length: 18 }, (_, i) => `edge${i + 1}.${DOMAIN}`),
];

const ALT_TLS_PORTS  = [2053, 2083, 2087, 8443];
const ALT_HTTP_PORTS = [8080, 8880, 2052];

const DEFAULT_CLEAN_IPS = [
  "104.19.230.65","172.65.19.210","172.65.172.83","172.65.5.165",
  "172.65.11.97","104.19.133.108","172.65.3.38","172.65.26.241",
  "104.18.180.218","104.17.231.210",
];

const WS_ONLY_PATHS = new Set(["/ws", "/ws-vless", "/grpc-vless"]);

const STRIP_REQ = new Set([
  "host","cf-connecting-ip","cf-ipcountry","cf-ray","cf-visitor",
  "x-forwarded-for","x-real-ip","x-forwarded-proto","x-forwarded-host",
  "cdn-loop","cf-worker","cf-ew-via",
]);

const STRIP_RESP = new Set(["alt-svc","x-powered-by","server"]);

const TG_COOLDOWN_TTL = 600;

// ─── IN-MEMORY STATE CACHE ────────────────────────────────
class StateCache {
  constructor() { this.cache = null; this.timestamp = 0; }
  isValid() { return this.cache && (Date.now() - this.timestamp) < (STATE_CACHE_TTL * 1000); }
  get() { return this.isValid() ? this.cache : null; }
  set(state) { this.cache = state; this.timestamp = Date.now(); }
  clear() { this.cache = null; this.timestamp = 0; }
}

const stateCache = new StateCache();

// ─── Entry Points ─────────────────────────────────────────
export default {
  async fetch(req, env, ctx) { return handleFetch(req, env, ctx); },
  async scheduled(event, env, ctx) { await runScheduledHealthCheck(env, ctx); },
};

// ─── MAIN ROUTER ──────────────────────────────────────────
async function handleFetch(req, env, ctx) {
  const url = new URL(req.url);
  const upg = (req.headers.get("Upgrade") ?? "").toLowerCase();

  if (upg === "websocket") return relayWS(req, env, ctx);

  switch (url.pathname) {
    case "/health":      return healthResponse(env, ctx);
    case "/ping":        return pingResponse(env, ctx);
    case "/sub":         return buildSub(env, ctx);
    case "/panel-debug": return panelDebugResponse(req, env, ctx);
    case "/worker-info": return workerInfoResponse(env, ctx);
  }

  if (WS_ONLY_PATHS.has(url.pathname)) {
    return new Response("WebSocket upgrade required", { status: 426 });
  }

  return proxyToPanel(req, env, ctx);
}

// ─── PANEL URL HELPER ─────────────────────────────────────
function getPanelOrigin(env) {
  return (
    env.HIDENLY_PANEL_URL?.trim() ||
    env.PANEL_BACKEND_URL?.trim() ||
    `http://${GERMANY_BACKEND_IP}:${GERMANY_BACKEND_PORT}`
  );
}

// ─── CORS HEADERS ─────────────────────────────────────────
function corsHeaders() {
  return {
    "Access-Control-Allow-Origin":      "*",
    "Access-Control-Allow-Methods":     "GET,POST,PUT,PATCH,DELETE,OPTIONS",
    "Access-Control-Allow-Headers":     "Content-Type,Authorization,X-Requested-With,Cookie,X-Csrf-Token",
    "Access-Control-Allow-Credentials": "true",
    "Access-Control-Max-Age":           "86400",
  };
}

// ─── PANEL PROXY ──────────────────────────────────────────
async function proxyToPanel(req, env, ctx) {
  const origin      = getPanelOrigin(env);
  const url         = new URL(req.url);
  const backendUrl  = `${origin}${url.pathname}${url.search}`;
  const backendHost = new URL(origin).hostname;
  const clientIp    = req.headers.get("CF-Connecting-IP") ?? "1.1.1.1";

  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders() });
  }

  const out = new Headers();
  for (const [k, v] of req.headers) {
    if (!STRIP_REQ.has(k.toLowerCase())) out.set(k, v);
  }
  out.set("Host",              backendHost);
  out.set("X-Real-IP",         clientIp);
  out.set("X-Forwarded-For",   clientIp);
  out.set("X-Forwarded-Proto", "https");
  out.set("X-Forwarded-Host",  url.hostname);

  const ctrl = new AbortController();
  const tid  = setTimeout(() => ctrl.abort(), PANEL_TIMEOUT);

  try {
    // FIX: Use http:// for IP-based backend, no TLS needed
    const resp = await fetch(backendUrl, {
      method:   req.method,
      headers:  out,
      body:     ["GET", "HEAD"].includes(req.method) ? undefined : req.body,
      redirect: "manual",
      signal:   ctrl.signal,
    });

    clearTimeout(tid);

    if (resp.status >= 300 && resp.status < 400 && resp.headers.has("location")) {
      const loc = resp.headers.get("location");
      const rh  = new Headers(corsHeaders());
      try {
        const locUrl = new URL(loc, backendUrl);
        if (locUrl.hostname === backendHost) {
          locUrl.hostname = url.hostname;
          locUrl.port     = "";
          locUrl.protocol = "https:";
          rh.set("location", locUrl.toString());
        } else {
          rh.set("location", loc);
        }
      } catch { rh.set("location", loc); }
      return new Response(null, { status: resp.status, headers: rh });
    }

    const rh = new Headers(corsHeaders());
    for (const [k, v] of resp.headers) {
      if (!STRIP_RESP.has(k.toLowerCase()) && k.toLowerCase() !== "set-cookie") {
        rh.set(k, v);
      }
    }

    const cookies = resp.headers.getSetCookie?.() ?? [];
    for (const c of cookies) {
      rh.append("set-cookie",
        c.replace(/;\s*domain=[^;]*/gi, "").replace(/;\s*secure/gi, "")
        + "; SameSite=None; Secure");
    }

    return new Response(resp.body, { status: resp.status, headers: rh });

  } catch (e) {
    clearTimeout(tid);
    return jsonResponse({
      error:  e.name === "AbortError" ? "panel timeout" : "panel error",
      detail: e.message,
      panel:  origin,
    }, 502);
  }
}

// ─── WEBSOCKET RELAY ──────────────────────────────────────
async function relayWS(req, env, ctx) {
  const pair   = new WebSocketPair();
  const [client, server] = Object.values(pair);
  server.accept();

  ctx.waitUntil((async () => {
    try {
      const state    = await getCachedState(env);
      // FIX: backends now use IP:port directly — no hostname subdomain fetches
      // host1/host2 = Host header sent to xray so it can match its inbound
      const backends = [
        { url: GERMANY_ORIGIN_WS, host: GERMANY_WS_HOST1 },
        { url: GERMANY_BACKUP_WS, host: GERMANY_WS_HOST2 },
      ];

      let backend = null;

      for (const b of backends) {
        try {
          backend = await openBackendWS(req, b.url, b.host);
          break;
        } catch (e) {
          console.warn(`[ws-relay] ${b.url} failed:`, e.message);
        }
      }

      if (!backend) {
        safeClose(server, 1011, "all backends failed");
        return;
      }

      pipeWebSockets(server, backend);
      await waitBothClosed(server, backend);

    } catch (err) {
      console.error("[ws-relay] relay error:", err);
      safeClose(server, 1011, "relay error");
    }
  })());

  return new Response(null, { status: 101, webSocket: client });
}

// ─── OPEN BACKEND WEBSOCKET ────────────────────────────────
// FIX: backendUrl = http://IP:port/path  (no CDN loop risk)
//      hostHeader = the hostname xray expects in "Host:"
async function openBackendWS(req, backendUrl, hostHeader) {
  const clientIp = req.headers.get("CF-Connecting-IP") ?? "1.1.1.1";

  const ctrl = new AbortController();
  const tid  = setTimeout(() => ctrl.abort(), WS_CONNECTION_TIMEOUT);

  try {
    const r = await fetch(backendUrl, {
      signal: ctrl.signal,
      headers: {
        "Upgrade":               "websocket",
        "Connection":            "Upgrade",
        "Host":                  hostHeader,
        "X-Real-IP":             clientIp,
        "X-Forwarded-For":       clientIp,
        "X-Forwarded-Host":      req.headers.get("Host") ?? "",
        "X-Forwarded-Proto":     "https",
        "Sec-WebSocket-Key":     req.headers.get("Sec-WebSocket-Key") ?? "dGhlIHNhbXBsZSBub25jZQ==",
        "Sec-WebSocket-Version": req.headers.get("Sec-WebSocket-Version") ?? "13",
      },
    });

    clearTimeout(tid);

    if (!r.webSocket) {
      throw new Error(`no WebSocket from backend (HTTP ${r.status})`);
    }

    r.webSocket.accept();
    return r.webSocket;
  } catch (e) {
    clearTimeout(tid);
    throw e;
  }
}

// ─── PIPE WEBSOCKETS ───────────────────────────────────────
function pipeWebSockets(a, b) {
  a.addEventListener("message", (e) => { try { b.send(e.data); } catch {} });
  b.addEventListener("message", (e) => { try { a.send(e.data); } catch {} });
  a.addEventListener("error",   () => safeClose(b, 1011, "peer error"));
  b.addEventListener("error",   () => safeClose(a, 1011, "peer error"));
}

function waitBothClosed(a, b) {
  return new Promise((done) => {
    let n = 0;
    const tick = () => { if (++n === 2) done(); };
    a.addEventListener("close", (e) => { safeClose(b, e.code || 1000, e.reason || ""); tick(); });
    b.addEventListener("close", (e) => { safeClose(a, e.code || 1000, e.reason || ""); tick(); });
  });
}

// ─── CACHED STATE ─────────────────────────────────────────
async function getCachedState(env) {
  const cached = stateCache.get();
  if (cached) return cached;

  const [deAlive] = await Promise.all([
    kvGet(env, KV_KEYS.DE_ALIVE),
  ]);

  const state = {
    de_alive: deAlive ?? "1",
  };

  stateCache.set(state);
  return state;
}

// ─── SCHEDULED HEALTH CHECK ───────────────────────────────
async function runScheduledHealthCheck(env, ctx) {
  const lastCheck = await kvGet(env, KV_KEYS.LAST_HEALTH_CHECK);
  const now = Date.now();

  if (lastCheck && (now - parseInt(lastCheck)) < HEALTH_CHECK_INTERVAL) return;

  await env.HEALTH_KV.put(KV_KEYS.LAST_HEALTH_CHECK, String(now), { expirationTtl: 86400 });

  const prevDe = await kvGet(env, KV_KEYS.DE_PREV);

  // FIX: probe via IP directly to avoid CDN loop
  const [de1Result, de2Result] = await Promise.allSettled([
    probeGermanyWS(GERMANY_ORIGIN_WS, GERMANY_WS_HOST1),
    probeGermanyWS(GERMANY_BACKUP_WS, GERMANY_WS_HOST2),
  ]);

  const deAlive = (de1Result.status === "fulfilled" && de1Result.value)
               || (de2Result.status === "fulfilled" && de2Result.value);

  const deStr   = deAlive ? "1" : "0";

  await Promise.all([
    env.HEALTH_KV.put(KV_KEYS.DE_ALIVE,   deStr,   { expirationTtl: KV_STATE_TTL }),
    env.HEALTH_KV.put(KV_KEYS.DE_PREV,    deStr,   { expirationTtl: KV_PREV_TTL }),
  ]);

  stateCache.clear();

  if (prevDe !== null && prevDe !== deStr) {
    const cooldownActive = (await kvGet(env, KV_KEYS.TG_COOLDOWN)) !== null;
    if (!cooldownActive) {
      const msg = deAlive
        ? "✅ *Germany VPS RECOVERED* — relay is operational."
        : `❌ *Germany VPS DOWN* — all clients affected!\nHost: ${GERMANY_BACKEND_IP}`;

      ctx.waitUntil(Promise.all([
        sendTelegram(env, msg),
        env.HEALTH_KV.put(KV_KEYS.TG_COOLDOWN, "1", { expirationTtl: TG_COOLDOWN_TTL }),
      ]));
    }
  }
}

// ─── BACKEND PROBES ───────────────────────────────────────
// FIX: pass hostHeader so fetch uses correct Host for xray routing
async function probeGermanyWS(url, hostHeader) {
  const ctrl = new AbortController();
  const tid  = setTimeout(() => ctrl.abort(), DE_HEALTH_TIMEOUT);

  try {
    const r = await fetch(url, {
      signal: ctrl.signal,
      headers: {
        "Upgrade":               "websocket",
        "Connection":            "Upgrade",
        "Host":                  hostHeader,
        "Sec-WebSocket-Key":     "dGhlIHNhbXBsZSBub25jZQ==",
        "Sec-WebSocket-Version": "13",
      },
    });
    return r.webSocket !== null;
  } catch { return false; }
  finally { clearTimeout(tid); }
}



// ─── CIDR HELPERS ─────────────────────────────────────────
function parseCidr(line) {
  const [raw, p] = line.split("/");
  const n = ipToInt(raw ?? "");
  return n !== null ? [n, parseInt(p ?? "32", 10)] : null;
}

function ipToInt(s) {
  const parts = s.split(".").map(Number);
  if (parts.length !== 4 || parts.some((p) => p < 0 || p > 255 || isNaN(p))) return null;
  return ((parts[0] * 256 + parts[1]) * 256 + parts[2]) * 256 + parts[3] >>> 0;
}

function isCfIp(ip) {
  const n = ipToInt(ip);
  if (n === null) return false;
  for (const [net, pre] of CF_RANGES) {
    const sh = 32 - pre;
    if ((n >>> sh) === (net >>> sh)) return true;
  }
  return false;
}

// ─── HTTP ENDPOINTS ───────────────────────────────────────
async function healthResponse(env, ctx) {
  const state = await getCachedState(env);
  return jsonResponse({
    ok:             true,
    version:        "v7.2-de-only",
    mode:           "germany_only",
    panel_backend:  getPanelOrigin(env),
    germany_ok:     state.de_alive === "1",
    backend_mode:   "direct_ip_no_loop",
    ts:             Date.now(),
  });
}

async function pingResponse(env, ctx) {
  const [d1, d2] = await Promise.allSettled([
    probeGermanyWS(GERMANY_ORIGIN_WS, GERMANY_WS_HOST1),
    probeGermanyWS(GERMANY_BACKUP_WS, GERMANY_WS_HOST2),
  ]);

  return jsonResponse({
    direct1_ok: d1.status === "fulfilled" ? d1.value : false,
    direct2_ok: d2.status === "fulfilled" ? d2.value : false,
    backend_ip: GERMANY_BACKEND_IP,
    ts:         Date.now(),
  });
}

async function panelDebugResponse(req, env, ctx) {
  const origin  = getPanelOrigin(env);
  const results = await Promise.all([
    testPanelPath(origin, "/"),
    testPanelPath(origin, "/health"),
    testPanelPath(origin, "/api/admin/user"),
  ]);

  return jsonResponse({
    panel_origin: origin,
    client_ip:    req.headers.get("CF-Connecting-IP") ?? "unknown",
    results,
    tip: results.every((r) => "error" in r)
      ? "Panel unreachable — check server IP/port"
      : "Panel reachable",
  });
}

async function testPanelPath(origin, path) {
  const url  = `${origin}${path}`;
  const ctrl = new AbortController();
  const tid  = setTimeout(() => ctrl.abort(), 8000);
  try {
    const r = await fetch(url, { signal: ctrl.signal, redirect: "manual" });
    return { path, status: r.status };
  } catch (e) {
    return { path, error: e.message };
  } finally { clearTimeout(tid); }
}

async function workerInfoResponse(env, ctx) {
  return jsonResponse({
    version:        "v7.2-de-only",
    domain:         DOMAIN,
    force_de_only:  FORCE_DE_ONLY,
    panel_backend:  getPanelOrigin(env),
    backend_ip:     GERMANY_BACKEND_IP,
    backend_port:   GERMANY_BACKEND_PORT,
    loop_fix:       "backend uses direct IP:port, not orange-cloud subdomains",
    edges_count:    EDGES.length,
  });
}

// ─── SUBSCRIPTION BUILDER ─────────────────────────────────
async function buildSub(env, ctx) {
  const cleanIps = await getCleanIPs(env);

  const mk = (host, port, security, extra, tag) =>
    `vless://${UUID}@${host}:${port}?encryption=none&security=${security}`
    + `&type=ws&host=${host}&path=%2Fws-vless${extra}#${tag}`;

  const edgeTls  = EDGES.map((h) => mk(h, 443, "tls", `&sni=${h}`, `DM-${h.split(".")[0]}-CF`));
  const edgeFrag = edgeTls.map(addFragment);
  const edgeAlt  = ALT_TLS_PORTS.flatMap((p) =>
    EDGES.map((h) => mk(h, p, "tls", `&sni=${h}`, `DM-${h.split(".")[0]}-${p}`)));
  const plain80  = cleanIps.map((ip, i) => {
    const h = EDGES[i % EDGES.length];
    return `vless://${UUID}@${ip}:80?encryption=none&security=none&type=ws&host=${h}&path=%2Fws-vless#DM-plain80-${i + 1}`;
  });
  const altHttp  = ALT_HTTP_PORTS.flatMap((p) =>
    cleanIps.map((ip, i) => {
      const h = EDGES[i % EDGES.length];
      return `vless://${UUID}@${ip}:${p}?encryption=none&security=none&type=ws&host=${h}&path=%2Fws-vless#DM-plain${p}-${i + 1}`;
    }));
  const direct   = [
    mk(`direct1.${DOMAIN}`, 443, "tls", `&sni=direct1.${DOMAIN}`, "DM-DE-direct1-443"),
    mk(`direct2.${DOMAIN}`, 443, "tls", `&sni=direct2.${DOMAIN}`, "DM-DE-direct2-443"),
    `vless://${UUID}@${GERMANY_BACKEND_IP}:80?encryption=none&security=none&type=ws&host=direct1.${DOMAIN}&path=%2Fws-vless#DM-DE-direct1-80`,
    `vless://${UUID}@${GERMANY_BACKEND_IP}:80?encryption=none&security=none&type=ws&host=direct2.${DOMAIN}&path=%2Fws-vless#DM-DE-direct2-80`,
  ];
  const gcoreHost = env.GCORE_HOST?.trim() ?? "";
  const gcore     = gcoreHost ? [
    mk(gcoreHost, 443, "tls", `&sni=${gcoreHost}`, "DM-Gcore"),
    mk(gcoreHost, 80,  "none", "", "DM-Gcore-80"),
  ] : [];
  const clean = cleanIps.map((ip, i) => {
    const h = EDGES[i % 5];
    return `vless://${UUID}@${ip}:443?encryption=none&security=tls&sni=${h}&type=ws&host=${h}&path=%2Fws-vless#DM-clean${i + 1}`;
  });
  const grpc = [
    `vless://${UUID}@cdn.${DOMAIN}:443?encryption=none&security=tls&type=grpc&serviceName=grpc-vless&host=cdn.${DOMAIN}&sni=cdn.${DOMAIN}#DM-gRPC`,
  ];

  const lines = [
    ...edgeAlt, ...edgeTls, ...edgeFrag, ...direct,
    ...gcore, ...gcore.map(addFragment), ...clean,
    ...plain80, ...altHttp, ...grpc,
  ];

  return new Response(toBase64(lines.join("\n")), {
    headers: {
      "Content-Type":                "text/plain; charset=utf-8",
      "Cache-Control":               "no-store",
      "Access-Control-Allow-Origin": "*",
      "X-Config-Count":              String(lines.length),
      "X-Worker-Version":            "v7.2-de-only",
    },
  });
}

async function getCleanIPs(env) {
  const raw = await kvGet(env, KV_KEYS.CLEAN_IPS);
  if (!raw) return DEFAULT_CLEAN_IPS;
  try {
    const parsed = JSON.parse(raw);
    if (Array.isArray(parsed)) {
      const ips = parsed.map(String).map((s) => s.trim()).filter(Boolean);
      return ips.length ? ips : DEFAULT_CLEAN_IPS;
    }
  } catch {}
  const ips = raw.split(/[,\n\r\t ]+/).map((s) => s.trim()).filter(Boolean);
  return ips.length ? ips : DEFAULT_CLEAN_IPS;
}

// ─── TELEGRAM ─────────────────────────────────────────────
async function sendTelegram(env, text) {
  const token  = env.TG_BOT_TOKEN?.trim();
  const chatId = env.TG_CHAT_ID?.trim();
  if (!token || !chatId) return;
  try {
    await fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
      method:  "POST",
      headers: { "Content-Type": "application/json" },
      body:    JSON.stringify({ chat_id: chatId, text, parse_mode: "Markdown" }),
    });
  } catch (e) { console.error("[telegram] Error:", e.message); }
}

// ─── UTILITIES ─────────────────────────────────────────────
async function kvGet(env, key) {
  try { return await env.HEALTH_KV.get(key); }
  catch (e) { console.error(`[kv] ${key}:`, e); return null; }
}

function safeClose(ws, code, reason) {
  try { ws.close(code, String(reason).slice(0, 123)); } catch {}
}

function jsonResponse(obj, status = 200) {
  return new Response(JSON.stringify(obj, null, 2), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", ...corsHeaders() },
  });
}

function addFragment(vlessUri) {
  const hash = vlessUri.lastIndexOf("#");
  if (hash === -1) return `${vlessUri}&fragment=1`;
  return `${vlessUri.slice(0, hash)}&fragment=1#${vlessUri.slice(hash + 1)}-F`;
}

function toBase64(s) {
  const bytes = new TextEncoder().encode(s);
  let bin = "";
  bytes.forEach((b) => { bin += String.fromCharCode(b); });
  return btoa(bin);
}

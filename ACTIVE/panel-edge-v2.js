// ============================================================================
// DreamMaker — Panel Edge v2 (Transparent Proxy)
// Subdomain: access.dreammaker-groupsoft.ir
// Backend:   http://82.115.26.105:2053/panel-proxy/ → Nginx → https://127.0.0.1:2822/jZ.../
//
// Unlike panel-access-worker.js (which adds its own HMAC cookie auth),
// this worker is a pure transparent reverse-proxy. The 3X-UI panel's own
// login/session handles authentication.
//
// DO NOT modify panel-access-worker.js — this is an independent second edge.
// ============================================================================

// Worker → http://82.115.26.105:2053/panel-proxy/  (HTTP, port 2053 already open to CF)
// Nginx on VPS: /panel-proxy/ → https://127.0.0.1:2822/jZMb26oGjigaPhSgj9/
// (proxy_ssl_verify off — loopback self-signed cert is fine)
const PANEL_ORIGIN   = "http://82.115.26.105:2053";
const PANEL_PREFIX   = "/panel-proxy";
const BACKEND_TIMEOUT_MS = 45_000;

const SECURITY_HEADERS = {
  "Strict-Transport-Security": "max-age=31536000; includeSubDomains; preload",
  "X-Content-Type-Options":    "nosniff",
  "X-Frame-Options":           "SAMEORIGIN",   // SAMEORIGIN (not DENY) — panel uses iframes
  "Referrer-Policy":           "strict-origin-when-cross-origin",
};

// Headers forwarded from CF to origin as-is (minus hop-by-hop)
const HOP_BY_HOP = new Set([
  "connection", "keep-alive", "proxy-authenticate", "proxy-authorization",
  "te", "trailers", "transfer-encoding", "upgrade",
  "cf-connecting-ip", "cf-ipcountry", "cf-ray", "cf-visitor",
]);

function buildBackendUrl(incomingUrl) {
  // Strip the public origin, prepend panel prefix
  // e.g. /login  ->  http://IP:2053/panel-proxy/login  -> Nginx -> https://127.0.0.1:2822/jZ.../login
  const url = new URL(incomingUrl);
  const path = url.pathname === "/" ? "/" : url.pathname;
  return `${PANEL_ORIGIN}${PANEL_PREFIX}${path}${url.search}`;
}

function rewriteLocation(location, publicOrigin) {
  // Panel may redirect to its own IP:port — rewrite to the public domain
  return location
    .replace(PANEL_ORIGIN + PANEL_PREFIX, publicOrigin)
    .replace(PANEL_ORIGIN, publicOrigin);
}

export default {
  async fetch(request, env) {
    // Diagnostic endpoint — verify worker is running
    if (new URL(request.url).pathname === "/__worker_ping") {
      return new Response(JSON.stringify({ ok: true, worker: "panel-edge-v2", ts: Date.now() }), {
        headers: { "Content-Type": "application/json" }
      });
    }

    const url          = new URL(request.url);
    const publicOrigin = url.origin;               // https://access.dreammaker-groupsoft.ir
    const backendUrl   = buildBackendUrl(request.url);
    const isWebSocket  = request.headers.get("Upgrade")?.toLowerCase() === "websocket";

    // ── WebSocket passthrough ────────────────────────────────────────────────
    if (isWebSocket) {
      // Cloudflare forwards WS upgrades natively — just re-fetch with same headers
      const wsReq = new Request(backendUrl, request);
      return fetch(wsReq);
    }

    // ── Build forwarded request headers ─────────────────────────────────────
    const fwdHeaders = new Headers();
    for (const [k, v] of request.headers) {
      if (!HOP_BY_HOP.has(k.toLowerCase())) fwdHeaders.set(k, v);
    }
    fwdHeaders.set("Host", "82.115.26.105:2053");

    // ── Fetch with timeout ───────────────────────────────────────────────────
    const controller = new AbortController();
    const timer      = setTimeout(() => controller.abort(), BACKEND_TIMEOUT_MS);

    let originResp;
    try {
      originResp = await fetch(backendUrl, {
        method:   request.method,
        headers:  fwdHeaders,
        body:     ["GET", "HEAD"].includes(request.method) ? undefined : request.body,
        redirect: "manual",
        signal:   controller.signal,
      });
    } catch (err) {
      clearTimeout(timer);
      if (err.name === "AbortError") return new Response(`Origin timeout | url=${backendUrl}`, { status: 504 });
      console.error("panel-edge-v2 fetch error:", err);
      return new Response(`Origin unreachable: ${err.message} | url=${backendUrl}`, { status: 502 });
    }
    clearTimeout(timer);

    // ── Build response headers ───────────────────────────────────────────────
    const respHeaders = new Headers(originResp.headers);

    // Rewrite Location on redirects
    const location = respHeaders.get("Location");
    if (location) {
      respHeaders.set("Location", rewriteLocation(location, publicOrigin));
    }

    // Rewrite Set-Cookie domain/path if panel sets them
    const setCookie = respHeaders.get("Set-Cookie");
    if (setCookie) {
      // Remove Secure flag mismatch issues; CF handles TLS
      respHeaders.set("Set-Cookie", setCookie.replace(/;\s*Secure/gi, "; Secure"));
    }

    // Add security headers
    for (const [k, v] of Object.entries(SECURITY_HEADERS)) {
      respHeaders.set(k, v);
    }

    // Remove hop-by-hop from origin response
    for (const h of HOP_BY_HOP) respHeaders.delete(h);

    // ── Body rewriting (HTML/JS/JSON — rewrite absolute URLs) ───────────────
    const ct = respHeaders.get("Content-Type") ?? "";
    if (ct.includes("text/html") || ct.includes("application/javascript") || ct.includes("application/json")) {
      const body = await originResp.text();
      const rewritten = body
        .replaceAll(PANEL_ORIGIN + PANEL_PREFIX, publicOrigin)
        .replaceAll(PANEL_ORIGIN, publicOrigin)
        .replaceAll(`"${PANEL_PREFIX}/`, `"/`)
        .replaceAll(`'${PANEL_PREFIX}/`, `'/`);
      return new Response(rewritten, {
        status:     originResp.status,
        statusText: originResp.statusText,
        headers:    respHeaders,
      });
    }

    return new Response(originResp.body, {
      status:     originResp.status,
      statusText: originResp.statusText,
      headers:    respHeaders,
    });
  },
};

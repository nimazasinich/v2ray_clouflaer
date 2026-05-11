// DreamMaker — admin.dreammaker-groupsoft.ir (transparent proxy)
// Backend: http://direct1.dreammaker-groupsoft.ir:2053/panel-proxy/ → Nginx → https://127.0.0.1:2822/jZMb26oGjigaPhSgj9/
// FIX: Changed from 82.115.26.105 IP to direct1.dreammaker-groupsoft.ir (grey-cloud)

const PANEL_ORIGIN   = "http://direct1.dreammaker-groupsoft.ir:2053";
const PANEL_PREFIX   = "/panel-proxy";
const BACKEND_TIMEOUT_MS = 45_000;

const SECURITY_HEADERS = {
  "Strict-Transport-Security": "max-age=31536000; includeSubDomains; preload",
  "X-Content-Type-Options":    "nosniff",
  "X-Frame-Options":           "SAMEORIGIN",
  "Referrer-Policy":           "strict-origin-when-cross-origin",
};

const HOP_BY_HOP = new Set([
  "connection", "keep-alive", "proxy-authenticate", "proxy-authorization",
  "te", "trailers", "transfer-encoding", "upgrade",
  "cf-connecting-ip", "cf-ipcountry", "cf-ray", "cf-visitor",
]);

function buildBackendUrl(incomingUrl) {
  const url = new URL(incomingUrl);
  const path = url.pathname === "/" ? "/" : url.pathname;
  return `${PANEL_ORIGIN}${PANEL_PREFIX}${path}${url.search}`;
}

function rewriteLocation(location, publicOrigin) {
  return location
    .replace(PANEL_ORIGIN + PANEL_PREFIX, publicOrigin)
    .replace(PANEL_ORIGIN, publicOrigin);
}

export default {
  async fetch(request, env) {
    if (new URL(request.url).pathname === "/__worker_ping") {
      return new Response(JSON.stringify({ ok: true, worker: "panel-access", ts: Date.now() }), {
        headers: { "Content-Type": "application/json" }
      });
    }

    const url          = new URL(request.url);
    const publicOrigin = url.origin;
    const backendUrl   = buildBackendUrl(request.url);
    const isWebSocket  = request.headers.get("Upgrade")?.toLowerCase() === "websocket";

    if (isWebSocket) {
      const wsReq = new Request(backendUrl, request);
      return fetch(wsReq);
    }

    const fwdHeaders = new Headers();
    for (const [k, v] of request.headers) {
      if (!HOP_BY_HOP.has(k.toLowerCase())) fwdHeaders.set(k, v);
    }
    fwdHeaders.set("Host", "direct1.dreammaker-groupsoft.ir:2053");

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
      console.error("panel-access fetch error:", err);
      return new Response(`Origin unreachable: ${err.message} | url=${backendUrl}`, { status: 502 });
    }
    clearTimeout(timer);

    const respHeaders = new Headers(originResp.headers);

    const location = respHeaders.get("Location");
    if (location) {
      respHeaders.set("Location", rewriteLocation(location, publicOrigin));
    }

    const setCookie = respHeaders.get("Set-Cookie");
    if (setCookie) {
      respHeaders.set("Set-Cookie", setCookie.replace(/;\s*Secure/gi, "; Secure"));
    }

    for (const [k, v] of Object.entries(SECURITY_HEADERS)) {
      respHeaders.set(k, v);
    }

    for (const h of HOP_BY_HOP) respHeaders.delete(h);

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

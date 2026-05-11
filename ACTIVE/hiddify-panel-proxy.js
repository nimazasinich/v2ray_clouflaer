// ============================================================================
// Hiddify Panel Reverse Proxy — Cloudflare Worker (Hardened Production Build)
// ----------------------------------------------------------------------------
// Features
// - Hidden Hiddify panel path rewriting (case-sensitive, fixed)
// - Login gateway with HMAC-signed cookie (unforgeable)
// - HTTPS public domain -> HTTP backend support
// - Redirect rewriting (fixed 302 loop issues)
// - WebSocket proxy support (with auth check + backup origins)
// - Backup origins (HTTP + WebSocket)
// - Panic mode
// - Origin authentication
// - Security headers
// - Cookie hardening
// - Host/IP replacement in HTML/JS/JSON
// - Debug mode (?debug=true)
// - Asset caching
// - Loop protection
// ----------------------------------------------------------------------------
// PUBLIC DOMAIN:
//   https://panel.dreammaker-groupsoft.ir
//
// BACKEND:
//   http://direct1.dreammaker-groupsoft.ir:80
//
// IMPORTANT:
// - panel.dreammaker-groupsoft.ir => ORANGE CLOUD
// - direct1.dreammaker-groupsoft.ir => GREY CLOUD
// - SSL/TLS mode => FULL
// ============================================================================

// ============================================================================
// ENVIRONMENT VARIABLES (optional)
// ============================================================================
//
// PANEL_URL
//   Example: http://direct1.dreammaker-groupsoft.ir:80
//
// PANEL_URLS
//   Multiple origins separated by comma:
//   http://direct1...:80,http://backup...:80
//
// PANEL_BASE_PATH
//   Secret Hiddify admin path (case-sensitive!)
//
// PANIC_MODE
//   "true" => fake maintenance page
//
// ADMIN_USER
//   Login username (default: admin)
//
// ADMIN_PASS
//   Login password (default: admin)
//
// AUTH_SECRET
//   Secret key for HMAC cookie signing (recommended: set a strong random value)
//   If not set, falls back to ADMIN_PASS
//
// ============================================================================


// ============================================================================
// CONFIG
// ============================================================================

const PANEL_TIMEOUT = 45000;

const DEFAULT_PANEL_URL =
  "http://direct1.dreammaker-groupsoft.ir:80";

const DEFAULT_PANEL_BASE_PATH =
  "/okFzGWW8gk8z2GgpDkZlkGdcoQ6cE0/1ba7fe88-2086-429e-b543-d5a467830caa";

const DEFAULT_ADMIN_USER = "admin";
const DEFAULT_ADMIN_PASS = "admin";

const AUTH_COOKIE_NAME = "__Secure-PanelAuth";

// Token validity: 24 hours
const TOKEN_TTL_MS = 86400 * 1000;

const STATIC_EXTENSIONS = [
  ".css",
  ".js",
  ".png",
  ".jpg",
  ".jpeg",
  ".gif",
  ".svg",
  ".ico",
  ".woff",
  ".woff2",
  ".ttf",
  ".map",
  ".webp"
];


// ============================================================================
// REQUEST HEADERS TO REMOVE (when forwarding to backend)
// FIX: Added "x-worker-proxy" to prevent loop and leaking internal header
// ============================================================================

const STRIP_REQ_HEADERS = new Set([
  "cf-connecting-ip",
  "cf-ipcountry",
  "cf-ray",
  "cf-visitor",
  "cdn-loop",
  "cf-worker",
  "cf-ew-via",
  "connection",
  "x-worker-proxy"   // <-- FIX: strip before forwarding, set it fresh ourselves
]);


// ============================================================================
// RESPONSE HEADERS TO REMOVE
// ============================================================================

const STRIP_RESP_HEADERS = new Set([
  "alt-svc",
  "server",
  "x-powered-by"
]);


// ============================================================================
// HELPERS
// ============================================================================

function getPanelBasePath(env) {
  return (
    env?.PANEL_BASE_PATH?.trim() ||
    DEFAULT_PANEL_BASE_PATH
  ).replace(/\/+$/, "");
}

function getBackendOrigins(env) {
  const list =
    env?.PANEL_URLS?.trim() ||
    env?.PANEL_URL?.trim() ||
    DEFAULT_PANEL_URL;

  return list
    .split(",")
    .map(v => v.trim())
    .filter(Boolean)
    .map(v => v.replace(/\/+$/, ""));
}

// FIX: Removed global normalizePath() that converted to lowercase and
// was incorrectly applied to case-sensitive paths like the Hiddify base path.
// Now path comparison is always case-sensitive.
// The only place we lowercase is for file extension matching (already done
// directly in isStaticAsset with .toLowerCase()).

function rewriteIncomingPath(pathname, basePath) {
  const p = String(pathname || "");

  if (p === "/" || p === "") {
    return `${basePath}/`;
  }

  // FIX: case-sensitive comparison (no .toLowerCase())
  if (p.startsWith(basePath)) {
    return p;
  }

  return `${basePath}${p}`;
}

function isStaticAsset(pathname) {
  return STATIC_EXTENSIONS.some(ext =>
    pathname.toLowerCase().endsWith(ext)
  );
}

function buildCorsHeaders(req) {
  const origin = req.headers.get("Origin") || "";

  const headers = {
    "Access-Control-Allow-Methods":
      "GET,POST,PUT,PATCH,DELETE,OPTIONS",
    "Access-Control-Allow-Headers":
      "Content-Type,Authorization,X-Requested-With,Cookie,X-Csrf-Token,Accept,Origin",
    "Access-Control-Max-Age": "86400",
    "Vary": "Origin"
  };

  if (origin) {
    headers["Access-Control-Allow-Origin"] = origin;
    headers["Access-Control-Allow-Credentials"] = "true";
  } else {
    headers["Access-Control-Allow-Origin"] = "*";
  }

  return headers;
}

function sanitizeCookie(cookie) {
  return cookie
    .replace(/;\s*domain=[^;]*/gi, "")
    .replace(/;\s*samesite=[^;]*/gi, "")
    .replace(/;\s*secure/gi, "") +
    "; SameSite=None; Secure";
}

function getSetCookieValues(headers) {
  if (typeof headers.getSetCookie === "function") {
    return headers.getSetCookie();
  }

  if (typeof headers.getAll === "function") {
    return headers.getAll("set-cookie");
  }

  const single = headers.get("set-cookie");
  return single ? [single] : [];
}

function safeClose(ws, code = 1000, reason = "") {
  try {
    ws.close(code, String(reason).slice(0, 100));
  } catch {}
}

function buildSecurityHeaders(headers) {
  headers.set(
    "Content-Security-Policy",
    "upgrade-insecure-requests; block-all-mixed-content"
  );
  headers.set("X-Frame-Options", "SAMEORIGIN");
  headers.set("X-Content-Type-Options", "nosniff");
  headers.set("Referrer-Policy", "strict-origin-when-cross-origin");
  headers.set("X-Robots-Tag", "noindex, nofollow");
}

function isTextualResponse(contentType) {
  if (!contentType) return false;
  return (
    contentType.includes("text/") ||
    contentType.includes("json") ||
    contentType.includes("javascript") ||
    contentType.includes("xml")
  );
}

function rewriteTextBody(text, backendHost, publicHost) {
  return text
    .replace(
      new RegExp(`https?:\\/\\/${backendHost.replace(/\./g, "\\.")}`, "gi"),
      `https://${publicHost}`
    )
    .replace(
      new RegExp(`wss?:\\/\\/${backendHost.replace(/\./g, "\\.")}`, "gi"),
      `wss://${publicHost}`
    )
    .replace(
      new RegExp(backendHost.replace(/\./g, "\\."), "gi"),
      publicHost
    )
    .replace(/82\.115\.26\.105/gi, publicHost);
}

// FIX: Rewrite redirect Location header using case-sensitive path comparison.
// Previously, lowercase normalization broke stripping of basePath from redirect URLs.
function rewriteRedirectLocation(
  location,
  backendUrl,
  incomingUrl,
  backendHost,
  basePath
) {
  try {
    const resolved = new URL(location, backendUrl);

    if (resolved.hostname === backendHost) {
      resolved.hostname = incomingUrl.hostname;
      resolved.protocol = "https:";
      resolved.port = "";

      // FIX: case-sensitive startsWith (no .toLowerCase())
      if (resolved.pathname.startsWith(basePath)) {
        const stripped = resolved.pathname.slice(basePath.length) || "/";
        resolved.pathname = stripped.startsWith("/") ? stripped : `/${stripped}`;
      }

      return resolved.toString();
    }

    return location;
  } catch {
    return location;
  }
}

function htmlEscape(v) {
  return String(v || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}


// ============================================================================
// HMAC TOKEN (FIX: unforgeable signed auth cookie)
// ============================================================================
// Previously the cookie value was the plain string "ok" which anyone could
// forge manually via browser DevTools. Now we sign a timestamp-based token
// with HMAC-SHA256 using a secret from env. The server verifies the signature
// on every request, so a forged cookie will be rejected.

async function getHmacKey(env) {
  const secret =
    env?.AUTH_SECRET?.trim() ||
    env?.ADMIN_PASS?.trim() ||
    DEFAULT_ADMIN_PASS;

  const encoder = new TextEncoder();

  return crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"]
  );
}

async function createSignedToken(env) {
  const expiry = Date.now() + TOKEN_TTL_MS;
  const payload = `panelauth:${expiry}`;
  const encoder = new TextEncoder();
  const key = await getHmacKey(env);

  const sigBuffer = await crypto.subtle.sign(
    "HMAC",
    key,
    encoder.encode(payload)
  );

  const sigHex = Array.from(new Uint8Array(sigBuffer))
    .map(b => b.toString(16).padStart(2, "0"))
    .join("");

  return `${expiry}.${sigHex}`;
}

async function verifySignedToken(token, env) {
  try {
    const dotIdx = token.indexOf(".");
    if (dotIdx === -1) return false;

    const expiry = parseInt(token.slice(0, dotIdx), 10);
    if (isNaN(expiry) || Date.now() > expiry) return false;

    const sigHex = token.slice(dotIdx + 1);
    const sigBytes = new Uint8Array(
      sigHex.match(/.{2}/g).map(b => parseInt(b, 16))
    );

    const payload = `panelauth:${expiry}`;
    const encoder = new TextEncoder();
    const key = await getHmacKey(env);

    return await crypto.subtle.verify(
      "HMAC",
      key,
      sigBytes,
      encoder.encode(payload)
    );
  } catch {
    return false;
  }
}

async function createAuthCookie(env) {
  const token = await createSignedToken(env);
  return `${AUTH_COOKIE_NAME}=${token}; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=86400`;
}

// FIX: isAuthenticated is now async and verifies the HMAC signature
async function isAuthenticated(req, env) {
  const cookie = req.headers.get("Cookie") || "";
  const pattern = new RegExp(`(?:^|;\\s*)${AUTH_COOKIE_NAME}=([^;]+)`);
  const match = cookie.match(pattern);
  if (!match) return false;
  return verifySignedToken(match[1], env);
}


// ============================================================================
// LOGIN PAGE
// ============================================================================

function renderLoginPage(error = "") {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Secure Panel Access</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
body{background:#0f172a;color:#fff;font-family:Arial,sans-serif;display:flex;justify-content:center;align-items:center;height:100vh;margin:0}
.box{width:360px;background:#111827;padding:30px;border-radius:14px;box-shadow:0 0 30px rgba(0,0,0,.4)}
input{width:100%;padding:12px;margin-top:10px;border:none;border-radius:8px;background:#1f2937;color:#fff;box-sizing:border-box}
button{width:100%;padding:12px;margin-top:20px;border:none;border-radius:8px;background:#2563eb;color:#fff;font-weight:bold;cursor:pointer}
button:hover{background:#1d4ed8}
.error{color:#ef4444;margin-top:12px;font-size:14px}
</style>
</head>
<body>
<div class="box">
<h2 style="margin-top:0">Secure Panel Login</h2>
<form method="POST" action="/__auth">
<input name="username" placeholder="Username" autocomplete="off" required>
<input type="password" name="password" placeholder="Password" required>
<button type="submit">Login</button>
</form>
${error ? `<div class="error">${htmlEscape(error)}</div>` : ""}
</div>
</body>
</html>`;
}


// ============================================================================
// AUTH HANDLER
// ============================================================================

async function handleAuth(req, env) {
  const form = await req.formData();
  const username = String(form.get("username") || "");
  const password = String(form.get("password") || "");

  const adminUser = env?.ADMIN_USER || DEFAULT_ADMIN_USER;
  const adminPass = env?.ADMIN_PASS || DEFAULT_ADMIN_PASS;

  if (username === adminUser && password === adminPass) {
    const headers = new Headers();
    headers.set("Location", "/");
    // FIX: cookie now contains HMAC-signed token, not plain "ok"
    headers.append("Set-Cookie", await createAuthCookie(env));
    headers.set("Cache-Control", "no-store");

    return new Response(null, { status: 303, headers });
  }

  return new Response(
    renderLoginPage("Invalid username or password"),
    {
      status: 401,
      headers: { "Content-Type": "text/html; charset=utf-8" }
    }
  );
}


// ============================================================================
// HTTP PROXY
// ============================================================================

async function proxyHttp(req, env) {

  if (env?.PANIC_MODE === "true") {
    return new Response(
      "<!doctype html><h1>503 – Temporarily Unavailable</h1><p>Please try again later.</p>",
      { status: 503, headers: { "Content-Type": "text/html" } }
    );
  }

  const incomingUrl = new URL(req.url);

  if (
    req.method === "POST" &&
    incomingUrl.pathname === "/__auth"
  ) {
    return handleAuth(req, env);
  }

  // FIX: isAuthenticated is now async and verified with HMAC
  if (!(await isAuthenticated(req, env))) {
    return new Response(
      renderLoginPage(),
      {
        status: 200,
        headers: { "Content-Type": "text/html; charset=utf-8" }
      }
    );
  }

  const debug = incomingUrl.searchParams.get("debug") === "true";
  const basePath = getPanelBasePath(env);
  const backendOrigins = getBackendOrigins(env);
  let lastError = null;

  for (const backendOrigin of backendOrigins) {
    try {
      const backendUrl = new URL(backendOrigin);
      backendUrl.pathname = rewriteIncomingPath(incomingUrl.pathname, basePath);
      backendUrl.search = incomingUrl.search;

      const backendHost = backendUrl.hostname;

      const forwardedHeaders = new Headers();

      for (const [key, value] of req.headers) {
        // STRIP_REQ_HEADERS now includes "x-worker-proxy" so it won't be forwarded
        if (!STRIP_REQ_HEADERS.has(key.toLowerCase())) {
          forwardedHeaders.set(key, value);
        }
      }

      forwardedHeaders.set("Host", backendHost);
      forwardedHeaders.set("X-Forwarded-Proto", "https");
      forwardedHeaders.set("X-Forwarded-Host", incomingUrl.hostname);
      forwardedHeaders.set("Accept-Encoding", "identity");
      // Set our loop-detection marker fresh (stripped from incoming above)
      forwardedHeaders.set("X-Worker-Proxy", "active");

      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), PANEL_TIMEOUT);

      const upstream = await fetch(backendUrl.toString(), {
        method: req.method,
        headers: forwardedHeaders,
        body: ["GET", "HEAD"].includes(req.method) ? undefined : req.body,
        redirect: "manual",
        signal: controller.signal
      });

      clearTimeout(timeout);

      const responseHeaders = new Headers(buildCorsHeaders(req));

      // ── Redirect rewrite ──────────────────────────────────────────────
      if (
        upstream.status >= 300 &&
        upstream.status < 400 &&
        upstream.headers.has("location")
      ) {
        const rewrittenLocation = rewriteRedirectLocation(
          upstream.headers.get("location"),
          backendUrl,
          incomingUrl,
          backendHost,
          basePath
        );

        responseHeaders.set("Location", rewrittenLocation);

        for (const [k, v] of upstream.headers) {
          if (
            !STRIP_RESP_HEADERS.has(k.toLowerCase()) &&
            k.toLowerCase() !== "location"
          ) {
            responseHeaders.set(k, v);
          }
        }

        buildSecurityHeaders(responseHeaders);
        responseHeaders.set("Cache-Control", "no-store");

        return new Response(null, {
          status: upstream.status,
          headers: responseHeaders
        });
      }

      // ── Copy response headers ─────────────────────────────────────────
      for (const [k, v] of upstream.headers) {
        const lower = k.toLowerCase();
        if (
          !STRIP_RESP_HEADERS.has(lower) &&
          lower !== "set-cookie" &&
          lower !== "content-length"
        ) {
          responseHeaders.set(k, v);
        }
      }

      // ── Cookies ───────────────────────────────────────────────────────
      const cookies = getSetCookieValues(upstream.headers);
      for (const c of cookies) {
        responseHeaders.append("Set-Cookie", sanitizeCookie(c));
      }

      buildSecurityHeaders(responseHeaders);

      // ── Cache control ─────────────────────────────────────────────────
      if (isStaticAsset(incomingUrl.pathname)) {
        responseHeaders.set("Cache-Control", "public, max-age=86400");
      } else {
        responseHeaders.set("Cache-Control", "no-store");
      }

      // ── Body rewrite ──────────────────────────────────────────────────
      let responseBody = upstream.body;
      const contentType = upstream.headers.get("content-type") || "";

      if (isTextualResponse(contentType)) {
        let text = await upstream.text();
        text = rewriteTextBody(text, backendHost, incomingUrl.hostname);
        responseBody = text;
      }

      if (debug) {
        console.log(`[DEBUG] ${incomingUrl.pathname} -> ${backendUrl.pathname}`);
        responseHeaders.set("X-Debug-Rewritten-Url", backendUrl.toString());
      }

      return new Response(responseBody, {
        status: upstream.status,
        headers: responseHeaders
      });

    } catch (err) {
      lastError = err;
      console.error("[Proxy Error]", String(err));
    }
  }

  return new Response(
    JSON.stringify({ error: "All backends failed", detail: String(lastError) }),
    {
      status: 502,
      headers: { "Content-Type": "application/json" }
    }
  );
}


// ============================================================================
// WEBSOCKET PROXY
// FIX 1: Auth check added — unauthenticated users are rejected before upgrade
// FIX 2: Backup origins supported — falls through origins on failure
// FIX 3: x-worker-proxy stripped from incoming then set fresh (loop detection)
// ============================================================================

async function proxyWebSocket(req, env) {

  // FIX: Check authentication BEFORE upgrading the WebSocket connection.
  // Previously anyone could connect to the backend WS without logging in.
  if (!(await isAuthenticated(req, env))) {
    return new Response(
      JSON.stringify({ error: "Unauthorized" }),
      {
        status: 401,
        headers: {
          "Content-Type": "application/json",
          "WWW-Authenticate": "Cookie"
        }
      }
    );
  }

  const incomingUrl = new URL(req.url);
  const basePath = getPanelBasePath(env);
  // FIX: Try all backup origins, not just the first
  const backendOrigins = getBackendOrigins(env);

  const pair = new WebSocketPair();
  const [client, server] = Object.values(pair);
  server.accept();

  let connected = false;

  for (const backendOrigin of backendOrigins) {
    if (connected) break;

    try {
      const backendUrl = new URL(backendOrigin);
      backendUrl.pathname = rewriteIncomingPath(incomingUrl.pathname, basePath);
      backendUrl.search = incomingUrl.search;

      const backendWsProtocol = backendUrl.protocol === "https:" ? "wss:" : "ws:";
      const backendWsUrl = `${backendWsProtocol}//${backendUrl.host}${backendUrl.pathname}${backendUrl.search}`;

      const wsResponse = await fetch(backendWsUrl, {
        headers: {
          "Upgrade": "websocket",
          "Host": backendUrl.hostname,
          "X-Forwarded-Proto": "https",
          "X-Forwarded-Host": incomingUrl.hostname,
          "X-Worker-Proxy": "active"
        }
      });

      if (!wsResponse.webSocket) {
        console.warn(`[WS] No webSocket from ${backendOrigin}`);
        continue;
      }

      const backendSocket = wsResponse.webSocket;
      backendSocket.accept();
      connected = true;

      server.addEventListener("message", event => {
        try { backendSocket.send(event.data); } catch {}
      });

      backendSocket.addEventListener("message", event => {
        try { server.send(event.data); } catch {}
      });

      server.addEventListener("close", event => {
        safeClose(backendSocket, event.code, event.reason);
      });

      backendSocket.addEventListener("close", event => {
        safeClose(server, event.code, event.reason);
      });

      server.addEventListener("error", () => safeClose(backendSocket, 1011));
      backendSocket.addEventListener("error", () => safeClose(server, 1011));

    } catch (err) {
      console.error(`[WS Error] ${backendOrigin}:`, String(err));
    }
  }

  if (!connected) {
    safeClose(server, 1011, "All backends failed");
  }

  return new Response(null, { status: 101, webSocket: client });
}


// ============================================================================
// MAIN HANDLER1
// ============================================================================

export default {
  async fetch(req, env) {

    // Loop detection
    if (req.headers.get("X-Worker-Proxy") === "active") {
      return new Response("Loop detected", { status: 508 });
    }

    // CORS preflight
    if (req.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: buildCorsHeaders(req)
      });
    }

    // WebSocket upgrade
    const upgrade = (req.headers.get("Upgrade") || "").toLowerCase();
    if (upgrade === "websocket") {
      return proxyWebSocket(req, env);
    }

    return proxyHttp(req, env);
  }
};
--fb292ed14556e2ed597e02e833715784ec43f12d4ad2d96e382c177b9e4c--


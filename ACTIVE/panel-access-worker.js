// ============================================================================
// 3X-UI Panel Reverse Proxy — Cloudflare Worker (Hardened Production Build)
// ----------------------------------------------------------------------------
// Purpose: Provide filter-free access to 3X-UI panel from Iran
// Public Domain: https://admin.dreammaker-groupsoft.ir
// Backend: http://82.115.26.105:2053/panel-proxy/ → Nginx → https://127.0.0.1:2822/jZMb26oGjigaPhSgj9/
// ============================================================================

const PANEL_TIMEOUT = 45000;

// Route through Nginx on port 2053 (same as all workers).
// Nginx /panel-proxy/ → https://127.0.0.1:2822/jZMb26oGjigaPhSgj9/ (proxy_ssl_verify off)
const DEFAULT_PANEL_URL = "http://82.115.26.105:2053";
const DEFAULT_PANEL_BASE_PATH = "/panel-proxy/";
const DEFAULT_ADMIN_USER = "admin";
const DEFAULT_ADMIN_PASS = "admin123";

const AUTH_COOKIE_NAME = "__Secure-3XUIAuth";
const TOKEN_TTL_MS = 86400 * 1000; // 24 hours

// Security headers
const SECURITY_HEADERS = {
  "Strict-Transport-Security": "max-age=31536000; includeSubDomains; preload",
  "X-Content-Type-Options": "nosniff",
  "X-Frame-Options": "DENY",
  "X-XSS-Protection": "1; mode=block",
  "Referrer-Policy": "strict-origin-when-cross-origin",
  "Content-Security-Policy": "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:; connect-src 'self'",
  "Permissions-Policy": "geolocation=(), microphone=(), camera=()"
};

// ============================================================================
// Utility: HMAC-SHA256 signing
// ============================================================================
async function hmacSign(message, secret) {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const signature = await crypto.subtle.sign("HMAC", key, encoder.encode(message));
  return Array.from(new Uint8Array(signature))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

async function verifyToken(token, secret) {
  try {
    const [timestamp, signature] = token.split(".");
    if (!timestamp || !signature) return false;
    
    const now = Date.now();
    const tokenTime = parseInt(timestamp, 10);
    if (now - tokenTime > TOKEN_TTL_MS) return false;
    
    const expectedSig = await hmacSign(timestamp, secret);
    return signature === expectedSig;
  } catch {
    return false;
  }
}

async function generateToken(secret) {
  const timestamp = Date.now().toString();
  const signature = await hmacSign(timestamp, secret);
  return `${timestamp}.${signature}`;
}

// ============================================================================
// Login page HTML
// ============================================================================
function loginPage(error = "") {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>3X-UI Panel - Login</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', sans-serif;
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      display: flex;
      justify-content: center;
      align-items: center;
      min-height: 100vh;
      padding: 20px;
    }
    .container {
      background: white;
      border-radius: 12px;
      box-shadow: 0 10px 40px rgba(0,0,0,0.2);
      padding: 40px;
      width: 100%;
      max-width: 400px;
    }
    h1 {
      color: #333;
      margin-bottom: 10px;
      font-size: 28px;
      text-align: center;
    }
    .subtitle {
      color: #666;
      text-align: center;
      margin-bottom: 30px;
      font-size: 14px;
    }
    .form-group {
      margin-bottom: 20px;
    }
    label {
      display: block;
      color: #555;
      margin-bottom: 8px;
      font-size: 14px;
      font-weight: 500;
    }
    input {
      width: 100%;
      padding: 12px;
      border: 2px solid #e0e0e0;
      border-radius: 8px;
      font-size: 14px;
      transition: border-color 0.3s;
    }
    input:focus {
      outline: none;
      border-color: #667eea;
    }
    button {
      width: 100%;
      padding: 12px;
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      color: white;
      border: none;
      border-radius: 8px;
      font-size: 16px;
      font-weight: 600;
      cursor: pointer;
      transition: transform 0.2s;
    }
    button:hover {
      transform: translateY(-2px);
    }
    button:active {
      transform: translateY(0);
    }
    .error {
      background: #fee;
      border: 1px solid #fcc;
      color: #c00;
      padding: 12px;
      border-radius: 8px;
      margin-bottom: 20px;
      font-size: 14px;
    }
    .footer {
      text-align: center;
      margin-top: 20px;
      color: #888;
      font-size: 12px;
    }
  </style>
</head>
<body>
  <div class="container">
    <h1>🔐 3X-UI Panel</h1>
    <p class="subtitle">Secure Admin Access</p>
    ${error ? `<div class="error">${error}</div>` : ''}
    <form method="POST" action="/__auth">
      <div class="form-group">
        <label for="username">Username</label>
        <input type="text" id="username" name="username" required autocomplete="username">
      </div>
      <div class="form-group">
        <label for="password">Password</label>
        <input type="password" id="password" name="password" required autocomplete="current-password">
      </div>
      <button type="submit">Login</button>
    </form>
    <div class="footer">
      Cloudflare-protected access
    </div>
  </div>
</body>
</html>`;
}

// ============================================================================
// Main handler
// ============================================================================
export default {
  async fetch(request, env, ctx) {
    try {
      const url = new URL(request.url);
      
      // Config from env or defaults
      const panelUrl = env.PANEL_URL || DEFAULT_PANEL_URL;
      const panelPath = env.PANEL_BASE_PATH || DEFAULT_PANEL_BASE_PATH;
      const adminUser = env.ADMIN_USER || DEFAULT_ADMIN_USER;
      const adminPass = env.ADMIN_PASS || DEFAULT_ADMIN_PASS;
      const authSecret = env.AUTH_SECRET || adminPass;
      
      // Panic mode
      if (env.PANIC_MODE === "true") {
        return new Response("Maintenance in progress", { status: 503 });
      }
      
      // Login endpoint
      if (url.pathname === "/__auth" && request.method === "POST") {
        const formData = await request.formData();
        const username = formData.get("username");
        const password = formData.get("password");
        
        if (username === adminUser && password === adminPass) {
          const token = await generateToken(authSecret);
          const response = Response.redirect(url.origin + "/", 302);
          response.headers.set(
            "Set-Cookie",
            `${AUTH_COOKIE_NAME}=${token}; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=86400`
          );
          return response;
        } else {
          return new Response(loginPage("Invalid credentials"), {
            status: 401,
            headers: { "Content-Type": "text/html" }
          });
        }
      }
      
      // Check auth cookie
      const cookies = request.headers.get("Cookie") || "";
      const authMatch = cookies.match(new RegExp(`${AUTH_COOKIE_NAME}=([^;]+)`));
      const authToken = authMatch ? authMatch[1] : null;
      
      if (!authToken || !(await verifyToken(authToken, authSecret))) {
        if (request.headers.get("Upgrade") === "websocket") {
          return new Response("Unauthorized", { status: 401 });
        }
        return new Response(loginPage(), {
          status: 200,
          headers: { "Content-Type": "text/html" }
        });
      }
      
      // Build backend URL
      const backendPath = panelPath + url.pathname.slice(1) + url.search;
      const backendUrl = panelUrl + backendPath;
      
      // WebSocket upgrade
      if (request.headers.get("Upgrade") === "websocket") {
        return fetch(backendUrl, {
          method: request.method,
          headers: request.headers,
          body: request.body,
        });
      }
      
      // Regular HTTP proxy
      const proxyHeaders = new Headers(request.headers);
      proxyHeaders.delete("Host");
      proxyHeaders.delete("cf-connecting-ip");
      proxyHeaders.delete("cf-ipcountry");
      proxyHeaders.delete("cf-ray");
      proxyHeaders.delete("cf-visitor");
      
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), PANEL_TIMEOUT);
      
      try {
        const response = await fetch(backendUrl, {
          method: request.method,
          headers: proxyHeaders,
          body: request.body,
          redirect: "manual",
          signal: controller.signal,
        });
        
        clearTimeout(timeoutId);
        
        // Build response
        const responseHeaders = new Headers(response.headers);
        
        // Rewrite Location headers
        const location = responseHeaders.get("Location");
        if (location) {
          const newLocation = location
            .replace(panelUrl, url.origin)
            .replace(panelPath, "/");
          responseHeaders.set("Location", newLocation);
        }
        
        // Add security headers
        Object.entries(SECURITY_HEADERS).forEach(([k, v]) => {
          responseHeaders.set(k, v);
        });
        
        // Rewrite content if HTML/JS/JSON
        const contentType = responseHeaders.get("Content-Type") || "";
        if (contentType.includes("text/html") || contentType.includes("application/javascript") || contentType.includes("application/json")) {
          let body = await response.text();
          body = body
            .replace(new RegExp(panelUrl.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'g'), url.origin)
            .replace(new RegExp(panelPath.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'g'), '/');
          
          return new Response(body, {
            status: response.status,
            statusText: response.statusText,
            headers: responseHeaders,
          });
        }
        
        return new Response(response.body, {
          status: response.status,
          statusText: response.statusText,
          headers: responseHeaders,
        });
        
      } catch (err) {
        clearTimeout(timeoutId);
        if (err.name === "AbortError") {
          return new Response("Backend timeout", { status: 504 });
        }
        throw err;
      }
      
    } catch (err) {
      console.error("Worker error:", err);
      return new Response("Internal error", { status: 500 });
    }
  },
};

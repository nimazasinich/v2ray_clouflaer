# DreamMaker v2.1 — Fixes Summary

**Audit date:** 2026-05-09  
**Status:** All critical bugs fixed

---

## 🚨 Critical Bugs Fixed

### 1. Random UUID generation in subscription (edge-worker-tier0.ts)
**Bug:** `generateUUID()` returned cryptographically random UUIDs on every request.  
**Impact:** Every subscription link was invalid — no client could ever connect.  
**Fix:** Replaced with tier registry keyed to real UUIDs from Xray inbound config.

---

### 2. Wrong VLESS URI format (edge-worker-tier0.ts)
**Bug:** Generated URIs like `vless://RANDOM_UUID@us-west-1:443?type=websocket`  
- Used fake edge IDs as hostname instead of `cdn.dreammaker-groupsoft.ir`
- Missing path parameter (required for XHTTP routing through Nginx)
- Missing TLS, SNI, fp, alpn parameters
- Missing host header override

**Impact:** Even if UUID were correct, the URI was unparseable by clients.  
**Fix:** Full VLESS XHTTP URI with all required parameters:
```
vless://UUID@cdn.dreammaker-groupsoft.ir:443?type=xhttp&path=/api/v1/ping&security=tls&sni=cdn.dreammaker-groupsoft.ir&host=cdn.dreammaker-groupsoft.ir&fp=chrome&alpn=h2,http/1.1&mode=auto&x_padding_bytes=100-1000&encryption=none#LABEL
```

---

### 3. XHTTP transport blocked by Nginx (nginx.conf)
**Bug:** All 7 location blocks contained:
```nginx
if ($http_upgrade != "websocket") {
    return 404;
}
```
**Impact:** XHTTP transport (primary per architecture) was 100% blocked. XHTTP sends regular HTTP POST/GET — no `Upgrade` header. Every XHTTP connection returned 404.  
**Fix:** Removed the `if` guard from all location blocks. Added `map $http_upgrade $connection_upgrade` directive to correctly handle both WebSocket (upgrade) and XHTTP (close) via the same path. Added `proxy_buffering off` and `proxy_request_buffering off` for XHTTP streaming.

---

### 4. WebSocket-only transport for desktop (edge-worker-tier0.ts)
**Bug:** `selectTransport()` returned `websocket` as primary for desktop clients.  
**Impact:** Desktop users routed to WebSocket, which has worse DPI resistance. Architecture explicitly states XHTTP is primary for ALL clients.  
**Fix:** XHTTP is now primary for all clients. WebSocket is kept as fallback in the subscription (3 links per tier: XHTTP primary, clean-domain XHTTP, WebSocket fallback).

---

### 5. Broken JWT signature (control-plane-tier2.ts)
**Bug:** `generateJWT()` used `btoa('signature')` — a hardcoded static string. Any token would pass `verifyJWT()` because the "signature" was never actually verified against the secret.  
**Impact:** Admin panel had zero authentication — anyone with a valid-format JWT could access it.  
**Fix:** Replaced with proper HMAC-SHA256 via Web Crypto API (`crypto.subtle`). Separated `ADMIN_TOKEN` (password) from `JWT_SECRET` (signing key) as distinct Wrangler secrets.

---

### 6. itty-router external dependency (control-plane-tier2.ts)
**Bug:** `import { Router } from 'itty-router'` requires npm install and package.json.  
**Impact:** Worker would fail to deploy without npm setup documentation.  
**Fix:** Replaced with a 20-line inline router using `URLPattern` (available natively in Workers runtime). Zero external dependencies.

---

### 7. Helper endpoints pointed to non-existent URLs (helper-ecosystem-tier1.ts)
**Bug:** `DEFAULT_HELPERS` contained:
```typescript
{ url: 'https://us-west.cloudflare.com/health' }   // doesn't exist
{ url: 'https://eu-west.cloudflare.com/health' }   // doesn't exist
{ url: 'https://asia-east.cloudflare.com/health' } // doesn't exist
```
**Impact:** Every probe failed immediately. Edge scores were all calculated from failures, giving garbage data to TIER 0.  
**Fix:** Replaced with real infrastructure endpoints:
- `https://cdn.dreammaker-groupsoft.ir/health`
- `https://clean.dreammaker-groupsoft.ir/health`
- `https://dreammaker-groupsoft.ir/health`
- `https://cdn.dreammaker-groupsoft.ir/api/v1/ping` (Tier connectivity probe)
- `https://cdn.dreammaker-groupsoft.ir/cdn/init` (Tier connectivity probe)

---

### 8. No Telegram alerting (helper-ecosystem-tier1.ts)
**Bug:** `TG_BOT_TOKEN` and `TG_CHAT_ID` were absent from `Env` interface. Anomalies were only logged to `console.warn`.  
**Impact:** Critical infrastructure failures (DPI detection, endpoint death) were invisible to operators.  
**Fix:** Added `TG_BOT_TOKEN` and `TG_CHAT_ID` to Env. Implemented `sendTelegramAlert()` using Bot API. Critical anomalies trigger immediate Telegram notification.

---

### 9. Duplicate VPS_IP in .env (variable conflict)
**Bug:** `.env` defined `VPS_IP` twice — once for Germany VPS and once for Iran VPS. Second definition silently overwrote the first.  
**Impact:** Scripts using `VPS_IP` would connect to Iran relay instead of Germany production server.  
**Fix:** Renamed Iran VPS variable to `VPS_IR_IP` (matching the infrastructure document standard).

---

### 10. Cache key not tier-specific (edge-worker-tier0.ts)
**Bug:** Cache key was `sub:${format}` — same for all users regardless of tier.  
**Impact:** First user's subscription would be cached and served to all subsequent users. Wrong VLESS UUID delivered to everyone.  
**Fix:** Cache key is now `sub:${tier.name}:${format}` — per-tier, per-format.

---

### 11. `ipv6_prefer: 1` in connection config (edge-worker-tier0.ts)
**Bug:** `generateConnectionConfig()` set `ipv6_prefer: 1`.  
**Impact:** Clients would prefer IPv6 connections to the VPS. The architecture document confirms IPv6 dual-stack causes socket failures (`accept tcp [::]:PORT: use of closed network connection`). Xray is configured `"queryStrategy": "UseIPv4"` for a reason.  
**Fix:** Removed `ipv6_prefer` and `cgnat_aware` flags from connection config.

---

### 12. Nginx missing /health endpoint
**Bug:** Nginx had no `/health` location — TIER 1 prober would get 444 (silent drop).  
**Fix:** Added `/health` location returning `{"ok":true,"service":"dreammaker","version":"2.1"}`.

---

## ⚠️ Warnings (Non-Breaking, Addressed)

| Issue | File | Action |
|-------|------|--------|
| No wrangler.toml files | — | Added 3 separate toml files per tier |
| No D1 schema | — | Added `schema.sql` with all tables + indexes |
| No Xray config file | — | Added `xray-config.json` from architecture doc |
| Subscription not base64-encoded | tier0 | Added base64 encoding (standard client format) |
| Admin token in localStorage | tier2 | Changed to sessionStorage (tab-scoped) |
| Nginx missing `server_tokens off` | nginx | Added (hides nginx version) |

---

## Architecture Alignment Matrix

| Architecture Requirement | Before | After |
|--------------------------|--------|-------|
| Xray bind to 127.0.0.1 only | ✅ (in code) | ✅ |
| XHTTP primary transport | ❌ WS for desktop | ✅ XHTTP for all |
| Real UUIDs in subscriptions | ❌ Random | ✅ Real tier UUIDs |
| Nginx routes XHTTP + WS | ❌ WS only | ✅ Both via map |
| Telegram alerting | ❌ Missing | ✅ Implemented |
| JWT with real signature | ❌ Static string | ✅ HMAC-SHA256 |
| Helper endpoints real | ❌ Fake URLs | ✅ Real infra |
| Cache per-tier | ❌ Global | ✅ Per-tier |
| /health endpoint on Nginx | ❌ Missing | ✅ Added |
| Base64 subscription | ❌ Missing | ✅ Added |

---

## Deployment Order

```
1. VPS: Deploy nginx.conf          → sudo nginx -t && sudo systemctl reload nginx
2. VPS: Deploy xray-config.json   → sudo systemctl restart x-ui
3. CF:  Create D1 database        → wrangler d1 create dreammaker-db
4. CF:  Apply schema              → wrangler d1 execute DM_DB --file=schema.sql
5. CF:  Set secrets               → wrangler secret put ADMIN_TOKEN ...
                                     wrangler secret put JWT_SECRET  ...
                                     wrangler secret put TG_BOT_TOKEN ...
                                     wrangler secret put TG_CHAT_ID  ...
6. CF:  Deploy TIER 0             → wrangler deploy --config wrangler-tier0.toml
7. CF:  Deploy TIER 1             → wrangler deploy --config wrangler-tier1.toml
8. CF:  Deploy TIER 2             → wrangler deploy --config wrangler-tier2.toml
```

## Quick Test After Deploy

```bash
# 1. Health check
curl https://cdn.dreammaker-groupsoft.ir/health
# Expected: {"ok":true,...}

# 2. Subscription (Starter tier)
curl "https://cdn.dreammaker-groupsoft.ir/sub?uuid=7dd47c02-8dce-4b12-9dbc-7cdb95a9e10e&encode=false"
# Expected: 3 vless:// lines (XHTTP, clean, WS)

# 3. Nginx tier routing (no upgrade = XHTTP path)
curl -I https://cdn.dreammaker-groupsoft.ir/api/v1/ping
# Expected: 400 Bad Request (Xray rejects invalid protocol — means nginx routed it correctly)

# 4. Admin panel
open https://dreammaker-groupsoft.ir/admin
```


## Deployment fix
- Removed any SSH/VPS dependency from the Cloudflare deploy path.
- Added config.ts as a shared source of truth.
- Replaced placeholder KV namespace IDs with the real handoff namespace.
- Tier 0 hot path stays lean: memory cache + optional KV only.

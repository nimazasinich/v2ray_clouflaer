# DreamMaker — Session Handoff
**Date:** 2026-05-11  
**Status:** Production running. One VPS-side step pending.

---

## Architecture (one paragraph)
Clients in Iran connect to `cdn.dreammaker-groupsoft.ir:443` (Cloudflare orange-cloud).  
Four Cloudflare Workers dispatch traffic: `edge-ws-relay-v4` relays WebSocket/gRPC, `dreammaker-tier0` serves subscriptions and health, `dreammaker-tier1` runs scheduled health monitoring, `hiddify-panel-proxy` proxies the legacy panel domain.  
Two new panel workers were added this session: `dreammaker-panel-edge-v2` (`access.*`) and `dreammaker-panel-access` (`admin.*`) — both reach the 3X-UI panel through Nginx on port 2053, not directly to port 2822.  
All traffic routes to the Germany VPS at `82.115.26.105:2053` (Nginx). Nginx routes by path to one of 7 Xray inbounds (ports 11001–11007, XHTTP `mode=auto`).

---

## VPS
| Item | Value |
|---|---|
| IP | `82.115.26.105` |
| SSH | **BLOCKED** — use VNC/KVM console only |
| Nginx port | `2053` (plain HTTP from Workers) |
| Panel port | `2822` (3X-UI HTTPS, self-signed cert) |
| Panel path | `/jZMb26oGjigaPhSgj9/` |
| Panel login | `admin` / `admin123` |

---

## Cloudflare
| Item | Value |
|---|---|
#| Account ID | `d902b91f0f1076e0601ffd6e7b4382c0` |
#| Zone ID | `7521f025c7660ad0f5ab6c57d787fa6f` |
#| Primary token | `cfut_9X9JcNyxRKrZTwKg8fdQ2ua26ftC6nk5ltQeurdwbd919108` |
|# KV namespace | `ef1a164f23424e9a9b23721fb0d16133` (binding: `HEALTH_KV`) |

---

## Active Worker Routes
```
dreammaker-panel-access     admin.dreammaker-groupsoft.ir/*
dreammaker-panel-edge-v2    access.dreammaker-groupsoft.ir/*
dreammaker-sales-bot        dreammaker-groupsoft.ir/tgbot
dreammaker-tier0            cdn.dreammaker-groupsoft.ir/health|ping|sub*
dreammaker-tier0            dreammaker-groupsoft.ir/health|ping|sub*
edge-ws-relay-v4            dreammaker-groupsoft.ir/ws*|ws-vless*|grpc-vless*
hiddify-panel-proxy         panel.dreammaker-groupsoft.ir/*
```

---

## Tier UUID Registry (canonical — do not change)
```
Tier       UUID                                    Port   Nginx path (XHTTP)   Nginx path (WS)
Starter    7dd47c02-8dce-4b12-9dbc-7cdb95a9e10e   11001  /api/v1/ping         /api/v1/ping-ws
Basic      92ebaa01-ec34-4601-a4dc-f6afdf822966   11002  /cdn/init            /cdn/init-ws
Standard   3d5e3adf-0912-4c78-9ca9-b87db334ce71   11003  /app/sync            /app/sync-ws
Plus       e8eb3d74-8e8c-4903-b878-8feb656ebb0c   11004  /api/v2/feed         /api/v2/feed-ws
Pro        b3540a54-67dd-452a-b5d8-45d6407b8da5   11005  /static/bundle.js    /static/bundle-ws
Elite      2680152c-0dc3-4fdb-b366-e936358b121f   11006  /media/stream        /media/stream-ws
Unlimited  89c0f294-3f94-4735-96cf-9c1aefdbcbb2   11007  /v2/content/live     /v2/content/live-ws
```

---

## Key Files
```
.wrangler/
├── .env                         ← all credentials (source of truth)
├── ACTIVE/
│   ├── worker.js                ← edge-ws-relay-v4 (WS/gRPC relay + panel fallback)
│   ├── tier0.js                 ← dreammaker-tier0 (sub generation, health)
│   ├── tier1.js                 ← dreammaker-tier1 (scheduled health monitor)
│   ├── hiddify-panel-proxy.js   ← hiddify-panel-proxy (panel.* subdomain)
│   ├── panel-access-worker.js   ← dreammaker-panel-access (admin.* — HMAC auth gate)
│   ├── panel-edge-v2.js         ← dreammaker-panel-edge-v2 (access.* — transparent proxy)
│   ├── wrangler-tier0.toml      ← wrangler config for tier0
├── bot/
│   ├── bot.js                   ← dreammaker-sales-bot (Telegram bot)
│   └── wrangler-bot.toml        ← wrangler config for bot
├── TOOLS/
│   ├── vps-apply-all.sh         ← FULL VPS setup (Nginx + Xray + BBR + Firewall)
│   └── nginx-panel-proxy-patch.sh ← MINIMAL patch: only adds /panel-proxy/ to Nginx
├── CONFIG/
│   └── working-configs.txt      ← live VLESS configs for all 7 tiers
```

---

## How Panel Access Works (important — read this)
Cloudflare Workers **cannot** connect directly to `https://82.115.26.105:2822` — the 3X-UI panel blocks Cloudflare egress IPs with HTTP 403.

**The fix (partially done):**
```
Browser → access.dreammaker-groupsoft.ir
       → panel-edge-v2 Worker
       → http://82.115.26.105:2053/panel-proxy/   ← Worker calls this
       → Nginx /panel-proxy/ location block        ← ROUTES to panel internally
       → https://127.0.0.1:2822/jZMb26oGjigaPhSgj9/  ← local loopback, ssl_verify off
       → 3X-UI native login page ✅
```

Both `panel-edge-v2.js` (access.*) and `panel-access-worker.js` (admin.*) are already updated and deployed to use `http://82.115.26.105:2053/panel-proxy/` as their backend.

---

## ⚠️ ONE PENDING STEP (requires VNC console)
**Nginx on the VPS does not yet have the `/panel-proxy/` location block.**  
Until this is applied, `access.*` and `admin.*` both return HTTP 403.

**Paste into VNC console:**
```bash
cp /etc/nginx/nginx.conf /root/nginx.conf.bak.$(date +%Y%m%d%H%M%S)

sed -i '/location \/ {/{
i\
        location /panel-proxy/ {\
            proxy_pass              https://127.0.0.1:2822/jZMb26oGjigaPhSgj9/;\
            proxy_ssl_verify        off;\
            proxy_set_header        Host              82.115.26.105:2822;\
            proxy_set_header        X-Real-IP         127.0.0.1;\
            proxy_set_header        X-Forwarded-For   127.0.0.1;\
            proxy_http_version      1.1;\
            proxy_set_header        Upgrade           $http_upgrade;\
            proxy_set_header        Connection        "upgrade";\
            proxy_buffering         off;\
            proxy_request_buffering off;\
        }
}' /etc/nginx/nginx.conf

nginx -t && systemctl reload nginx && echo "SUCCESS"
```

After this, both `https://access.dreammaker-groupsoft.ir` and `https://admin.dreammaker-groupsoft.ir` will show the native 3X-UI login.

---

## What Was Done This Session
1. ✅ Added CF tokens to `.env` (CF_TOKEN1–5)
2. ✅ Fixed Pro tier WebSocket path in `tier0.js` (`/static/bundle-ws` not `/static/bundle.js-ws`)
3. ✅ Removed MIME boundary corruption from `tier0.js`
4. ✅ Deployed `dreammaker-tier0` via CF REST API
5. ✅ Deployed `dreammaker-panel-access` to `admin.dreammaker-groupsoft.ir`
6. ✅ Built `vps-apply-all.sh` (Nginx + Xray + BBR + iptables + geo updates)
7. ✅ Built and deployed Telegram sales bot (`dreammaker-sales-bot`)
8. ✅ Created `panel-edge-v2.js` (transparent proxy, no custom auth gate)
9. ✅ Deployed `dreammaker-panel-edge-v2` to `access.dreammaker-groupsoft.ir`
10. ✅ Fixed root cause of panel 403: switched both panel workers from direct `:2822` to Nginx `/panel-proxy/` on port 2053
11. ✅ Updated `panel-access-worker.js` backend to same Nginx proxy
12. ✅ Updated `.env` with `PANEL_PUBLIC_URL_1/2` and `PANEL_NGINX_PROXY`
13. ⏳ VPS Nginx `/panel-proxy/` location — **needs VNC** (see above)

---

## Subscription Links (live — tested)
Fetch all configs for any tier:
```
https://cdn.dreammaker-groupsoft.ir/sub?uuid=<TIER_UUID>
```
Returns base64-encoded VLESS configs. Starter UUID: `7dd47c02-8dce-4b12-9dbc-7cdb95a9e10e`  
Example decoded first line:
```
vless://7dd47c02...@dreammaker-groupsoft.ir:443?encryption=none&type=xhttp&path=%2Fapi%2Fv1%2Fping&security=tls&host=cdn.dreammaker-groupsoft.ir&sni=cdn.dreammaker-groupsoft.ir&fp=chrome&alpn=h2%2Chttp%2F1.1&x_padding_bytes=100-1000#DM-Starter
```

---

## Telegram Bot
#- Token: `7437859619:AAH-2MJdlNmNf7ZSlj16zf-g0QJqB-TIxJU`
- Username: `@Freqbasterd_bot`
- Route: `dreammaker-groupsoft.ir/tgbot`
- Commands: `/start`, `/plans`, `/buy <tier>`, admin approve/reject inline buttons

---

## Known Issues / Notes
- `edge-ws-relay-v4` has a catch-all `proxyToPanel()` fallback that sends unmatched paths to `http://82.115.26.105:2053`. This is intentional for its own CDN routes but is why panel workers must NOT share routes with it.
- All workers deploy via CF REST API (not `wrangler CLI` — network connectivity issues from this machine).
- VPS SSH (port 22) is permanently blocked at datacenter level. All VPS changes require VNC/KVM console.
- No Iran VPS exists. Never add `VPS_IR_*` variables.

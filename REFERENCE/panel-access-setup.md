# Panel Access Setup - 2026-05-11

## Objective
Make 3X-UI panel accessible from Iran without VPN via Cloudflare Worker proxy.

## Configuration
- **Backend Panel:** https://82.115.26.105:2822/jZMb26oGjigaPhSgj9/
- **Credentials:** admin / admin123
- **Public Domain:** https://admin.dreammaker-groupsoft.ir
- **Worker Name:** dreammaker-panel-access

## Completed Steps
1. [x] Updated `.env` with panel credentials
2. [x] Created `panel-access-worker.js` (reverse proxy with auth)
3. [x] Created `wrangler-panel-access.toml` (deployment config)
4. [x] Created DNS A record for `admin.dreammaker-groupsoft.ir` (orange-cloud)

## Deployment Status
- **Status:** Pending (network connectivity issue during wrangler deploy)
- **Alternative:** Deploy via Cloudflare API or dashboard

## Deployment Commands
```powershell
# Set env vars
$env:CLOUDFLARE_API_TOKEN="cfut_9X9JcNyxRKrZTwKg8fdQ2ua26ftC6nk5ltQeurdwbd919108"
$env:CLOUDFLARE_ACCOUNT_ID="d902b91f0f1076e0601ffd6e7b4382c0"

# Deploy
cd .wrangler\ACTIVE
wrangler deploy --config wrangler-panel-access.toml
```

## Features
- HMAC-signed authentication cookie (24h validity)
- Secure headers (HSTS, X-Frame-Options, CSP)
- Path rewriting (hides `/jZMb26oGjigaPhSgj9/` from public URL)
- WebSocket proxy support
- Panic mode toggle
- Backend timeout: 45s

## Manual Deployment (if wrangler fails)
Use Cloudflare dashboard → Workers → Create Worker → paste `panel-access-worker.js` → add route `admin.dreammaker-groupsoft.ir/*`

## Next Steps
Once deployed, panel will be accessible at:
https://admin.dreammaker-groupsoft.ir (no VPN required from Iran)

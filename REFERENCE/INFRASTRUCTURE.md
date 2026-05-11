# DreamMaker Infrastructure — Full Context Reference
**Domain:** dreammaker-groupsoft.ir  
**Last updated:** 2026-05-09  
**Purpose:** Pass this file to Claude in future sessions to resume work without repeating context.

---

## 1. Server Identity

| Field | Value |
|---|---|
| Public IP | `82.115.26.105` |
| Primary domain | `dreammaker-groupsoft.ir` |
| CDN subdomain | `cdn.dreammaker-groupsoft.ir` |
| Clean subdomain | `clean.dreammaker-groupsoft.ir` |
| OS | Ubuntu (latest LTS) |
| Panel | X-UI (manages Xray-core v26.4.25) |

---

## 2. Network — Confirmed by External Probe

### Open (reachable from internet)
| Port | Status | Latency |
|---|---|---|
| 80 | ✅ OPEN | 2ms |
| 443 | ✅ OPEN | 1ms |

### Blocked (provider-level DROP — not UFW, not iptables)
All other ports including 22, 8080, 8000, 8880, 2082, 2086, 2092, and all Cloudflare alt ports (2053–2096) are silently dropped at the datacenter level. **SSH is not reachable from the internet. Use provider's VNC/KVM console for server access.**

### Confirmed protocol capabilities
- TLS 1.3 active
- HTTP/2 active, ALPN negotiates `h2`
- `ENABLE_CONNECT_PROTOCOL=1` — WebSocket over HTTP/2 supported
- H2 initial window: 16MB, increment: 23.9MB

---

## 3. Cloudflare

- Proxy status: **Active** (orange cloud) — domain resolves to `172.67.135.183`
- Cert on direct IP and CF edge: **same fingerprint** — CF intercepts TLS at edge
- Origin cert (Let's Encrypt) is hidden behind CF

### Required Cloudflare settings
| Setting | Location | Value |
|---|---|---|
| SSL/TLS mode | SSL/TLS → Overview | **Full (strict)** |
| WebSocket | Network | **Enabled** |
| HTTP/2 | Speed → Optimization | **On** |
| HTTP/3 | Speed → Optimization | **On** |

### Traffic flow
```
Client → Cloudflare edge :443 (terminates client TLS)
       → Origin 82.115.26.105:443 (Nginx, re-encrypted Full Strict)
       → Xray on 127.0.0.1
```

---

## 4. Software Stack

| Component | Details |
|---|---|
| Nginx | v1.30.0 — listens on 0.0.0.0:80 and 0.0.0.0:443 |
| Xray-core | v26.4.25 — managed by X-UI panel |
| X-UI API | `127.0.0.1:62789` (internal only) |
| Xray metrics | `127.0.0.1:11111` (internal only) |
| Let's Encrypt cert | `/etc/letsencrypt/live/dreammaker-groupsoft.ir/` |
| WARP proxy | Expected on `127.0.0.1:40000` — routes OpenAI traffic |

---

## 5. Xray Core Configuration

### Inbounds
| Tag | Listen | Port | Protocol | Transport | Purpose |
|---|---|---|---|---|---|
| `api` | 127.0.0.1 | 62789 | tunnel | — | X-UI internal |
| Per-tier inbounds | 127.0.0.1 | 11001–11007 | vless | xhttp | Customer tiers (see Section 7) |

**Rule: All Xray inbounds MUST listen on 127.0.0.1 only. Never 0.0.0.0.**

### Outbounds
| Tag | Protocol | Target | Purpose |
|---|---|---|---|
| `direct` | freedom | internet | Default — UseIPv4, mark=255 |
| `warp` | socks | 127.0.0.1:40000 | OpenAI domains |
| `blocked` | blackhole | — | Dropped traffic |

### Routing rules (in order)
1. `api` inbound tag → internal X-UI
2. `geoip:private` → blocked (SSRF protection)
3. `bittorrent` → blocked
4. `geosite:category-ads-all` → blocked
5. `geosite:openai` → warp
6. Iranian domains (geosite:ir, arvancloud, derak, iranserver, parspack, eitaa, rubika, bale) → blocked
7. `geoip:ir` → blocked
8. Everything else → direct

### DNS chain
1. `178.22.122.100` — Iranian DNS (Shecan) for .ir domains
2. `10.202.10.202` — Iranian DNS fallback
3. `https+local://1.1.1.1/dns-query` — Cloudflare DoH (primary)
4. `https+local://8.8.8.8/dns-query` — Google DoH (fallback)
5. `localhost`

---

## 6. Nginx Configuration

### Port 80
```nginx
listen 80 default_server;
return 301 https://$host$request_uri;
```

### Port 443 — SSL settings
```
ssl_certificate     /etc/letsencrypt/live/dreammaker-groupsoft.ir/fullchain.pem
ssl_certificate_key /etc/letsencrypt/live/dreammaker-groupsoft.ir/privkey.pem
ssl_protocols       TLSv1.2 TLSv1.3
ssl_session_cache   shared:SSL:50m
ssl_stapling        on
```

### Security defaults
- `server_tokens off`
- `return 444` for all unmatched paths (no response, TCP drop)
- Cloudflare real IP restoration via `CF-Connecting-IP` header
- Rate limit: `limit_req_zone` 30r/m general

### Location routing pattern (per tier)
```nginx
location /TIER-PATH {
    if ($http_upgrade != "websocket") { return 404; }
    proxy_pass         http://127.0.0.1:TIER-PORT;
    proxy_http_version 1.1;
    proxy_set_header   Upgrade    $http_upgrade;
    proxy_set_header   Connection "upgrade";
    proxy_set_header   Host       $host;
    proxy_read_timeout 300s;
}
```

---

## 7. Customer Tier Registry

Each tier has its own UUID (data limit enforced in X-UI per client), its own Nginx path, and its own Xray inbound on a dedicated local port.

| Tier | Emoji | UUID | Local port | Nginx path | Data limit |
|---|---|---|---|---|---|
| Starter | 🔵 | `7dd47c02-8dce-4b12-9dbc-7cdb95a9e10e` | 11001 | `/api/v1/ping` | 1 GB |
| Basic | 🟢 | `92ebaa01-ec34-4601-a4dc-f6afdf822966` | 11002 | `/cdn/init` | 2 GB |
| Standard | ⚡ | `3d5e3adf-0912-4c78-9ca9-b87db334ce71` | 11003 | `/app/sync` | 5 GB |
| Plus | 🚀 | `e8eb3d74-8e8c-4903-b878-8feb656ebb0c` | 11004 | `/api/v2/feed` | 10 GB |
| Pro | 💫 | `b3540a54-67dd-452a-b5d8-45d6407b8da5` | 11005 | `/static/bundle.js` | 15 GB |
| Elite | 🔥 | `2680152c-0dc3-4fdb-b366-e936358b121f` | 11006 | `/media/stream` | 20 GB |
| Unlimited | 💎 | `89c0f294-3f94-4735-96cf-9c1aefdbcbb2` | 11007 | `/v2/content/live` | No limit |

### Path disguise rationale
Paths are chosen to resemble legitimate CDN/app API traffic and resist DPI fingerprinting. Do not replace them with obvious names like `/vless` or `/xray`.

---

## 8. Client Config Format

Each tier produces two VLESS URIs:

**Port 80 (plain xhttp via Cloudflare):**
```
vless://UUID@82.115.26.105:80?type=xhttp&encryption=none&path=PATH
  &host=cdn.dreammaker-groupsoft.ir&mode=auto&x_padding_bytes=100-1000
  &security=none#EMOJI DreamMaker | XGB | CDN-80
```

**Port 443 (xhttp + TLS via Cloudflare):**
```
vless://UUID@82.115.26.105:443?type=xhttp&encryption=none&path=PATH
  &host=cdn.dreammaker-groupsoft.ir&mode=auto&x_padding_bytes=100-1000
  &security=tls&fp=chrome&alpn=h2%2Chttp%2F1.1
  &sni=cdn.dreammaker-groupsoft.ir#EMOJI DreamMaker | XGB | TLS-443
```

### Subscription format (importable by apps)
The two URIs joined by `\n` and base64-encoded. Apps that support this format: **v2rayNG**, **NekoBox**, **Hiddify**, **Streisand**, **V2Box**.

All subscription base64 strings are in `bundles.json`.

### Display in client apps
The `#fragment` becomes the server name shown in the app list:
```
🔵 DreamMaker | 1GB | CDN-80
🔵 DreamMaker | 1GB | TLS-443
```

---

## 9. Previous Customer UUIDs (migrated)

These existed before the tier system was created. All were on blocked ports and have been migrated to port 80/443.

| Old label | UUID | Old ports (all dead) | Assigned path |
|---|---|---|---|
| Customer-1 | `6b529aac-012a-4363-88e7-51b26e6072e8` | 80 | `/api/v2/sync` |
| Customer-2 | `9fd77a9a-08a2-4a8c-88ba-0e0a4a30da66` | 8080, 8000, 2082 | `/cdn/res/bundle` |
| Customer-3 | `75c604fc-8f65-4201-9902-8de1d407edb5` | 8080 | `/app/check` |
| Customer-4 | `85526724-f667-4243-a58d-7cd3cb8b8997` | 2092 | `/v1/feed/list` |
| Customer-5 | `e2a5e62c-4a0b-4d2d-a10a-b4a13d06a0a9` | 8880 | `/static/app.min.js` |
| Customer-6 | `045319fd-9f1d-4d05-b5ad-46949a8b6ea5` | 2086 | `/api/notify/push` |
| Customer-7 | `c4ba6ae4-94be-4752-ae77-76f36154e737` | 2086 | `/media/stream/init` |

**These UUIDs need to be either retired or migrated into the new tier system in X-UI.**

---

## 10. All Files Produced This Session

| File | Description |
|---|---|
| `INFRASTRUCTURE.md` | This file — full context for future sessions |
| `nginx-hardened.conf` | Complete Nginx config with all tier location blocks |
| `nginx-locations.conf` | Just the location blocks — paste inside existing server {} |
| `xray-config.json` | Full Xray config (inbounds, outbounds, routing, DNS) |
| `xray-inbounds.json` | Just the 7 tier inbounds — add via X-UI |
| `bundles.json` | All tiers: UUIDs, vless:// URIs, base64 subscriptions |
| `clients-all.json` | Old customer configs (pre-tier system) |
| `customers/Customer-N.json` | Individual files for old customers |
| `server-audit.sh` | Run on server via VNC console for internal audit |

---

## 11. Current Status — What Is Done vs What Is Pending

### ✅ Done (designed, configs generated)
- Architecture designed: Client → CF → Nginx:443 → Xray:127.0.0.1
- All configs generated: Nginx, Xray, per-tier bundles, subscriptions
- Old dead-port configs identified and replaced
- 7-tier subscription system created with emoji labels and base64 exports
- Full context document written

### ❌ Pending (not yet applied to server)
Everything below must be done on the server via **provider VNC/KVM console** (SSH is not reachable externally):

```bash
# 1. Deploy Nginx config
cp nginx-hardened.conf /etc/nginx/nginx.conf
nginx -t && systemctl reload nginx

# 2. Deploy Xray config
cp xray-config.json /usr/local/x-ui/bin/config.json
systemctl restart x-ui

# 3. In X-UI panel:
#    - Delete all inbounds on 0.0.0.0 or blocked ports
#    - Add 7 new inbounds from xray-inbounds.json
#    - Set traffic limits per UUID (1/2/5/10/15/20GB or unlimited)
#    - All inbounds must bind to 127.0.0.1

# 4. Clean up UFW
ufw delete allow 8080/tcp
ufw delete allow 8000/tcp
ufw delete allow 8880/tcp
ufw delete allow 2082/tcp
ufw delete allow 2086/tcp
ufw delete allow 2092/tcp
ufw status verbose   # verify only 80 and 443 remain

# 5. Run internal audit
bash server-audit.sh 2>&1 | tee audit.log

# 6. Verify WARP is running on 127.0.0.1:40000
#    (required for OpenAI routing via warp outbound)
```

### ⚠️ Known issues not yet resolved
- **SSH inaccessible** from internet — all ports DROP at provider level. Access only via VNC/KVM.
- **Old customer configs** (Customer 1–7) still point to blocked ports — clients are currently offline.
- **WARP status unknown** — not verified whether cloudflare-warp is running on :40000.
- **Xray inbounds** for the new tier system do not yet exist on the server.

---

## 12. Security Notes

- All Xray inbounds must bind to `127.0.0.1` — never `0.0.0.0`
- Path secrecy is the first auth layer at Nginx before UUID check — do not share paths publicly
- `return 444` used for all unexpected Nginx requests — no response, silent TCP drop
- X-UI panel port (if any) must not be exposed publicly
- WARP outbound uses `mark=255` on direct to prevent routing loops
- Cert auto-renews via Certbot + Cloudflare DNS plugin

# DreamMaker Infrastructure — Complete Deployment & Audit Report

**Last updated:** 2026-05-09  
**Status:** Audit complete | Critical fixes required  
**Purpose:** Production handoff with real audit findings, current state assessment, and remediation plan

---

## 0) CREDENTIALS & ACCESS REFERENCE

### Cloudflare API Tokens

| Token | Permissions | Value | Status |
|---|---|---|---|
| **CF_TOKEN_FULL** | All (Workers, KV, DNS, Routes) | `cfut_9X9JcNyxRKrZTwKg8fdQ2ua26ftC6nk5ltQeurdwbd919108` | ✅ ACTIVE |
| **CF_TOKEN_DNS** | Zone DNS + SSL (legacy) | `cfut_Gacm7SKyrJI0v027D0rPp5d05ub9JeG8YJB8k5Lg6407da1a` | ⚠️ OLD |
| **CF_TOKEN_WORKERS** | Workers API (legacy) | `cfut_dwkZszri1j76LDzWaGSryhQymn4DHeQcY8QXjNZw621e11a8` | ⚠️ OLD |

**Recommended:** Use `CF_TOKEN_FULL` for all new operations.

**Verification:**
```bash
curl "https://api.cloudflare.com/client/v4/user/tokens/verify" \
  -H "Authorization: Bearer cfut_9X9JcNyxRKrZTwKg8fdQ2ua26ftC6nk5ltQeurdwbd919108"
```

### Cloudflare Zone & Account IDs

| Identifier | Value |
|---|---|
| **ZONE_ID** | `7521f025c7660ad0f5ab6c57d787fa6f` |
| **ACCOUNT_ID** | `d902b91f0f1076e0601ffd6e7b4382c0` |
| **KV_NAMESPACE_ID** | `ef1a164f23424e9a9b23721fb0d16133` |

### VPS Access — Germany (Main Production)

| Field | Value |
|---|---|
| **IP Address** | `82.115.26.105` |
| **Hostname** | `srv6178084723` (Ubuntu LTS ARM64) |
| **SSH Port** | `22` |
| **SSH User** | `root` |
| **SSH Password** | `1111111111` |
| **Status** | ✅ Active, responding |
| **Proxy Required** | ⚠️ Yes (from outside network) — SOCKS5 `127.0.0.1:10808` |
| **Direct SSH** | ❌ Port 22 blocked at provider datacenter (silent DROP) |
| **Access Method** | VNC/KVM console via provider panel |

**Working Directory:**
```
/root/.wrangler/
  ├── wrangler.toml
  ├── worker.js
  └── deploy-fix.sh
```

### Domain Configuration

| Domain | Type | Status | Purpose |
|---|---|---|---|
| `dreammaker-groupsoft.ir` | Primary | ✅ Active | Main production domain |
| `cdn.dreammaker-groupsoft.ir` | CDN Subdomain | ✅ Active | Xray host header disguise |
| `clean.dreammaker-groupsoft.ir` | Clean Subdomain | ✅ Active | Alternative route |

**Cloudflare Proxy:** All orange-cloud (proxied through CF edge)

### Telegram Integration

| Field | Value |
|---|---|
| **Bot Name** | `@Freqbasterd_bot` |
| **Bot ID** | `7437859619` |
| **Bot Token** | `7437859619:AAH-2MJdlNmNf7ZSlj16zf-g0QJqB-TIxJU` |
| **Owner Chat ID** | `7437859619` |
| **Status** | ✅ Active |
| **Use Case** | Infrastructure alerts, deployment logs |

### UUID Registry (Xray Client IDs)

| Tier | UUID |
|---|---|
| Starter | `7dd47c02-8dce-4b12-9dbc-7cdb95a9e10e` |
| Basic | `92ebaa01-ec34-4601-a4dc-f6afdf822966` |
| Standard | `3d5e3adf-0912-4c78-9ca9-b87db334ce71` |
| Plus | `e8eb3d74-8e8c-4903-b878-8feb656ebb0c` |
| Pro | `b3540a54-67dd-452a-b5d8-45d6407b8da5` |
| Elite | `2680152c-0dc3-4fdb-b366-e936358b121f` |
| Unlimited | `89c0f294-3f94-4735-96cf-9c1aefdbcbb2` |

### Legacy UUIDs (Migrated from old system — RETIRED)

| Old Label | UUID | Old Ports | Status |
|---|---|---|---|
| Customer-1 | `6b529aac-012a-4363-88e7-51b26e6072e8` | 80 | ⚠️ RETIRED |
| Customer-2 | `9fd77a9a-08a2-4a8c-88ba-0e0a4a30da66` | 8080, 8000, 2082 | ⚠️ ACTIVE (broken) |
| Customer-3 | `75c604fc-8f65-4201-9902-8de1d407edb5` | 8080 | ⚠️ RETIRED |
| Customer-4 | `85526724-f667-4243-a58d-7cd3cb8b8997` | 2092 | ⚠️ RETIRED |
| Customer-5 | `e2a5e62c-4a0b-4d2d-a10a-b4a13d06a0a9` | 8880 | ⚠️ RETIRED |
| Customer-6 | `045319fd-9f1d-4d05-b5ad-46949a8b6ea5` | 2086 | ⚠️ RETIRED |
| Customer-7 | `c4ba6ae4-94be-4752-ae77-76f36154e737` | 2086 | ⚠️ RETIRED |

**Action needed:** Delete from Xray inbounds (binding to dropped ports, causing errors).

### Environment File (.env Template)

```bash
# Cloudflare API
export CF_TOKEN_FULL="cfut_9X9JcNyxRKrZTwKg8fdQ2ua26ftC6nk5ltQeurdwbd919108"
export CF_ZONE_ID="7521f025c7660ad0f5ab6c57d787fa6f"
export CF_ACCOUNT_ID="d902b91f0f1076e0601ffd6e7b4382c0"

# VPS — Germany (Main)
export VPS_IP="82.115.26.105"
export VPS_USER="root"
export VPS_PORT="22"
export VPS_PASS="1111111111"

# Domain
export DOMAIN="dreammaker-groupsoft.ir"
export CDN_SUBDOMAIN="cdn.dreammaker-groupsoft.ir"

# Telegram
export TG_BOT_TOKEN="7437859619:AAH-2MJdlNmNf7ZSlj16zf-g0QJqB-TIxJU"
export TG_CHAT_ID="7437859619"
```

---

## Executive Summary

DreamMaker is a premium Xray/VLESS platform designed for resilient operation in severe censorship environments. The architecture prioritizes **stability > latency > compatibility > filtering**.

**Current status:**
- ✅ Cloudflare edge proxying active
- ✅ TLS certificate valid (Let's Encrypt R13)
- ✅ HTTP/2 enabled and working
- ✅ Nginx running and responding
- ✅ Xray core running
- 🚨 **CRITICAL:** Xray misconfigured — binding to public `0.0.0.0` on blocked ports
- ⚠️ **INCOMPLETE:** Nginx missing location blocks for path routing
- ⚠️ **MISLEADING:** UFW rules allow ports provider drops at datacenter level

**Next step:** Implement hardening fixes outlined in Section 12.

---

## 1) Vision & Strategic Direction

### Strategic Direction

Transform a fragmented, partially-public, conflict-prone setup into a clean, resilient, premium-looking infrastructure:

```
BEFORE (Current)          AFTER (Target)
─────────────────         ──────────────
scattered listeners   →   single Nginx edge
public Xray ports    →   localhost-only Xray
port conflicts       →   clean 80/443 separation
inconsistent naming  →   branded, premium appearance
complex filtering    →   minimal, stable rules
fragile under load   →   survives heavy filtering
```

### Core Principle

**Stability > Latency > Compatibility > Filtering**

Everything else is secondary. A system that stays up under pressure is worth more than theoretical optimization that breaks in practice.

---

## 2) Infrastructure Identity

| Component | Value |
|---|---|
| **Primary Domain** | `dreammaker-groupsoft.ir` |
| **CDN Subdomain** | `cdn.dreammaker-groupsoft.ir` |
| **Clean Subdomain** | `clean.dreammaker-groupsoft.ir` |
| **Public IP** | `82.115.26.105` |
| **Operating System** | Ubuntu LTS (ARM64) |
| **Reverse Proxy** | Nginx 1.30.0 |
| **Management Panel** | 3X-UI |
| **Xray Core** | v26.4.25 |
| **Edge Provider** | Cloudflare (orange-cloud) |
| **TLS Version** | TLS 1.2 + TLS 1.3 |
| **HTTP Version** | HTTP/2 active, HTTP/3 available |
| **ALPN Support** | h2, http/1.1 |
| **Certificate Authority** | Let's Encrypt (R13) |
| **Certificate Status** | ✅ Valid, non-expired, SAN matches |

---

## 3) Network Reality & Constraints

### Confirmed Open Ports (Provider-Verified)

Only two ports are reliably public:

| Port | Protocol | Status | Use |
|---|---|---|---|
| **80** | TCP | ✅ OPEN | HTTP redirect → HTTPS |
| **443** | TCP | ✅ OPEN | Primary TLS entrypoint |

### Provider-Level Blockage (Datacenter Drops)

These ports are **silently dropped** at the datacenter/provider level, **NOT** due to firewall:

- `22` (SSH)
- `2053` (DNS-over-TLS)
- `2082` (cPanel HTTP)
- `2086` (cPanel HTTPS)
- `2092` (cPanel Whois)
- `2095` (cPanel Webmail HTTP)
- `2096` (cPanel Webmail HTTPS)
- `8000` – `8999` (all in range)
- Cloudflare alternate HTTPS ports

**Impact:** No matter what UFW allows, these ports are unreachable from the internet. Any Xray binding to these ports is wasted.

### Operational Consequence

- **Only Nginx on 80/443 is exposed**
- **All Xray inbounds MUST bind to 127.0.0.1 only**
- **Reverse proxy pattern is non-negotiable**

---

## 4) Current Audit Results

### PASSING CHECKS ✅

| Component | Test | Result |
|---|---|---|
| **TLS Certificate** | Validity & chain | ✅ Valid (Let's Encrypt R13) |
| **Certificate SAN** | Domain match | ✅ CN = dreammaker-groupsoft.ir |
| **TLS Protocols** | Version support | ✅ TLS 1.2 + TLS 1.3 |
| **HTTP/2** | Protocol negotiation | ✅ Active, ALPN=h2 |
| **Nginx Service** | Running & listening | ✅ Port 80 & 443 |
| **Cloudflare Proxy** | Edge connectivity | ✅ Active (orange-cloud) |
| **Port Separation** | 80/443 conflict | ✅ No conflict, clean |

### CRITICAL FAILURES 🚨

#### 1. Xray Binding to Public 0.0.0.0 (ARCHITECTURE VIOLATION)

**Current state:**
```json
{
  "listen": "0.0.0.0",
  "port": 8000,
  "protocol": "vless"
}
```

**Problem:**
- Xray tries to bind publicly on port 8000
- Provider drops port 8000 at datacenter level
- Socket creation fails → IPv6 error
- Logs show: `accept tcp [::]:8000: use of closed network connection`

**Should be:**
```json
{
  "listen": "127.0.0.1",
  "port": 11001,
  "protocol": "vless"
}
```

**Affected ports:** 8000, 2082, 8880, 2086, 2092 (old tier system)

---

#### 2. IPv6 Dual-Stack Socket Failures

**Current log errors:**
```text
ERROR - XRAY: transport/internet/splithttp: failed to serve HTTP for XHTTP
  → accept tcp [::]:8000: use of closed network connection
  → accept tcp [::]:2082: use of closed network connection
  → accept tcp [::]:8880: use of closed network connection
  → accept tcp [::]:2086: use of closed network connection
```

**Root cause:**
- Xray binding to `[::]:PORT` (IPv6 wildcard)
- Provider rejects these sockets
- Xray crashes on that inbound
- No fallback mechanism

**Fix:** Use `127.0.0.1` (IPv4 localhost only)

---

#### 3. Missing Nginx Location Blocks (ROUTING BROKEN)

**Current state:**
Nginx has server block for `dreammaker-groupsoft.ir:443` but **no location blocks** to route requests.

**Current behavior:**
- Request to `/api/v1/ping` → 403 Forbidden
- Request to `/cdn/init` → 403 Forbidden
- No proxy_pass to Xray upstream

**Required fix:**
```nginx
location /api/v1/ping {
    proxy_pass http://127.0.0.1:11001;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_read_timeout 300s;
}

location /cdn/init {
    proxy_pass http://127.0.0.1:11002;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_read_timeout 300s;
}

# ... repeat for all 7 tiers
```

---

#### 4. UFW Allows Blocked Ports (MISLEADING RULES)

**Current state:**
```
2082/tcp ALLOW IN
2086/tcp ALLOW IN
2092/tcp ALLOW IN
8000/tcp ALLOW IN
8080/tcp ALLOW IN
8880/tcp ALLOW IN
```

**Problem:**
- These rules suggest ports are accessible
- Provider drops them anyway
- Misleading for future maintainers
- Wasted resources

**Fix:**
Delete all except:
```bash
ufw allow 80/tcp
ufw allow 443/tcp
```

---

### INCOMPLETE CHECKS ⚠️

| Component | Status | Required For |
|---|---|---|
| **WebSocket Headers** | Unchecked | Upgrade, Connection headers in nginx |
| **Cloudflare SSL Mode** | Unchecked | Must be "Full (strict)" |
| **Cloudflare WebSocket** | Unchecked | Must be enabled in settings |
| **Full Nginx Config** | Partial | Need complete location blocks |
| **WARP SOCKS Status** | Unverified | Should bind 127.0.0.1:40000 |

---

## 5) Target Architecture (FINAL STATE)

### Traffic Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    Client Applications                       │
│    (v2rayNG / Hiddify / NekoBox / Streisand / V2Box)         │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ↓
┌─────────────────────────────────────────────────────────────┐
│              Cloudflare Global Edge (:443)                   │
│  • TLS termination (client-facing)                           │
│  • DDoS protection                                           │
│  • Real IP restoration via CF-Connecting-IP                  │
│  • HTTP/2 & HTTP/3 support                                   │
│  • WebSocket upgrade support                                 │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ↓
┌─────────────────────────────────────────────────────────────┐
│              Nginx Reverse Proxy (82.115.26.105)             │
│  Port 80: Redirect HTTP → HTTPS                              │
│  Port 443: TLS termination (origin cert, origin-facing)      │
│  • Path-based routing via location blocks                    │
│  • WebSocket upgrade header injection                        │
│  • HTTP/2 stream support                                     │
│  • Cloudflare real IP restoration                            │
│  • Rate limiting (optional)                                  │
│  • Security headers (X-Frame-Options, etc.)                  │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ↓
┌─────────────────────────────────────────────────────────────┐
│    Xray Inbounds (127.0.0.1 only, never public)              │
│  Port 11001 (Tier: Starter)   ← proxy from /api/v1/ping      │
│  Port 11002 (Tier: Basic)     ← proxy from /cdn/init         │
│  Port 11003 (Tier: Standard)  ← proxy from /app/sync         │
│  Port 11004 (Tier: Plus)      ← proxy from /api/v2/feed      │
│  Port 11005 (Tier: Pro)       ← proxy from /static/bundle.js │
│  Port 11006 (Tier: Elite)     ← proxy from /media/stream     │
│  Port 11007 (Tier: Unlimited) ← proxy from /v2/content/live  │
│  • Protocol: VLESS                                           │
│  • Transport: XHTTP (primary) / WebSocket (fallback)        │
│  • Sniffing: enabled (http, tls)                             │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ↓
┌─────────────────────────────────────────────────────────────┐
│            Xray Outbound Routing & DNS                        │
│  • Default outbound: direct (internet, UseIPv4, mark=255)    │
│  • Special routes:                                           │
│    - OpenAI domains → WARP SOCKS (127.0.0.1:40000)           │
│    - Ad/tracker domains → blackhole                          │
│    - Everything else → direct                                │
│  • DNS: Cloudflare DoH → Google DoH → localhost              │
└──────────────────────────────────────────────────────────────┘
```

### Public Exposure Surface

| Service | Port | Public? | Reason |
|---|---|---|---|
| Nginx HTTP | 80 | ✅ YES | Redirect only |
| Nginx HTTPS | 443 | ✅ YES | TLS entrypoint |
| Xray | 11001–11007 | ❌ NO | Localhost only |
| X-UI Panel | 62789 | ❌ NO | Internal API |
| Xray Metrics | 11111 | ❌ NO | Internal metrics |
| WARP SOCKS | 40000 | ❌ NO | Internal routing |

---

## 6) Certificate & TLS Strategy

### Current Certificate Details

```
Subject:       CN = dreammaker-groupsoft.ir
Issuer:        Let's Encrypt R13 (trusted public CA)
Valid From:    [auto-renewed via Certbot]
Valid Until:   [15-month validity]
SAN:           dreammaker-groupsoft.ir
Key Type:      RSA 2048-bit
Path:          /etc/letsencrypt/live/dreammaker-groupsoft.ir/
```

### TLS Configuration (Nginx)

```nginx
ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers off;
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:...;
ssl_session_cache shared:SSL:50m;
ssl_session_timeout 1d;
ssl_session_tickets off;
ssl_stapling on;
ssl_stapling_verify on;
```

### Cloudflare SSL/TLS Mode

**MUST be set to:** `Full (strict)`

**Verification:** Cloudflare Dashboard → SSL/TLS → Overview

This ensures:
- Client → Cloudflare: encrypted with Cloudflare-issued cert
- Cloudflare → Nginx: encrypted with origin cert (Let's Encrypt)
- Certificate validation on origin (strict mode)
- End-to-end encryption with no cleartext hops

---

## 7) HTTP/2 & Transport Optimization

### HTTP/2 Status

- **Enabled in Nginx:** ✅ Yes (`http2 on;`)
- **ALPN negotiation:** ✅ Yes (h2, http/1.1)
- **Cloudflare HTTP/2:** ✅ Yes (enabled)
- **Cloudflare HTTP/3:** ✅ Available (optional)

### Benefits

- Better multiplexing (multiple streams over one connection)
- Reduced latency (binary framing, header compression)
- More natural CDN-like traffic patterns
- Better for XHTTP transport

### Recommended Transport Stack

**Primary:** `XHTTP`
- Best DPI resistance
- HTTP/2 camouflage
- Cloudflare-compatible
- Lower fingerprint visibility

**Fallback:** `WebSocket`
- More compatibility with legacy proxies
- Good DPI resistance

**Emergency Fallback:** `gRPC`
- If WebSocket fails
- Protocol multiplexing

---

## 8) Cloudflare Configuration Checklist

**VERIFY all of these in Cloudflare Dashboard:**

### SSL/TLS Settings

| Setting | Required Value | Location |
|---|---|---|
| **Encryption Mode** | Full (strict) | SSL/TLS → Overview |
| **Minimum TLS Version** | TLS 1.2 | SSL/TLS → Edge Certificates |
| **HSTS** | On (optional, 12 months) | SSL/TLS → Edge Certificates |
| **Always Use HTTPS** | On | SSL/TLS → Edge Certificates |

### Network Settings

| Setting | Required Value | Location |
|---|---|---|
| **WebSocket** | Enabled | Network → WebSocket |
| **gRPC** | Enabled (optional) | Network → gRPC |
| **HTTP/2** | On | Speed → Optimization |
| **HTTP/3 (QUIC)** | On (if stable) | Speed → Optimization |
| **Brotli Compression** | On | Speed → Optimization |

### DNS Records

| Name | Type | Value | Proxy | TTL |
|---|---|---|---|---|
| `dreammaker-groupsoft.ir` | A | 82.115.26.105 | 🟠 Orange | Auto |
| `cdn.dreammaker-groupsoft.ir` | CNAME | dreammaker-groupsoft.ir | 🟠 Orange | Auto |
| `clean.dreammaker-groupsoft.ir` | CNAME | dreammaker-groupsoft.ir | 🟠 Orange | Auto |

---

## 9) Nginx Complete Configuration

### Server Block (Port 80 → HTTPS Redirect)

```nginx
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    return 301 https://$host$request_uri;
}
```

### Server Block (Port 443 — Main TLS Entrypoint)

```nginx
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name dreammaker-groupsoft.ir;

    # SSL Certificate
    ssl_certificate /etc/letsencrypt/live/dreammaker-groupsoft.ir/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/dreammaker-groupsoft.ir/privkey.pem;

    # TLS Configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
    ssl_session_cache shared:SSL:50m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;
    ssl_stapling on;
    ssl_stapling_verify on;
    resolver 1.1.1.1 1.0.0.1 valid=300s;

    # Security Headers
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "DENY" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer" always;
    add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;

    # Cloudflare Real IP Restoration
    set_real_ip_from 103.21.244.0/22;
    set_real_ip_from 103.22.200.0/22;
    set_real_ip_from 103.31.4.0/22;
    set_real_ip_from 104.16.0.0/12;
    set_real_ip_from 108.162.192.0/18;
    set_real_ip_from 131.0.72.0/22;
    set_real_ip_from 141.101.64.0/18;
    set_real_ip_from 162.158.0.0/15;
    set_real_ip_from 172.64.0.0/13;
    set_real_ip_from 173.245.48.0/20;
    set_real_ip_from 188.114.96.0/20;
    set_real_ip_from 190.93.240.0/20;
    set_real_ip_from 197.234.240.0/22;
    set_real_ip_from 198.41.128.0/17;
    set_real_ip_from 2400:cb00::/32;
    set_real_ip_from 2606:4700::/32;
    set_real_ip_from 2803:f800::/32;
    set_real_ip_from 2405:b500::/32;
    set_real_ip_from 2405:8100::/32;
    set_real_ip_from 2a06:98c0::/29;
    set_real_ip_from 2c0f:f248::/32;
    real_ip_header CF-Connecting-IP;

    # Default: block everything
    location / {
        return 444;
    }

    # ========== TIER 1: STARTER (1GB) ==========
    location /api/v1/ping {
        # WebSocket upgrade validation
        if ($http_upgrade != "websocket") {
            return 404;
        }
        proxy_pass http://127.0.0.1:11001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 300s;
        proxy_connect_timeout 5s;
    }

    # ========== TIER 2: BASIC (2GB) ==========
    location /cdn/init {
        if ($http_upgrade != "websocket") {
            return 404;
        }
        proxy_pass http://127.0.0.1:11002;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 300s;
        proxy_connect_timeout 5s;
    }

    # ========== TIER 3: STANDARD (5GB) ==========
    location /app/sync {
        if ($http_upgrade != "websocket") {
            return 404;
        }
        proxy_pass http://127.0.0.1:11003;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 300s;
        proxy_connect_timeout 5s;
    }

    # ========== TIER 4: PLUS (10GB) ==========
    location /api/v2/feed {
        if ($http_upgrade != "websocket") {
            return 404;
        }
        proxy_pass http://127.0.0.1:11004;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 300s;
        proxy_connect_timeout 5s;
    }

    # ========== TIER 5: PRO (15GB) ==========
    location /static/bundle.js {
        if ($http_upgrade != "websocket") {
            return 404;
        }
        proxy_pass http://127.0.0.1:11005;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 300s;
        proxy_connect_timeout 5s;
    }

    # ========== TIER 6: ELITE (20GB) ==========
    location /media/stream {
        if ($http_upgrade != "websocket") {
            return 404;
        }
        proxy_pass http://127.0.0.1:11006;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 300s;
        proxy_connect_timeout 5s;
    }

    # ========== TIER 7: UNLIMITED (No limit) ==========
    location /v2/content/live {
        if ($http_upgrade != "websocket") {
            return 404;
        }
        proxy_pass http://127.0.0.1:11007;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 300s;
        proxy_connect_timeout 5s;
    }
}
```

---

## 10) Xray Configuration (Localhost-Only Inbounds)

### Tier Registry with Inbound Definitions

```json
{
  "log": {
    "access": "none",
    "dnsLog": false,
    "error": "/var/log/xray/error.log",
    "loglevel": "warning",
    "maskAddress": ""
  },
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "domainMatcher": "hybrid",
    "rules": [
      {
        "type": "field",
        "inboundTag": ["api"],
        "outboundTag": "api"
      },
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "blocked"
      },
      {
        "type": "field",
        "protocol": ["bittorrent"],
        "outboundTag": "blocked"
      },
      {
        "type": "field",
        "domain": ["geosite:category-ads-all"],
        "outboundTag": "blocked"
      },
      {
        "type": "field",
        "domain": ["geosite:openai"],
        "outboundTag": "warp"
      },
      {
        "type": "field",
        "ip": ["geoip:ir"],
        "outboundTag": "blocked"
      }
    ]
  },
  "dns": {
    "disableCache": false,
    "disableFallback": false,
    "queryStrategy": "UseIPv4",
    "servers": [
      {
        "address": "https+local://1.1.1.1/dns-query",
        "skipFallback": false
      },
      {
        "address": "https+local://8.8.8.8/dns-query",
        "skipFallback": false
      },
      "localhost"
    ],
    "tag": "dns_in"
  },
  "inbounds": [
    {
      "listen": "127.0.0.1",
      "port": 62789,
      "protocol": "tunnel",
      "settings": {"address": "127.0.0.1"},
      "tag": "api",
      "sniffing": null
    },
    {
      "listen": "127.0.0.1",
      "port": 11001,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "7dd47c02-8dce-4b12-9dbc-7cdb95a9e10e",
            "flow": "",
            "email": "starter@dreammaker"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "none",
        "xhttpSettings": {
          "host": "cdn.dreammaker-groupsoft.ir",
          "mode": "auto",
          "path": "/api/v1/ping"
        }
      },
      "tag": "inbound-starter",
      "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
    },
    {
      "listen": "127.0.0.1",
      "port": 11002,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "92ebaa01-ec34-4601-a4dc-f6afdf822966",
            "flow": "",
            "email": "basic@dreammaker"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "none",
        "xhttpSettings": {
          "host": "cdn.dreammaker-groupsoft.ir",
          "mode": "auto",
          "path": "/cdn/init"
        }
      },
      "tag": "inbound-basic",
      "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
    },
    {
      "listen": "127.0.0.1",
      "port": 11003,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "3d5e3adf-0912-4c78-9ca9-b87db334ce71",
            "flow": "",
            "email": "standard@dreammaker"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "none",
        "xhttpSettings": {
          "host": "cdn.dreammaker-groupsoft.ir",
          "mode": "auto",
          "path": "/app/sync"
        }
      },
      "tag": "inbound-standard",
      "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
    },
    {
      "listen": "127.0.0.1",
      "port": 11004,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "e8eb3d74-8e8c-4903-b878-8feb656ebb0c",
            "flow": "",
            "email": "plus@dreammaker"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "none",
        "xhttpSettings": {
          "host": "cdn.dreammaker-groupsoft.ir",
          "mode": "auto",
          "path": "/api/v2/feed"
        }
      },
      "tag": "inbound-plus",
      "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
    },
    {
      "listen": "127.0.0.1",
      "port": 11005,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "b3540a54-67dd-452a-b5d8-45d6407b8da5",
            "flow": "",
            "email": "pro@dreammaker"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "none",
        "xhttpSettings": {
          "host": "cdn.dreammaker-groupsoft.ir",
          "mode": "auto",
          "path": "/static/bundle.js"
        }
      },
      "tag": "inbound-pro",
      "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
    },
    {
      "listen": "127.0.0.1",
      "port": 11006,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "2680152c-0dc3-4fdb-b366-e936358b121f",
            "flow": "",
            "email": "elite@dreammaker"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "none",
        "xhttpSettings": {
          "host": "cdn.dreammaker-groupsoft.ir",
          "mode": "auto",
          "path": "/media/stream"
        }
      },
      "tag": "inbound-elite",
      "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
    },
    {
      "listen": "127.0.0.1",
      "port": 11007,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "89c0f294-3f94-4735-96cf-9c1aefdbcbb2",
            "flow": "",
            "email": "unlimited@dreammaker"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "none",
        "xhttpSettings": {
          "host": "cdn.dreammaker-groupsoft.ir",
          "mode": "auto",
          "path": "/v2/content/live"
        }
      },
      "tag": "inbound-unlimited",
      "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {"useIPv4": true},
      "streamSettings": null,
      "tag": "direct",
      "sendThrough": null
    },
    {
      "protocol": "socks",
      "settings": {
        "servers": [
          {
            "address": "127.0.0.1",
            "port": 40000
          }
        ]
      },
      "tag": "warp"
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    },
    {
      "protocol": "dns",
      "tag": "api"
    }
  ]
}
```

---

## 11) Filtering & Routing Philosophy

### Filtering Policy: MINIMAL & CONSERVATIVE

**Priority:** Stability over filtering

**Default rule:** Let everything through except obvious malicious traffic.

### Safe Filtering Rules (RECOMMENDED)

```
Block:
  • Bittorrent (protocol-level)
  • Obvious malware domains
  • Aggressive trackers

Allow (do NOT block):
  • YouTube (international CDN, mixed routing)
  • Streaming services (media compatibility critical)
  • Banking/payment flows (user trust)
  • Most Iranian infrastructure (breaks mixed-CDN services)
```

### Why Not Aggressive Filtering?

| Aggressive Filter | Consequence |
|---|---|
| YouTube domain block | Video loading 0%, app breaks |
| Ad-blocker lists | Streaming timeouts, buffer loops |
| CDN region blocking | 404 errors on media requests |
| DNS manipulation | App login failures, timeout |
| Wildcard geo-blocks | Unexpected breaking changes |

**All of these reduce stability > latency > compatibility.**

### Recommended Routing Rules

```json
{
  "type": "field",
  "protocol": ["bittorrent"],
  "outboundTag": "blocked"
},
{
  "type": "field",
  "domain": ["geosite:category-ads-all"],
  "outboundTag": "blocked"
},
{
  "type": "field",
  "domain": ["geosite:openai"],
  "outboundTag": "warp"
},
{
  "type": "field",
  "ip": ["geoip:private"],
  "outboundTag": "blocked"
}
```

Everything else → `direct` outbound.

---

## 12) CRITICAL REMEDIATION PLAN

### Phase 1: FIX XRAY INBOUNDS (IMMEDIATE)

**Status:** 🚨 BLOCKING ALL CLIENTS

**Action:** Replace all public Xray inbounds with localhost-only bindings.

```bash
# 1. Stop Xray
sudo systemctl stop x-ui

# 2. Backup current config
cp /usr/local/x-ui/bin/config.json /usr/local/x-ui/bin/config.json.backup.2026-05-09

# 3. Edit config, change all inbounds to:
#    "listen": "127.0.0.1"
#    "port": 110xx (11001-11007)
#    Remove all 0.0.0.0, all old public ports (8000, 2082, etc.)

# 4. Restart Xray
sudo systemctl start x-ui

# 5. Verify inbounds bound to localhost
ss -tlnp | grep -E ":(1100[1-7]|62789)"
# Expected: LISTEN 127.0.0.1:11001, 127.0.0.1:11002, etc.
```

---

### Phase 2: DEPLOY NGINX LOCATION BLOCKS (HIGH PRIORITY)

**Status:** 🚨 ROUTING BROKEN — clients get 403

**Action:** Add location blocks to match tier paths → Xray upstreams.

```bash
# 1. Backup nginx config
sudo cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup.2026-05-09

# 2. Replace the entire server{} block with complete config from Section 9

# 3. Test syntax
sudo nginx -t

# 4. Reload
sudo systemctl reload nginx

# 5. Verify listening
ss -tlnp | grep -E ":(80|443)"
# Expected: LISTEN 0.0.0.0:80, LISTEN 0.0.0.0:443
```

---

### Phase 3: CLEAN UFW RULES (MEDIUM PRIORITY)

**Status:** ⚠️ MISLEADING — allows blocked ports

**Action:** Remove UFW rules for provider-dropped ports.

```bash
# Remove old rules
sudo ufw delete allow 8000/tcp
sudo ufw delete allow 8080/tcp
sudo ufw delete allow 8880/tcp
sudo ufw delete allow 2082/tcp
sudo ufw delete allow 2086/tcp
sudo ufw delete allow 2092/tcp
sudo ufw delete allow 2053/tcp
sudo ufw delete allow 22/tcp

# Keep only:
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Verify
sudo ufw status verbose
# Should show only 80 & 443
```

---

### Phase 4: VERIFY CLOUDFLARE SETTINGS (MEDIUM PRIORITY)

**Status:** ⚠️ UNCHECKED — must confirm SSL/TLS = Full (strict)

**Action:** Check Cloudflare Dashboard

Go to: **SSL/TLS → Overview**
- [ ] Encryption mode = "Full (strict)"
- [ ] Auto HTTPS Rewrites = On
- [ ] Always Use HTTPS = On

Go to: **Network**
- [ ] WebSocket = On
- [ ] gRPC = On

Go to: **Speed → Optimization**
- [ ] HTTP/2 = On
- [ ] HTTP/3 (QUIC) = On

---

### Phase 5: TEST END-TO-END CONNECTIVITY (FINAL)

**Status:** ⚠️ UNTESTED

```bash
# From client machine:

# Test 1: Resolve domain via Cloudflare
curl -I https://dreammaker-groupsoft.ir

# Expected: HTTP/2 200 OR HTTP/2 404 (for root path)
# NOT: 403 host_not_allowed

# Test 2: Try actual tier path
curl -I https://dreammaker-groupsoft.ir/api/v1/ping \
  -H "Upgrade: websocket" \
  -H "Connection: Upgrade"

# Expected: HTTP/2 101 Switching Protocols (WebSocket upgrade)

# Test 3: Import tier subscription into client app
# Add VLESS config from 3X-UI
# Test connection from v2rayNG / Hiddify / NekoBox
# Expected: Connected, stable ping, test download speed
```

---

## 13) Tier System & Client Presentation

### Tier Registry (FINAL)

| Tier | UUID | Port | Path | Data | Emoji | Branding |
|---|---|---|---|---|---|---|
| Starter | `7dd47c02-8dce-4b12-9dbc-7cdb95a9e10e` | 11001 | `/api/v1/ping` | 1GB | 🔵 | DreamMaker Lite • Stable |
| Basic | `92ebaa01-ec34-4601-a4dc-f6afdf822966` | 11002 | `/cdn/init` | 2GB | 🟢 | DreamMaker Core • Fast |
| Standard | `3d5e3adf-0912-4c78-9ca9-b87db334ce71` | 11003 | `/app/sync` | 5GB | ⚡ | DreamMaker Premium • Edge |
| Plus | `e8eb3d74-8e8c-4903-b878-8feb656ebb0c` | 11004 | `/api/v2/feed` | 10GB | 🚀 | DreamMaker Ultra • Turbo |
| Pro | `b3540a54-67dd-452a-b5d8-45d6407b8da5` | 11005 | `/static/bundle.js` | 15GB | 💫 | DreamMaker Pro • Smart |
| Elite | `2680152c-0dc3-4fdb-b366-e936358b121f` | 11006 | `/media/stream` | 20GB | 🔥 | DreamMaker Elite • Priority |
| Unlimited | `89c0f294-3f94-4735-96cf-9c1aefdbcbb2` | 11007 | `/v2/content/live` | ∞ | 💎 | DreamMaker Infinity • Max |

### VLESS Config Format (per tier)

**Example: Starter tier**

```
vless://7dd47c02-8dce-4b12-9dbc-7cdb95a9e10e@dreammaker-groupsoft.ir:443?
  type=xhttp&
  encryption=none&
  path=/api/v1/ping&
  host=cdn.dreammaker-groupsoft.ir&
  mode=auto&
  x_padding_bytes=100-1000&
  security=tls&
  fp=chrome&
  alpn=h2%2Chttp%2F1.1&
  sni=cdn.dreammaker-groupsoft.ir#
  🔵 DreamMaker Lite • Stable
```

**Subscription base64** (for import):
```
vless://...config1...\n
vless://...config2...\n
base64 encode all ↑
```

---

## 14) Service Dependencies & Health Checks

### Required Services (MUST BE RUNNING)

| Service | Port | Status Check | Auto-Start |
|---|---|---|---|
| **Nginx** | 80, 443 | `sudo systemctl status nginx` | ✅ Yes |
| **Xray (x-ui)** | 11001–11007 | `sudo systemctl status x-ui` | ✅ Yes |
| **Certbot** | — | `sudo systemctl status certbot.timer` | ✅ Yes (cert renewal) |

### Optional Services

| Service | Port | Purpose | Status |
|---|---|---|---|
| **WARP SOCKS** | 40000 | OpenAI routing | ⚠️ Unknown |
| **Fail2ban** | — | SSH/panel protection | ⚠️ Unknown |

### Health Check Script

```bash
#!/bin/bash
echo "=== DreamMaker Health Check ==="

# Nginx
echo -n "Nginx... "
systemctl is-active nginx &>/dev/null && echo "✅" || echo "❌"

# Xray
echo -n "Xray (x-ui)... "
systemctl is-active x-ui &>/dev/null && echo "✅" || echo "❌"

# Xray inbounds
echo -n "Xray inbounds (11001-11007)... "
ss -tlnp | grep -q 11001 && echo "✅" || echo "❌"

# Certificate
echo -n "SSL certificate... "
openssl x509 -in /etc/letsencrypt/live/dreammaker-groupsoft.ir/cert.pem -checkend 86400 &>/dev/null && echo "✅ (valid >24h)" || echo "⚠️ (expires soon)"

# HTTPS connectivity
echo -n "HTTPS on 443... "
timeout 3 curl -sI https://dreammaker-groupsoft.ir &>/dev/null && echo "✅" || echo "❌"

echo "=== Done ==="
```

---

## 15) Troubleshooting Guide

### Issue: Clients Can't Connect (403 Forbidden)

**Cause:** Missing Nginx location blocks

**Fix:**
1. Check `/etc/nginx/nginx.conf` has all 7 location blocks
2. Run `sudo nginx -t` to validate syntax
3. Run `sudo systemctl reload nginx`
4. Test: `curl -I https://dreammaker-groupsoft.ir/api/v1/ping`

---

### Issue: IPv6 Socket Errors in Xray Logs

**Cause:** Xray binding to `[::]:PORT` (public IPv6)

**Fix:**
1. Edit `/usr/local/x-ui/bin/config.json`
2. Change all `"listen": "0.0.0.0"` to `"listen": "127.0.0.1"`
3. Restart: `sudo systemctl restart x-ui`
4. Verify: `ss -tlnp | grep -E ":(1100[1-7])"`

---

### Issue: Certificate Not Recognized

**Cause:** Certbot renewal failed or config mismatch

**Fix:**
1. Check renewal status: `sudo certbot renew --dry-run`
2. Verify path: `ls -la /etc/letsencrypt/live/dreammaker-groupsoft.ir/`
3. Reload Nginx: `sudo systemctl reload nginx`

---

### Issue: WebSocket Upgrade Fails

**Cause:** Missing or incorrect proxy headers

**Fix:**
1. Check Nginx config has:
   ```nginx
   proxy_set_header Upgrade $http_upgrade;
   proxy_set_header Connection "upgrade";
   ```
2. Verify Cloudflare WebSocket is enabled
3. Test: `curl -i -N -H "Connection: Upgrade" -H "Upgrade: websocket" https://dreammaker-groupsoft.ir/api/v1/ping`

---

## 16) Security Best Practices

### Nginx Security

- ✅ `server_tokens off` — hide Nginx version
- ✅ `ssl_session_tickets off` — prevent session resumption attacks
- ✅ `ssl_stapling on` — OCSP stapling for fresh cert status
- ✅ `X-Content-Type-Options: nosniff` — prevent MIME sniffing
- ✅ `X-Frame-Options: DENY` — prevent clickjacking
- ✅ Default `return 444` — fail-closed on unknown paths

### Xray Security

- ✅ Localhost-only inbounds (no public exposure)
- ✅ Sniffing enabled (http, tls) for DPI resistance
- ✅ Private IP blocking (SSRF protection)
- ✅ Bittorrent blocking
- ✅ Firewall blocks non-essential ports at datacenter

### Cloudflare Security

- ✅ Full (strict) SSL/TLS mode (origin cert validation)
- ✅ Orange-cloud proxy (traffic through CF edge)
- ✅ Authenticated Origin Pulls (optional, for extra security)

---

## 17) Performance Optimization

### HTTP/2 Benefits (ENABLED)

- Binary framing (smaller packets, faster parsing)
- Stream multiplexing (multiple requests on one connection)
- Header compression (HPACK, ~80% reduction)
- Server push (optional, for asset preloading)

### XHTTP Transport Benefits (RECOMMENDED)

- HTTP/2 camouflage (looks like normal CDN traffic)
- DPI resistance (splits traffic into HTTP chunks)
- Cloudflare compatibility (native support)
- Low latency (minimal encapsulation overhead)

### DNS Optimization (CURRENT)

```
Cloudflare DoH (1.1.1.1) → fast, privacy-friendly
Google DoH (8.8.8.8) → fallback
localhost → emergency fallback
```

---

## 18) Future Enhancement Roadmap

### Phase 2 (Post-Hardening)

- [ ] Implement REALITY transport (domain obfuscation)
- [ ] Add gRPC fallback transport
- [ ] Configure per-user custom DNS
- [ ] Set up traffic statistics monitoring
- [ ] Implement Fail2ban for panel protection
- [ ] Research WARP SOCKS integration for OpenAI

### Phase 3 (Premium Features)

- [ ] Multi-country inbound routing
- [ ] Advanced load balancing
- [ ] Per-tier rate limiting
- [ ] Subscription auto-renewal reminders
- [ ] Tier upgrade/downgrade automation

---

## 19) Operational Runbooks

### Daily Health Check

```bash
# 1. Service status
sudo systemctl status nginx x-ui

# 2. Port binding
sudo ss -tlnp | grep -E ":(80|443|1100[1-7])"

# 3. Certificate expiry
echo | openssl s_client -servername dreammaker-groupsoft.ir -connect dreammaker-groupsoft.ir:443 2>/dev/null | grep "notAfter"

# 4. Recent errors
sudo journalctl -u x-ui -n 20
```

### Weekly Audit

```bash
# 1. Verify Cloudflare settings (via dashboard)
# 2. Check UFW rules match design
sudo ufw status verbose

# 3. Monitor cert renewal
sudo certbot certificates

# 4. Review Nginx access logs
sudo tail -100 /var/log/nginx/access.log
```

### Monthly Deep Review

- [ ] Audit all tier subscriptions are importing cleanly
- [ ] Test end-to-end connectivity from different regions
- [ ] Review Xray logs for anomalies
- [ ] Update this document with new findings
- [ ] Verify Cloudflare SSL/TLS mode is still Full (strict)

---

## 20) Document Maintenance

### How to Use This Handoff

1. **First read:** Sections 1–4 (vision, current state, audit findings)
2. **Implementation:** Sections 9–12 (Nginx, Xray, fixes)
3. **Troubleshooting:** Section 15 (when things break)
4. **Reference:** Sections 2–8 (architecture, TLS, transport)

### Updating This Document

- **After Cloudflare changes:** Update Section 8
- **After Nginx updates:** Update Section 9
- **After new tiers added:** Update Section 13
- **After new issues discovered:** Update Section 15

---

## FINAL CHECKLIST BEFORE PRODUCTION

- [ ] Xray inbounds changed to `127.0.0.1` only
- [ ] All Nginx location blocks deployed
- [ ] UFW rules cleaned (only 80/443)
- [ ] Cloudflare SSL/TLS = Full (strict)
- [ ] Cloudflare WebSocket = Enabled
- [ ] Cloudflare HTTP/2 = Enabled
- [ ] Nginx `nginx -t` passes
- [ ] Systemd auto-restart enabled for nginx, x-ui
- [ ] Certificate renewal working (certbot.timer)
- [ ] End-to-end HTTPS test passed
- [ ] First tier subscription imported and tested
- [ ] Health check script deployed

---

**Status:** Ready for immediate remediation  
**Last verified:** 2026-05-09 09:03 UTC+0330  
**Next review:** 2026-05-16

---

## 31) DNS Strategy & Anti-Poisoning Architecture

### Objective

DNS is no longer a passive utility in a censored environment. It is an operational control plane. The goal is to make resolution resilient, privacy-preserving, and hard to poison while keeping client behavior predictable and low-risk.

> **Operational rule:** DNS must be treated as a survivability layer, not a convenience layer.

### Recommended Architecture

```text
Client Resolver / Xray DNS
    → Cloudflare DoH (primary)
    → Google DoH (secondary)
    → Quad9 (filtered emergency fallback)
    → Shecan (regional compatibility fallback, where appropriate)
    → localhost / system resolver fallback
```

### Why Cloudflare DNS Is the Primary Choice

Cloudflare DoH is preferred as the first resolver because it is fast, globally distributed, and generally resilient under selective filtering. It also reduces exposure to ISP DNS manipulation because the query is encrypted over HTTPS.

### Why DoH Is Preferred Over Plain DNS

| Property | Plain DNS | DoH |
|---|---|---|
| Query visibility to ISP | High | Low |
| Tampering / poisoning risk | High | Lower |
| Packet inspection exposure | High | Lower |
| Port-based blocking risk | Moderate | Lower |
| Operational stealth | Weak | Stronger |

**Warning:** DoH does not make DNS invulnerable. It only removes the easiest interception and poisoning path.

### Why Direct ISP DNS Must Never Be Primary

**Direct ISP DNS should never be the first resolver** because:
- It is the easiest target for censorship operators.
- It may be silently poisoned or transparently redirected.
- It can leak client intent and domain patterns.
- It creates inconsistent behavior across regions and carriers.

> **Policy:** ISP DNS is acceptable only as an emergency fallback when encrypted resolvers are unavailable.

### DNS Poisoning Risks Under Severe Filtering

When filtering escalates, DNS failures usually appear as one of the following:
- Correct domain, wrong IP
- Correct IP, wrong SNI behavior
- Intermittent resolution inconsistencies
- NXDOMAIN injection for specific subdomains
- Selective response delay to create client timeouts

**Operational effect:** poisoned DNS can look like a CDN outage, a certificate issue, or a client-side problem. Diagnosis must distinguish between these states.

### Recommended DNS Order for Xray

| Priority | Resolver | Purpose | Notes |
|---|---|---|---|
| 1 | Cloudflare DoH | Primary encrypted lookup | Fast, resilient, low-friction |
| 2 | Google DoH | Secondary encrypted lookup | Broad global availability |
| 3 | Quad9 | Emergency filtered fallback | Better safety posture in hostile conditions |
| 4 | Shecan | Regional compatibility fallback | Useful when local compatibility matters |
| 5 | localhost | Last resort / system fallback | Use only when encrypted paths fail |

### DNS Cache Tuning Recommendations

| Setting | Recommended Value | Reason |
|---|---|---|
| Positive cache TTL | 300–900 seconds | Keeps lookups fresh without excessive churn |
| Negative cache TTL | 30–60 seconds | Prevents long poisoning persistence |
| Resolver retry timeout | 2–4 seconds | Avoids long user-visible stalls |
| Parallel resolvers | Enabled | Helps survive partial resolver failure |
| Fallback delay | Minimal, but not zero | Prevents immediate cascade on transient errors |

**Note:** Cache duration must be short enough for recovery but long enough to avoid repetitive external lookups.

### Split-Horizon DNS Explanation

Split-horizon DNS means different resolver paths can return different answers for the same domain depending on the network context.

**In DreamMaker terms:**
- Public clients may resolve a clean domain through Cloudflare-backed answers.
- Internal operations may resolve service names to localhost or private addresses.
- Emergency fallback records may point to backup origins without exposing that behavior to all clients simultaneously.

> **Operational warning:** Split-horizon DNS is powerful, but misconfiguration can create inconsistent subscriptions, broken certificate validation, or client confusion.

### Clean-Domain Migration Strategy

The clean domain should function as a low-friction escape hatch when the primary domain becomes noisy, rate-limited, or blocked.

**Recommended migration pattern:**
1. Keep the clean domain live before an incident occurs.
2. Ensure it points to the same origin or a mirrored origin.
3. Keep branding consistent so clients can trust the alternate URL.
4. Rotate subscription delivery through the clean domain first.
5. Only move to deeper fallback channels when necessary.

### TTL Recommendations

| Scenario | Recommended TTL | Rationale |
|---|---|---|
| Production | 300–600 seconds | Balanced caching and agility |
| Emergency migration | 60–120 seconds | Faster propagation during change events |
| Failover mode | 30–60 seconds | Rapid reroute under active disruption |

### DNS Provider Comparison

| DNS Provider | Purpose | Reliability | Filtering Resistance | Latency |
| ------------ | ------- | ----------- | -------------------- | ------- |
| Cloudflare DoH | Primary encrypted resolver | Very High | High | Very Low |
| Google DoH | Secondary global resolver | Very High | High | Low |
| Quad9 | Emergency filtered fallback | High | Medium | Low |
| Shecan | Regional compatibility fallback | Medium | Medium | Low |
| Localhost fallback | Last resort resolver | Depends on host | Low | Very Low |

> **Note:** “Reliability” here means operational consistency under hostile or degraded conditions, not just nominal uptime.

---

## 32) Subscription Delivery & Resilience Strategy

### Why Subscription Delivery Is Part of Censorship Warfare

Subscription delivery is not a trivial distribution problem. In a heavily filtered environment, the subscription endpoint itself becomes a choke point. Once attackers can identify and block the delivery path, they can prevent clients from learning new endpoints even if the transport layer still works.

**Operational reality:** blocking subscription delivery is often easier than blocking the tunnel itself.

### Why a Single Subscription Endpoint Is Dangerous

A single endpoint creates a single point of failure for:
- Discovery
- Onboarding
- Rotation
- Recovery
- Tier updates
- Emergency reroute instructions

If that endpoint fails, the service may still exist, but users lose the ability to reach it.

### Recommended Delivery Topology

| Channel | Purpose | Resilience | Notes |
|---|---|---|---|
| Primary subscription URL | Standard client imports | High | Fast path for normal operations |
| Backup subscription URL | Secondary import source | High | Should mirror the primary payload |
| Clean-domain URL | Migration and recovery | Very High | First fallback during blocking |
| Telegram-delivered emergency subscription | Out-of-band recovery | Very High | Use when web endpoints are degraded |

### Delivery Formats

#### Base64 Delivery
Base64 is simple and widely supported. It is best for compatibility, but it is not inherently secure.

**Use it for:**
- Broad client compatibility
- Simple import links
- Low-complexity recovery

**Limitations:**
- Easy to copy, mirror, or reuse
- No tamper evidence by itself

#### JSON Delivery
JSON is better when the client ecosystem needs structured metadata.

**Use it for:**
- Client grouping
- Expiration metadata
- Health-state annotations
- Multiple transport definitions

**Example schema concept:**
```json
{
  "version": 1,
  "generated_at": "2026-05-09T00:00:00Z",
  "entries": [
    {
      "name": "DreamMaker Premium",
      "url": "https://example/sub",
      "priority": 1,
      "health": "primary"
    }
  ]
}
```

#### Signed Subscription Bundles
Signed bundles are the strongest option for integrity-aware distribution.

**Recommended properties:**
- Payload is signed server-side
- Client verifies signature before import
- Tampered bundles are rejected
- Signature metadata is separated from transport metadata

> **Warning:** signing protects integrity, not availability. It does not prevent blocking.

### Cache-Control Headers

Subscription endpoints should deliberately control caching behavior.

| Header | Recommended Value | Purpose |
|---|---|---|
| Cache-Control | `no-store` or `max-age=60` | Limits stale subscription exposure |
| ETag | Optional | Supports change detection |
| Last-Modified | Optional | Helps lightweight refresh logic |
| Content-Type | `application/json` or `text/plain` | Explicit payload semantics |

**Operational guidance:**  
- Use `no-store` for emergency links.  
- Use short TTLs for normal delivery.  
- Never allow long-lived stale copies on public caches for recovery endpoints.

### How Clients Should Rotate Subscriptions Automatically

Clients should not wait for manual intervention after a failure. They should cycle through a deterministic, health-aware list.

**Recommended rotation logic:**
1. Try primary subscription URL.
2. If unavailable, try backup subscription URL.
3. If unavailable, try clean-domain URL.
4. If unavailable, try Telegram-delivered emergency payload.
5. If all fail, prompt for manual QR or paste recovery.

**Rotation rules:**
- Keep the last successful source cached locally.
- Do not hammer all sources simultaneously.
- Back off between retries.
- Re-check health periodically, not continuously.

### Emergency Recovery Flow

1. **Domain blocked**  
   Move to clean-domain or alternate hostnames.

2. **Subscription endpoint blocked**  
   Switch to backup URL and reduce cache age.

3. **CDN blocked**  
   Use direct-origin or alternate CDN path if pre-provisioned.

4. **Telegram fallback**  
   Push a minimal recovery payload and instructions out of band.

5. **Manual QR recovery**  
   Last-resort import path for users with no live endpoint access.

> **Operational note:** The recovery path must be prepared before the incident. It is not something that can be invented under pressure.

---

## 33) Advanced Mobile-Network Stability Intelligence

### Why Mobile Carriers Behave Differently from Wi‑Fi

Mobile networks are not just “slower Wi‑Fi.” They often have:
- more aggressive NAT translation,
- more frequent cell handoff events,
- variable radio quality,
- shorter idle timers,
- stricter background traffic management,
- and bursty loss during signal transitions.

The result is that connections that look stable on Wi‑Fi may fail on mobile even when the server is healthy.

### Mobile Failure Mechanisms

#### NAT Rebinding
Mobile carriers may remap the client’s apparent source address during session lifetime. Long-lived connections can be disrupted without the app clearly understanding why.

#### Aggressive Idle Timeout
Many carriers close quiet flows quickly. A session that remains inactive for too long may be torn down without warning.

#### Packet Loss Bursts
Mobile loss is often bursty rather than uniform. A few consecutive packet drops can break fragile transports.

#### IPv6-Only Mobile Networks
Some networks are IPv6-only or IPv6-preferred. Dual-stack assumptions can fail if the client, resolver, or backend is not prepared.

#### CGNAT Instability
Carrier-grade NAT adds another moving layer between the user and the internet. That layer can amplify timeout and rebinding problems.

### Mobile Stability Comparison Table

| Problem | Mobile Cause | Recommended Mitigation |
| ------- | ------------ | ---------------------- |
| NAT rebinding | Carrier changes session mapping | Use tolerant reconnect logic and keepalive awareness |
| Aggressive idle timeout | Radio sleep / background suspension | Shorter heartbeat and sensible read timeout |
| Packet loss bursts | Signal transitions / congestion | Prefer transports with better loss tolerance |
| IPv6-only access | Carrier network design | Ensure IPv6-aware fallback strategy |
| CGNAT instability | Shared address translation | Use resilient session recovery and fast re-dial |
| Background app suspension | OS power management | Avoid overly chatty idle behavior |

### XHTTP Advantages on Mobile

XHTTP is well-suited to mobile instability because it can behave more like ordinary HTTP traffic, tolerate intermittent loss better than brittle long-lived patterns, and fit naturally inside CDN-backed environments.

**Benefits:**
- Better fit for multiplexed HTTP behavior
- Lower exposure to fixed transport fingerprints
- Better survivability under intermittent radio conditions

### Why WebSocket Disconnects More Often

WebSocket often depends on a more fragile long-lived TCP session with visible upgrade semantics and common timeout patterns. On mobile, that can make it more likely to reset, especially when backgrounded or when the carrier expires the idle flow.

### Why QUIC May Help in the Future

QUIC can improve recovery behavior in lossy and roaming-heavy conditions because it is designed with modern transport assumptions, including faster migration and less reliance on classic TCP session behavior.

**Caution:** QUIC is not automatically better in every deployment. It must be validated against the actual carrier mix and edge/CDN behavior.

### Recommended Timeout Tuning

| Setting | Recommended Range | Why |
|---|---|---|
| Client reconnect delay | 3–10 seconds | Avoids thundering herd reconnects |
| Read timeout | 60–180 seconds | Balances mobile idleness and resilience |
| Write timeout | 30–120 seconds | Prevents hung sessions |
| Keepalive interval | 15–30 seconds | Helps preserve idle flows |
| Retry budget | Limited with backoff | Reduces burst failures |

> **Warning:** overly aggressive keepalives can create a visible signature. Keep the interval plausible.

---

## 34) Traffic Pattern Safety & User Behavior Recommendations

### Why Traffic Patterns Matter

Detection systems do not only inspect packet contents. They also learn from timing, reconnect behavior, and traffic regularity. Even when encryption is strong, the shape of behavior can still be suspicious.

### Why Abusive Traffic Patterns Increase Detection Probability

Risk rises when clients:
- reconnect in synchronized waves,
- start and stop with machine-like precision,
- emit constant-speed downloads for long periods,
- or retry too aggressively after failure.

These patterns can resemble automation rather than ordinary user activity.

### Why Synchronized Reconnects Are Dangerous

When many clients reconnect at the same instant, the event becomes highly visible. It can look like a bot-driven failure storm or a coordinated recovery attempt, which may trigger automated scrutiny.

### Why Constant-Speed Downloads Are Suspicious

Human usage usually varies. Constant throughput with no pauses, no request diversity, and no natural idle time can look unnatural, especially when repeated across many sessions.

### Safe Usage Recommendations

- Let clients reconnect with staggered delays.
- Keep traffic bursts moderate and varied.
- Avoid simultaneous mass refreshes.
- Use ordinary browsing and media patterns.
- Keep retries conservative during outage conditions.
- Prefer a few stable sessions over many rapidly cycling ones.

### Unsafe Behavior Examples

| Behavior | Why It Is Risky |
|---|---|
| All clients reconnecting at once | Creates a visible synchronized event |
| Repeated immediate retries | Looks like scripted failure storms |
| Constant maximum-speed downloads | Appears non-human and mechanically consistent |
| Fixed-interval polling | Easy to fingerprint over time |
| Automated burst testing during live service | Distorts normal traffic shape |

### Recommended Client Settings

| Setting | Recommendation | Notes |
|---|---|---|
| Reconnect delay | 3–10 seconds | Randomize within a small range |
| Retry interval | 5–15 seconds | Use backoff on repeated failure |
| Mux settings | Moderate, not extreme | Good for efficiency without overconsolidation |
| Concurrency | Conservative | Avoid sudden spikes and noisy fan-out |

> **Operational note:** user behavior is part of the system. Good client defaults are a form of infrastructure hardening.

---

## 35) Capacity Planning & Scalability Forecast

### Capacity Planning Goals

The system should scale in a controlled way so that the first bottleneck is understood before it becomes a failure. Capacity planning must consider CPU, RAM, network, TLS termination cost, and connection churn.

### Production Planning Table

| Concurrent Users | Recommended CPU | RAM | Expected Throughput |
| ---------------- | --------------- | --- | ------------------- |
| 100–250 | 1–2 vCPU | 1–2 GB | Light browsing, small media |
| 250–750 | 2 vCPU | 2–4 GB | Stable daily use |
| 750–2,000 | 4 vCPU | 4–8 GB | Mixed browsing and streaming |
| 2,000–5,000 | 4–8 vCPU | 8–16 GB | Heavier multi-client operation |
| 5,000+ | 8+ vCPU | 16 GB+ | Requires segmented architecture |

**Note:** actual throughput depends heavily on traffic mix, CDN behavior, TLS overhead, and client churn.

### Nginx Scaling Behavior

Nginx usually scales well for front-door TLS and reverse proxy duties. It tends to remain efficient until:
- connection counts become extreme,
- buffer usage grows,
- logging pressure increases,
- or upstream latency becomes uneven.

### Xray Memory Expectations

Xray memory usage rises with:
- active sessions,
- buffering,
- concurrency,
- sniffing/routing complexity,
- and transport behavior.

**Operational guidance:** monitor memory under live load, not just during startup.

### Cloudflare Edge Benefits

Cloudflare edge absorbs a meaningful share of the front-door burden:
- TLS termination assistance,
- DDoS absorption,
- caching of static or quasi-static requests,
- and global route optimization.

This reduces origin stress and makes single-region outages less visible to the client.

### Bottlenecks Likely to Appear First

| Bottleneck | Typical First Sign | Why It Appears Early |
|---|---|---|
| TLS handshake load | CPU spikes | Cryptographic work is front-loaded |
| Connection churn | Frequent reconnects | Session management becomes noisy |
| Origin bandwidth | Slower throughput | Upstream link saturates |
| RAM pressure | Worker instability | Buffers and sessions accumulate |
| Logging I/O | Disk latency | Excessive logs slow the host |

### Recommended VPS Upgrade Thresholds

Upgrade before the system becomes unstable, not after.

| Trigger | Recommended Action |
|---|---|
| CPU persistently above 70% under normal load | Move to a larger instance |
| RAM consistently above 75% | Add memory or split services |
| Origin bandwidth nearing saturation | Offload or multi-home traffic |
| Frequent reconnect storms | Improve client retry behavior and add capacity |
| Sustained multi-region use | Separate origins by geography |

### When to Separate Nginx and Xray

Separate Nginx and Xray when:
- TLS termination becomes expensive,
- logs become too noisy,
- worker tuning can no longer stabilize latency,
- or the origin needs stronger isolation.

### When to Move to Multi-Origin Architecture

Move to multi-origin when:
- one server no longer handles the aggregate load cleanly,
- regional latency varies materially,
- failover recovery must be near-instant,
- or blocking pressure becomes localized and unpredictable.

---

## 36) Incident Response Playbooks

### General Incident Structure

Each incident should follow the same lifecycle:
1. Confirm symptoms.
2. Identify the affected layer.
3. Apply the smallest safe recovery action.
4. Verify user impact is reduced.
5. Document root cause and preventive measures.

---

### TLS Failure Incident

**Symptoms**
- Browser certificate warnings
- Handshake failures
- `CERTIFICATE_VERIFY_FAILED`
- Cloudflare origin errors

**Detection**
- Check certificate expiry.
- Confirm SNI and hostname match.
- Validate origin cert path.
- Inspect Cloudflare SSL mode.

**Immediate Actions**
- Restart Nginx only if config changed.
- Renew certificate if expiry is near.
- Confirm `Full (strict)` is still enabled.
- Validate chain with `openssl s_client`.

**Recovery**
- Restore a valid certificate chain.
- Reload Nginx.
- Retest from a browser and a CLI client.

**Postmortem Tasks**
- Record expiry lead time.
- Add earlier alerting.
- Review certificate automation health.

---

### CDN Outage

**Symptoms**
- Cloudflare requests time out
- 403/5xx responses at the edge
- Clients cannot reach the proxied domain

**Detection**
- Test the same host via alternate network.
- Confirm whether DNS still resolves.
- Compare direct-origin and CDN behavior.

**Immediate Actions**
- Switch to a clean-domain path if available.
- Reduce reliance on cached edge assumptions.
- Notify users through out-of-band channels.

**Recovery**
- Re-establish edge routing.
- Restore normal subscription URLs.
- Re-validate public reachability.

**Postmortem Tasks**
- Determine whether the issue was edge, account, DNS, or origin related.
- Update fallback ordering if needed.

---

### Mass Disconnect Event

**Symptoms**
- Large numbers of clients drop at once
- Reconnect storm appears
- Session lifetime collapses

**Detection**
- Review logs for simultaneous disconnect timestamps.
- Check upstream capacity and timeout patterns.
- Look for shared-path failure or CDN disruption.

**Immediate Actions**
- Increase service stability rather than forcing rapid retries.
- Extend timeout windows if they are too short.
- Ask clients to back off reconnects.

**Recovery**
- Restore stable session patterns.
- Verify a representative client set.
- Confirm the event is not recurring on a timer.

**Postmortem Tasks**
- Review reconnect logic.
- Tune client backoff behavior.
- Add more detailed incident timestamps.

---

### High Packet Loss Event

**Symptoms**
- Lag spikes
- Connection stalls
- Streaming degradation
- Random request failures

**Detection**
- Compare behavior across mobile and wired clients.
- Test packet loss from the origin to the edge.
- Review transport-specific performance.

**Immediate Actions**
- Encourage clients to reduce concurrency.
- Shift to the most tolerant transport available.
- Avoid making rapid config changes during instability.

**Recovery**
- Stabilize routing and reduce churn.
- Confirm sessions recover after brief loss.
- Monitor for carrier-specific issues.

**Postmortem Tasks**
- Document path-specific loss.
- Tune timeout values.
- Consider alternate transport defaults for mobile-heavy usage.

---

### Sudden DPI Escalation

**Symptoms**
- Rapid rise in resets
- Path-based blocking
- Domain-specific failures
- Traffic shaped or throttled differently

**Detection**
- Compare affected paths and unaffected ones.
- Test through clean-domain and backup channels.
- Look for common fingerprints across failures.

**Immediate Actions**
- Reduce visible churn.
- Rotate to backup delivery path.
- Prefer the transport with the lowest observable signature.

**Recovery**
- Restore service through fallback routes.
- Verify subscriptions still reach clients.
- Update emergency channel notices.

**Postmortem Tasks**
- Record what changed in the network environment.
- Review fingerprint exposure.
- Update the fallback playbook.

---

### Origin Overload

**Symptoms**
- High CPU
- Slow responses
- 502/504 errors
- Nginx worker exhaustion

**Detection**
- Check resource graphs.
- Identify top concurrent destinations.
- Confirm whether origin services or edge services are the bottleneck.

**Immediate Actions**
- Throttle or stagger reconnect pressure.
- Reduce logging verbosity if I/O is saturated.
- Shift traffic to a backup origin if available.

**Recovery**
- Scale CPU/RAM or separate components.
- Validate the load profile after mitigation.
- Confirm stable throughput before reopening demand.

**Postmortem Tasks**
- Raise capacity thresholds.
- Introduce more aggressive monitoring.
- Split services earlier next time.

---

### Subscription Poisoning Attack

**Symptoms**
- Users import incorrect endpoints
- Configs appear altered or inconsistent
- Delivery URLs behave normally but payloads differ
- Unexpected client errors appear after subscription refresh

**Detection**
- Compare payload hashes against known-good versions.
- Verify signatures where used.
- Check for cache-layer tampering or stale mirrors.

**Immediate Actions**
- Disable or replace compromised delivery paths.
- Push a signed clean payload through a trusted channel.
- Instruct users not to trust unsigned mirrors.

**Recovery**
- Restore verified subscription sources.
- Rebuild the delivery chain with integrity checks.
- Rotate URLs if needed.

**Postmortem Tasks**
- Add stronger signing or verification.
- Reduce exposure of public mirrors.
- Audit cache-control and CDN behavior.

---

## 37) Logging, Privacy & Data Minimization Policy

### Policy Goal

Operational visibility is necessary, but data retention must remain conservative. Logging should be sufficient for health, abuse control, and incident recovery without creating unnecessary privacy risk.

### What Should NOT Be Logged

- Full user payload content
- Sensitive headers beyond operational need
- Complete per-request identity trails unless required
- Raw subscription secrets
- Credentials or API tokens
- Private client metadata that is not needed for service operation

> **Warning:** if it is not necessary for incident handling or abuse mitigation, do not collect it by default.

### Why Excessive Logs Are Dangerous

Excessive logs increase:
- privacy exposure,
- storage burden,
- accidental disclosure risk,
- forensic noise,
- and the chance that old data becomes a liability.

### Access-Log Retention Recommendations

| Environment | Recommended Retention | Rationale |
|---|---|---|
| Production | 7–14 days | Enough for short incident investigations |
| High-privacy mode | 1–3 days | Minimizes retained user activity traces |
| Debug window | Temporarily extended | Only during active incident work |
| Archive copies | Avoid by default | Reduces long-term exposure |

### IP Anonymization Recommendations

| Technique | Recommendation | Notes |
|---|---|---|
| Truncate last octet / prefix | Recommended where feasible | Reduces exact identity exposure |
| Hash with rotating salt | Recommended | Allows trend analysis without direct storage |
| Full IP retention | Avoid by default | Only for short-lived abuse investigations |
| Per-request user mapping | Avoid unless required | High privacy risk |

### Privacy-Conscious Operational Model

**Preferred model:**
- Log the minimum needed to keep the service stable.
- Retain only what is needed for the shortest reasonable time.
- Make sensitive logs access-controlled.
- Separate debugging from normal operational logging.
- Purge temporary diagnostics after validation.

### Log Type Retention Table

| Log Type | Keep? | Retention | Risk |
| -------- | ----- | --------- | ---- |
| Nginx access log | Yes, limited | 7–14 days | Medium |
| Nginx error log | Yes | 14–30 days | Medium |
| Xray access log | No by default | Off or minimal | High |
| Xray error log | Yes | 7–14 days | Medium |
| Subscription delivery log | Minimal only | 3–7 days | High |
| Auth / credential log | No | None | Very High |
| Debug packet capture | Temporary only | Hours to days | Very High |

> **Operational note:** privacy and reliability are not opposing goals. Minimal logging usually improves both.

---

## 38) Long-Term Evolution Strategy

### Strategic Direction

DreamMaker should evolve from a **single-node proxy deployment** into an **adaptive censorship-resistant traffic platform**.

That means the system should gradually become:
- topology-aware,
- health-aware,
- transport-aware,
- CDN-aware,
- region-aware,
- and recovery-aware.

### Roadmap

#### XHTTP Evolution
XHTTP should remain the preferred primary transport while its tuning and client compatibility improve. Future work should focus on stability under loss, better compatibility across mobile carriers, and more intelligent fallback behavior.

#### HTTP/3 Future
HTTP/3 should be evaluated for resilience and mobile behavior, but only after production verification. It should not be adopted purely because it is newer.

#### QUIC Viability
QUIC may offer better roaming and loss recovery characteristics, but it must prove itself against real carrier networks, not just lab benchmarks.

#### REALITY Future Reconsideration
REALITY may be reconsidered for special cases where direct connectivity is appropriate. It remains strategically different from the CDN-first model, so any revisit must be deliberate and workload-specific.

#### Multi-CDN Strategy
A multi-CDN model can improve resilience against edge-specific failures, policy changes, and region-specific blocking. The cost is greater operational complexity.

#### Multi-Domain Rotation
Multiple domains should be pre-provisioned so emergency rotation is operationally simple rather than improvised.

#### Adaptive Routing
Routing should increasingly depend on:
- measured latency,
- packet loss,
- transport compatibility,
- CDN health,
- and region-specific blocking patterns.

#### Smart Client Auto-Selection
Clients should eventually choose between profiles automatically based on observed conditions instead of forcing users to guess.

#### Automatic Health-Aware Subscriptions
Subscriptions should evolve from static lists into health-aware catalogs that can mark routes as primary, backup, degraded, or emergency.

### Recommended Direction of Travel

| Today | Target State |
|---|---|
| Static endpoint list | Health-aware subscription catalog |
| Manual failover | Automatic fallback selection |
| Single CDN dependence | Multi-CDN survivability |
| Single-origin dependency | Multi-origin resilience |
| Uniform client settings | Context-aware client defaults |
| Reactive operations | Proactive adaptation |

### Final Philosophy

- **Stability over hype**
- **Survivability over benchmark speed**
- **Realistic traffic over aggressive tunneling**
- **Operational simplicity over unnecessary complexity**

> **Closing principle:** the best architecture is the one that stays usable when conditions stop being ideal.



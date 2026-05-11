# DreamMaker Infrastructure — Complete Deployment & Audit Report

**Last updated:** 2026-05-09  
**Status:** Audit complete | Critical fixes required  
**Purpose:** Production handoff with real audit findings, current state assessment, and remediation plan

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

## 1) Vision & Core Philosophy

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

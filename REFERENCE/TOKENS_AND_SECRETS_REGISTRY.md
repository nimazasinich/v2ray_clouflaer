# TOKENS & SECRETS REGISTRY

**Last Updated:** 2026-05-10  
**Security Level:** 🔴 SENSITIVE — Handle with care  
**Purpose:** Centralized index of all credentials and their locations

---

## ⚠️ CRITICAL SECURITY NOTES

### DO NOT:
- ❌ Commit `.env` file to Git
- ❌ Expose tokens in logs or error messages
- ❌ Share this file publicly
- ❌ Use production tokens in development
- ❌ Log actual token values anywhere

### DO:
- ✅ Rotate tokens every 90 days
- ✅ Use .env.example as template only
- ✅ Load tokens from environment at runtime
- ✅ Reference this file only internally
- ✅ Verify token permissions before use

---

## 🔐 CLOUDFLARE API TOKENS

### Token 1: CF_TOKEN_FULL (RECOMMENDED FOR ALL OPERATIONS)

**Location:** 
- File: `DreamMaker_Infrastructure_Handoff_Master_Enriched.md`
- Section: `0) CREDENTIALS & ACCESS REFERENCE`
- Table: `Cloudflare API Tokens`

**Value Format:**
```
cfut_9X9JcNyxRKrZTwKg8fdQ2ua26ftC6nk5ltQeurdwbd919108
```

**Permissions:**
- ✅ Workers (create, update, deploy)
- ✅ KV Namespace (read, write, delete)
- ✅ DNS (create, read, update, delete)
- ✅ Account (read)

**Usage:**
```bash
export CLOUDFLARE_API_TOKEN="cfut_9X9JcNyxRKrZTwKg8fdQ2ua26ftC6nk5ltQeurdwbd919108"

# Deploy worker
npx wrangler deploy

# Update KV
npx wrangler kv:namespace create "subscriptions"

# Verify token
curl -H "Authorization: Bearer cfut_9X9JcNyxRKrZTwKg8fdQ2ua26ftC6nk5ltQeurdwbd919108" \
     https://api.cloudflare.com/client/v4/user/tokens/verify
```

**Status:** ✅ ACTIVE | Expires: [Check CF Dashboard]

---

### Token 2: CF_TOKEN_DNS (LEGACY - deprecated)

**Location:**
- File: `DreamMaker_Infrastructure_Handoff_Master_Enriched.md`
- Section: `0) CREDENTIALS & ACCESS REFERENCE`

**Value Format:**
```
cfut_Gacm7SKyrJI0v027D0rPp5d05ub9JeG8YJB8k5Lg6407da1a
```

**Permissions:**
- DNS read/write (zone level)
- SSL certificate management

**Status:** ⚠️ OLD | Phased out in favor of CF_TOKEN_FULL

---

### Token 3: CF_TOKEN_WORKERS (LEGACY - deprecated)

**Location:**
- File: `DreamMaker_Infrastructure_Handoff_Master_Enriched.md`
- Section: `0) CREDENTIALS & ACCESS REFERENCE`

**Value Format:**
```
cfut_dwkZszri1j76LDzWaGSryhQymn4DHeQcY8QXjNZw621e11a8
```

**Permissions:**
- Workers API (limited)

**Status:** ⚠️ OLD | Phased out in favor of CF_TOKEN_FULL

---

## 🆔 CLOUDFLARE IDENTIFIERS

### ZONE_ID (dreammaker-groupsoft.ir)

**Location:**
- File: `DreamMaker_Infrastructure_Handoff_Master_Enriched.md`
- Section: `0) CREDENTIALS & ACCESS REFERENCE`
- Table: `Cloudflare Zone & Account IDs`

**Value:**
```
7521f025c7660ad0f5ab6c57d787fa6f
```

**Usage:**
```bash
# List DNS records
curl -X GET "https://api.cloudflare.com/client/v4/zones/7521f025c7660ad0f5ab6c57d787fa6f/dns_records" \
  -H "Authorization: Bearer $CF_TOKEN_FULL"

# Update DNS record
curl -X PUT "https://api.cloudflare.com/client/v4/zones/7521f025c7660ad0f5ab6c57d787fa6f/dns_records/{record_id}"
```

**Where to find:** Cloudflare Dashboard → Overview → Zone ID

---

### ACCOUNT_ID

**Location:**
- File: `DreamMaker_Infrastructure_Handoff_Master_Enriched.md`
- Section: `0) CREDENTIALS & ACCESS REFERENCE`
- Table: `Cloudflare Zone & Account IDs`

**Value:**
```
d902b91f0f1076e0601ffd6e7b4382c0
```

**Usage:**
```bash
# Workers API calls
curl -X GET "https://api.cloudflare.com/client/v4/accounts/d902b91f0f1076e0601ffd6e7b4382c0/workers/routes"
```

**Where to find:** Cloudflare Dashboard → Account Settings

---

### KV_NAMESPACE_ID

**Location:**
- File: `DreamMaker_Infrastructure_Handoff_Master_Enriched.md`
- Section: `0) CREDENTIALS & ACCESS REFERENCE`
- Table: `Cloudflare Zone & Account IDs`

**Value:**
```
ef1a164f23424e9a9b23721fb0d16133
```

**Bound in:** `wrangler.toml` (via dashboard, not in TOML)

**Usage:**
```bash
# In Worker code
const subCache = env.SUBSCRIPTION_CACHE;  // KV namespace
await subCache.put("key", "value", { expirationTtl: 3600 });
```

**Note:** KV binding configured in Cloudflare Dashboard (Workers → edge-ws-relay-v4 → Settings → KV Namespace Bindings)

---

## 🖥️ VPS ACCESS CREDENTIALS

### ✅ ACTIVE: Germany VPS (Primary Production)

**Location:**
- File: `DreamMaker_Infrastructure_Handoff_Master_Enriched.md`
- Section: `0) CREDENTIALS & ACCESS REFERENCE`
- Table: `VPS Access — Germany (Main Production)`

**Hostname:**
```
82.115.26.105
```

**SSH Access:**
```bash
# Method 1: Via SOCKS5 proxy (recommended)
ssh -o ProxyCommand="nc -X 5 -x 127.0.0.1:10808 %h %p" root@82.115.26.105

# Method 2: VNC Console (through provider panel)
# No SSH possible on port 22 (provider blocks)
```

**Credentials:**
- **User:** `root`
- **Password:** `1111111111`

**SSH Port:** `22` (blocked at provider, use VNC instead)

**Working Directory:**
```
/root/.wrangler/
├── wrangler.toml
├── worker.js
├── nginx.conf
├── xray-config.json
└── deploy-fix.sh
```

**Files Located Here:**
- ✅ `nginx.conf` — Active Nginx config (reload with `nginx -s reload`)
- ✅ `xray-config.json` — Active Xray config (restart with `systemctl restart xray`)
- ✅ `wrangler.toml` — Cloudflare Workers config (deploy with `wrangler deploy`)
- ✅ `worker.js` — Current edge worker code

**Status:** ✅ ACTIVE PRODUCTION

---

### ⚠️ LEGACY: Iran VPS (NOT USED IN PRIMARY SETUP)

**IMPORTANT:** This VPS is NOT part of the active deployment. Remove from new deployment procedures.

**Location:**
- File: `DreamMaker_Infrastructure_Handoff_Master_Enriched.md`
- Section: `0) CREDENTIALS & ACCESS REFERENCE`
- Table: `VPS Access — Iran (Relay/Secondary)` (DEPRECATED)

**Hostname:**
```
87.107.108.53
```

**SSH Access (Direct):**
```bash
ssh -p 2222 root@87.107.108.53
```

**Credentials:**
- **User:** `root`
- **Password:** `1111111111`
- **Port:** `2222`

**Status:** ⚠️ LEGACY | REMOVE FROM ACTIVE PROCEDURES

**Why Removed:**
- Not part of primary production path
- Redundant with Germany VPS
- Simplifies deployment and maintenance
- All essential functions now on Germany VPS + Cloudflare

**Do NOT use for:**
- ❌ Active deployments
- ❌ Production config updates
- ❌ Primary Xray/Nginx operations

---

## 🌐 DOMAIN & DNS

### Primary Domain

**Domain:**
```
dreammaker-groupsoft.ir
```

**Location:**
- File: `DreamMaker_Infrastructure_Handoff_Master_Enriched.md`
- Section: `0) CREDENTIALS & ACCESS REFERENCE`
- Table: `Domain Configuration`

**DNS Records (Cloudflare):**

| Name | Type | Value | Proxy | TTL |
|---|---|---|---|---|
| `dreammaker-groupsoft.ir` | A | `82.115.26.105` | 🟠 Orange (proxied) | Auto |
| `cdn.dreammaker-groupsoft.ir` | CNAME | `dreammaker-groupsoft.ir` | 🟠 Orange (proxied) | Auto |
| `clean.dreammaker-groupsoft.ir` | CNAME | `dreammaker-groupsoft.ir` | 🟠 Orange (proxied) | Auto |

**Cloudflare Settings:**
- SSL/TLS: `Full (strict)`
- WebSocket: Enabled
- HTTP/2: Enabled
- HTTP/3 (QUIC): Enabled (optional)

**Where to manage:** Cloudflare Dashboard → Domains → dreammaker-groupsoft.ir → DNS

---

## 📱 TELEGRAM BOT

### Bot Details

**Location:**
- File: `DreamMaker_Infrastructure_Handoff_Master_Enriched.md`
- Section: `0) CREDENTIALS & ACCESS REFERENCE`
- Table: `Telegram Integration`

**Bot Token:**
```
7437859619:AAH-2MJdlNmNf7ZSlj16zf-g0QJqB-TIxJU
```

**Bot ID:**
```
7437859619
```

**Bot Username:**
```
@Freqbasterd_bot
```

**Owner Chat ID:**
```
7437859619
```

**Usage:**
```python
import telebot

bot = telebot.TeleBot("7437859619:AAH-2MJdlNmNf7ZSlj16zf-g0QJqB-TIxJU")

# Send alert
bot.send_message(7437859619, "🚨 Infrastructure alert!")
```

**Purpose:**
- Deployment notifications
- Error alerts
- System health status
- Manual commands

**Status:** ✅ ACTIVE

---

## 🔑 XRAY CLIENT IDs (UUIDs)

### Active Tier UUIDs

**Location:**
- File: `DreamMaker_Infrastructure_Handoff_Master_Enriched.md`
- Section: `0) CREDENTIALS & ACCESS REFERENCE`
- Table: `UUID Registry (Xray Client IDs)`

**Each tier has unique UUID for client identification:**

| Tier | UUID | Port | Size |
|---|---|---|---|
| **Starter** | `7dd47c02-8dce-4b12-9dbc-7cdb95a9e10e` | 11001 | 1GB |
| **Basic** | `92ebaa01-ec34-4601-a4dc-f6afdf822966` | 11002 | 2GB |
| **Standard** | `3d5e3adf-0912-4c78-9ca9-b87db334ce71` | 11003 | 5GB |
| **Plus** | `e8eb3d74-8e8c-4903-b878-8feb656ebb0c` | 11004 | 10GB |
| **Pro** | `b3540a54-67dd-452a-b5d8-45d6407b8da5` | 11005 | 15GB |
| **Elite** | `2680152c-0dc3-4fdb-b366-e936358b121f` | 11006 | 20GB |
| **Unlimited** | `89c0f294-3f94-4735-96cf-9c1aefdbcbb2` | 11007 | No limit |

**Used in:** `xray-config.json` → `inbounds[].settings.clients[].id`

**Status:** ✅ ACTIVE

---

### Retired/Legacy UUIDs

**Location:**
- File: `DreamMaker_Infrastructure_Handoff_Master_Enriched.md`
- Section: `0) CREDENTIALS & ACCESS REFERENCE`
- Table: `Legacy UUIDs (Migrated from old system — RETIRED)`

**Status:** ⚠️ RETIRED | DO NOT USE

**Action:** Delete from `xray-config.json` if still present

---

## 📄 ENVIRONMENT FILE (.env)

### Template Location

**File:** `.env.example`  
**Path:** `C:\Users\Dreammaker\Desktop\sh\files (3)\.wrangler\.env.example`

**Contents:**
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

### How to Use

```bash
# 1. Copy template
cp .env.example .env

# 2. Load in shell session
source .env

# 3. Verify
echo $CF_TOKEN_FULL  # Should show token (in actual env, not this doc!)
```

### Git Configuration

**Add to `.gitignore`:**
```
.env
.env.local
.env.*.local
env
env.*
```

**Status:** .env is git-ignored (secure)

---

## 🔌 PORT & CONNECTION MAPPING

### Ports in Use

```
Port    | Protocol  | Service          | Binding      | Public? | Status
--------|-----------|------------------|--------------|---------|--------
80      | TCP       | Nginx HTTP       | 0.0.0.0      | ✅ YES  | Active
443     | TCP       | Nginx HTTPS      | 0.0.0.0      | ✅ YES  | Active
11001   | TCP       | Xray (Tier 1)    | 127.0.0.1    | ❌ NO   | Active
11002   | TCP       | Xray (Tier 2)    | 127.0.0.1    | ❌ NO   | Active
11003   | TCP       | Xray (Tier 3)    | 127.0.0.1    | ❌ NO   | Active
11004   | TCP       | Xray (Tier 4)    | 127.0.0.1    | ❌ NO   | Active
11005   | TCP       | Xray (Tier 5)    | 127.0.0.1    | ❌ NO   | Active
11006   | TCP       | Xray (Tier 6)    | 127.0.0.1    | ❌ NO   | Active
11007   | TCP       | Xray (Tier 7)    | 127.0.0.1    | ❌ NO   | Active
40000   | TCP       | WARP SOCKS proxy | 127.0.0.1    | ❌ NO   | Active
62789   | TCP       | Xray API tunnel  | 127.0.0.1    | ❌ NO   | Active
```

### ⚠️ PORTS NO LONGER IN USE

```
Port    | Reason                          | Status
--------|----------------------------------|--------
22      | SSH blocked by provider          | ❌ Blocked
2053    | DNS-over-TLS, provider blocks   | ❌ Blocked
2082    | cPanel HTTP, provider blocks    | ❌ Blocked
2086    | cPanel HTTPS, provider blocks   | ❌ Blocked
2092    | cPanel Whois, provider blocks   | ❌ Blocked
2095    | cPanel Webmail HTTP, provider   | ❌ Blocked
2096    | cPanel Webmail HTTPS, provider  | ❌ Blocked
8000    | Xray (old), provider blocks     | ❌ Blocked
8080    | Xray (old), provider blocks     | ❌ Blocked
8880    | Xray (old), provider blocks     | ❌ Blocked
```

**Important:** Port 2053 is NOT used for any production connection. Do NOT configure services on blocked ports.

---

## ✅ CHECKLIST FOR SECURITY

- [ ] Rotate CF tokens every 90 days
- [ ] Review .gitignore includes `.env`
- [ ] Verify no tokens in logs
- [ ] Check Germany VPS SSH via proxy is working
- [ ] Test Cloudflare token with `curl /verify`
- [ ] Confirm Iran VPS is not in active deployment scripts
- [ ] Verify no port 2053 configuration in active setup
- [ ] Check Xray binds to 127.0.0.1 (not 0.0.0.0)
- [ ] Validate Nginx reverse proxy headers are correct
- [ ] Confirm Telegram bot token is not exposed

---

End of Registry

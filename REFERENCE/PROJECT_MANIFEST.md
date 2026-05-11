# DreamMaker Infrastructure — Project Manifest & File Index

**Last Generated:** 2026-05-10  
**Project Root:** `C:\Users\Dreammaker\Desktop\sh\files (3)\.wrangler\`  
**Status:** ✅ ORGANIZED | Ready for Cursor AI Integration

---

## 🎯 QUICK START FOR CURSOR

### Essential Files (READ FIRST)
1. **DreamMaker_Infrastructure_Handoff_Master_Enriched.md** — Complete infrastructure overview, architecture, and current state
2. **TOKENS_AND_SECRETS_REGISTRY.md** — Where all credentials are stored and how to use them
3. **PROJECT_STRUCTURE.md** — Complete file organization guide

### Active Deployment Directory
```
Primary Working Directory: /root/.wrangler/ (Germany VPS: 82.115.26.105)
├── wrangler.toml          [Main Cloudflare Workers config]
├── worker.js              [Edge relay implementation]
└── deploy-fix.sh          [Deployment script]
```

### Port Mapping (No Iranian VPS involvement)
```
Port 80/443 (Public)      → Nginx reverse proxy (82.115.26.105)
Port 11001-11007 (Local)  → Xray inbound tiers (127.0.0.1 only)
Port 62789 (Local)        → Xray API tunnel
Port 40000 (Local)        → WARP SOCKS routing (OpenAI, special routes)
```

---

## 📁 DIRECTORY STRUCTURE

### 1. DOCUMENTATION (Latest)
```
✅ DreamMaker_Infrastructure_Handoff_Master_Enriched.md
   └─ PRIMARY HANDOFF DOCUMENT
      • Complete architecture diagram
      • Current audit results
      • All credentials reference (section 0)
      • Critical fixes required (section 12)
      • Deployment procedures (section 13)

✅ DreamMaker_Infrastructure_Context_v2.md
   └─ Context for previous iterations
   
✅ TOKENS_AND_SECRETS_REGISTRY.md (THIS FILE)
   └─ WHERE ALL TOKENS/CREDS ARE LOCATED
   
✅ PROJECT_STRUCTURE.md
   └─ COMPLETE FILE ORGANIZATION
```

### 2. CLOUDFLARE WORKERS & EDGE (Tier 0 — Edge Gateway)
```
✅ worker.js
   └─ Current production worker deployed to CF edge
      • WebSocket relay for VLESS-over-WS
      • Subscription endpoint
      • Verification & caching logic
      Status: DEPLOYED (use wrangler deploy to update)

✅ wrangler.toml
   └─ Cloudflare Workers config
      • Service name: edge-ws-relay-v4
      • KV namespace binding
      • Routes configuration
      Status: ACTIVE

⚠️ edge-worker-tier0.ts (LEGACY)
   └─ TypeScript version of worker (for reference)
   
⚠️ edge-worker-v11.ts (REFERENCE)
   └─ Previous iteration (archived)
   
📋 config.ts / config (1).ts
   └─ Configuration exports (reference)
```

### 3. BACKEND LOGIC (Tier 1 — Helpers)
```
✅ helper-ecosystem-tier1.ts
   └─ Helper functions for Xray config generation
      • UUID management
      • Inbound/outbound builders
      Status: REFERENCE (integrated into deploy scripts)

✅ control-plane-tier2.ts
   └─ Control plane for multi-tier management
      • Tier configuration
      • Subscription handling
      Status: REFERENCE
```

### 4. XRAY SERVER CONFIG (Tier 2 — Core)
```
✅ xray-config.json
   └─ Primary Xray configuration
      • 7 inbound tiers (11001-11007)
      • All bound to 127.0.0.1 (NOT public)
      • VLESS+XHTTP protocol
      • Sniffing enabled
      Status: ACTIVE (on Germany VPS)

✅ xray-tiers.json
   └─ Tier definitions
      • Starter (1GB)
      • Basic (2GB)
      • Standard (5GB)
      • Plus (10GB)
      • Pro (15GB)
      • Elite (20GB)
      • Unlimited (no limit)

✅ xray-config-clean.json
   └─ Clean version (no commented sections)

⚠️ xray-inbounds.json
   └─ Legacy inbound definitions (DEPRECATED, use xray-config.json)
   
⚠️ xray (1).json
   └─ Backup copy
```

### 5. NGINX REVERSE PROXY CONFIG (Tier 1 — Frontend)
```
✅ nginx.conf
   └─ Main Nginx configuration
      • Server blocks for port 80 (redirect) + 443 (TLS)
      • Location blocks for all 7 tiers
      • Cloudflare real IP restoration
      • WebSocket upgrade headers
      Status: ACTIVE (on Germany VPS)

✅ nginx-hardened.conf
   └─ Enhanced version with additional security
      • CSP headers
      • Rate limiting
      • Advanced caching

✅ nginx-locations.conf
   └─ Modular location blocks (for reference)
```

### 6. DEPLOYMENT SCRIPTS (Tier 0 — Automation)
```
✅ deploy.sh
   └─ Main deployment script
      • Copies configs to Germany VPS
      • Reloads Nginx
      • Restarts Xray
      Status: READY

✅ deploy-fix.sh
   └─ Emergency fix script
      • Resets Xray to localhost-only
      • Applies UFW corrections
      Status: READY

✅ deploy-worker-dreammaker.sh
   └─ Deploys worker to Cloudflare
      • Uses wrangler deploy

✅ deploy-worker-dreammaker-keys.sh
   └─ Sets CF API tokens as secrets

⚠️ task1-nginx-fix.sh
   └─ Individual fix scripts
   
⚠️ task2-clean-domain-fix.sh
   
⚠️ task4-e2e-test.sh
   └─ End-to-end verification
```

### 7. DATABASE & DATA (Optional)
```
✅ schema.sql
   └─ Database schema (if using SQL backend)
      • User table
      • Subscription table
      • Audit logs

⚠️ rclone-mount-config.json
   └─ Remote storage config (archived)
```

### 8. CONFIGURATION TEMPLATES
```
✅ .env.example
   └─ Environment variable template
      • CF tokens
      • VPS credentials
      • Domain names
      Status: TEMPLATE (create actual .env from this)

✅ tsconfig.json
   └─ TypeScript config for compilation
   
✅ worker-stubs.d.ts
   └─ TypeScript definitions for Cloudflare bindings
```

### 9. REFERENCE & GUIDES
```
✅ DreamMaker_Enhanced_Sections_10.md
   └─ Enhanced documentation sections

✅ FINAL_AUDIT.md
   └─ Complete audit results

✅ FIXES_SUMMARY.md
   └─ All critical fixes documented

✅ HANDOFF_IMPLEMENTATION_MAP.md
   └─ Implementation checklist

✅ DEPLOYMENT_GUIDE.md
   └─ Step-by-step deployment

✅ INFRASTRUCTURE.md
   └─ Infrastructure overview

✅ README.md
   └─ General readme

✅ problem.txt
   └─ Known issues log
```

### 10. ARCHIVED & LEGACY
```
⚠️ 000000000/ (directory)
   └─ Complete backup of all configs
   └─ Exact replicas of active setup
   
⚠️ dreammaker-infrastructure-v5-fixed/
   └─ Previous major version
   
⚠️ dreammaker-infrastructure-complete/
   └─ Reference complete setup
   
⚠️ *.zip / *.tar.gz
   └─ Compressed backups
```

### 11. METADATA & LINKS
```
✅ dreammaker-links.txt
   └─ Important URLs and links

✅ dreammaker-subscription.txt
   └─ Subscription configuration

⚠️ .env (actual file — NOT committed, git-ignored)
   └─ Active credentials (NOT in repo)

⚠️ env (1) / env (1) - Copy
   └─ Backup env files
```

---

## 📊 FILE MODIFICATION TIMELINE (Latest First)

### 2026-05-10 (TODAY)
- ✅ PROJECT_MANIFEST.md — Created
- ✅ TOKENS_AND_SECRETS_REGISTRY.md — Created
- ✅ PROJECT_STRUCTURE.md — Created

### 2026-05-09 (YESTERDAY)
- 📝 DreamMaker_Infrastructure_Handoff_Master_Enriched.md — Last updated
- 📝 nginx.conf — Last updated
- 📝 xray-config.json — Last updated

### Previous Versions (Archived)
- `DreamMaker_Infrastructure_Handoff_Master (1).md`
- `DreamMaker_Infrastructure_Context_v2 (1).md`
- `INFRASTRUCTURE (1).md`
- All dated versions in backup folders

---

## 🔐 CREDENTIALS LOCATION REFERENCE

**⚠️ IMPORTANT:** Do NOT commit `.env` or any files containing actual tokens to version control.

| Type | Location | File | Status |
|---|---|---|---|
| **CF Full Token** | DreamMaker_Infrastructure_Handoff_Master_Enriched.md § 0 | Section 0: CREDENTIALS | ✅ Active |
| **CF Zone ID** | Section 0 | Table: Cloudflare Zone & Account IDs | ✅ Active |
| **CF Account ID** | Section 0 | Table: Cloudflare Zone & Account IDs | ✅ Active |
| **CF KV Namespace** | Section 0 | Table: Cloudflare Zone & Account IDs | ✅ Active |
| **Germany VPS Creds** | Section 0 | Table: VPS Access — Germany | ✅ Active |
| **Telegram Bot Token** | Section 0 | Table: Telegram Integration | ✅ Active |
| **Telegram Chat ID** | Section 0 | Table: Telegram Integration | ✅ Active |
| **Xray UUIDs (All 7)** | Section 0 | Table: UUID Registry | ✅ Active |
| **.env Template** | `.env.example` | Root directory | ✅ Template |

---

## 🚀 DEPLOYMENT WORKFLOW

### To Deploy Updated Configs to Germany VPS:

```bash
# 1. SSH into Germany VPS (requires SOCKS5 proxy at 127.0.0.1:10808)
ssh -o ProxyCommand="nc -X 5 -x 127.0.0.1:10808 %h %p" root@82.115.26.105

# 2. Navigate to working directory
cd /root/.wrangler

# 3. Copy new configs (from this directory)
# Option A: Manual via SFTP
scp -o ProxyCommand="nc -X 5 -x 127.0.0.1:10808 %h %p" \
    nginx.conf root@82.115.26.105:/etc/nginx/sites-available/dreammaker-groupsoft.ir

# Option B: Run deploy script
bash deploy.sh

# 4. Verify deployment
curl -I https://dreammaker-groupsoft.ir/api/v1/ping
curl -I https://cdn.dreammaker-groupsoft.ir/cdn/init
```

### To Deploy Worker Update to Cloudflare:

```bash
# 1. Ensure wrangler.toml has correct API token
export CLOUDFLARE_API_TOKEN="cfut_9X9JcNyxRKrZTwKg8fdQ2ua26ftC6nk5ltQeurdwbd919108"

# 2. Deploy
npx wrangler deploy --name edge-ws-relay-v4

# 3. Verify
curl -I https://dreammaker-groupsoft.ir/
```

---

## ✅ CURSOR AI INTEGRATION CHECKLIST

- [x] All files categorized and indexed
- [x] Credentials location documented
- [x] No Iranian VPS references in active setup
- [x] Port 2053 clarification (not used, provider blocks)
- [x] Latest versions identified
- [x] Deployment procedures documented
- [x] Legacy versions archived
- [x] .gitignore configured (env files excluded)

---

## 📌 IMPORTANT NOTES

### ⚠️ REMOVE THESE FROM ACTIVE DEPLOYMENT:
- **Iranian VPS (87.107.108.53)** — NO LONGER PART OF PRIMARY SETUP
  - Only used for backup/testing if needed
  - Not referenced in production configs
  - Remove from deployment scripts

### ✅ PRODUCTION SETUP USES ONLY:
- **Germany VPS (82.115.26.105)** — Primary production
- **Cloudflare Edge** — DDoS protection and routing
- **Domain: dreammaker-groupsoft.ir** — All traffic routed here

### 🚫 PORTS NOT IN USE:
- Port 2053 — Provider blocks at datacenter level
- Ports 2082, 2086, 2092, 2095, 2096 — All blocked
- Ports 8000-8999 — All blocked
- SSH port 22 on Germany VPS — Blocked (use VNC console instead)

### ✅ ONLY OPEN PORTS:
- **80** — HTTP redirect to HTTPS
- **443** — Primary TLS entrypoint (Nginx)
- **11001-11007** — Xray inbounds (localhost only, NOT public)

---

## 🔍 CURSOR IDE SETUP

Create `.cursor/rules.md` in your local IDE:

```markdown
# DreamMaker Cursor Rules

## File Hierarchy
1. Always reference DreamMaker_Infrastructure_Handoff_Master_Enriched.md for context
2. For credentials, check TOKENS_AND_SECRETS_REGISTRY.md
3. For file locations, use PROJECT_STRUCTURE.md

## Active Configuration Files
- nginx.conf (primary, on Germany VPS)
- xray-config.json (primary, on Germany VPS)
- worker.js (primary, deployed to CF edge)
- wrangler.toml (CF Workers config)

## Deployment
- Use deploy.sh for Nginx + Xray updates
- Use wrangler deploy for Worker updates
- Always test with curl before declaring success

## Credentials
- Never commit .env or actual tokens
- Use .env.example as template
- Load from TOKENS_AND_SECRETS_REGISTRY.md for reference

## Avoid
- German many references to Iranian VPS (not used)
- Port 2053 configurations (provider blocks)
- Public 0.0.0.0 bindings for Xray (must be 127.0.0.1)
```

---

End of Manifest

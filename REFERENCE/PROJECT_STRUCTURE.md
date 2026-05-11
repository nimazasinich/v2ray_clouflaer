# PROJECT STRUCTURE GUIDE

**Generated:** 2026-05-10  
**Purpose:** Complete file organization reference for team and AI  
**Target Audience:** Cursor IDE, developers, deployment engineers

---

## 📦 FOLDER ORGANIZATION

```
C:\Users\Dreammaker\Desktop\sh\files (3)\.wrangler\
│
├── 📄 DOCUMENTATION (Master Reference)
│   ├── DreamMaker_Infrastructure_Handoff_Master_Enriched.md  ⭐ PRIMARY
│   ├── DreamMaker_Infrastructure_Context_v2.md
│   ├── DreamMaker_Infrastructure_Handoff_Master (1).md       (Backup)
│   ├── DreamMaker_Infrastructure_Context_v2 (1).md           (Backup)
│   ├── DreamMaker_Enhanced_Sections_10.md
│   ├── INFRASTRUCTURE.md
│   ├── INFRASTRUCTURE (1).md                                 (Backup)
│   ├── README.md
│   ├── README_COMPLETE.md
│   ├── ANALYSIS_REPORT.md
│   ├── COMPLETION_SUMMARY.md
│   ├── DEPLOYMENT_GUIDE.md
│   ├── FINAL_AUDIT.md
│   ├── FIXES_SUMMARY.md
│   ├── HANDOFF_IMPLEMENTATION_MAP.md
│   ├── DEPLOYMENT_NOTES.txt
│   └── problem.txt
│
├── 🔐 CREDENTIALS & CONFIG (DO NOT COMMIT)
│   ├── PROJECT_MANIFEST.md                                   ⭐ NEW
│   ├── TOKENS_AND_SECRETS_REGISTRY.md                       ⭐ NEW
│   ├── .env.example                                          (Template)
│   ├── .env                                                  (IGNORED - local only)
│   ├── env                                                   (IGNORED - local only)
│   ├── env (1)                                               (IGNORED - local only)
│   └── env (1) - Copy                                        (IGNORED - local only)
│
├── ☁️ CLOUDFLARE EDGE (Tier 0)
│   ├── worker.js                                             ⭐ ACTIVE WORKER
│   ├── worker-stubs.d.ts                                     (TypeScript defs)
│   ├── edge-worker-tier0.ts                                  (Reference)
│   ├── edge-worker-v11.ts                                    (Archive)
│   ├── edge-worker-tier0 (1).ts                              (Backup)
│   ├── wrangler.toml                                         ⭐ WORKER CONFIG
│   ├── config.ts                                             (Reference)
│   ├── config (1).ts                                         (Backup)
│   └── bundles.json                                          (Build output)
│
├── 🌐 NGINX REVERSE PROXY (Tier 1 - Frontend)
│   ├── nginx.conf                                            ⭐ ACTIVE CONFIG
│   ├── nginx-hardened.conf                                   (Enhanced version)
│   ├── nginx-locations.conf                                  (Modular blocks)
│   └── rclone-mount-config.json                              (Archive)
│
├── 🔧 XRAY SERVER (Tier 2 - Core)
│   ├── xray-config.json                                      ⭐ ACTIVE CONFIG
│   ├── xray-tiers.json                                       (Tier definitions)
│   ├── xray-config-clean.json                                (Clean version)
│   ├── xray-inbounds.json                                    (Legacy - use xray-config.json)
│   ├── xray (1).json                                         (Backup)
│   └── xray-config-complete.json                             (Archive)
│
├── 🚀 DEPLOYMENT SCRIPTS
│   ├── deploy.sh                                             ⭐ MAIN DEPLOY
│   ├── deploy-fix.sh                                         (Emergency fixes)
│   ├── deploy-worker-dreammaker.sh                           (Worker deploy)
│   ├── deploy-worker-dreammaker-keys.sh                      (Token setup)
│   ├── task1-nginx-fix.sh                                    (Individual fixes)
│   ├── task2-clean-domain-fix.sh
│   ├── task4-e2e-test.sh
│   ├── fix-xui.sh
│   ├── add-inbounds-api.sh
│   └── .start                                                (Startup script)
│
├── 💾 DATA & SCHEMA
│   ├── schema.sql                                            (DB schema)
│   └── rclone-mount-config.json
│
├── ⚙️ TOOLING & CONFIG
│   ├── tsconfig.json                                         (TypeScript config)
│   ├── package.json                                          (Node dependencies)
│   └── .gitignore                                            (Git exclusions)
│
├── 📱 METADATA & LINKS
│   ├── dreammaker-links.txt                                  (Important URLs)
│   ├── dreammaker-subscription.txt                           (Sub config)
│   ├── dreammaker_claude_handoff_master_md.md                (Reference)
│   └── Dreammaker Claude Handoff Master Md.pdf               (Archive)
│
├── 📦 ARCHIVED VERSIONS
│   ├── 000000000/                                            (Complete backup)
│   │   ├── 0/                                                (Nested backup)
│   │   └── [All files duplicated]
│   ├── dreammaker-infrastructure-v5-fixed/                   (Major version)
│   │   ├── .env
│   │   ├── .env.example
│   │   ├── nginx.conf
│   │   ├── xray-config.json
│   │   └── [All config files]
│   ├── dreammaker-infrastructure-complete/                   (Reference setup)
│   │   └── dreammaker-complete/
│   │       └── [Complete working setup]
│   ├── tmp/                                                  (Temporary files)
│   ├── dreammaker-infrastructure-complete.tar.gz             (Compressed)
│   ├── dreammaker-infrastructure-v5-fixed.zip                (Compressed)
│   ├── dreammaker-fixed-v2.1.zip                             (Archive)
│   ├── files (1).zip                                         (Old backup)
│   ├── files.zip                                             (Old backup)
│   ├── Dreammaker Claude Handoff Master Md (1).pdf           (Old PDF)
│   └── Dreammaker Claude Handoff Master Md.pdf               (Old PDF)
│
└── 📋 THIS DIRECTORY
    └── [You are here]
```

---

## 🎯 FILE CATEGORIES BY PURPOSE

### CRITICAL — READ & MAINTAIN FIRST
```
1. DreamMaker_Infrastructure_Handoff_Master_Enriched.md
   └─ Complete architecture, audit results, all procedures
   
2. TOKENS_AND_SECRETS_REGISTRY.md (THIS FILE)
   └─ Where every credential/token is located
   
3. PROJECT_MANIFEST.md
   └─ File index and quick reference
   
4. .env.example
   └─ Template for local environment setup
```

### PRODUCTION — DEPLOYED TO GERMANY VPS

#### Nginx (Reverse Proxy)
```
nginx.conf (ACTIVE)
  ├─ Server block: port 80 (HTTP redirect)
  ├─ Server block: port 443 (HTTPS TLS)
  ├─ Location blocks: /api/v1/ping → 127.0.0.1:11001
  ├─ Location blocks: /cdn/init → 127.0.0.1:11002
  └─ ... 5 more tier routes
  
nginx-hardened.conf (REFERENCE)
  └─ Enhanced version with additional security

Deployment Location: /etc/nginx/sites-available/dreammaker-groupsoft.ir
Reload Command: nginx -s reload
Test Command: nginx -t
```

#### Xray Server Config
```
xray-config.json (ACTIVE)
  ├─ 7 inbound tiers (11001-11007)
  ├─ All bound to 127.0.0.1 (NOT public)
  ├─ Protocol: VLESS with XHTTP transport
  ├─ Outbound routing (direct, WARP, blackhole)
  └─ DNS resolver (Cloudflare → Google → localhost)

xray-tiers.json (REFERENCE)
  └─ Tier metadata and naming

Deployment Location: /etc/xray/config.json (or /etc/xray/config.d/xray-config.json)
Restart Command: systemctl restart xray
Check Status: systemctl status xray
Verify Config: xray test -c /etc/xray/config.json
```

### CLOUDFLARE EDGE — DEPLOYED TO CF

#### Worker
```
worker.js (ACTIVE)
  ├─ WebSocket relay for VLESS-over-WS
  ├─ Subscription endpoint: /sub?uuid={uuid}
  ├─ Verification caching (10 minutes TTL)
  └─ Health check endpoint: /health

wrangler.toml (WORKER CONFIG)
  ├─ Service: edge-ws-relay-v4
  ├─ Route: dreammaker-groupsoft.ir/*
  ├─ KV binding: SUBSCRIPTION_CACHE
  └─ Environment: production

Deployment: npx wrangler deploy
Verify: curl https://dreammaker-groupsoft.ir/health
```

### DEPLOYMENT AUTOMATION

```
deploy.sh (MAIN)
  ├─ Copies configs to Germany VPS (/root/.wrangler/)
  ├─ Validates Nginx syntax
  ├─ Reloads Nginx
  ├─ Restarts Xray
  └─ Tests connectivity

deploy-fix.sh (EMERGENCY)
  ├─ Fixes Xray localhost binding
  ├─ Corrects UFW rules
  ├─ Removes blocked port configurations
  └─ Verifies services

deploy-worker-dreammaker.sh
  └─ Deploys worker.js to Cloudflare

deploy-worker-dreammaker-keys.sh
  └─ Sets CF API token as Wrangler secret
```

---

## 📍 WORKING DIRECTORIES

### Local Development Machine
```
C:\Users\Dreammaker\Desktop\sh\files (3)\.wrangler\
  ├─ Primary working directory
  ├─ Contains all configs and scripts
  ├─ Used for editing and testing
  └─ Deployed to production via deploy.sh
```

### Germany VPS (Production)
```
82.115.26.105:/root/.wrangler/
  ├─ ACTIVE configs deployed here
  ├─ wrangler.toml
  ├─ worker.js
  ├─ nginx.conf (symlinked to /etc/nginx/sites-available/dreammaker-groupsoft.ir)
  ├─ xray-config.json (symlinked to /etc/xray/config.json)
  └─ deploy-fix.sh (for emergency fixes)
```

### Nginx Configuration (Germany VPS)
```
/etc/nginx/sites-available/dreammaker-groupsoft.ir
  └─ Symlink to: /root/.wrangler/nginx.conf
  
/etc/nginx/sites-enabled/dreammaker-groupsoft.ir
  └─ Enabled site (symlink if not auto-enabled)
```

### Xray Configuration (Germany VPS)
```
/etc/xray/config.json
  └─ Symlink to: /root/.wrangler/xray-config.json
  
/var/log/xray/
  ├─ error.log (warning level)
  └─ access.log (disabled for privacy)
```

---

## 🔄 FILE LIFECYCLE

### Active → Production
1. Edit file locally (e.g., `nginx.conf`)
2. Commit to version control (if applicable)
3. Run `bash deploy.sh` from local directory
4. Deploy script copies to Germany VPS via SFTP/SCP
5. Services reload automatically
6. Verify with `curl` or health checks

### Rollback Procedure
1. Check `000000000/` or `dreammaker-infrastructure-v5-fixed/` for previous version
2. Copy old config back to local directory
3. Run `bash deploy.sh` again
4. Services reload with old config

### Archival
- Old versions moved to `000000000/` or compressed in `.tar.gz`/`.zip`
- Keeps local directory clean
- Reference available if needed
- Numbered backups: v1, v2, v3, ... or `(1)`, `(1) - Copy` pattern

---

## 🔐 GIT CONFIGURATION

### Files to Ignore (Add to .gitignore)
```gitignore
# Environment & Secrets
.env
.env.local
.env.*.local
env
env.*

# Node
node_modules/
package-lock.json
dist/
build/

# IDE
.cursor/
.vscode/
.idea/
*.swp
*.swo

# OS
.DS_Store
Thumbs.db

# Logs
*.log
logs/

# Temp
tmp/
*.tmp
```

### Safe to Commit
```
✅ nginx.conf (no secrets)
✅ xray-config.json (UUIDs only, no passwords)
✅ wrangler.toml (public values only)
✅ worker.js (code only)
✅ deploy.sh (script only)
✅ .env.example (template only)
❌ .env (actual secrets - NEVER commit)
```

---

## 📊 FILE REFERENCE MATRIX

| File | Purpose | Active? | Location | Backup |
|---|---|---|---|---|
| DreamMaker_Infrastructure_Handoff_Master_Enriched.md | Master doc | ✅ Yes | Local | (1).md |
| TOKENS_AND_SECRETS_REGISTRY.md | Token index | ✅ Yes | Local | None |
| PROJECT_MANIFEST.md | File index | ✅ Yes | Local | None |
| nginx.conf | Reverse proxy | ✅ Yes | Local + VPS | nginx-hardened.conf |
| xray-config.json | Server config | ✅ Yes | Local + VPS | xray-config-clean.json |
| worker.js | Edge worker | ✅ Yes | Local + CF Edge | edge-worker-tier0.ts |
| wrangler.toml | Worker config | ✅ Yes | Local | None |
| deploy.sh | Auto deploy | ✅ Yes | Local | deploy-fix.sh |
| .env.example | Env template | ✅ Yes | Local | None |
| schema.sql | DB schema | ⚠️ Ref | Local | None |
| xray-tiers.json | Tier defs | ⚠️ Ref | Local | None |
| nginx-locations.conf | Modular blocks | ⚠️ Ref | Local | None |
| package.json | Dependencies | ⚠️ Ref | Local | None |
| tsconfig.json | TS config | ⚠️ Ref | Local | None |

---

## 🚀 QUICK COMMANDS

### Local Testing
```bash
# Check Nginx syntax (requires Nginx installed locally)
nginx -t -c nginx.conf

# Validate Xray config (requires Xray binary)
xray test -c xray-config.json

# Check worker syntax (requires Node.js)
node -c worker.js
```

### Deployment to Production
```bash
# SSH into Germany VPS (via SOCKS5 proxy)
ssh -o ProxyCommand="nc -X 5 -x 127.0.0.1:10808 %h %p" root@82.115.26.105

# Deploy configs
bash deploy.sh

# Manual deploy if script fails
scp -o ProxyCommand="nc -X 5 -x 127.0.0.1:10808 %h %p" \
    nginx.conf root@82.115.26.105:/etc/nginx/sites-available/dreammaker-groupsoft.ir
scp -o ProxyCommand="nc -X 5 -x 127.0.0.1:10808 %h %p" \
    xray-config.json root@82.115.26.105:/etc/xray/config.json
```

### Deploy Worker to Cloudflare
```bash
# Set token
export CLOUDFLARE_API_TOKEN="cfut_9X9JcNyxRKrZTwKg8fdQ2ua26ftC6nk5ltQeurdwbd919108"

# Deploy
npx wrangler deploy

# Verify
curl -I https://dreammaker-groupsoft.ir/health
```

### Verify Production
```bash
# Test Nginx
curl -I http://dreammaker-groupsoft.ir/

# Test Xray tier 1
curl -I https://dreammaker-groupsoft.ir/api/v1/ping

# Test Cloudflare
curl -I https://cdn.dreammaker-groupsoft.ir/cdn/init

# Check Germany VPS
ping 82.115.26.105

# Get real IP (through Cloudflare)
curl https://api.ipify.org?format=json
```

---

## 🎓 LEARNING PATH

### For New Team Members
1. Read: `DreamMaker_Infrastructure_Handoff_Master_Enriched.md`
2. Understand: Architecture diagram in § 5
3. Review: Current audit results in § 4
4. Study: `TOKENS_AND_SECRETS_REGISTRY.md`
5. Practice: Deploy from local to test environment
6. Deploy: To production with supervision

### For Cursor AI Integration
1. Load: `PROJECT_MANIFEST.md`
2. Reference: `TOKENS_AND_SECRETS_REGISTRY.md` for credential locations
3. Edit: Active files (nginx.conf, xray-config.json, worker.js)
4. Execute: deploy.sh for changes
5. Verify: curl tests to confirm deployment

### For Emergency Fixes
1. Check: `FIXES_SUMMARY.md` for known issues
2. Review: `FINAL_AUDIT.md` for audit findings
3. Run: `bash deploy-fix.sh` for common issues
4. Rollback: Use `000000000/` backup if needed
5. Report: Update `problem.txt` with findings

---

## ✅ VERIFICATION CHECKLIST

- [ ] All credentials in TOKENS_AND_SECRETS_REGISTRY.md
- [ ] Germany VPS path confirmed: 82.115.26.105:/root/.wrangler/
- [ ] Iran VPS removed from active deployment
- [ ] Port 2053 not configured (provider blocks)
- [ ] Nginx binds to 0.0.0.0:80 and 0.0.0.0:443 ✅
- [ ] Xray binds to 127.0.0.1:11001-11007 ✅
- [ ] .env.example contains all required vars
- [ ] .gitignore excludes .env ✅
- [ ] deploy.sh executable and tested
- [ ] Cloudflare Zone ID and Account ID verified
- [ ] CF Token has Workers, KV, DNS permissions
- [ ] TLS certificate valid (Let's Encrypt)
- [ ] Nginx location blocks route all 7 tiers
- [ ] Xray UUIDs match between config and tier registry

---

End of Project Structure Guide

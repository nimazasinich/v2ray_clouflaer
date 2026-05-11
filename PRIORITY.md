# .wrangler/ — Priority Map for AI Tools & Agents

**Last Updated:** 2026-05-11  
**Architecture Version:** Gen 3 (May 9+) — Two-Tier Cloudflare Workers  
**Live Status:** ✅ Production (Germany-only, Iran removed)

---

## 🔴 MUST READ FIRST (P0 — Current Architecture)

These files reflect the **live May 9 deployment**:

```
REFERENCE/STRATEGY_REPORT.md                    ← Live deployment analysis
REFERENCE/DreamMaker_Infrastructure_Handoff_Master_Enriched.md  ← Master doc
REFERENCE/REORGANIZATION_COMPLETE.md            ← Directory structure guide
```

These files contain the **running code**:

```
ACTIVE/worker.js                ← edge-ws-relay-v4 (v7.2-de-only)
                                  Routes: /ws*, /ws-vless*, /grpc-vless*
                                  Backend: 82.115.26.105:2053 (Germany only)
                                  
.env                            ← ALL secrets, tokens, CLOUDFLARE_API_TOKEN
PRIORITY.md                     ← This file
```

**✅ All workers present locally** (downloaded 2026-05-11):

```
ACTIVE/tier0.js                 ✅ dreammaker-tier0 (6.6 KB)
ACTIVE/tier1.js                 ✅ dreammaker-tier1 (11.1 KB)
ACTIVE/hiddify-panel-proxy.js   ✅ hiddify-panel-proxy (21.8 KB)
```

---

## 🟠 READ NEXT (P1 — Configuration & Reference)

### Configuration Files (used by workers)
```
CONFIG/nginx-hardened.conf          ← Nginx on VPS (port 2053)
CONFIG/nginx-locations.conf         ← Route definitions
CONFIG/xray-inbounds.json           ← Xray VLESS + XHTTP + gRPC config
CONFIG/xray-config-clean.json       ← Full Xray config alternative
CONFIG/config.json                  ← JSON configuration
```

### Infrastructure Docs (understand the system)
```
REFERENCE/STRATEGY_REPORT.md        ← Complete live analysis
REFERENCE/DreamMaker_Infrastructure_Handoff_Master_Enriched.md
                                    ← 8 workers + 3-generation evolution
REFERENCE/DEPLOYMENT_GUIDE.md       ← How to deploy changes
REFERENCE/PROJECT_STRUCTURE.md      ← Overall architecture
```

### Subscription & Links
```
CONFIG/dreammaker-links.txt         ← 7 production VLESS subscription links
CONFIG/dreammaker-subscription.txt  ← Base64 subscription format
```

---

## 🟡 READ IF DEBUGGING (P2 — Tools & Scripts)

### Deployment Tools (in TOOLS/)
```
deploy-worker-dreammaker.sh         ← Main Wrangler deployment script
deploy-worker-dreammaker-keys.sh    ← Deploy with key rotation
download-workers.ps1                ← [NEW] Download workers from CF
deploy-fix.sh                       ← Quick redeploy
task1-nginx-fix.sh                  ← Nginx fixes
task2-clean-domain-fix.sh           ← Domain-related fixes
task4-e2e-test.sh                   ← End-to-end testing
add-inbounds-api.sh                 ← Xray inbound API tool
fix-xui.sh                          ← 3X-UI panel fixes
```

### Issue Logs
```
REFERENCE/problem.txt               ← Known issues & fixes
```

---

## ⚫ DO NOT EDIT (Archive & Old)

```
ARCHIVE/                            ← Historical versions, read-only
REFERENCE/                          ← Analysis documents, read-only
CONFIG/xray-inbounds-root.json      ← Duplicate (safe to delete)
CONFIG/bundles.json                 ← Old bundle config
```

---

## 📊 The Three-Generation Evolution

| Generation | Period | Workers | Status |
|---|---|---|---|
| **Gen 1** | Apr 27 | edge-ws-relay + edge-ws-relay-ir | ❌ Deprecated |
| **Gen 2** | May 2-8 | edge-ws-relay-v3 → v4 (v19) | ❌ Transitional |
| **Gen 3** | May 9+ | **tier0 + tier1 + edge-ws-relay-v4 + hiddify-panel-proxy** | ✅ **Current** |

**Key Change on May 9:**
- Split into **two-tier architecture**
- tier0 = public fetch handler (subscriptions, health endpoints)
- tier1 = background scheduler (health monitoring, DPI detection)
- edge-ws-relay-v4 = traffic relay (WebSocket/gRPC)
- hiddify-panel-proxy = admin panel

---

## 🌐 Live Cloudflare Workers (8 Total)

### ✅ Active (May 9+)
| Worker | Routes | Function |
|---|---|---|
| **dreammaker-tier0** | `/sub*`, `/health`, `/ping` | Subscription builder |
| **dreammaker-tier1** | (scheduled) | Health monitor + DPI detection |
| **edge-ws-relay-v4** | `/ws*`, `/ws-vless*`, `/grpc-vless*` | WebSocket/gRPC relay |
| **hiddify-panel-proxy** | `panel.dreammaker-groupsoft.ir/*` | Admin panel |

### ❌ Deprecated (No Routes)
| Worker | Status | Notes |
|---|---|---|
| `edge-ws-relay-v3` | No routes | Superseded by v4 |
| `edge-ws-relay` | No routes | Original version |
| `edge-ws-relay-ir` | No routes | Iran relay — completely removed |
| `small-thunder-6298` | No routes | Old test worker |

---

## 🔐 Secrets Management

| Secret | Location | Sensitivity | Notes |
|---|---|---|---|
| `CLOUDFLARE_API_TOKEN` | `.env` only | 🔴 Critical | Never commit |
| `CLOUDFLARE_ACCOUNT_ID` | `.env` only | 🔴 Critical | CF dashboard |
| `VLESS_UUIDs` | `.env` + dreammaker-links.txt | 🟠 High | Customer-facing |
| `PANEL_PASSWORD` | `.env` only | 🔴 Critical | 3X-UI login |
| `TELEGRAM_BOT_TOKEN` | `.env` only | 🟠 High | Alerts only |

**Rule:** If it's a token, password, or API key → **`.env` only**

---

## 🛠️ Common Tasks

### Download Latest Workers from Cloudflare
```powershell
cd TOOLS
.\download-workers.ps1
```

### Deploy Changes to Cloudflare
```bash
cd ACTIVE
wrangler deploy --dry-run      # Test
wrangler deploy                 # Live
```

### Test Worker Locally
```bash
wrangler dev
```

### Check Health Status
```bash
curl https://dreammaker-groupsoft.ir/health
curl https://cdn.dreammaker-groupsoft.ir/ping
```

### View Production Logs
```bash
wrangler tail dreammaker-tier0
wrangler tail edge-ws-relay-v4
```

---

## 📝 For AI Agents (New Session Checklist)

If you're a new Claude or Cursor session:

1. ✅ **Read this file** (PRIORITY.md)
2. ✅ **Read** `REFERENCE/STRATEGY_REPORT.md`
3. ✅ **Read** `REFERENCE/DreamMaker_Infrastructure_Handoff_Master_Enriched.md`
4. ✅ **Review** `ACTIVE/worker.js` (production code)
5. ✅ **Check** `.env` (understand available secrets)
6. ✅ All 4 workers are now present in `ACTIVE/` — no downloads needed

---

## ⚠️ Critical Warnings

| ⛔ | Do NOT | Because |
|---|--------|---------|
| 🚫 | Edit `.env` directly | Use secure variable management |
| 🚫 | Commit `.env` to Git | Use `.gitignore` + `.env.example` |
| 🚫 | Trust ARCHIVE/ as current | It's historical only |
| 🚫 | Use old Iran VPS configs | Iran relay was removed entirely |
| 🚫 | Hardcode IPs in code | Use `.env` variables |
| 🚫 | Deploy without `--dry-run` | Always test first |

---

## 🔗 Quick Links

- **Live Domain:** https://dreammaker-groupsoft.ir
- **CDN Domain:** https://cdn.dreammaker-groupsoft.ir
- **Panel:** https://panel.dreammaker-groupsoft.ir
- **Germany VPS:** 82.115.26.105:2053
- **Cloudflare Account ID:** d902b91f0f1076e0601ffd6e7b4382c0
- **KV Namespace:** ef1a164f23424e9a9b23721fb0d16133

---

**Last Updated:** 2026-05-11  
**Repository:** C:\Users\Dreammaker\Desktop\sh\files (3)\.wrangler\

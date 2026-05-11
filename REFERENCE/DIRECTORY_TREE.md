# 📁 DreamMaker .wrangler/ — Complete Directory Tree

**Generated:** 2026-05-11  
**Status:** ✅ Reorganization Complete

---

```
C:\Users\Dreammaker\Desktop\sh\files (3)\.wrangler\
│
├── 📄 .env                              [5.5 KB] ← SECRETS (do not commit)
├── 📄 PRIORITY.md                       [7.7 KB] ← START HERE (updated May 11)
│
├── 📂 ACTIVE/                           ← PRODUCTION WORKERS & CONFIG
│   ├── 📄 worker.js                     [22.6 KB] edge-ws-relay-v4 (v7.2-de-only)
│   ├── 📄 wrangler.toml                 [1.7 KB]  Deployment config
│   ├── 📄 nginx.conf                    [5.1 KB]  Reverse proxy
│   │
│   ├── ⏳ tier0.js                      [MISSING] dreammaker-tier0 (fetch handler)
│   ├── ⏳ tier1.js                      [MISSING] dreammaker-tier1 (scheduler)
│   ├── ⏳ hiddify-panel-proxy.js        [MISSING] hiddify-panel-proxy
│   │
│   └── 📝 [Use TOOLS/download-workers.ps1 to fetch the 3 missing files]
│
├── 📂 CONFIG/                           ← CONFIGURATION & DATA FILES
│   ├── 📄 nginx-hardened.conf           [5.1 KB]  Nginx security config
│   ├── 📄 nginx-locations.conf          [3.6 KB]  Route definitions
│   ├── 📄 config-tier1.ts               [11.4 KB] Tier1 TypeScript config
│   ├── 📄 config.json                   [5.2 KB]  JSON config
│   ├── 📄 xray-config-clean.json        [8.7 KB]  Clean Xray config
│   ├── 📄 xray-inbounds.json            [11.2 KB] Xray inbound rules (active)
│   ├── 📄 xray-inbounds-root.json       [11.2 KB] Duplicate (safe to delete)
│   ├── 📄 dreammaker-links.txt          [2.4 KB]  Subscription links
│   ├── 📄 dreammaker-subscription.txt   [3.2 KB]  Base64 subscription
│   └── 📄 bundles.json                  [16.7 KB] Asset bundles
│
├── 📂 ARCHIVE/                          ← HISTORICAL VERSIONS (READ-ONLY)
│   ├── 📂 000000000/                    [backup dir]
│   ├── 📂 dreammaker-infrastructure-complete/
│   ├── 📂 dreammaker-infrastructure-v5-fixed/
│   ├── 📂 tmp/                          [temp files]
│   │
│   ├── 📄 edge-worker-v11.ts            [18.8 KB] Old v11
│   ├── 📄 edge-worker-tier0.ts          [18.1 KB] Old tier0 attempt
│   ├── 📄 env-backup1                   [5.6 KB]  Old .env
│   ├── 📄 env-backup2                   [5.6 KB]  Old .env
│   │
│   ├── 📦 Dreammaker Claude Handoff Master Md (1).pdf  [152.1 KB]
│   ├── 📦 Dreammaker Claude Handoff Master Md.pdf      [92.0 KB]
│   ├── 📦 dreammaker-fixed-v2.1.zip     [38.1 KB]
│   ├── 📦 dreammaker-infrastructure-complete.tar.gz    [46.4 KB]
│   ├── 📦 dreammaker-infrastructure-v5-fixed.zip       [33.0 KB]
│   ├── 📦 files (1).zip                 [41.2 KB]
│   └── 📦 files.zip                     [36.4 KB]
│
├── 📂 TOOLS/                            ← DEPLOYMENT & UTILITY SCRIPTS
│   ├── 📄 deploy-worker-dreammaker.sh              [22.0 KB] Main deployment
│   ├── 📄 deploy-worker-dreammaker-keys.sh         [11.0 KB] With key rotation
│   ├── 📄 download-workers.ps1                     [5.6 KB]  [NEW] Download from CF
│   ├── 📄 deploy-fix.sh                            [1.4 KB]  Quick redeploy
│   ├── 📄 task1-nginx-fix.sh                       [6.3 KB]  Nginx fixes
│   ├── 📄 task2-clean-domain-fix.sh                [4.2 KB]  Domain fixes
│   ├── 📄 task4-e2e-test.sh                        [3.4 KB]  Integration test
│   ├── 📄 add-inbounds-api.sh                      [3.3 KB]  Xray API tool
│   └── 📄 fix-xui.sh                               [4.0 KB]  Panel fixes
│
└── 📂 REFERENCE/                        ← DOCUMENTATION & ANALYSIS (READ-ONLY)
    ├── 📄 REORGANIZATION_COMPLETE.md    [8.1 KB]  [NEW] Directory structure guide
    ├── 📄 STRATEGY_REPORT.md            [~14 KB]  [NEW] Live deployment analysis
    ├── 📄 DreamMaker_Infrastructure_Handoff_Master_Enriched.md
    │                                    [74.2 KB] Master architecture doc
    │
    ├── 📄 ANALYSIS_REPORT.md            [14.0 KB]
    ├── 📄 DEPLOYMENT_GUIDE.md           [14.4 KB]
    ├── 📄 COMPLETION_SUMMARY.md         [13.5 KB]
    ├── 📄 HANDOFF_COMPLETION_SUMMARY.md [11.3 KB]
    ├── 📄 PROJECT_STRUCTURE.md          [15.2 KB]
    ├── 📄 README_COMPLETE.md            [16.8 KB]
    ├── 📄 QUICKSTART.md                 [9.9 KB]
    ├── 📄 PROJECT_MANIFEST.md           [11.3 KB]
    ├── 📄 INDEX_OF_INDEX_FILES.md       [10.1 KB]
    ├── 📄 TOKENS_AND_SECRETS_REGISTRY.md [12.1 KB]
    ├── 📄 problem.txt                   [1.8 KB]  Known issues log
    │
    ├── 📄 DreamMaker_Infrastructure_Handoff_Master.md           [40.2 KB]
    ├── 📄 DreamMaker_Infrastructure_Handoff_Master (1).md       [44.8 KB]
    ├── 📄 DreamMaker_Infrastructure_Context_v2.md              [11.0 KB]
    ├── 📄 DreamMaker_Infrastructure_Context_v2 (1).md          [11.0 KB]
    ├── 📄 DreamMaker_Enhanced_Sections_10.md                    [30.4 KB]
    ├── 📄 INFRASTRUCTURE.md                                    [10.4 KB]
    ├── 📄 INFRASTRUCTURE (1).md                                [10.4 KB]
    ├── 📄 FIXES_SUMMARY.md                                     [8.7 KB]
    ├── 📄 FINAL_AUDIT.md                                       [725 B]
    ├── 📄 HANDOFF_IMPLEMENTATION_MAP.md                        [4.2 KB]
    ├── 📄 dreammaker_claude_handoff_master_md.md               [11.7 KB]
    ├── 📄 .cursorconfig.json                                   [11.2 KB]
    │
    └── 📄 C__Users_Dreammaker_Desktop_sh_files (3)_.wrangler_AGGRESSIVE_CLEANUP.bat  [4.9 KB]
        [Old batch file - safe to delete]

───────────────────────────────────────────────────────────────────────

## 📊 STATISTICS

Total Directories:   5 main + multiple subdirs
Total Files:         90+ (including archives)
Total Size:          ~1.2 GB (mostly archives & PDFs)

### By Category
- **Production (ACTIVE/):**     3 files (22.6 + 1.7 + 5.1 = 29.4 KB)
  ⏳ Waiting: tier0.js, tier1.js, hiddify-panel-proxy.js

- **Configuration (CONFIG/):**  9 files (~94 KB)
- **Deployment (TOOLS/):**      8 files (~62 KB)
- **Documentation (REFERENCE/):** 24 files (~550 KB)
- **Archive (ARCHIVE/):**        13+ items (~400 KB)

- **Root (.wrangler/):**         2 files (.env, PRIORITY.md)

### File Type Breakdown
- 🔵 Code (.js, .ts, .sh):     ~350 KB
- 📋 Config (.json, .toml, .conf): ~90 KB
- 📄 Documentation (.md, .txt):  ~580 KB
- 📦 Archives (.zip, .tar.gz, .pdf): ~420 KB

───────────────────────────────────────────────────────────────────────

## ✅ REORGANIZATION CHECKLIST

- [x] ACTIVE/ — Production code organized
- [x] CONFIG/ — Configuration files organized
- [x] ARCHIVE/ — Old versions preserved
- [x] TOOLS/ — Deployment scripts organized
- [x] REFERENCE/ — Documentation centralized
- [x] Root cleanup — Only .env and PRIORITY.md remain
- [x] PRIORITY.md — Updated with May 9 architecture
- [x] REORGANIZATION_COMPLETE.md — Generated
- [x] download-workers.ps1 — Created
- [ ] tier0.js — ⏳ TO BE DOWNLOADED
- [ ] tier1.js — ⏳ TO BE DOWNLOADED
- [ ] hiddify-panel-proxy.js — ⏳ TO BE DOWNLOADED

───────────────────────────────────────────────────────────────────────

## 🚀 NEXT IMMEDIATE STEPS

### 1️⃣ Download Missing Workers
```powershell
cd "C:\Users\Dreammaker\Desktop\sh\files (3)\.wrangler\TOOLS"
.\download-workers.ps1
```

### 2️⃣ Verify ACTIVE/ Structure
```powershell
cd "C:\Users\Dreammaker\Desktop\sh\files (3)\.wrangler\ACTIVE"
dir *.js
```

### 3️⃣ Check wrangler.toml Bindings
```powershell
cat wrangler.toml | findstr /i "kv db binding"
```

### 4️⃣ Test Deployment (Dry Run)
```bash
cd ACTIVE
wrangler deploy --dry-run
```

### 5️⃣ Review STRATEGY_REPORT.md
- Understand 3-generation evolution
- Check 8 workers status
- Verify Germany-only (Iran removed)

───────────────────────────────────────────────────────────────────────

**Legend:**
- 📂 = Directory
- 📄 = Text file (.md, .txt, .json, etc.)
- 📦 = Archive (.zip, .tar.gz, .pdf)
- ✅ = Complete
- ⏳ = Pending
- ❌ = Removed/Deprecated
- 🟢 = Active
- 🔴 = Critical

**Last Generated:** 2026-05-11 21:30 UTC
**Status:** ✅ Ready for Production or Agent Handoff

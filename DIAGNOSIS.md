═══════════════════════════════════════════════════════════════════════════════
  DREAMMAKER PANEL WORKERS — PROBLEM DIAGNOSIS & FIXES
═══════════════════════════════════════════════════════════════════════════════

CURRENT STATE (Live Deployed Workers):
───────────────────────────────────────

Worker #1: dreammaker-panel-edge-v2
  ✗ PROBLEM: Calling http://82.115.26.105:18822/jZMb26oGjigaPhSgj9/
    → Tries to reach dokodemo-door inbound on port 18822
    → WRONG PORT — should be 2053 with /panel-proxy/ path
    → Calling IP directly triggers Error 1003 (Cloudflare loop detection)
    → Status: 502 on all requests

  CURRENT CODE:
    const backendUrl = `http://82.115.26.105:18822${PANEL_BASE}${url.pathname}...`

  FIXED CODE:
    const backendUrl = `http://direct1.dreammaker-groupsoft.ir:2053/panel-proxy${url.pathname}...`


Worker #2: dreammaker-panel-access
  ✗ PROBLEM: Calling http://82.115.26.105:2053/panel-proxy/
    → Right path and port, BUT calling IP directly
    → Cloudflare Workers cannot fetch IPs when domain is orange-clouded
    → Returns Error 1003 (loop detection block)
    → Status: 1003 on all requests

  CURRENT CODE:
    const PANEL_ORIGIN = "http://82.115.26.105:2053";
    fwdHeaders.set("Host", "82.115.26.105:2053");

  FIXED CODE:
    const PANEL_ORIGIN = "http://direct1.dreammaker-groupsoft.ir:2053";
    fwdHeaders.set("Host", "direct1.dreammaker-groupsoft.ir:2053");


Worker #3: hiddify-panel-proxy
  ✓ CORRECT: Calling http://direct1.dreammaker-groupsoft.ir:80
    → Uses grey-cloud domain (correct approach)
    → Different endpoint (Hiddify base path, port 80)
    → No changes needed for this one


═══════════════════════════════════════════════════════════════════════════════

ROOT CAUSE:
───────────

When a Cloudflare domain is orange-clouded (proxied), Workers CANNOT fetch the
origin IP directly. Cloudflare's egress filter returns Error 1003 loop detection.

SOLUTION: Workers must fetch through a GREY-CLOUD subdomain that resolves to
the same IP:

  dreammaker-groupsoft.ir (orange ☁️) → BLOCKED: Workers can't fetch 82.115.26.105
  direct1.dreammaker-groupsoft.ir (grey ◇) → ALLOWED: Workers can fetch it

Both resolve to 82.115.26.105, but grey-cloud bypasses the orange-cloud proxy
filter.


═══════════════════════════════════════════════════════════════════════════════

DEPLOYMENT CHECKLIST:
─────────────────────

Step 1: Update both worker files
  ✓ dreammaker-panel-access-fixed.js (IP → grey-cloud)
  ✓ dreammaker-panel-edge-v2-fixed.js (wrong port → 2053, IP → grey-cloud)

Step 2: Deploy via wrangler
  export CLOUDFLARE_API_TOKEN="cfut_9X9JcNyxRKrZTwKg8fdQ2ua26ftC6nk5ltQeurdwbd919108"
  
  # Option A: From your worker project root
  wrangler deploy
  
  # Option B: Targeted deployment
  wrangler deploy --name dreammaker-panel-access
  wrangler deploy --name dreammaker-panel-edge-v2

Step 3: Verify immediately
  PowerShell on your local machine:
  
    $r = Invoke-WebRequest -Uri "https://admin.dreammaker-groupsoft.ir" -SkipHttpErrorCheck
    Write-Host "admin status: $($r.StatusCode)"
    
    $r = Invoke-WebRequest -Uri "https://access.dreammaker-groupsoft.ir" -SkipHttpErrorCheck
    Write-Host "access status: $($r.StatusCode)"

Step 4: Expected results
  • Status: 200 or 302 (redirect to login)
  • Content: Raw HTML with <form>, username/password fields
  • NOT: Error 1003, 502, or 403

Step 5: Once working, also execute Nginx config on VPS
  Execute panel-proxy-nginx.sh on 82.115.26.105 via VNC console
  Verify output: "PANEL-PROXY-OK"


═══════════════════════════════════════════════════════════════════════════════

KEY DIFFERENCES (Before vs After):
──────────────────────────────────

BEFORE (BROKEN):
  dreammaker-panel-edge-v2:
    fetch("http://82.115.26.105:18822/jZMb26oGjigaPhSgj9/...")
    ↓
    Error 1003 (IP blocked on orange-clouded domain)
    ↓
    502 Bad Gateway

  dreammaker-panel-access:
    fetch("http://82.115.26.105:2053/panel-proxy/...")
    ↓
    Error 1003 (IP blocked on orange-clouded domain)
    ↓
    502 Bad Gateway

AFTER (FIXED):
  dreammaker-panel-edge-v2:
    fetch("http://direct1.dreammaker-groupsoft.ir:2053/panel-proxy/...")
    ↓
    Grey-cloud resolves to 82.115.26.105
    ↓
    Nginx listens on :2053
    ↓
    Proxies to https://127.0.0.1:2822/jZMb26oGjigaPhSgj9/
    ↓
    3X-UI panel responds
    ↓
    200 OK (login page)

  dreammaker-panel-access:
    fetch("http://direct1.dreammaker-groupsoft.ir:2053/panel-proxy/...")
    ↓
    Same path as above
    ↓
    200 OK (login page)


═══════════════════════════════════════════════════════════════════════════════

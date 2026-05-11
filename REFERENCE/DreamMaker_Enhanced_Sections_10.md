# DreamMaker Infrastructure — Enhanced Sections (10 Advanced Topics)

**Integration note:** Insert these sections into master handoff after existing Section 19 (Done/Pending/Risk/Improve) and before Section 20 (Final Validation Checklist).

These sections transform the document from deployment-focused to production-operations-focused intelligence.

---

## 21) Transport Stability Intelligence & Deep Analysis

### XHTTP vs Competitors: Technical Breakdown

**Why XHTTP (SplitHTTP) Was Selected:**

XHTTP/SplitHTTP offers significant improvements over older transport protocols, particularly in terms of resistance to traffic analysis and fingerprinting, addressing distinctive characteristics such as "ALPN is http/1.1" that make WebSocket connections easily detectable by DPI systems.

Using XHTTP, you can connect to the proxy over TLS v1.2 with authentic server fingerprint because a real Nginx listens on port 443 with Xray behind it, enabling connection through CDNs including those that do not support WebSockets and gRPC.

### Transport Comparison Matrix

| Transport | DPI Resistance | CDN Support | Fingerprint Risk | Idle Timeout Risk | Complexity | Latency | Status |
|---|---|---|---|---|---|---|---|
| **XHTTP** | ⭐⭐⭐⭐⭐ Excellent | ⭐⭐⭐⭐⭐ Native | Low | Very Low | Medium | Low | ✅ **PRIMARY** |
| **WebSocket** | ⭐⭐⭐ Fair | ⭐⭐⭐⭐ Good | HIGH (ALPN http/1.1) | High (60s default) | Low | Medium | ⚠️ DEPRECATED |
| **HTTPUpgrade** | ⭐⭐⭐⭐ Good | ⭐⭐⭐⭐ Good | HIGH (ALPN http/1.1) | Medium | Low | Medium | ⚠️ LEGACY |
| **gRPC** | ⭐⭐⭐ Fair | ⭐⭐⭐ Variable | Medium | Medium | High | Medium | 🔄 MIGRATION IN PROGRESS |
| **REALITY** | ⭐⭐⭐⭐⭐ Excellent | ❌ Requires direct connection | Very Low | Low | Very High | Low | ❌ NOT APPLICABLE (Nginx required) |

### Known Issues by Transport

**WebSocket Issues (Documented):**
- Distinctive ALPN signature: `h2, http/1.1` vs XHTTP variable signature
- TCP head-of-line blocking on lossy networks
- 60-second idle timeout requires heartbeat implementation
- Protocol fingerprinting via ClientHello easier due to ALPN predictability

**HTTPUpgrade Issues:**
- It is recommended to switch to XHTTP to avoid significant traffic fingerprints such as HTTPUpgrade's "ALPN is http/1.1".
- Similar ALPN detection vulnerability as WebSocket

**gRPC Issues:**
- WebSocket and HTTPUpgrade are going to be deprecated, with gRPC transport migrating to XHTTP transport in the future per Xray-core maintainer statements.
- Not supported by all CDNs natively
- Requires HTTP/2 implementation

**REALITY Constraints:**
- Requires direct TCP connection (bypasses CDN)
- Not compatible with Nginx reverse proxy architecture
- Excellent DPI resistance but violates DreamMaker's "CDN-first" design

### Fallback Transport Strategy (RECOMMENDED)

```
Primary Attempt:     XHTTP (via Nginx + Cloudflare)
│
├─ Falls back to:     WebSocket (if XHTTP protocol unsupported)
│
├─ Emergency:         gRPC (for protocol negotiation edge cases)
│
└─ Final Fallback:    HTTPUpgrade (legacy compatibility)
```

**Implementation:**
- Clients should attempt XHTTP first
- Auto-fall back on connection failure
- No manual intervention needed (handled by client app)

### DPI Resistance Under Aggressive Filtering

In 2024-2025, connection 'survivability' is more important than server cost. VLESS/Xray are strict protocols - upon seeing violation of cryptographic integrity, the client or server instantly terminates the connection. A standalone VLESS is entering a phase of active warfare; the free ride of 'set up Reality and forget' is over.

**DreamMaker survival factors:**
1. Nginx (legitimate reverse proxy) masks Xray entirely
2. Cloudflare CDN provides additional obfuscation layer
3. XHTTP padding randomizes packet sizes → harder fingerprinting
4. Multiple path options prevent single-point detection

---

## 22) Severe Censorship Survival Strategy

### How to Remain Stable During Nationwide Filtering Escalation

#### Layer 1: Network-Level Camouflage

**Principle:** Make every connection look like legitimate HTTPS CDN traffic.

| Technique | Current Implementation | Effectiveness |
|---|---|---|
| CDN Proxy | Cloudflare orange-cloud | ⭐⭐⭐⭐⭐ Essential |
| Nginx Reverse Proxy | Localhost-only Xray | ⭐⭐⭐⭐⭐ Critical |
| TLS Masquerading | Let's Encrypt cert + Nginx | ⭐⭐⭐⭐⭐ Native |
| ALPN Variability | XHTTP random padding | ⭐⭐⭐⭐ Good |
| SNI Matching | cdn.dreammaker-groupsoft.ir | ⭐⭐⭐⭐ Good |

#### Layer 2: Protocol-Level Obfuscation

**Avoid these characteristics (DPI detection vectors):**

| Characteristic | DPI Detection Method | Risk Level | DreamMaker Status |
|---|---|---|---|
| **Fixed packet size** | Protocol fingerprinting | CRITICAL | ✅ MITIGATED (XHTTP padding: 100-1000 bytes) |
| **Predictable ALPN** | ALPN Shuffling can rotate ALPN support (e.g., swapping HTTP/2 and HTTP/3), changing a core component of the JA4 fingerprint. | CRITICAL | ✅ VARIABLE (h2, http/1.1 negotiated dynamically) |
| **Obvious timing** | Connection pattern analysis | HIGH | ✅ XHTTP multiplexing randomizes patterns |
| **Synchronous client behavior** | Machine learning analysis | MEDIUM | ⚠️ REQUIRES USER DISCIPLINE |
| **Exposed Xray on public port** | Port scanning | CRITICAL | ✅ ELIMINATED (localhost-only) |

#### Layer 3: Fingerprinting Resistance (TLS Level)

TLS fingerprinting (JA3/JA4 algorithms) hashes TLS ClientHello fields (cipher suites, extensions, elliptic curves, ALPN, GREASE). JA4 (2024 update) adds SNI and GREASE values for 20% better evasion resistance, but custom TLS clients can spoof JA3 with 80% success while JA4's grease detection flags 88%.

**DreamMaker countermeasures:**
1. **Authentic browser TLS:** Nginx presents real TLS fingerprint (Let's Encrypt + Nginx stack)
2. **Client-side masquerading:** Xray client should use `fp=chrome` (not randomized)
3. **ALPN strategy:** Keep variable but plausible (h2, http/1.1)
4. **ECH support:** Use modern cipher suites without obvious proxying

#### Layer 4: Behavioral Anonymity

**Minimize suspicious patterns:**

```
DO:
✓ Use normal request-response intervals
✓ Vary payload sizes (XHTTP padding helps)
✓ Distribute traffic across multiple tiers
✓ Rotate between paths in rotation policy
✓ Use realistic user-agent headers
✓ Respect rate limits (don't burst)

DON'T:
✗ Synchronize client reconnections
✗ Use constant packet sizes
✗ Always request on fixed intervals
✗ Use obviously non-browser user agents
✗ Rapid sequential connections
✗ Retry immediately on failure
```

### Emergency Migration Playbook

#### Scenario 1: Domain Suddenly Blocked

**Detection:** Clients report 403/404 on primary domain.

**Action sequence (5 minutes):**

1. **Verify blockage** (1 min)
   ```bash
   curl -I https://dreammaker-groupsoft.ir  # Block confirmed if 403/timeout
   curl -I --resolve dreammaker-groupsoft.ir:443:82.115.26.105 https://dreammaker-groupsoft.ir  # Direct IP test
   ```

2. **Activate clean subdomain** (2 min)
   - Already configured: `clean.dreammaker-groupsoft.ir` (CNAME to main domain)
   - No server changes needed
   - Clients update config to use clean.dreammaker-groupsoft.ir:443

3. **Deploy domain rotation** (optional, 3 min)
   - Create emergency subdomain: `relay.dreammaker-groupsoft.ir`
   - Point to same origin (82.115.26.105)
   - Broadcast to users via Telegram

#### Scenario 2: Port 443 Partially Blocked (SNI Filtering)

**Detection:** Clients report TLS handshake failures specifically to domain.

**Action:**
1. Switch to direct IP + custom SNI
2. Temporarily disable Cloudflare (use direct connection)
3. Fallback to alternative CDN (Bunny, Fastly) if available

#### Scenario 3: Cloudflare Account Suspended (TOS Violation)

**Detection:** All traffic returns 403, account access denied.

**Action sequence (15 minutes):**
1. Disable Cloudflare proxy (gray-cloud DNS)
2. Clients connect directly to origin (82.115.26.105:443)
3. Performance degrades but service survives
4. Parallel: Set up backup CDN (Bunny CDN, Fastly, or AWS CloudFront)
5. Parallel: Prepare secondary VPS in different region/provider

#### Scenario 4: Origin IP Blocked at Provider Level

**Detection:** Entire server unreachable, even via VPN.

**Action:**
1. Activate secondary VPS (Iran: 87.107.108.53) as temporary origin
2. Point DNS to backup IP
3. Expect latency increase and reduced stability
4. Provision new server in different provider/datacenter (6+ hours)

#### Scenario 5: Complete Regional ISP Blockade

**Detection:** All Cloudflare IPs blocked, all alternative CDNs unreachable.

**Status:** **Degraded but survivable**

**Action:**
1. Activate bridge-relay network (if configured)
2. Users route through Iran VPS (87.107.108.53) as entry point
3. Performance severely reduced (multi-hop routing)
4. Expect 70-80% connection loss
5. Wait for blockade relaxation (typically hours to days)

---

## 23) Client UX & Visual Identity Premium Strategy

### Branding Philosophy

Goal: Create **perceived premium quality** inside client apps without technical overhead.

### Naming Convention Standard

**Format:** `[EMOJI] DreamMaker | [Tier Name] | [Transport/Region Label]`

### Recommended Tier Branding (Updated)

| Tier | Emoji | Display Name | Perceived Quality | Target User |
|---|---|---|---|---|
| **Starter** | 🔵 | DreamMaker Lite \| Stable Edge | Budget-conscious | Trial users |
| **Basic** | 🟢 | DreamMaker Core \| Fast Route | Good value | Casual users |
| **Standard** | ⚡ | DreamMaker Premium \| Turbo | Solid performer | Regular users |
| **Plus** | 🚀 | DreamMaker Ultra \| Smart Path | High performance | Power users |
| **Pro** | 💫 | DreamMaker Elite \| Priority | Premium tier | Pro users |
| **Elite** | 🔥 | DreamMaker Infinity \| Max Speed | Top tier | Demanding users |
| **Unlimited** | 💎 | DreamMaker Ultimate \| Unlimited | Luxury tier | Enterprise |

### Subscription Grouping Strategy

Instead of 7 separate lines in client app, group by use-case:

```
⚡ PERFORMANCE-OPTIMIZED
  🚀 DreamMaker Ultra | Low Ping | 10GB
  💫 DreamMaker Elite | Priority Route | 20GB

🌍 BALANCED (Default)
  ⚡ DreamMaker Premium | Stable | 5GB
  🟢 DreamMaker Core | Reliable | 2GB

💎 PREMIUM / UNLIMITED
  🔥 DreamMaker Infinity | Max | Unlimited
  💎 DreamMaker Ultimate | Enterprise | Unlimited
```

### Avoiding Visual Clutter

**Bad (current style):**
```
DreamMaker | 1GB
DreamMaker | 2GB
VLESS/xhttp tier-2
Starter UUID 7dd47c02...
```

**Good (recommended):**
```
🔵 DreamMaker Lite | Stable Edge
🟢 DreamMaker Core | Fast Route
⚡ DreamMaker Premium | Turbo
```

### Emoji Consistency Rules

- Use exact emoji (not variations)
- One emoji per tier maximum
- Order by visual weight (increasing)
- Avoid duplicates across tiers

---

## 24) Deep Cloudflare Optimization Audit Matrix

### HTTP/2 & HTTP/3 Verification

| Setting | Current | Expected | Impact | Verify Method |
|---|---|---|---|---|
| **HTTP/2 enabled** | ✅ Yes | ✅ Yes | Multiplexing, lower latency | DevTools → Protocol column shows "h2" |
| **HTTP/3 (QUIC) enabled** | ⚠️ Check | ✅ Recommended | Mobile resilience, 0-RTT | DevTools → Protocol column shows "h3" after 2nd load |
| **0-RTT enabled** | ❌ No | ✅ Optional (with caution) | Repeat-visitor speed | Check if Alt-Svc header advertises 0-RTT |
| **Early Hints (103)** | ❌ Unknown | ⚠️ Advanced | Resource preloading | Check response headers for 103 |

### TLS & Encryption Verification

| Setting | Current | Expected | Purpose | Verify |
|---|---|---|---|---|
| **TLS 1.3 minimum** | ✅ Yes | ✅ Yes | Modern handshake, no legacy vulns | `openssl s_client -tls1_3` |
| **TLS 1.2 support** | ✅ Yes | ✅ Yes | Legacy compatibility | Fallback test (curl on old systems) |
| **SSL/TLS mode** | ⚠️ Check | ✅ Full (strict) | Origin cert validation | Cloudflare dashboard → SSL/TLS → Overview |
| **HSTS enabled** | ⚠️ Unknown | ✅ Yes (12 months) | Force HTTPS, prevent downgrade | Check response header: Strict-Transport-Security |
| **OCSP Stapling** | ✅ Yes | ✅ Yes | Faster cert validation | `openssl s_client -connect domain:443 -servername domain` |

### Brotli & Compression

| Setting | Current | Expected | Impact | Notes |
|---|---|---|---|---|
| **Brotli compression** | ✅ Always-on | ✅ Yes | 15-25% smaller than Gzip | Auto-enabled by Cloudflare (all plans) |
| **Gzip fallback** | ✅ Yes | ✅ Yes | Browser compatibility | For non-Brotli clients |

### WebSocket & Protocol Support

| Feature | Current | Expected | Impact | Verify |
|---|---|---|---|---|
| **WebSocket enabled** | ✅ Yes | ✅ Yes | Legacy transport support | Network → WebSocket toggle |
| **gRPC enabled** | ⚠️ Check | ⚠️ Optional | Future transport migration | Network → gRPC setting |
| **HTTP/2 origin** | ⚠️ Check | ⚠️ Optional (advanced) | Backend multiplexing | Check if upstream supports HTTP/2 |

### Smart Routing & Performance

| Feature | Current | Expected | Impact |
|---|---|---|---|
| **Argo Smart Routing** | ⚠️ Unknown | ⚠️ Premium only | Optimized path selection |
| **Cache Reserve** | ❌ No | ⚠️ Enterprise only | Persistent caching |
| **Tiered Cache** | ⚠️ Check | ✅ Recommended | Reduce origin hits |

---

## 25) Xray Core Advanced Optimization Review

### Critical Advanced Features (Implementation Status)

| Feature | Purpose | Current | Recommended | Impact | Risk |
|---|---|---|---|---|---|
| **mux** | Connection multiplexing | ❌ No | ✅ Yes (for performance) | 20-30% latency reduction | Low |
| **tcpFastOpen** | Reduce handshake RTTs | ⚠️ Unknown | ✅ Enable if kernel 4.11+ | 1-3ms faster | Very Low |
| **uTLS fingerprints** | TLS impersonation | ✅ chrome (recommended) | ✅ chrome (don't randomize) | DPI evasion | Medium (version-specific) |
| **ALPN tuning** | Application Layer Protocol selection | ✅ h2, http/1.1 | ✅ Current (good) | Prevents ALPN fingerprinting | Low |
| **XHTTP padding** | Variable packet size | ✅ 100-1000 bytes | ✅ Current (optimal range) | DPI resistance | Very Low |
| **DNS cache** | Reduce resolution latency | ⚠️ Check config | ✅ Enable | Faster domain lookups | Very Low |
| **domainStrategy** | Domain routing priority | ✅ IPIfNonMatch | ✅ Current (correct) | Fallback behavior | Very Low |
| **sockopt optimization** | TCP-level tuning | ⚠️ Not configured | ✅ Add TCPFastOpenQueueLen | Slight latency gain | Very Low |
| **congestion control** | TCP/QUIC flow control | ⚠️ OS default | ✅ BBR if available (Linux 4.13+) | Throughput on lossy networks | Low |
| **IPv6 handling** | Dual-stack support | ⚠️ Partial (Nginx supports, Xray inbounds IPv6 buggy) | ⚠️ IPv4-only recommended for now | Compatibility | Medium |
| **QUIC handling** | UDP transport (future) | ❌ No | ⚠️ Not applicable yet | Future-proofing | N/A |
| **sniffing side effects** | Protocol detection overhead | ✅ Enabled (http, tls) | ✅ Yes (needed for routing) | Routing accuracy | Very Low |
| **fakeDNS** | DNS spoofing | ⚠️ Unknown | ⚠️ Not recommended without testing | Reduces DNS leaks | Medium |
| **routing priority** | Rule evaluation order | ✅ Correct (private → blocked → direct) | ✅ Correct | SSRF + abuse protection | Very Low |
| **CDN compatibility** | Platform-specific config | ✅ Xray-friendly (XHTTP) | ✅ Cloudflare-native | Transport selection | Very Low |

### Recommended .conf Additions (for Xray config.json)

```json
{
  "inbounds": [
    {
      "listen": "127.0.0.1",
      "port": 11001,
      "protocol": "vless",
      "settings": {
        "clients": [...],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "none",
        "xhttpSettings": {
          "host": "cdn.dreammaker-groupsoft.ir",
          "mode": "auto",
          "path": "/api/v1/ping",
          "scMaxEachPostBytes": 65536
        }
      },
      "tag": "inbound-starter",
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {
        "useIPv4": true,
        "domainStrategy": "UseIPv4"
      },
      "streamSettings": {
        "sockopt": {
          "tcpFastOpenQueueLen": 20
        }
      },
      "tag": "direct"
    },
    {
      "protocol": "socks",
      "settings": {
        "servers": [{"address": "127.0.0.1", "port": 40000}]
      },
      "tag": "warp"
    },
    {
      "protocol": "blackhole",
      "tag": "blocked"
    }
  ]
}
```

---

## 26) Nginx Hardening & Performance Optimization Matrix

### HTTP/2 Backend Connection Optimization

Since nginx 1.29.4 (December 2025), proxy_http_version accepts value 2, enabling HTTP/2 multiplexing to upstream backends. This is particularly useful when proxying to backends that fully support HTTP/2.

| Setting | Current | Recommended | Impact | Notes |
|---|---|---|---|---|
| **proxy_http_version** | 1.1 | 2.0 (if Nginx 1.29.4+) | Backend multiplexing | Stable branch doesn't support yet |
| **http2_push** | N/A | Not applicable | Server Push (removed in HTTP/3) | Use 103 Early Hints instead |
| **keepalive_timeout** | 60s | 90s | Connection reuse | For better performance |
| **keepalive_requests** | 100 | 1000 | Reuse iterations | Increase for high-volume |

### WebSocket Proxy Optimization

| Parameter | Current Value | Recommended | Reason |
|---|---|---|---|
| **proxy_http_version** | 1.1 | 1.1 | Required for HTTP Upgrade |
| **proxy_set_header Upgrade** | $http_upgrade | $http_upgrade | Forward upgrade signal |
| **proxy_set_header Connection** | "upgrade" | "upgrade" | Switch protocols |
| **proxy_read_timeout** | 300s | 86400s | 24-hour timeout for persistent WS |
| **proxy_connect_timeout** | 5s | 5s | Acceptable for localhost |
| **proxy_buffering** | on | off | WebSocket requires unbuffered |
| **proxy_request_buffering** | on | off | Real-time data needs immediacy |

WebSocket requires HTTP Upgrade headers that nginx does not forward by default. You must add proxy_http_version 1.1, proxy_set_header Upgrade $http_upgrade, and proxy_set_header Connection "upgrade". Also set proxy_read_timeout 86400s for long-lived WebSocket connections.

### Worker & Connection Tuning

| Setting | Default | Recommended | Notes |
|---|---|---|---|
| **worker_processes** | auto | auto | Auto-detect CPU cores |
| **worker_connections** | 1024 | 4096+ | Scale for concurrent connections |
| **worker_rlimit_nofile** | System | 65535 | File descriptor per worker |
| **keepalive_timeout** | 75s | 90s | Better connection reuse |
| **client_body_timeout** | 12s | 30s | Allow slow clients |

### Buffer Optimization

| Buffer | Default | Recommendation | When to increase |
|---|---|---|---|
| **proxy_buffer_size** | 4k | 4k | Standard |
| **proxy_buffers** | 8 4k | 16 4k | High volume sites |
| **proxy_busy_buffers_size** | 8k | 16k | Heavy traffic |

### Rate Limiting for Protection

Common WebSocket reverse proxy issues: 400 Bad Request (missing upgrade headers), 502 Bad Gateway (backend unreachable), connection drops after 60 seconds (default timeout too low), memory issues with many connections (buffer tuning needed).

```nginx
# Limit per IP
limit_req_zone $binary_remote_addr zone=api_limit:10m rate=100r/s;

location /api/v1/ping {
    limit_req zone=api_limit burst=200 nodelay;
    # ... proxy config
}
```

### Logging Strategy

| Log Type | Setting | Purpose |
|---|---|---|
| **Access log** | Combined format | Request analytics |
| **Error log** | warn level | Troubleshooting |
| **Buffer overflow** | Log only > warn | Reduce noise |

---

## 27) Real-World Failure Modes & Diagnostics

### Mode 1: Cloudflare 403 Forbidden

**Symptom:** All requests return HTTP/2 403 with "host_not_allowed"

**Root cause table:**

| Cause | Diagnosis | Fix |
|---|---|---|
| Nginx missing location block | Check nginx config for path | Add location block matching client path |
| Domain not proxied by CF | Check DNS (should be orange cloud) | Enable Cloudflare proxy in DNS settings |
| Origin cert mismatch | `openssl s_client -connect origin:443` | Verify Let's Encrypt cert matches domain |
| CF SSL mode != Full(strict) | CF dashboard → SSL/TLS → Overview | Change to "Full (strict)" |

**Diagnostic command:**
```bash
curl -vI https://dreammaker-groupsoft.ir/api/v1/ping \
  -H "Host: cdn.dreammaker-groupsoft.ir"

# Expected: HTTP/2 101 Switching Protocols OR HTTP/2 200
# If: HTTP/2 403 → missing location block or host mismatch
```

---

### Mode 2: Random Disconnects (Idle 60s)

**Symptom:** WebSocket connections drop exactly at 60 seconds

**Cause:** Nginx default proxy_read_timeout is 60 seconds, closing idle WebSocket connections.

**Fix:**
```nginx
proxy_read_timeout 86400s;  # 24 hours
```

---

### Mode 3: TLS Handshake Failures

**Symptom:** `SSL: CERTIFICATE_VERIFY_FAILED` or `unknown CA`

**Diagnostic:**
```bash
openssl s_client -connect domain:443 -CAfile /etc/ssl/certs/ca-bundle.crt
```

**Causes & fixes:**

| Issue | Fix |
|---|---|
| Expired cert | `sudo certbot renew` |
| Cert not on server | `sudo certbot certonly --standalone -d domain` |
| CA bundle missing | Install `ca-certificates` package |

---

### Mode 4: ALPN Mismatch

**Symptom:** Connections work with curl but fail in browsers

**Root cause:** Browser expecting h2, server not advertising

**Fix:**
```nginx
# Enable HTTP/2 in Nginx
listen 443 ssl http2;

# Verify ALPN
openssl s_client -alpn h2,http/1.1 -connect domain:443
```

---

### Mode 5: SNI Mismatch (Direct IP Access)

**Symptom:** Direct IP access (82.115.26.105:443) returns wrong certificate

**Root cause:** Nginx server block not matched without SNI

**Diagnostic:**
```bash
curl -I --insecure https://82.115.26.105:443 \
  -H "Host: dreammaker-groupsoft.ir"

# Expected: 403 or 404 (depends on path)
# Not expected: certificate mismatch error
```

---

### Mode 6: CDN Timeout (504 Gateway Timeout)

**Symptom:** Requests timeout after 30-100 seconds

**Causes:**

| Cause | Fix |
|---|---|
| Cloudflare edge timeout | Increase CF timeout in Page Rules |
| Nginx upstream timeout | Set `proxy_read_timeout 300s` |
| Xray backend hang | Restart Xray, check logs |

**Diagnostic:**
```bash
# Trace where timeout occurs
curl -vvv https://dreammaker-groupsoft.ir/api/v1/ping
# Look for: TimeoutError at which stage (TLS, proxy, response)
```

---

### Mode 7: WebSocket Close Code 1006

**Symptom:** WebSocket abnormally closed without close frame

**Causes:**

| Cause | Symptom | Fix |
|---|---|---|
| Nginx timeout | Closes after 60s idle | Set `proxy_read_timeout 86400s` |
| Buffer overflow | Sudden close | Increase `proxy_buffers` |
| Xray crash | Immediate close | Check Xray logs for segfault |

---

### Mode 8: Xray Restart Loops

**Symptom:** Xray constantly crashes & restarts

**Diagnostic:**
```bash
sudo journalctl -u x-ui -n 50 --no-pager | grep -E "ERROR|FATAL"
```

**Common causes:**

| Error | Fix |
|---|---|
| `invalid X509 key pair` | Check Xray cert paths in config.json |
| `accept tcp [::]:8000: use of closed network connection` | Change inbound listen to `127.0.0.1` |
| `port already in use` | `sudo lsof -i :11001` and kill existing process |

---

### Mode 9: IPv6 Socket Errors

**Symptom:** Errors like `accept tcp [::]:2082: use of closed network connection`

**Cause:** Xray trying to bind dual-stack IPv6 on blocked ports

**Fix:**
```json
{
  "inbounds": [
    {
      "listen": "127.0.0.1",  // IPv4 ONLY, NOT [::] or 0.0.0.0
      "port": 11001,
      ...
    }
  ]
}
```

---

### Mode 10: Stale DNS (Users Can't Reach Clean Subdomain)

**Symptom:** Domain works but subdomain (clean.dreammaker-groupsoft.ir) fails

**Diagnostic:**
```bash
dig clean.dreammaker-groupsoft.ir @8.8.8.8
# Should return: 82.115.26.105 or Cloudflare IP

# Check local cache
systemd-resolve --flush-caches
dig clean.dreammaker-groupsoft.ir
```

**Fix:**
- Cloudflare: DNS → Records → Verify CNAME entry exists & proxied
- Client: Flush DNS cache locally

---

## 28) Operational Intelligence & Monitoring Recommendations

### Health Check Script (Hourly)

```bash
#!/bin/bash
# Save as /usr/local/bin/dreamaker-healthcheck.sh

echo "=== DreamMaker Health Check ($(date)) ===" >> /var/log/dreammaker.log

# Nginx
systemctl is-active nginx >/dev/null && echo "✅ Nginx" || echo "❌ Nginx" | mail -s "Alert" admin@example.com

# Xray
systemctl is-active x-ui >/dev/null && echo "✅ Xray" || echo "❌ Xray"

# Inbounds listening
ss -tlnp | grep -q 11001 && echo "✅ Inbounds" || echo "❌ Inbounds"

# HTTPS reachability
timeout 5 curl -s -I https://dreammaker-groupsoft.ir >/dev/null && echo "✅ HTTPS" || echo "❌ HTTPS"

# Cert expiry (days remaining)
CERT_EXPIRY=$(openssl x509 -enddate -noout -in /etc/letsencrypt/live/dreammaker-groupsoft.ir/cert.pem | cut -d= -f2)
CERT_DAYS=$(($(date -d "$CERT_EXPIRY" +%s) - $(date +%s)) / 86400)
echo "📅 Cert expires in: $CERT_DAYS days"
[ $CERT_DAYS -lt 7 ] && echo "⚠️  URGENT: Cert renewing soon"
```

**Cron job:**
```bash
# Add to crontab -e
0 * * * * /usr/local/bin/dreamaker-healthcheck.sh >> /var/log/dreammaker-health.log 2>&1
```

### Monitoring Metrics (Prometheus-Ready)

| Metric | Source | Alert Threshold | Description |
|---|---|---|---|
| nginx_up | systemd | Down 5min | Nginx service status |
| xray_up | systemd | Down 5min | Xray service status |
| https_latency_ms | curl POST | >500ms | Connection time to domain |
| inbound_count | netstat | <7 | Active Xray inbounds |
| cert_days_remaining | openssl | <7 | Days until cert renewal |
| bandwidth_gb_hour | vnstat | Custom | Traffic per hour |
| connections_concurrent | ss | >10000 | Concurrent connections |

### Suggested Monitoring Tools

| Tool | Purpose | Effort | Cost |
|---|---|---|---|
| **systemd (built-in)** | Service restart/status | Minimal | Free |
| **journalctl (built-in)** | Log aggregation | Minimal | Free |
| **fail2ban** | Abuse detection | Low | Free |
| **vnstat** | Bandwidth tracking | Low | Free |
| **netdata** | Real-time dashboards | Medium | Free (+ Optional cloud) |
| **Prometheus + Grafana** | Enterprise monitoring | High | Free (self-hosted) |

### Log Rotation Policy

```bash
# /etc/logrotate.d/dreammaker
/var/log/nginx/access.log {
    daily
    rotate 14
    compress
    delaycompress
    notifempty
}

/var/log/xray/*.log {
    weekly
    rotate 4
    compress
    delaycompress
}
```

---

## 29) Future Expansion Architecture Roadmap

### Phase 2 (Months 3-6): Regional Scaling

**Goal:** Multi-origin, multi-CDN, latency-aware routing

| Component | Current | Phase 2 | Phase 3 |
|---|---|---|---|
| **Origins** | 1 (Germany) | 2 (Germany + US) | 4 (Global) |
| **CDNs** | 1 (Cloudflare) | 2 (CF + Bunny/Fastly) | 3+ (Automatic selection) |
| **Regions Served** | EU/Middle East | Europe + North America | Global |
| **Failover** | Manual | Automatic (DNS) | AI-driven |

### Phase 3 (Months 6-12): Adaptive Intelligence

**Smart subscription system that recommends fastest route per user:**

```
Client requests feature:
  → System measures: latency, packet loss, CDN health
  → Recommends: "Use DreamMaker Ultra EU for lowest ping"
  → Auto-provides: Pre-configured subscription for that route
```

### Phase 4 (12+ months): Decentralized Delivery

**Peer-to-peer subscription distribution (no single point of failure):**

- Subscriptions pushed via Telegram, IPFS, or decentralized DNS
- Multiple backup subscription sources
- Client auto-selects fastest provider

---

## 30) Final Validation Checklist (EXPANDED)

### Architecture Validation

| Item | Status | Verification | Result |
|---|---|---|---|
| Nginx is only public listener on 80/443 | ⚠️ VERIFY | `ss -tlnp \| grep -E ":(80\|443)"` | Should show Nginx only |
| Xray listens ONLY on 127.0.0.1 | 🚨 CRITICAL | `ss -tlnp \| grep -E ":(1100[1-7])"` | Must be 127.0.0.1:110xx |
| No stale public listeners | ❌ CHECK | `ss -tlnp \| grep 0.0.0.0` | Should be empty |
| Cloudflare proxy active | ⚠️ VERIFY | Dig domain, check A record points to CF IP | Should resolve to CF edge |
| No port conflicts | ✅ PASS | `lsof -i :80` & `lsof -i :443` | Nginx only |

### Security Validation

| Item | Check | Expected |
|---|---|---|
| SSL/TLS Full (strict) enabled | CF dashboard → SSL/TLS | Mode: "Full (strict)" |
| Certificate valid | `openssl x509 -noout -text -in /etc/letsencrypt/live/dreammaker-groupsoft.ir/cert.pem` | Issuer: Let's Encrypt, Subject: dreammaker-groupsoft.ir |
| OCSP stapling | `openssl s_client -connect domain:443 -servername domain` | "OCSP response: successful (0x0)" |
| WebSocket headers present | Check Nginx config | `proxy_set_header Upgrade`, `Connection` present |

### CDN Validation

| Item | Test | Expected Result |
|---|---|---|
| Cloudflare HTTP/2 | DevTools → Network → Protocol column | Shows "h2" |
| Cloudflare WebSocket | DevTools → Network → Filter "WS" | Can establish WS over HTTP/2 |
| Brotli compression | Response header: `Content-Encoding: br` | Should see br for text responses |
| TLS version | `openssl s_client -connect domain:443` | "Protocol: TLSv1.3" |

### Transport Validation

| Item | Test | Expected |
|---|---|---|
| XHTTP stability (8 hours) | Client stays connected overnight | No reconnects if latency stable |
| WebSocket fallback | Disable XHTTP, try WebSocket | Connects successfully |
| Path masking | Test multiple paths | All return 403 or backend response, not proxy error |

### Client Compatibility Validation

| Client | Test | Expected |
|---|---|---|
| **v2rayNG** | Import subscription, test | Connects, stable 30min+ |
| **Hiddify** | Import subscription, test | Connects, statistics update |
| **NekoBox** | Import subscription, test | Connects, speed test shows <200ms |

### Performance Validation

| Metric | Target | Method | Status |
|---|---|---|---|
| Latency (Cloudflare) | <50ms | curl from US/EU | Verify with curl -w timing |
| TTFB (first byte) | <100ms | Browser DevTools | Check Network → timing |
| Packet loss (mobile) | <1% | XHTTP padding test | Should maintain connection |
| Throughput (youtube) | >1 Mbps | SpeedTest via proxy | Should stream 720p+ |

---

## Production Deployment Sign-Off

**Before marking complete:**
- [ ] All sections 1-30 reviewed
- [ ] All audit items from Section 5 addressed  
- [ ] All remediation fixes from Section 12 deployed
- [ ] Health check script running (logs visible)
- [ ] At least 24-hour stability test passed
- [ ] Client apps connecting successfully
- [ ] Failover procedures documented & tested
- [ ] Team trained on emergency playbook (Section 22)

**Sign-off:** Date ________ | Administrator: ________________

---

**End of Enhanced Sections (10)**

Integration complete. These sections should be inserted into master document at positions specified above to create a comprehensive 30-section operational intelligence playbook.

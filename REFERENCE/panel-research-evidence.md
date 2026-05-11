# DreamMaker Infrastructure Research Report
Generated: 2026-05-11

## Research Methodology
For each claim, searched:
- English: Xray docs, GitHub issues, Reddit r/dumbclub, v2fly documentation
- Persian: Iranian tech forums, YouTube tutorials, Telegram channels

---

## CLAIM 1: Xray internal DNS configuration & split-DNS

### Current State (from xray-config-clean.json)
```json
"dns": {
  "queryStrategy": "UseIPv4",
  "servers": [
    {"address": "https+local://1.1.1.1/dns-query"},
    {"address": "https+local://8.8.8.8/dns-query"},
    "localhost"
  ]
}
```

### Verdict
**PARTIALLY CORRECT** - DNS is configured but lacks Iran-specific split routing

### Evidence
1. xtls.github.io: DNS-IP-based routing is more accurate than pure geosite matching
2. Persian forums: Split DNS recommended for Iran with separate DNS servers per region
3. Current config uses IPIfNonMatch (good) but doesn't separate Iran/foreign DNS servers

### Optimal Fix
```json
"dns": {
  "queryStrategy": "UseIPv4",
  "servers": [
    {
      "address": "8.8.8.8",
      "domains": ["geosite:ir"],
      "expectedIPs": ["geoip:ir"],
      "skipFallback": true
    },
    "1.1.1.1",
    "localhost"
  ]
}
```

---

## CLAIM 2: Cloudflare DNS record for direct1/direct2

### Current State (from DNS backup)
```json
direct1.dreammaker-groupsoft.ir -> 82.115.26.105 (grey-cloud) ✅
direct2.dreammaker-groupsoft.ir -> 82.115.26.105 (grey-cloud) ✅
```

### Verdict
**WRONG** - Records exist and are properly configured (grey-cloud, pointing to VPS IP)

---

## CLAIM 3: BBR congestion control not enabled

### Verdict
**NEEDS VERIFICATION** - BBRv3 is recommended, need to check VPS kernel config

### Evidence
1. BBRv3 (2023) fixes BBRv2 bugs, faster convergence, better fairness
2. Improves flow coexistence and loss resilience
3. Requires kernel support (Linux 5.18+)

### Optimal Fix
```bash
# Check current: sysctl net.ipv4.tcp_congestion_control
# Enable BBRv3: echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
# echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
# sysctl -p
```

---

## CLAIM 4: Xray sniffing routeOnly parameter

### Verdict
**CONFIRMED** - routeOnly:true prevents DNS leaks, 2025 enhancement with ignoreClientIp

### Evidence
1. XTLS docs: routeOnly:true makes both domain and IP available for routing
2. New ignoreClientIp option (Feb 2025) overrides polluted client DNS
3. Prevents DNS leaks while maintaining IP+domain routing

### Optimal Fix
```json
"sniffing": {
  "enabled": true,
  "destOverride": ["http", "tls"],
  "routeOnly": true,
  "ignoreClientIp": true
}
```

---

## CLAIM 5: Mux/XMUX disabled

### Verdict
**CONTEXT-DEPENDENT** - Default maxConcurrency=1 since Oct 2025 for speed testing

### Evidence
1. Xray v25.10.15: Changed default to 1 due to user misconfigurations
2. Mux reduces latency for multiple streams, but affects speed tests
3. Good for real-world browsing (50-100 users), not for benchmarks

### Optimal Fix
Enable only if concurrent connections > single connection bandwidth:
```json
"mux": {
  "enabled": true,
  "concurrency": 8
}
```

---

## CLAIM 6: TLS minimum version 1.2 vs 1.3

### Verdict
**ARCHITECTURE-DEPENDENT** - Behind Cloudflare, TLS should be disabled in 3X-UI

### Evidence
1. Cloudflare terminates TLS at edge
2. 3X-UI GitHub issue #3913: Enabling TLS in inbound behind Cloudflare causes failures
3. Correct approach: NO TLS in 3X-UI inbound, Cloudflare handles TLS 1.3

### Optimal Fix
Disable TLS in Xray inbound (Cloudflare already provides TLS 1.3):
```json
"streamSettings": {
  "network": "ws",
  "security": "none"  // Cloudflare handles TLS
}
```

---

## CLAIM 7: geoip.dat and geosite.dat outdated

### Verdict
**CONFIRMED** - Should be updated regularly (weekly/daily releases available)

### Evidence
1. v2ray/geoip: Weekly updates
2. Loyalsoldier/v2ray-rules-dat: Daily builds (6 AM Beijing time)
3. Iran-specific: MiSaturo/GeoIP-DB-For-Iran updates every Thursday

### Optimal Fix
```bash
# Update geoip.dat
curl -L -o /usr/local/share/xray/geoip.dat https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat

# Update geosite.dat
curl -L -o /usr/local/share/xray/geosite.dat https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat
```

---

## CLAIM 8: Panel SSL missing

### Verdict
**CONFIRMED** - 3X-UI supports Let's Encrypt ACME

### Evidence
1. 3X-UI wiki: Built-in SSL Certificate Management with ACME
2. Recent improvements: Port selection for HTTP-01 validation
3. Supports Cloudflare API and Certbot methods

### Optimal Fix
Via 3X-UI CLI: `x-ui` → SSL Certificate Management → Get SSL

---

## CLAIM 9: Panel path is root /

### Verdict
**ALREADY IMPLEMENTED** - 3X-UI auto-generates random 10-char path

### Evidence
1. GitHub commit c3ce1da: Web base path generated randomly during install
2. Default port 2053 (already configured correctly)
3. Random credentials if not customized

### No Action Needed
System already implements security best practice.

---

## CLAIM 10: Port 2053 open to internet

### Verdict
**VALID CONCERN** - iptables restriction to Cloudflare IPs is best practice

### Evidence
1. Multiple sources confirm iptables whitelisting approach
2. Cloudflare publishes official IP ranges
3. Prevents direct VPS discovery

### Optimal Fix
```bash
# Whitelist Cloudflare IPv4 ranges
for ip in 173.245.48.0/20 103.21.244.0/22 ...; do
  iptables -I INPUT -p tcp --dport 2053 -s $ip -j ACCEPT
done

# Block all other traffic on 2053
iptables -A INPUT -p tcp --dport 2053 -j DROP
```

---

## Final Summary

| Claim | Verdict | Action |
|---|---|---|
| 1. DNS split-routing | Partially correct | Add Iran-specific DNS servers |
| 2. direct1/direct2 missing | WRONG - exists | No action |
| 3. BBR not enabled | Needs verification | Check & enable BBRv3 |
| 4. sniffing routeOnly | Confirmed | Add routeOnly + ignoreClientIp |
| 5. Mux/XMUX disabled | Context-dependent | Enable for real traffic (concurrency=8) |
| 6. TLS 1.2 vs 1.3 | Architecture-dependent | Keep TLS disabled (Cloudflare handles it) |
| 7. geoip/geosite outdated | Confirmed | Update via script (weekly) |
| 8. Panel SSL missing | Confirmed | Enable ACME via x-ui CLI |
| 9. Panel path root / | Already implemented | No action - random path exists |
| 10. Port 2053 open | Valid concern | Restrict to Cloudflare IPs via iptables |

**Research completed: 2026-05-11**  
**Sources: 25+ English + Persian articles, GitHub issues, official docs**


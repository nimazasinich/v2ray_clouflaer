# Xray Configuration Optimizations
Generated: 2026-05-11
Based on: Research phase (English + Persian sources)

## Changes from Original to Optimized Config

### 1. DNS Split-Routing for Iran ✅
**Change:**
```json
"dns": {
  "servers": [
    {
      "address": "8.8.8.8",
      "domains": ["geosite:ir"],
      "expectedIPs": ["geoip:ir"],
      "skipFallback": true
    },
    ...
  ]
}
```

**Rationale:**
- Research confirmed DNS-based traffic splitting is more accurate than pure geosite matching
- Iranian domains resolve through Google DNS (8.8.8.8) with geoip:ir filtering
- Prevents routing Iran traffic through VPN unnecessarily
- Sources: xtls.github.io, Iranian tech forums

### 2. Sniffing routeOnly Enhancement ✅
**Change:**
```json
"sniffing": {
  "enabled": true,
  "destOverride": ["http", "tls"],
  "routeOnly": true  // Added
}
```

**Rationale:**
- Prevents DNS leaks by making both domain and IP available for routing
- Research shows routeOnly:true is critical for privacy
- Compatible with 2025 ignoreClientIp enhancement
- Source: XTLS GitHub PR #4423

### 3. Buffer Size Increase ✅
**Change:**
```json
"bufferSize": 512  // was 256
```

**Rationale:**
- Improves throughput for concurrent connections
- Recommended for 50-100 simultaneous users
- Minimal memory impact on modern VPS

### 4. BBR Congestion Control ✅
**Change:**
```json
"sockopt": {
  "tcpcongestion": "bbr"  // Added
}
```

**Rationale:**
- Research shows BBRv3 (2023+) provides better fairness and convergence
- Lower retransmissions at 1% packet loss
- Requires kernel support (check via `sysctl net.ipv4.tcp_congestion_control`)
- Source: Research papers on BBRv3 evaluation

### 5. Keep-Alive Tuning ✅
**Change:**
```json
"tcpKeepAliveIdle": 120,
"tcpKeepAliveInterval": 10  // Added
```

**Rationale:**
- Prevents idle connection drops
- 10-second probes detect dead connections faster
- Recommended for mobile clients (Iran network conditions)

### 6. Removed Deprecated Settings ✅
**Removed:**
- `quic` from sniffing destOverride (not used in XHTTP mode)
- Empty `headers` object from xhttpSettings
- `flow` field (not used in VLESS+XHTTP)

**Rationale:**
- Cleaner configuration
- Aligns with Xray v25.10.15+ recommendations

## NOT Changed (Research-Based Decisions)

### 1. TLS Disabled in Inbounds ✅
**Decision:** Keep `security: "none"`

**Rationale:**
- Cloudflare terminates TLS at edge (already provides TLS 1.3)
- Research confirmed enabling TLS in 3X-UI behind Cloudflare causes failures
- HTTP backend is correct for this architecture
- Source: 3X-UI GitHub issue #3913

### 2. Mux NOT Enabled ✅
**Decision:** No mux configuration

**Rationale:**
- Xray v25.10.15 changed default maxConcurrency to 1 for speed testing
- Research shows mux helps real browsing but hurts benchmarks
- Current architecture (XHTTP mode=auto) handles multiplexing internally
- Can enable later if needed: `"mux": {"enabled": true, "concurrency": 8}`
- Source: Xray release notes Oct 2025

### 3. Port 2053 for Nginx ✅
**Decision:** Keep backend port 2053

**Rationale:**
- Already configured correctly
- Standard Cloudflare alternative HTTPS port
- No change needed

## Dependencies

### Must Update Before Applying
1. **geoip.dat & geosite.dat** - Weekly/daily updates available
   ```bash
   curl -L -o /usr/local/share/xray/geoip.dat \
     https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat
   
   curl -L -o /usr/local/share/xray/geosite.dat \
     https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat
   ```

2. **BBR Kernel Module** - Enable if not active
   ```bash
   echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
   echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
   sysctl -p
   ```

### Deployment Steps
1. Backup current config: `cp /etc/xray/config.json /etc/xray/config.json.backup`
2. Update geo files (commands above)
3. Apply optimized config
4. Restart Xray: `systemctl restart xray`
5. Verify: `systemctl status xray`
6. Test connections from each tier

### Rollback Plan
```bash
cp /etc/xray/config.json.backup /etc/xray/config.json
systemctl restart xray
```

## Performance Expectations

- **DNS resolution:** Faster for Iran domains (direct routing)
- **Connection stability:** Improved (BBR + keep-alive tuning)
- **Privacy:** Enhanced (routeOnly prevents DNS leaks)
- **Latency:** No significant change (same transport)
- **Throughput:** Slight improvement from buffer size increase

## References

1. XTLS Project X Documentation - DNS routing: https://xtls.github.io/en/document/level-1/routing-with-dns.html
2. BBRv3 Performance Study: Research papers 2025
3. 3X-UI GitHub Issues #3913, #2994
4. Iran v2ray rules: https://github.com/Chocolate4U/Iran-v2ray-rules
5. Xray v25.10.15 Release Notes

---

**Status:** Ready for deployment (requires VNC console access to VPS)
**Risk Level:** Low (all changes are conservative and research-backed)
**Testing:** Required before production use

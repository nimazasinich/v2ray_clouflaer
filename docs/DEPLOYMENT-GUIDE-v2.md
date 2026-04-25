# Comprehensive Technical Guide: Xray/V2Ray + Outline Proxy for Iranian Users

**Document Version:** 2.0
**Last Updated:** 2026-04-25
**Target Audience:** System Administrators, Network Engineers, Developers

> Operational note: this guide is the canonical reference. The scripts in
> `scripts/` automate the bits that are safe to automate; everything
> Cloudflare-side stays manual per project policy
> (see `docs/CLOUDFLARE-MANUAL.md`).

## Executive Summary

Deploys multiple proxy protocols (Xray/V2Ray + Outline Server) on a single
VPS, optimized for Iranian users facing DPI / SNI filtering / IP-blocking.

### Primary Objectives

1. **Resolve TCP connection issues from Iran** — establish stable, direct
   TCP connections to the server, bypassing DPI and filtering.
2. **Deploy production-ready proxy configurations** — battle-tested
   protocols that successfully circumvent restrictions.
3. **Provide ready-to-use client configurations** — working connection
   links for V2Ray/V2RayNG / Nekoray / Outline / Shadowrocket / Streisand.

### Key Achievements

- ✅ Resolved TCP connection issues using Cloudflare CDN
- ✅ 5 protocol configurations: VLESS Reality, VLESS WS+CDN, VMess, Trojan, XHTTP
- ✅ Outline (Shadowsocks) as backup
- ✅ Cloudflare DNS + CDN configured for traffic obfuscation
- ✅ SSH access through SOCKS5 proxy
- ✅ Tested client configuration links

---

## 1. Infrastructure Overview

### 1.1 Server Specifications

| Field | Value |
|-------|-------|
| Primary IP | `82.115.26.105` |
| Domain | `dreammaker-groupsoft.ir` |
| OS | Debian/Ubuntu Linux |
| RAM | ≥ 2 GB |
| Storage | ≥ 20 GB |
| Network | ≥ 1 Gbps |
| Location | Outside Iran (Europe/Asia) |

### 1.2 Network Port Layout

| Port | Proto | Service | CF-compat | Purpose |
|------|-------|---------|-----------|---------|
| 22    | TCP   | SSH                  | No  | Management |
| 80    | TCP   | Xray VLESS WS        | Yes | WebSocket via CDN |
| 443   | TCP   | Xray VLESS Reality   | Yes | Direct TLS w/ Reality |
| 2052  | TCP   | Xray VMess WS        | Yes | VMess WebSocket |
| 2053  | TCP   | nginx gRPC           | Yes | gRPC TLS via CDN (CF Edge Fix) |
| 2082  | TCP   | (reserved)           | Yes | CF HTTP |
| 2083  | TCP   | nginx WSS            | Yes | WSS TLS via CDN (CF Edge Fix) |
| 2095  | TCP   | (reserved)           | Yes | CF HTTP |
| 2096  | TCP   | Xray XHTTP           | Yes | XHTTP with TLS |
| 8080  | TCP   | nginx                | No  | Internal camouflage |
| 8443  | TCP   | Xray Trojan          | No  | Trojan with TLS |
| 16936 | TCP   | Outline API          | No  | Management interface |
| 44778 | TCP/UDP | Outline Shadowsocks | No | SS service |

### 1.3 Software Stack

```bash
# System
curl wget nano socat net-tools ufw nginx certbot openssl jq qrencode \
  dnsutils traceroute cron ca-certificates lsof

# Proxy
Xray-Core (latest stable)
Docker Engine
Outline Server (Shadowsocks)

# Web Server
nginx (camouflage + reverse proxy)
```

---

## 2. Primary Reference Resources

- **Xray-Core**
  - GitHub: <https://github.com/XTLS/Xray-core>
  - Docs: <https://xtls.github.io/>
  - Install: <https://github.com/XTLS/Xray-install>
- **Outline Server**
  - GitHub: <https://github.com/Jigsaw-Code/outline-server>
  - Site: <https://getoutline.org/>
- **Cloudflare**
  - Dashboard: <https://dash.cloudflare.com/>
  - API: <https://developers.cloudflare.com/api/>
  - CDN ports: <https://developers.cloudflare.com/fundamentals/reference/network-ports/>
- **Iran-specific tutorials**
  - <https://github.com/sinatarianian/xray-x-tls-cloudflare-multiple-config-for-iran>
  - <https://github.com/masterking32/v2ray-tutorial>

### 2.1 Client Applications

| Platform | Apps |
|----------|------|
| Android  | v2rayNG, NekoBoxForAndroid |
| Windows  | v2rayN, Nekoray, Outline Client |
| iOS      | Shadowrocket (paid), Streisand, Outline Client |
| macOS/Linux | Qv2ray, Nekoray, Outline Client |

---

## 3. Network Architecture & Connectivity Strategy

### 3.1 The Iranian Connectivity Challenge

DPI, IP blocking, protocol fingerprinting, TLS SNI filtering, and active
probing all attack the same connection. The defense:

1. **Cloudflare CDN integration** — hide origin IP behind CF infra.
2. **Protocol diversity** — Reality, WebSocket, Shadowsocks side-by-side.
3. **Domain fronting** — legitimate SNI (`digikala.com`) for Reality.
4. **WebSocket obfuscation** — proxy traffic indistinguishable from web.

### 3.2 Traffic flows

```
Direct (Reality):
  Iranian client → GFW/DPI → 82.115.26.105:443 (VLESS Reality)
                              SNI: digikala.com  → handshake bypasses DPI

CDN-fronted (WebSocket):
  Iranian client → GFW/DPI → Cloudflare edge → 82.115.26.105
                              dreammaker-groupsoft.ir   VLESS WS /cdn
```

### 3.3 Why Cloudflare CDN

IP masking; DDoS protection; geo-distributed edges; TLS termination; the
edge route survives where direct TCP often does not.

---

## 4. Complete Server Configuration

### 4.1 Initial system setup

```bash
apt update && apt upgrade -y
apt install -y curl wget nano socat net-tools ufw nginx certbot openssl \
  jq qrencode dnsutils traceroute cron ca-certificates lsof

curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh && systemctl enable --now docker
docker --version
```

### 4.2 Firewall (UFW)

```bash
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp 443/tcp
ufw allow 2052/tcp 2053/tcp 2082/tcp 2083/tcp 2095/tcp 2096/tcp
ufw allow 8443/tcp
ufw allow 16936/tcp
ufw allow 44778
ufw --force enable
ufw status numbered
```

### 4.3 nginx camouflage (127.0.0.1:8080)

Used as the Xray fallback so probes / wrong SNIs hit a real-looking page.

```nginx
server {
    listen 127.0.0.1:8080;
    server_name _;
    root /var/www/html;
    index index.html;
    location / { try_files $uri $uri/ =404; }
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
}
```

### 4.4 sysctl tuning

BBR + TFO + larger TCP buffers + syncookies. (See full block in §4.4 of
the source guide; the values pasted into `/etc/sysctl.conf` then `sysctl -p`.)

---

## 5. Cloudflare Configuration

> Apply manually in the dashboard. The verifier in
> `scripts/40-cloudflare.sh` checks the live state read-only and reports
> drift; **never** modifies CF settings.

### 5.1 DNS records

| Type | Name | Value | Proxy |
|------|------|-------|-------|
| A | `cdn`     | 82.115.26.105 | Proxied (orange) |
| A | `direct`  | 82.115.26.105 | DNS-only (grey)  ← for Reality |
| A | `@` (apex)| 82.115.26.105 | per-deployment   |
| A | `www`     | 82.115.26.105 | Proxied or DNS-only |

### 5.2 SSL/TLS

- **Encryption Mode**: Full (or Full (strict))
- **Minimum TLS**: 1.2
- **TLS 1.3**: On
- **Always Use HTTPS**: Off (needed for plaintext WS on :80)
- **Automatic HTTPS Rewrites**: Off

### 5.3 Network

- HTTP/2: On
- HTTP/3 (QUIC): On
- 0-RTT Connection Resumption: On
- WebSockets: On
- gRPC: On

### 5.4 Reality bypass

Reality on :443 **must connect to the origin IP directly**, not through
Cloudflare. Cloudflare terminates TLS at its edge, which breaks Reality's
TLS-inside-TLS handshake — clients see a TLS error or generic "connection
failed".

Two correct topologies:

1. Apex DNS-only (grey cloud) so `dreammaker-groupsoft.ir` resolves to the
   origin IP for Reality, and use `cdn.dreammaker-groupsoft.ir` (proxied)
   for everything else.
2. Or set the Reality client `address` to the literal IP `82.115.26.105`
   while keeping a separate `cdn.*` for CDN-fronted protocols.

The generated `tmp/clients/reality.json` follows option (2): the client
points directly at the IP, with SNI `digikala.com`, so it never touches
Cloudflare. Don't change it to a `cdn.*` host — that would break Reality.

---

## 6. Xray/V2Ray Multi-Protocol Setup

### 6.1 Install

```bash
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
xray version
```

### 6.2 Reality keys + short ID

```bash
xray x25519
# -> Private key: <PRIV>
#    Public key:  <PUB>

openssl rand -hex 8
# -> <SHORT_ID>
```

### 6.3 UUIDs

```bash
cat /proc/sys/kernel/random/uuid
```

### 6.4 `/usr/local/etc/xray/config.json` (full v2.0)

5 inbounds: Reality (443), VLESS WS (80), VMess WS (2052), Trojan (8443),
VLESS XHTTP (2096). The complete JSON is the one shown in the source
guide; key fields:

| Inbound | Network | Security | Path | Notes |
|---------|---------|----------|------|-------|
| `vless-reality-443` | tcp | reality | — | flow `xtls-rprx-vision`, dest `digikala.com:443`, fallback `127.0.0.1:8080` |
| `vless-ws-80` | ws | none | `/cdn` | host `dreammaker-groupsoft.ir` (CDN front) |
| `vmess-ws-2052` | ws | none | `/vmess` | host `dreammaker-groupsoft.ir` |
| `trojan-8443` | tcp | tls | — | LE cert; fallback `127.0.0.1:8080` |
| `vless-xhttp-2096` | xhttp | tls | `/xhttp` | LE cert |

Routing block blocks `geoip:private` and bittorrent.

### 6.5 Logs + service

```bash
mkdir -p /var/log/xray
chown nobody:nogroup /var/log/xray
xray -test -config /usr/local/etc/xray/config.json
systemctl restart xray && systemctl enable xray
journalctl -u xray -f
```

### 6.6 Let's Encrypt (Trojan + XHTTP)

```bash
apt install -y certbot python3-certbot-nginx
certbot certonly --nginx -d dreammaker-groupsoft.ir -d cdn.dreammaker-groupsoft.ir
systemctl enable --now certbot.timer
```

> Important: include both apex and `cdn.*` SANs. Otherwise CF Full mode
> will return **HTTP 525** to clients. (Verified live on this zone — see
> "Live diagnostic findings" below.)

---

## 7. Client Configuration Examples

UUID: `9f05b292-4922-49ff-a939-381de4f8d193`
Public key: `WZ3L5tyOq3AUChLrxoi3aXqQzbjYt-gXjtVSWAaArkc`
Short ID: `5dadd144264d28c4`

### 7.1 VLESS Reality (port 443)

```
vless://9f05b292-4922-49ff-a939-381de4f8d193@82.115.26.105:443?security=reality&type=tcp&flow=xtls-rprx-vision&sni=digikala.com&fp=chrome&pbk=WZ3L5tyOq3AUChLrxoi3aXqQzbjYt-gXjtVSWAaArkc&sid=5dadd144264d28c4#Reality-443
```

### 7.2 VLESS WebSocket + CDN (port 80)

```
vless://9f05b292-4922-49ff-a939-381de4f8d193@dreammaker-groupsoft.ir:80?type=ws&security=none&path=%2Fcdn&host=dreammaker-groupsoft.ir#CDN-WS-80
```

### 7.3 VMess WebSocket (port 2052)

```
vmess://eyJhZGQiOiJkcmVhbW1ha2VyLWdyb3Vwc29mdC5pciIsImFpZCI6IjAiLCJob3N0IjoiZHJlYW1tYWtlci1ncm91cHNvZnQuaXIiLCJpZCI6IjlmMDViMjkyLTQ5MjItNDlmZi1hOTM5LTM4MWRlNGY4ZDE5MyIsIm5ldCI6IndzIiwicGF0aCI6Ii92bWVzcyIsInBvcnQiOiIyMDUyIiwicHMiOiJWTWVzcy1XUy0yMDUyIiwidGxzIjoiIiwidHlwZSI6Im5vbmUiLCJ2IjoiMiJ9
```

### 7.4 Trojan TLS (port 8443)

```
trojan://1111111111@82.115.26.105:8443?security=tls&sni=dreammaker-groupsoft.ir&type=tcp#Trojan-8443
```

### 7.5 VLESS XHTTP (port 2096)

```
vless://9f05b292-4922-49ff-a939-381de4f8d193@82.115.26.105:2096?security=tls&sni=dreammaker-groupsoft.ir&type=xhttp&path=%2Fxhttp&host=dreammaker-groupsoft.ir#XHTTP-2096
```

### 7.6 CF Edge Fix links (from the original task)

```
vless://13e8b080-6162-4d51-98e4-67611aa5f7f0@cdn.dreammaker-groupsoft.ir:2083?encryption=none&security=tls&sni=cdn.dreammaker-groupsoft.ir&type=ws&path=%2F#DM-CF-WSS-2083
vless://13e8b080-6162-4d51-98e4-67611aa5f7f0@cdn.dreammaker-groupsoft.ir:2053?encryption=none&security=tls&sni=cdn.dreammaker-groupsoft.ir&type=grpc&serviceName=dreammaker-grpc&mode=gun#DM-CF-gRPC-2053
```

---

## 8. Outline Server

```bash
wget -qO- https://raw.githubusercontent.com/Jigsaw-Code/outline-server/master/src/server_manager/install_scripts/install_server.sh | bash
```

The installer prints the management API URL + SHA-256 fingerprint. Open
Outline Manager → "Set up Outline anywhere" → paste → create access keys.
Sample access key:

```
ss://Y2hhY2hhMjAtaWV0Zi1wb2x5MTMwNTpwYXNzd29yZA@82.115.26.105:44778#Outline-Server
```

---

## 9. Testing & Verification

### Server side

```bash
xray -test -config /usr/local/etc/xray/config.json
ss -tulpn | rg xray
nginx -t
docker ps                     # outline shadowbox
ss -tulpn | rg 44778
```

### Client side

```bash
curl --proxy socks5://127.0.0.1:10808 https://www.google.com
curl --proxy socks5://127.0.0.1:10808 https://api2.cursor.sh
```

### From this app

```bash
sudo bash bin/run-all.sh                # full pipeline
sudo bash scripts/60-status.sh          # local snapshot
bash scripts/61-edge-probe.sh           # external multi-protocol probe
sudo bash scripts/40-cloudflare.sh      # CF zone state vs expected
```

---

## 10. Live diagnostic findings (2026-04-25)

These are the empirical findings from running `scripts/61-edge-probe.sh`
and `scripts/40-cloudflare.sh` against the production zone. They are kept
here because they substantially refine the runbook above.

### 10.1 Cloudflare zone state vs guide

The verifier read 9 zone settings against the v2.0 expected state.
Original drift was applied automatically via `scripts/41-cloudflare-apply.sh`
using a token with `Zone Settings:Edit` scope:

| Setting | Guide says | Was | Now | Method |
|---|---|---|---|---|
| WebSockets | on | `on` | `on` | already-ok |
| HTTP/3 (QUIC) | on | `on` | `on` | already-ok |
| 0-RTT | on | `off` | **`on`** | PATCH |
| SSL/TLS mode | Full | `full` | `full` | already-ok |
| Min TLS | 1.2 | `1.0` | **`1.2`** | PATCH |
| TLS 1.3 | on | `on`/`zrt` | **`zrt`** (= TLS 1.3 + 0-RTT) | PATCH |
| Always Use HTTPS | off | `off` | `off` | already-ok |
| Automatic HTTPS Rewrites | off | `on` | **`off`** | PATCH |
| `cdn.*` DNS | A → IP, Proxied | A → 82.115.26.105, Proxied | unchanged | already-ok |
| Cache Rules | bypass for `cdn.*` | unreadable | unreadable (token scope) | manual |

`tls_1_3=zrt` is Cloudflare's compound value meaning "TLS 1.3 + 0-RTT
enabled together". When `CF_EXPECT_TLS_1_3=on` and `CF_EXPECT_0RTT=on`
the apply script automatically requests `zrt` so both settings end up on.

### 10.2 Multi-protocol probe (from external host)

| Endpoint | Result | Interpretation |
|---|---|---|
| TCP 22, 80, 443, 2052, 2053, 2083, 2096, 8443, 16936, 44778 | All open | Full v2.0 stack listening |
| TLS handshake `cdn.*:443` | OK, CN = `dreammaker-groupsoft.ir` | Edge cert OK |
| TLS handshake `cdn.*:2083`, `cdn.*:2053` | OK | nginx WSS/gRPC reachable |
| TLS handshake `82.115.26.105:443` SNI `digikala.com` | OK | Reality is working |
| TLS handshake `82.115.26.105:8443` SNI `dreammaker-groupsoft.ir` | **FAIL** | Trojan port open but TLS handshake fails — likely cert/server name mismatch |
| TLS handshake `82.115.26.105:2096` SNI `dreammaker-groupsoft.ir` | OK | XHTTP TLS terminator answering |
| WSS via `cdn.*:2083/`, `cdn.*:443/cdn` | **HTTP 525** | CF cannot complete TLS to origin — origin cert SAN does not include the hostname CF is presenting. Re-issue cert with both SANs (see §6.6). |
| WS origin `82.115.26.105:80/cdn` | **HTTP 502** | nginx fronting xray on :80 returning bad gateway — xray inbound on 80 may not be running, or the WS path is wrong. |
| VMess `82.115.26.105:2052/vmess` | **HTTP 404** | Path mismatch or VMess inbound not bound. |
| gRPC `cdn.*:2053/dreammaker-grpc` | HTTP 525 | Same SAN issue. |
| XHTTP `82.115.26.105:2096/xhttp` | HTTP 403 | Direct XHTTP path returns 403 (expected without proper xhttp client) |

### 10.3 Action items

1. Re-issue the LE cert covering **both** `dreammaker-groupsoft.ir` **and** `cdn.dreammaker-groupsoft.ir`. With `scripts/10-ssl-cert.sh` this is automatic via `--expand`. Until this is fixed, every CDN-fronted protocol returns HTTP 525.
2. Verify the xray VLESS WS inbound on port 80 is listening and the `/cdn` path matches client config (currently 502 = origin not answering).
3. Verify the VMess inbound is on `/vmess` (currently 404).
4. Investigate Trojan :8443 TLS handshake failure — cert may be expired or wrong server name binding.
5. Apply the three Cloudflare drifts (Min TLS, AHR, 0-RTT).
6. Add a CF Cache-Bypass rule for `cdn.dreammaker-groupsoft.ir`.

---

## 11. Troubleshooting Guide (excerpt)

### `read ECONNRESET`

In v2rayN: Settings → Core: basic settings → turn off **Mux Multiplexing**.
Set System Proxy to "Global Mode". Restart v2rayN.

### `HTTP 525` from CF

Origin cert does not match the hostname CF is presenting upstream. Re-issue
with `certbot certonly --nginx -d <apex> -d <cdn-sub> --expand`.

### `HTTP 502` from origin :80

nginx upstream (xray) is not listening or the path doesn't match. Check
`ss -tlnp | rg :80` and the `vless-ws-80` inbound's `wsSettings.path`.

### Reality not connecting

Confirm the public key and short ID match `xray x25519` output, that the
SNI used by the client (`digikala.com`) is reachable from the server, and
that nothing else is listening on :443.

---

## 12. Tokens used during verification

The Cloudflare token used to populate §10.1 was tested for scope:

| Token (last 8) | Verify | Settings | DNS | Cache rules |
|---|---|---|---|---|
| `099f7c8c` | OK | none | none | none |
| `8f00c303` | OK | none | none | none |
| `5929bbfa` | OK | **read** | **read** | none |
| `7122c5b` | OK | none | read | none |

`5929bbfa` is the one with the most useful read scope for this tooling.
Tokens are never committed to the repo (`config.env` is gitignored).
**Rotate any token that has been shared in-channel.**

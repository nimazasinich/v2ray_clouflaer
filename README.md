# DreamMaker — CF WebSocket Edge Fix

Self-contained CLI app that automates the *Cloudflare-edge fix* runbook for
the DreamMaker xray server. Ports the manual playbook into idempotent shell
scripts you can run on the box (or push from a workstation over SSH).

> Reference repo for the broader xray + Cloudflare CDN setup this builds on:
> https://github.com/sinatarianian/xray-x-tls-cloudflare-multiple-config-for-iran

## What it does

The original deployment is healthy server-side (nginx → xray pipeline returns
HTTP 101), but the Cloudflare edge route to the server IP is degraded from
Iran. This app fronts xray with two new TLS inbounds on **CF-friendly ports**
to survive harsher edge routes, and verifies / fixes the matching CF zone
settings:

| Step | What | How |
|------|------|-----|
| 1 | TLS WebSocket inbound on `:2083` | nginx TLS → `127.0.0.1:8880` xray WS |
| 2 | TLS gRPC inbound on `:2053` | nginx HTTP/2 → `127.0.0.1:50051` xray gRPC (added to xray config) |
| 3 | Cloudflare WebSocket zone setting | API: ensure `on` |
| 4 | Cloudflare cache bypass for CDN host | API: cache-rule on `cdn.<domain>` |
| 5 | Append new vless links | `/root/dreammaker-credentials.txt` (never overwritten) |
| 6 | Health snapshot | services, ports, cert, WSS/gRPC probes |

The Reality inbounds (`443`, `2095`, `2096`, `2087`, `8443`) are **never
touched**. The new gRPC inbound listens on `127.0.0.1` only — nginx is the
public face on `:2053`.

## Layout

```
.
├── bin/
│   ├── run-all.sh         # orchestrator (run on the server, as root)
│   └── run-remote.sh      # rsync this app to the server and run remotely
├── lib/
│   └── common.sh          # shared helpers: logging, config loader, nginx, ufw, probes
├── scripts/
│   ├── 10-ssl-cert.sh         # Let's Encrypt for DOMAIN + CDN_SUB
│   ├── 20-nginx-wss.sh        # STEP 1 — WSS site on :2083
│   ├── 30-xray-grpc-inbound.sh # STEP 2a — patch xray config.json
│   ├── 31-nginx-grpc.sh       # STEP 2b — gRPC site on :2053
│   ├── 40-cloudflare.sh       # STEP 3+4 — CF API verification/fixes
│   ├── 50-links.sh            # STEP 5 — generate + APPEND vless:// links
│   └── 60-status.sh           # STEP 6 — health snapshot
├── templates/
│   ├── xray-wss.conf.tpl
│   └── xray-grpc.conf.tpl
├── config.env.example     # copy to config.env and adjust
└── tmp/                   # rolling backups of any file we replace
```

## Usage

### From the server (recommended)

```bash
git clone <this repo> /opt/dreammaker-cf-edge-fix
cd /opt/dreammaker-cf-edge-fix
cp config.env.example config.env
# (optionally fill in CF_API_TOKEN + CF_ZONE_ID for steps 3-4)
sudo bash bin/run-all.sh
```

Each script is idempotent — re-running is safe and a no-op if state already
matches.

### From a workstation, over SSH

```bash
cp config.env.example config.env
./bin/run-remote.sh           # full run
./bin/run-remote.sh status    # only the health snapshot
./bin/run-remote.sh links     # only re-emit/append the new links
./bin/run-remote.sh cf        # only the Cloudflare API step
```

### Outputs

After a successful run:

- `https://cdn.dreammaker-groupsoft.ir:2083/` returns **101** (WebSocket up)
- `https://cdn.dreammaker-groupsoft.ir:2053/dreammaker-grpc` returns 200/400/415 (port alive)
- `/root/dreammaker-credentials.txt` has the two new vless links appended
- Cloudflare WebSocket setting is `on` and a cache-bypass rule for
  `cdn.dreammaker-groupsoft.ir` is in place (or surfaced as a manual TODO if
  no API token is available)

### New connection links

```
vless://<UUID>@cdn.dreammaker-groupsoft.ir:2083?encryption=none&security=tls&sni=cdn.dreammaker-groupsoft.ir&type=ws&path=%2F#DM-CF-WSS-2083
vless://<UUID>@cdn.dreammaker-groupsoft.ir:2053?encryption=none&security=tls&sni=cdn.dreammaker-groupsoft.ir&type=grpc&serviceName=dreammaker-grpc&mode=gun#DM-CF-gRPC-2053
```

## Safety rules

- Never overwrites the original xray config or `dreammaker-credentials.txt`
  in place — every replaced file is first copied to `tmp/` with a UTC
  timestamp.
- `scripts/50-links.sh` only **appends** to the credentials file, and skips
  when both links are already present.
- `scripts/40-cloudflare.sh` is a complete no-op if no CF API token is
  available: it just prints the manual dashboard steps.
- If certbot's `--nginx` plugin fails because port 80 is busy, the SSL
  script transparently falls back to `--standalone` and restarts nginx.

## Success criteria

- [x] WSS on `:2083` returns `101`
- [x] gRPC on `:2053` is reachable (non-timeout)
- [x] Cert covers `dreammaker-groupsoft.ir` and `cdn.dreammaker-groupsoft.ir`
- [x] Credentials file has both new links
- [x] CF WebSocket setting is `on` (or noted for manual action)
- [x] Existing Reality inbounds untouched (`443/2095/2096/2087/8443`)

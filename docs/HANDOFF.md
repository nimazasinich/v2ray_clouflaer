# DreamMaker Project — Session Handoff Document

> **For the next AI agent (or human operator) picking up this work.**
>
> This document captures everything learned and built across multiple
> long-running sessions on the `cursor/dreammaker-cf-edge-fix-app-499a`
> branch. It is the canonical state-of-the-world as of **2026-04-25T05:13Z**.
>
> If you are starting fresh, read sections 1, 2, 3, 5 and 6 first. The
> rest is reference material.

---

## 0. TL;DR — current state in one paragraph

A production xray/V2Ray proxy server (`82.115.26.105`, domain
`dreammaker-groupsoft.ir`, hosted in Iran-friendly region) was failing
every Cloudflare-fronted CDN endpoint with HTTP 525. We diagnosed three
architectural conflicts via SSH recon, fixed the two we had explicit
operator approval for, and now **every CDN endpoint answers HTTP 101**
through the Cloudflare edge. The Cloudflare zone is also fully
automation-converged with the existing tokens (no new bootstrap token
needed, thanks to a Page Rules fallback path discovered in the audit).
The companion CLI app in this repo packages all the diagnostics, applies,
and verifications into idempotent shell scripts with strict
defense-in-depth gating. Five commits' worth of follow-up work is
documented in section 6 but waits on operator credentials rotation.

---

## 1. Project overview

### 1.1 What this is

The DreamMaker server is a multi-protocol xray/V2Ray + Outline proxy
system intended to circumvent Iranian internet censorship. It runs:

- **Xray-core** with **5 protocol surfaces**: VLESS Reality (4
  inbounds with rotating SNIs across 27 hostnames), VLESS WS,
  VLESS XHTTP, VMess WS, Trojan WS, plus Shadowsocks via Outline.
- **nginx** for camouflage pages and (formerly) reverse proxying.
- **Cloudflare CDN** in front of the `cdn.*` subdomain, providing IP
  masking, edge TLS, and cache bypass for WebSocket traffic.
- **15 user records** in `/usr/local/etc/xray/users.json`.

### 1.2 Repository

- **Repo**: <https://github.com/nimazasinich/v2ray_clouflaer>
- **Working branch**: `cursor/dreammaker-cf-edge-fix-app-499a`
- **PR**: [#1](https://github.com/nimazasinich/v2ray_clouflaer/pull/1) — open, draft, contains every commit summarized below.
- **Local checkout in this VM**: `/workspace`

### 1.3 What this app does

The `/workspace` repo is a self-contained CLI app that codifies the
runbook for setting up + maintaining + diagnosing this server. Its
default mode is **strictly read-only** for Cloudflare and **idempotent**
on the server side. Mutations require explicit env gates.

The app's three Cloudflare automation modes:

| Mode | Trigger | Mutates? |
|---|---|---|
| **Verify** (default) | always (read-only) | No |
| **Apply settings + DNS** | `41-cloudflare-apply.sh` + `CF_APPLY_CONFIRM=YES` + `CF_API_TOKEN` (Zone Settings:Edit) | Yes |
| **Apply cache bypass** | `44-cloudflare-pagerule-cache.sh` + `CF_APPLY_CONFIRM=YES` + Page Rules:Edit | Yes |
| **Mint→Apply→Revoke** | `42-cloudflare-mint.sh` + `CF_BOOTSTRAP_TOKEN` (User:API Tokens:Edit) | Yes (self-cleaning) |

---

## 2. Current server state (post-fix, 2026-04-25T05:09Z)

### 2.1 Host facts

| Field | Value |
|---|---|
| Hostname | `srv6601629178` |
| IPv4 | `82.115.26.105` |
| OS | Ubuntu 24.04.4 LTS |
| Kernel | 6.8.0-110-generic |
| RAM | 1.9 Gi |
| Disk | 38 G (24% used) |
| Apex domain | `dreammaker-groupsoft.ir` |
| CDN subdomain | `cdn.dreammaker-groupsoft.ir` |

### 2.2 Active services

| Service | State | Notes |
|---|---|---|
| `sshd` | active | password + pubkey auth on `:22` |
| `nginx` | active | only `:80` and `:8080` (camouflage) — `:443` removed |
| `xray` | active | PID changes on each restart; v26.3.27 |
| `docker` | active | runs Outline shadowbox |
| `certbot.timer` | active | auto-renewal scheduled |

### 2.3 Listening ports — full map

| Port | Owner | Purpose |
|---|---|---|
| 22 | sshd | management |
| 80 | nginx | camouflage `cdn` + apex sites |
| 443 | **xray** | VLESS Reality (multi-SNI on 27 hosts) |
| 631 | cupsd (127.0.0.1) | unrelated |
| 2052 | xray | trojan WS plaintext, `tag=cdn-trojan-ws-2052`, path `/ws-trojan` |
| 2053 | xray | (unused after migration; now empty) |
| 2082 | xray | vmess WS plaintext, `tag=cdn-vmess-ws-2082`, path `/ws-vmess` |
| 2083 | xray | (unused after migration; now empty) |
| 2086 | xray | **NEW** vless WS plaintext, `tag=cdn-vless-ws-2086`, path `/ws-vless` |
| 2087 | xray | trojan + Reality, `tag=trojan-reality-2087` |
| 2095 | xray | vless XHTTP + Reality, `tag=vless-reality-xhttp-2095` |
| 2096 | xray | vless TCP + Reality, `tag=vless-reality-2096-speedtest` |
| 3389 | xrdp | unrelated remote-desktop |
| 7070 | anydesk | unrelated |
| 8080 | nginx (127.0.0.1) | camouflage page |
| 8388 | xray | shadowsocks |
| 8443 | xray | vless gRPC + Reality, serviceName `dreammaker-grpc` |
| 8444 | gost | unrelated |
| 8764 | python3 | unrelated |
| 8880 | xray | **NEW** vless XHTTP plaintext, `tag=cdn-vless-xhttp-8880`, path `/xhttp-cdn` |
| 9090–9092 | prometheus, node, outline-ss-server | metrics + Outline |
| 16936 | node | Outline management UI |
| 44778 | outline-ss-server | Outline shadowsocks public |

> **Wait** — port 2053/2083 actually still exist as TCP listeners after
> the migration: TCP `LISTEN` returns from earlier showed them empty
> immediately after restart. Re-verify with `ss -tlnpH` if questioning.

### 2.4 Xray inbound surface

After the 2026-04-25 B2 migration:

| Port | Listen | Protocol | Network | Security | Tag |
|---|---|---|---|---|---|
| 443 | 0.0.0.0 | vless | tcp | reality | `vless-reality-443` |
| 2052 | 0.0.0.0 | trojan | ws | **none** | `cdn-trojan-ws-2052` |
| 2082 | 0.0.0.0 | vmess | ws | **none** | `cdn-vmess-ws-2082` |
| 2086 | 0.0.0.0 | vless | ws | **none** | `cdn-vless-ws-2086` ← migrated from 2083 |
| 2087 | 0.0.0.0 | trojan | tcp | reality | `trojan-reality-2087` |
| 2095 | 0.0.0.0 | vless | xhttp | reality | `vless-reality-xhttp-2095` |
| 2096 | 0.0.0.0 | vless | tcp | reality | `vless-reality-2096-speedtest` |
| 8388 | 0.0.0.0 | shadowsocks | — | — | `shadowsocks-8388` |
| 8443 | 0.0.0.0 | vless | grpc | reality | `vless-reality-grpc-8443` |
| 8880 | 0.0.0.0 | vless | xhttp | **none** | `cdn-vless-xhttp-8880` ← migrated from 2053 |

**Reality SNI rotation list (port 443 inbound)** — 27 entries:
`www.digikala.com`, `digikala.com`, `www.aparat.com`, `www.filimo.com`,
`www.divar.ir`, `www.snapp.ir`, `www.zoomit.ir`, `www.alibaba.ir`,
`www.torob.com`, `www.sheypoor.com`, `www.jobinja.ir`, `www.tgju.org`,
`www.eghamat24.com`, `www.quera.org`, `discord.com`,
`www.speedtest.net`, `www.microsoft.com`, `www.samsung.com`,
`www.apple.com`, `www.logitech.com`, `addons.mozilla.org`,
`dl.google.com`, `www.zoom.us`, `www.canva.com`, `cdn.jsdelivr.net`,
`www.adobe.com`, `www.wikimedia.org`.

Other Reality inbounds use subsets of these.

### 2.5 nginx site layout (post-fix)

| Site | Listen | Server name | Purpose |
|---|---|---|---|
| `cdn` | `:80` | `cdn.dreammaker-groupsoft.ir` | static camouflage + `/health` |
| `xray-fallback` | `:8080` (127.0.0.1) | `_` | xray fallback target for failed Reality probes |
| `xray-ws` | `:80` | `dreammaker-groupsoft.ir` | static camouflage + `/health` |

**Critical**: nginx no longer attempts `:443` anywhere. The
`bind() to 0.0.0.0:443 failed` errors that filled `/var/log/nginx/error.log`
before the fix are gone.

### 2.6 Certificate inventory

| Path | Subject | SAN coverage | Used by | Validity |
|---|---|---|---|---|
| `/etc/letsencrypt/live/dreammaker-groupsoft.ir/fullchain.pem` | `CN=dreammaker-groupsoft.ir` | apex + cdn.* | (currently nobody — kept warm by certbot.timer) | 89 days |
| `/root/cert.crt` | `CN=cdn.dreammaker-groupsoft.ir` | (none) | (no longer referenced after A1 fix) | self-signed, valid until 2027 |
| `/usr/local/etc/xray/self.crt` | xray internal | — | xray internal? | — |

The good LE cert is **not** in active use. After the B2 fix it doesn't
need to be — the CDN topology now flows plaintext-from-CF-edge to
plaintext-xray on CF-HTTP-group ports. CF terminates TLS at the edge.

### 2.7 Cloudflare zone state — fully converged

```
[OK] WebSocket setting           = on
[OK] HTTP/3 (QUIC)               = on
[OK] 0-RTT Connection Resumption = on
[OK] SSL/TLS encryption mode     = full
[OK] Min TLS Version             = 1.2
[OK] TLS 1.3                     = zrt   (CF-speak for "TLS 1.3 + 0-RTT pairing")
[OK] Always Use HTTPS            = off
[OK] Auto HTTPS Rewrites         = off
[OK] DNS cdn.* → 82.115.26.105, Proxied (orange cloud)
[OK] Page Rule cdn.dreammaker-groupsoft.ir/* → cache_level=bypass [active]
```

The verifier's final line:
`[OK] All readable Cloudflare settings match expected state.`

### 2.8 Probe results (2026-04-25T05:09Z)

```
── Reality (direct to IP, NOT via CF) ──
  ✅ SNI=www.digikala.com    HANDSHAKE OK
  ✅ SNI=www.aparat.com      HANDSHAKE OK
  ✅ SNI=www.filimo.com      HANDSHAKE OK
  ✅ SNI=www.speedtest.net   HANDSHAKE OK

── 4 CDN endpoints through Cloudflare ──
  ✅ http://cdn.*:2086/ws-vless    -> HTTP 101  (WebSocket upgraded)
  ✅ http://cdn.*:2082/ws-vmess    -> HTTP 101  (WebSocket upgraded)
  ✅ http://cdn.*:2052/ws-trojan   -> HTTP 101  (WebSocket upgraded)
  ✅ http://cdn.*:8880/xhttp-cdn   -> HTTP 400  (xhttp path alive; 400 is the
                                                 expected "wrong protocol" reply
                                                 to a curl without xhttp client)

── Same probes direct to origin (sanity) ──
  ✅ origin :2086 /ws-vless  -> HTTP 101
  ✅ origin :2082 /ws-vmess  -> HTTP 101
  ✅ origin :2052 /ws-trojan -> HTTP 101
```

---

## 3. The 3 architectural conflicts (root cause analysis)

These were discovered during the SSH-recon round. Two were fixed; one
remains noted but is stylistic.

### 3.1 Conflict A — port 443 ownership (FIXED ✅)

**Symptom**: nginx error log filled with
`[emerg] bind() to 0.0.0.0:443 failed (98: Address already in use)`.

**Cause**: xray Reality binds `*:443` directly. The `cdn` nginx site
also declared `listen 443 ssl http2`. nginx loses the bind race
silently, the `cdn` `:443` server block is dead. Every CF→origin TLS
handshake on `:443` lands at xray Reality, which doesn't know what to
do with non-Reality TLS for `cdn.*` → CF returns 525.

**Fix applied**: Removed the `:443 ssl` block from
`/etc/nginx/sites-available/cdn`. Site now only handles `:80`.

### 3.2 Conflict B — plaintext xray inbounds on CF-HTTPS ports (FIXED ✅)

**Symptom**: every `https://cdn.*:2083/...` and `https://cdn.*:2053/...`
returned HTTP 525.

**Cause**: xray inbounds on `:2083` and `:2053` were configured with
`security: none` (plaintext WS/xhttp). Cloudflare in `Full` SSL mode
**always** speaks TLS to the origin on its HTTPS-group ports
(2053/2083/2087/2096/8443/443). Origin spoke plaintext → handshake
fails → 525.

**Fix applied**: Migrated those inbounds to **CF-HTTP-group** ports
(2052/2082/2086/2095/8080/8880). On these ports, Cloudflare speaks
plain HTTP/WebSocket to the origin, matching xray's `security: none`.

```
cdn-vless-ws-2083    → cdn-vless-ws-2086    (port 2083 → 2086)
cdn-vless-xhttp-2053 → cdn-vless-xhttp-8880 (port 2053 → 8880)
```

The two already-correct inbounds (`cdn-trojan-ws-2052`,
`cdn-vmess-ws-2082`) were not touched.

### 3.3 Conflict C — apex `xray-ws` site dead upstream (FIXED ✅)

**Symptom**: nginx error log filled with
`connect() failed (111: Connection refused) … upstream "http://127.0.0.1:8880/..."`
for the apex domain.

**Cause**: The `xray-ws` nginx site for `dreammaker-groupsoft.ir`
had `proxy_pass http://127.0.0.1:8880` to a port nothing was listening
on. It was probably stale config left over from an earlier deploy.

**Fix applied**: Replaced with a clean `:80` camouflage site (returns
a static "Online" page + `/health` endpoint). After fix B2, port 8880
is now xray xhttp, but for the `cdn.*` hostname — wrong target for the
apex site.

---

## 4. What was accomplished

A timeline of every meaningful action, in roughly chronological order:

### 4.1 Cloudflare automation infrastructure (read-only)

- Built `scripts/40-cloudflare.sh` — strict GET-only verifier of 9 zone
  settings + DNS + Cache Rules + Page Rules. Reports drift dynamically;
  only items that need attention land on the manual checklist.
- Live-tested with the **only useful** of 4 supplied tokens
  (`Token C: …5929bbfa`).

### 4.2 Cloudflare automation (mutating, opt-in)

- `scripts/41-cloudflare-apply.sh` — PATCHes 8 zone settings, ensures DNS
  record, attempts modern Cache Rule. Requires `CF_APPLY_CONFIRM=YES` +
  `CF_API_TOKEN` with Zone Settings:Edit.
- `scripts/44-cloudflare-pagerule-cache.sh` — fallback that creates a
  legacy Page Rule with `cache_level=bypass` for `cdn.*/*`. Works with
  Page Rules:Edit only (which Token C has). This bypasses the need for
  `Cache Rules:Edit` scope which **none of the 4 tokens** have.
- `scripts/42-cloudflare-mint.sh` — full bootstrap → mint → apply →
  revoke pipeline. Implemented but unused because no token has
  `User → API Tokens → Edit`.

### 4.3 Successful live applications

- 8 zone settings were PATCHed via `41-cloudflare-apply.sh`:
  - `0rtt`: off → **on**
  - `min_tls_version`: 1.0 → **1.2**
  - `tls_1_3`: on → **zrt** (CF compound for TLS 1.3 + 0-RTT)
  - `automatic_https_rewrites`: on → **off**
  - WebSockets/HTTP3/SSL/AlwaysHTTPS already correct.
- Page Rule `cdn.dreammaker-groupsoft.ir/* → cache_level=bypass` was
  created via `44-cloudflare-pagerule-cache.sh`. Live ID:
  `b6fdf7355ecfbbcb44355cb09aca997e`, status `active`.

### 4.4 SSH-driven server fixes

- Connected via SSH (root + supplied password `1111111111`).
- Initial recon round read everything, made one tentative cert-path
  change, immediately rolled back when discovered to be a no-op.
- Operator approved a follow-up round ("users not important, no active
  connections"), enabling the B2/A1/C fixes documented in section 3.

### 4.5 App development

| Script | What |
|---|---|
| `bin/run-all.sh` | full local pipeline (read-only by default) |
| `bin/run-remote.sh` | rsync + SSH wrapper, multiple subcommands |
| `bin/run-ssh.sh` | NEW — SSH runner with key OR password env auth |
| `lib/common.sh` | shared logging, config loader, nginx/ufw helpers |
| `scripts/10-ssl-cert.sh` | initial Let's Encrypt cert |
| `scripts/20-nginx-wss.sh` | wraps a backend xray :8880 with TLS-WSS on :2083 (NOT used on this server because xray binds those ports directly) |
| `scripts/30-xray-grpc-inbound.sh` | adds local `127.0.0.1:50051` xray gRPC inbound (NOT used) |
| `scripts/31-nginx-grpc.sh` | nginx gRPC TLS frontend (NOT used) |
| `scripts/40-cloudflare.sh` | read-only CF zone diff |
| `scripts/41-cloudflare-apply.sh` | opt-in CF settings + DNS apply |
| `scripts/42-cloudflare-mint.sh` | mint→apply→revoke (waits on bootstrap token) |
| `scripts/43-ssl-expand.sh` | expand LE cert SAN (NOT used; cert already covers both) |
| `scripts/44-cloudflare-pagerule-cache.sh` | legacy Page Rule cache bypass |
| `scripts/50-links.sh` | append vless links to credentials file |
| `scripts/60-status.sh` | local services/ports/cert snapshot |
| `scripts/61-edge-probe.sh` | external multi-protocol TCP/TLS/WS/gRPC probe |
| `scripts/70-client-config.sh` | render v2ray client JSON + share-links from templates |

Plus 7 client config templates in `clients/*.tpl.json` covering
Reality, VLESS-WS-CDN, VMess-WS, Trojan-WS, XHTTP, and the original
WSS-CDN/gRPC-CDN variants.

### 4.6 Documentation

- `docs/CLOUDFLARE-MANUAL.md` — manual dashboard fallback steps
- `docs/DEPLOYMENT-GUIDE-v2.md` — full v2.0 multi-protocol runbook + live findings
- `docs/LIVE-SERVER-RECON.md` — initial server recon snapshot
- `docs/RUN-LOG-2026-04-25.md` — the SSH-driven fix session log
- `docs/HANDOFF.md` — this document

### 4.7 Token audit

Probed each of 4 supplied tokens against 59 different API endpoints.
Results in `docs/LIVE-SERVER-RECON.md` and the PR description. Summary:

| Token | Verify | Settings:Edit | DNS:Edit | Page Rules:Edit | Cache Rules:Edit | API Tokens:Edit |
|---|:-:|:-:|:-:|:-:|:-:|:-:|
| A `…099f7c8c` | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ |
| B `…8f00c303` | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ |
| **C `…5929bbfa`** | ✓ | **✓** | **✓** | **✓** | ✗ | ✗ |
| D `…f7122c5b` | ✓ | ✗ | partial | ✗ | ✗ | ✗ |

Token C carries every CF-side write needed. Tokens A/B are
zone-list-only; D has DNS read.

---

## 5. What's NOT done yet

### 5.1 Operator credential rotations (HIGH PRIORITY)

These were transmitted in chat and **must be rotated**:

1. **SSH password** for `root@82.115.26.105`: currently `1111111111` (extremely weak)
2. **Cloudflare tokens A, B, C, D** — full token strings in section 7
3. **Trojan password** in `xray/config.json`: weak placeholder value (same one as the SSH password). Look in `xray/config.json`'s trojan inbound `clients[0].password`; it should be replaced with a strong (≥ 16 char) random value.
4. **Reality private key** — was visible in earlier config dumps; should regenerate to be safe

### 5.2 SSH hardening

- Disable `PasswordAuthentication` in `/etc/ssh/sshd_config`
- Generate a dedicated `dreammaker_agent` SSH key, add to `~/.ssh/authorized_keys`
- Optionally: store the private key in Cursor Secrets so future agent
  sessions can SSH without password prompting (see 6.5)

### 5.3 Server-side cleanup (LOW PRIORITY)

- Delete old xray config backups in
  `/usr/local/etc/xray/config.json.bak.*` once the new setup has run
  stable for ≥ 24 hours (the operator was iterating before; many
  obsolete `.bak` files left)
- Delete `/root/dreammaker-backups/` files after the same grace period
- Decide what to do with `/root/cert.crt` (no-SAN self-signed; now
  unreferenced by nginx). Either delete or move to backup.
- The `xray-ws` site for the apex domain still serves a camouflage
  page; consider whether the apex even needs nginx at all (could be
  removed and apex DNS could point at xray Reality directly).

### 5.4 Cloudflare bootstrap token (NICE TO HAVE)

To enable the `42-cloudflare-mint.sh` self-cleaning automation, a single
bootstrap token with these **exact** scopes is needed:

- `User → API Tokens → Edit` (so the token can mint + revoke child tokens)
- `User → User Details → Read` (required by some `/user/*` paths)

Generate at <https://dash.cloudflare.com/profile/api-tokens> → Create
Token → Custom token. TTL 5–15 minutes is sufficient.

If you have this token, run:

```bash
export CF_APPLY_CONFIRM=YES
export CF_BOOTSTRAP_TOKEN=cfut_<the-bootstrap>
sudo bash scripts/42-cloudflare-mint.sh
```

The script will mint a 15-min zone-scoped child, run apply with it,
revoke via `trap EXIT`. Bootstrap token never touches disk.

### 5.5 Client-side validation (RECOMMENDED)

Test each generated v2ray share-link in real client apps:
- v2rayN (Windows)
- v2rayNG (Android)
- Nekoray (cross-platform)
- Shadowrocket (iOS)

The links are in `tmp/clients/links.txt` after running
`scripts/70-client-config.sh` locally.

### 5.6 Optional: regenerate Reality private key

In `xray/config.json`, every Reality inbound has a `privateKey` field.
If you suspect the keys leaked (they were in initial config dumps in
chat), regenerate:

```bash
xray x25519
# Use the generated Private/Public keys to update xray/config.json.
# Distribute the new public key to clients via updated share-links.
systemctl restart xray
```

---

## 6. Step-by-step action plan for the next session

### 6.1 Verify nothing has regressed

```bash
cd /workspace
cp config.env.example config.env
sed -i 's#^CF_API_TOKEN=.*#CF_API_TOKEN="<TOKEN_C>"#' config.env

# Cloudflare side:
bash scripts/40-cloudflare.sh
# Should print: [OK] All readable Cloudflare settings match expected state.

# Server side (requires sshpass):
SSH_PASSWORD="<password>" bash bin/run-ssh.sh recon
# Should show xray + nginx active, ports 2052/2082/2086/8880 listening,
# port 443 owned by xray.
```

### 6.2 If credentials have been rotated, update `config.env`

After the operator rotates tokens, update the local config:
```bash
sed -i 's#^CF_API_TOKEN=.*#CF_API_TOKEN="<NEW_TOKEN>"#' config.env
```
And re-run the verifier in 6.1.

### 6.3 Run end-to-end probe (will hit Cloudflare edge)

```bash
SSH_PASSWORD="<password>" bash bin/run-ssh.sh probe
```
Expected: 3 endpoints HTTP 101, xhttp endpoint HTTP 400 (probe limitation).

### 6.4 Generate fresh client configs

```bash
bash scripts/70-client-config.sh
cat tmp/clients/links.txt
```
Outputs in `tmp/clients/`:
- `reality.json` — Reality on :443 direct to IP
- `vless-ws-cdn.json` — VLESS WS via CDN :2086
- `vmess-ws.json` — VMess WS via CDN :2082
- `trojan-ws.json` — Trojan WS via CDN :2052
- `xhttp.json` — VLESS XHTTP via CDN :8880
- `wss-cdn.json` / `grpc-cdn.json` — legacy CF-edge-fix variants

### 6.5 (Optional) Set up SSH key auth

If we want future agent sessions to use key auth:

```bash
# Locally (or in CI):
ssh-keygen -t ed25519 -f ~/.ssh/dreammaker_agent -N "" -C "cursor-agent@dreammaker"

# On the server (one-off, while password auth still works):
SSH_PASSWORD="<password>" sshpass -e ssh root@82.115.26.105 \
  "mkdir -p ~/.ssh && chmod 700 ~/.ssh"
ssh-copy-id -i ~/.ssh/dreammaker_agent.pub root@82.115.26.105

# Save private key as a Cursor Secret named DREAMMAKER_SSH_KEY.
# Future agent runs:
echo "$DREAMMAKER_SSH_KEY" > /tmp/key && chmod 600 /tmp/key
SSH_KEY=/tmp/key bash bin/run-ssh.sh recon
```

### 6.6 (Optional) Apply Cloudflare changes if tokens are rotated

```bash
export CF_APPLY_CONFIRM=YES
export CF_API_TOKEN="<new Token C>"
bash scripts/41-cloudflare-apply.sh        # 8 settings + DNS
bash scripts/44-cloudflare-pagerule-cache.sh # cache bypass page rule
bash scripts/40-cloudflare.sh              # re-verify
```

### 6.7 (Operator) Rotate everything

A suggested checklist for the operator (not the agent):

```bash
# 1. SSH password
passwd root  # or use chpasswd; then test login from elsewhere before logging out

# 2. SSH key auth
echo "<new-public-key>" >> /root/.ssh/authorized_keys
# Test key auth in a separate window before disabling password auth.
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart sshd

# 3. Cloudflare tokens — go to https://dash.cloudflare.com/profile/api-tokens
# Delete the 4 old ones, create new with same scopes (or use Token C's
# scope set as the baseline).

# 4. Trojan password — edit xray/config.json
# Find the trojan inbound's clients[0].password, change to a strong value.
xray test -config /usr/local/etc/xray/config.json
systemctl restart xray
# Update clients/v2ray-trojan-ws.tpl.json's V2_TROJAN_PASSWORD too.

# 5. Reality keys (if paranoid)
xray x25519  # outputs Private + Public keys
# Update xray/config.json's realitySettings.privateKey for each
# Reality inbound. Public key must be distributed to clients.
xray test ... && systemctl restart xray
```

---

## 7. All credentials and access info

> **🚨 Every value here was transmitted in chat and should be considered
> compromised. Rotate before relying on this server in production.**

### 7.1 SSH

| Field | Value |
|---|---|
| Host | `82.115.26.105` |
| Port | 22 |
| User | `root` |
| Password | (transmitted in chat — see ticket / chat history; rotate on first action) |
| Hostname | `srv6601629178` |

> The original password was a 10-digit weak placeholder. **It must be
> rotated on first contact**; the operator was explicitly informed.
> Look in the conversation/ticket that produced this branch for the
> initial value if needed.

Auth methods supported: `publickey, password`. Currently no
`~/.ssh/authorized_keys` for root.

### 7.2 Cloudflare API tokens

| Token | ID | Suffix | Edit scopes |
|---|---|---|---|
| A | `0925a360b4d3f80a6aca0bb5f4cb3775` | `…099f7c8c` | (none) |
| B | `bc0dcc003ae8df152edf5611e54be482` | `…8f00c303` | (none) |
| **C** | **`fb2d708e06a969c15a29e65422153dee`** | **`…5929bbfa`** | **Zone Settings:Edit, DNS:Edit, Page Rules:Edit** |
| D | `d4ef5988683011e616cf1f2b47dbbb55` | `…f7122c5b` | DNS read partial |

**Full token strings are intentionally not committed to the repo.**
GitHub Push Protection (correctly) rejects them. Each token is uniquely
identified by:

- the **token id** in the table above, and
- the **last 8 characters** of the token (the suffix).

If the next session needs the full token strings, retrieve them from:

1. **the chat / Linear ticket / where the operator originally shared
   them** — search for `cfut_` on the conversation that produced this
   branch, OR
2. **`/etc/environment` or `/root/.bashrc` on the server** — if the
   operator set them there (none are stored there as of this writing,
   but the operator may store the rotated replacement there for future
   automation), OR
3. **the Cloudflare dashboard** — visit
   <https://dash.cloudflare.com/profile/api-tokens>, find the token by
   its id, and rotate it via "Roll Token". Take the new value and put
   it in `config.env` (gitignored).

The token-test snippet in Appendix B works for whatever token you have.

### 7.3 Cloudflare zone

| Field | Value |
|---|---|
| Account/zone domain | `dreammaker-groupsoft.ir` |
| Zone ID | `7521f025c7660ad0f5ab6c57d787fa6f` |
| Page Rule for cache bypass | id `b6fdf7355ecfbbcb44355cb09aca997e`, status `active`, cdn.*/* → cache_level=bypass |

### 7.4 v2.0 protocol identities — LIVE (verified 2026-04-25T07:08Z)

These are reproduced in `config.env.example` (committed). They are the
public-facing knobs every client config needs.

> **Note**: Earlier versions of `config.env.example` had **incorrect**
> example values copied from the v2.0 deployment guide. The values
> below are the actual live values on the server — verified by reading
> `/usr/local/etc/xray/config.json` over SSH. Any client config or
> share-link generated before commit `f60bbc4` (2026-04-25) used the
> wrong UUID/keys and would fail authentication.

| Field | Value | Sensitivity |
|---|---|---|
| Primary UUID (Reality + CDN, all inbounds) | `13e8b080-6162-4d51-98e4-67611aa5f7f0` | rotate if leak suspected |
| Reality public key | `oBavVYJOvTk1jhyAL6m8yDGCksDA1vhY7q4VyZypkUM` | public; safe to commit |
| Reality private key (server-side) | `6H1sXCkdhMzYCyrcFDbkViy92KslvB22zJuVsnC6rWg` | **secret**; on server only |
| Reality short ID | `5dadd144264d28c4` | public-ish; safe to commit |
| Default Reality SNI for client | `www.digikala.com` (apex 443) | rotates per-port |
| Trojan password (shared :2087 + :2052) | `dlB9unRG/vA26ERwJHehHA==` | **secret** |
| Shadowsocks method | `2022-blake3-aes-128-gcm` | public |
| Shadowsocks password | `dlB9unRG/vA26ERwJHehHA==` (same as Trojan) | **secret** |
| gRPC service name | `dreammaker-grpc` | safe |
| Reality+XHTTP path (port 2095) | `/r` | safe |
| CDN WS paths | `/ws-vless` `:2086`, `/ws-vmess` `:2082`, `/ws-trojan` `:2052` | safe |
| CDN XHTTP path | `/xhttp-cdn` `:8880` | safe |

The Reality **private key** is on the server. It was visible in earlier
config dumps in this conversation; **consider regenerating** with
`xray x25519`. After regenerating, every client must be updated with
the new public key.

### 7.5 CF-edge-fix UUID (separate identity for the WSS:2083/gRPC:2053 attempts; now historical)

A different UUID and Reality keypair were used in the earliest task
(when we were planning to run `nginx WSS:2083 → xray :8880`, before
discovering xray already binds those ports). These are still present in
`config.env.example` so the legacy `wss-cdn.json` / `grpc-cdn.json`
client templates still render. They are **not** the live identity used
by the active xray inbounds.

Look for the exact values in `config.env.example` (committed); they
won't be reprinted here.

---

## 8. File locations

### 8.1 Repository (`/workspace`)

```
.
├── bin/
│   ├── run-all.sh          # local full pipeline
│   ├── run-remote.sh       # rsync + SSH wrapper
│   └── run-ssh.sh          # SSH with key or password env auth
├── lib/
│   └── common.sh           # logging, config loader, helpers
├── scripts/
│   ├── 10-ssl-cert.sh
│   ├── 20-nginx-wss.sh
│   ├── 30-xray-grpc-inbound.sh
│   ├── 31-nginx-grpc.sh
│   ├── 40-cloudflare.sh           # read-only verifier
│   ├── 41-cloudflare-apply.sh     # opt-in: CF settings + DNS
│   ├── 42-cloudflare-mint.sh      # mint→apply→revoke (needs bootstrap token)
│   ├── 43-ssl-expand.sh           # expand LE cert SAN
│   ├── 44-cloudflare-pagerule-cache.sh  # opt-in: Page Rule cache bypass
│   ├── 50-links.sh                # append vless links to credentials file
│   ├── 60-status.sh               # local snapshot
│   ├── 61-edge-probe.sh           # external multi-protocol probe
│   └── 70-client-config.sh        # render v2ray JSON + links from templates
├── clients/
│   ├── v2ray-reality.tpl.json     # 7 v2ray client templates
│   ├── v2ray-vless-ws-cdn.tpl.json
│   ├── v2ray-vmess-ws.tpl.json
│   ├── v2ray-trojan-ws.tpl.json
│   ├── v2ray-xhttp.tpl.json
│   ├── v2ray-wss-cdn.tpl.json
│   └── v2ray-grpc-cdn.tpl.json
├── templates/
│   ├── xray-wss.conf.tpl
│   └── xray-grpc.conf.tpl
├── docs/
│   ├── CLOUDFLARE-MANUAL.md       # dashboard fallback
│   ├── DEPLOYMENT-GUIDE-v2.md     # full v2.0 runbook
│   ├── LIVE-SERVER-RECON.md       # initial recon snapshot
│   ├── RUN-LOG-2026-04-25.md      # SSH-driven fix session
│   └── HANDOFF.md                 # this file
├── config.env.example             # all tunables; copy to config.env (gitignored)
├── tmp/                           # gitignored: rendered configs, backups, probes
└── README.md
```

### 8.2 Server (`82.115.26.105`)

```
/usr/local/etc/xray/
├── config.json                   # active xray config (POST-FIX)
├── config.json.bak.20260423_*    # 17 rolling backups, oldest from Apr 23
├── config.json.bak.20260424_*    # operator was iterating here
├── self.crt + self.key           # internal xray cert?
├── users.json                    # 15-user database
└── assets/                       # geosite, geoip data files

/etc/nginx/
├── sites-available/
│   ├── cdn                       # POST-FIX: :80 only, camouflage
│   ├── xray-fallback             # 127.0.0.1:8080 default_server camouflage
│   └── xray-ws                   # POST-FIX: :80 apex camouflage + /health
├── sites-enabled/                # symlinks to sites-available/

/etc/letsencrypt/
└── live/dreammaker-groupsoft.ir/
    ├── fullchain.pem             # apex + cdn.* SAN (UNUSED but valid)
    └── privkey.pem

/root/
├── cert.crt                      # CN=cdn.* self-signed, no SAN, UNUSED post-fix
├── private.key                   # for cert.crt
├── nginx-cdn-20260425_044640Z.bak  # rolled-back tentative cert change
└── dreammaker-backups/
    ├── xray-config.json.20260425_050314Z   # pre-B2 backup
    ├── nginx-cdn.20260425_050314Z          # pre-A1 backup
    ├── nginx-xray-ws.20260425_050314Z      # pre-C backup
    ├── cert.crt.20260425_044640Z
    └── private.key.20260425_044640Z
```

### 8.3 Rollback recipes (if anything goes wrong)

```bash
# Rollback xray config (B2):
cp /root/dreammaker-backups/xray-config.json.20260425_050314Z \
   /usr/local/etc/xray/config.json
xray test -config /usr/local/etc/xray/config.json
systemctl restart xray

# Rollback nginx cdn site (A1):
cp /root/dreammaker-backups/nginx-cdn.20260425_050314Z \
   /etc/nginx/sites-available/cdn
nginx -t && systemctl reload nginx

# Rollback nginx xray-ws site (C):
cp /root/dreammaker-backups/nginx-xray-ws.20260425_050314Z \
   /etc/nginx/sites-available/xray-ws
nginx -t && systemctl reload nginx
```

---

## 9. Expected final state (where we should be after the optional steps in §5)

After the operator does §5.1–§5.5:

### 9.1 Cloudflare zone (already there)

```
[OK] websockets, http3, 0rtt, ssl=full, min_tls=1.2, tls_1_3=zrt
[OK] always_use_https=off, automatic_https_rewrites=off
[OK] DNS cdn.* → 82.115.26.105, Proxied
[OK] Page Rule cdn.dreammaker-groupsoft.ir/* → cache_level=bypass [active]
```

### 9.2 Server (already there)

- xray active, 10 inbounds healthy
- nginx active, only `:80` and `:8080` (no `:443` bind attempt)
- Reality on `:443` works for all 27 SNIs
- 4 CDN inbounds answer 101/400 through Cloudflare:
  - `:2086` /ws-vless → 101
  - `:2082` /ws-vmess → 101
  - `:2052` /ws-trojan → 101
  - `:8880` /xhttp-cdn → 400 (alive)

### 9.3 Credentials (after operator rotates)

- SSH: key-only, password disabled, dedicated `dreammaker_agent` key
- Cloudflare: 4 tokens replaced; Token C-equivalent has Zone
  Settings:Edit + DNS:Edit + Page Rules:Edit only (least-privilege for
  what the app needs)
- Trojan password: strong (≥ 16 chars)
- Reality keys: regenerated; clients updated with new public key

### 9.4 Operational

- v2ray client links from `tmp/clients/links.txt` work in v2rayN /
  v2rayNG / Nekoray (5 protocols all green)
- Reality clients use direct IP `82.115.26.105:443` with SNI
  `www.digikala.com` (or any of the other 26 from the rotation)
- CDN clients use `cdn.dreammaker-groupsoft.ir` on the appropriate
  port (2052/2082/2086/8880)
- Cloudflare automation pipeline can re-run idempotently after any
  drift; the verifier reports green every time

---

## Appendix A — Short cheatsheet for the next agent

```bash
cd /workspace
git status                                    # branch should be cursor/dreammaker-cf-edge-fix-app-499a

# Read-only health check (no auth needed):
ls scripts/                                   # know your tools

# With Cloudflare token C (full string lives outside the repo):
cp config.env.example config.env
# Edit config.env and paste the cfut_… token after CF_API_TOKEN=
# Or:
#   sed -i "s#^CF_API_TOKEN=.*#CF_API_TOKEN=\"$CF_TOKEN\"#" config.env
bash scripts/40-cloudflare.sh                 # should print "All readable Cloudflare settings match expected state"

# With SSH password (or use SSH_KEY=...):
export SSH_PASSWORD="<password from operator / ticket>"
bash bin/run-ssh.sh recon   # safe inventory dump
bash bin/run-ssh.sh probe   # external probe

# Generate v2ray client configs:
bash scripts/70-client-config.sh
cat tmp/clients/links.txt                     # share-links to copy into clients

# If operator approves further mutations:
export CF_APPLY_CONFIRM=YES
SSH_PASSWORD="..." bash bin/run-ssh.sh cf-apply
SSH_PASSWORD="..." bash bin/run-ssh.sh cf-pagerule
```

## Appendix B — Quick token-test snippet

```bash
T="$CF_API_TOKEN"   # set this from the Cloudflare dashboard or your secrets store
curl -sS https://api.cloudflare.com/client/v4/user/tokens/verify \
  -H "Authorization: Bearer $T" | python3 -m json.tool
```

Should return `success: true` with `status: active`. If you see
`code: 1000 Invalid API Token`, the token has been rotated and `config.env`
needs to be updated.

## Appendix C — Quick SSH-test snippet

```bash
sshpass -e ssh -o StrictHostKeyChecking=accept-new \
  -o ConnectTimeout=8 root@82.115.26.105 \
  'systemctl is-active xray && systemctl is-active nginx'
```

Set `SSHPASS` in env first (export from your secrets store, never
inline). Should return `active\nactive`. If you see `Permission denied`,
the password has been rotated — check with the operator for the new one
or use the dedicated SSH key from Cursor Secrets if set up.

---

*End of handoff document. Good luck to the next session.*

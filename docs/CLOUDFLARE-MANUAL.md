# Cloudflare — dashboard checklist (manual or automated)

By default, this app's `bin/run-all.sh` **never modifies** Cloudflare
settings — `scripts/40-cloudflare.sh` only reads current state and
reports drift. Use this checklist to apply every gap by hand.

Two opt-in automation modes exist if you'd rather not touch the
dashboard:

| Script | Token requirement | What it does |
|---|---|---|
| `scripts/41-cloudflare-apply.sh` | `CF_API_TOKEN` with `Zone Settings:Edit` + `DNS:Edit` + `Cache Rules:Edit` | PATCHes/POSTs/PUTs to converge the zone to `CF_EXPECT_*` in `config.env`. Requires `CF_APPLY_CONFIRM=YES`. |
| `scripts/42-cloudflare-mint.sh` | `CF_BOOTSTRAP_TOKEN` with `User → API Tokens → Edit` | Mints a 15-minute zone-scoped child token, runs apply with it, then revokes the child via a `trap EXIT` (always, even on apply failure). |

The rest of this document is the manual fallback.

> If you want the read-only verification output, export a token as
> `CF_API_TOKEN` in `config.env` (or in the environment) before running
> `scripts/40-cloudflare.sh`. The token is used only for `GET` calls against
> the Cloudflare API.
>
> For full visibility the token needs these **read-only** permissions on the
> `dreammaker-groupsoft.ir` zone:
>
> - `Zone → Zone → Read`
> - `Zone → Zone Settings → Read` (for the WebSocket setting check)
> - `Zone → Cache Rules → Read` (for the cache-rule check)
>
> A token with only `Zone:Read` scope can resolve the zone id but the
> WebSocket and Cache-Rules checks will report `10000: Authentication error`
> — this is expected and surfaces as a warning, not a failure.
>
> See `docs/DEPLOYMENT-GUIDE-v2.md` for the full v2.0 deployment runbook
> (Reality, WS+CDN, VMess, Trojan, XHTTP, Outline) that this checklist is
> the Cloudflare half of.

---

## 1. DNS

- **Dashboard → DNS → Records**
- Ensure there is an `A` record named `cdn` pointing at `82.115.26.105`.
- **Proxy status**: *Proxied* (orange cloud).

## 2. SSL/TLS

- **SSL/TLS → Overview**
  - Mode: **Full** (or **Full (strict)** if origin cert chains validate).
- **SSL/TLS → Edge Certificates**
  - Minimum TLS Version: **TLS 1.2**.
  - TLS 1.3: **On**.
  - Always Use HTTPS: **Off** (the v2.0 stack uses plaintext WS on :80).
  - Automatic HTTPS Rewrites: **Off**.

## 3. Network

- **WebSockets**: **On** (critical — without this WSS via the edge fails)
- **HTTP/2**: **On**
- **HTTP/3 (QUIC)**: **On**
- **0-RTT Connection Resumption**: **On**
- **gRPC**: **On**

## 4. Caching — Cache Rules

Create a new cache rule to prevent CF from buffering WebSocket / SSE chunks:

- **Dashboard → Caching → Cache Rules → Create rule**
- **Name**: `Bypass Xray WebSocket`
- **When incoming requests match…**
  - Field: **Hostname**
  - Operator: **equals**
  - Value: `cdn.dreammaker-groupsoft.ir`
- **Then** → *Cache eligibility* → **Bypass cache**.
- Save and deploy.

## 5. Security (optional, recommended)

- **Security → WAF → Tools → IP Access Rules** — if geo-blocking is enabled,
  make sure Iran is allowed (or loosen to `Challenge` instead of `Block` for
  the CDN subdomain).
- **Security → Settings → Browser Integrity Check**: **Off** for the CDN
  subdomain if users see challenge pages on WebSocket upgrade.

## 6. Verification after changes

From a workstation with `curl`:

```bash
# Should return 101 Switching Protocols via the CF edge:
curl -sk -o /dev/null -w "%{http_code}\n" --max-time 7 \
  -H "Upgrade: websocket" -H "Connection: Upgrade" \
  -H "Sec-WebSocket-Version: 13" \
  -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
  https://cdn.dreammaker-groupsoft.ir:2083/

# gRPC liveness (200/400/415 all mean "port alive"):
curl -sk -o /dev/null -w "%{http_code}\n" --max-time 7 \
  https://cdn.dreammaker-groupsoft.ir:2053/dreammaker-grpc
```

Then re-run the app's verifier on the server to snapshot service+port+probe
state:

```bash
sudo bash scripts/60-status.sh
```

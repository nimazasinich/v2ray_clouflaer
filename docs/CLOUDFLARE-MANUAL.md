# Cloudflare — manual dashboard checklist

This app **never modifies** Cloudflare settings. `scripts/40-cloudflare.sh`
only reads current state (when a token is provided) and prints this
checklist. Apply every step manually in the Cloudflare Dashboard on the
`dreammaker-groupsoft.ir` zone.

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

---

## 1. DNS

- **Dashboard → DNS → Records**
- Ensure there is an `A` record named `cdn` pointing at `82.115.26.105`.
- **Proxy status**: *Proxied* (orange cloud).

## 2. SSL/TLS

- **SSL/TLS → Overview**
  - Mode: **Full** (or **Full (strict)** if origin cert chains validate).
- **SSL/TLS → Edge Certificates**
  - Minimum TLS Version: **TLS 1.2** (1.3 preferred).
  - Always Use HTTPS: **On**.
  - Automatic HTTPS Rewrites: **On**.

## 3. Network — WebSockets (CRITICAL)

- **Dashboard → Network → WebSockets**
- Toggle must be **On**.
- If it is off, WSS on `:2083` will not work through the edge even if origin
  returns 101.

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

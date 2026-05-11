# DreamMaker Infrastructure — Context & Handoff Reference

**Domain:** `dreammaker-groupsoft.ir`  
**CDN Subdomain:** `cdn.dreammaker-groupsoft.ir`  
**Clean Subdomain:** `clean.dreammaker-groupsoft.ir`  
**Last Updated:** `2026-05-09`  
**Purpose:** A polished handoff document for future sessions. Use this file to resume work without re-discovering the current architecture, visual design rules, or remaining deployment tasks.

---

## 1) Executive Summary

The current build should be treated as a **clean rebuild** with a hardened edge layer and no public Xray listeners.

### Target architecture

```text
Client
  → Cloudflare Edge :443
  → Nginx :443
  → Local WebSocket / gRPC inbound
  → Xray bound to 127.0.0.1 only
```

### Design priorities

1. **Stability first**
2. **Real latency / real throughput**
3. **Minimal public exposure**
4. **Clean client UX**
5. **Visual polish in subscription labels**
6. **Conservative filtering** (avoid breaking video/CDN playback)

---

## 2) Server Identity

| Field | Value |
|---|---|
| Public IP | `82.115.26.105` |
| Primary domain | `dreammaker-groupsoft.ir` |
| CDN subdomain | `cdn.dreammaker-groupsoft.ir` |
| Clean subdomain | `clean.dreammaker-groupsoft.ir` |
| OS | Ubuntu LTS |
| Panel | X-UI |
| Core | Xray-core `v26.4.25` |

---

## 3) Confirmed Network Reality

### Publicly reachable ports

| Port | Status | Notes |
|---|---:|---|
| 80/tcp | Open | Reaches Nginx |
| 443/tcp | Open | Reaches Nginx + TLS |

### Provider-level behavior

The provider/datacenter silently drops most non-standard public ports externally.

Do **not** assume public reachability of:
- `22`
- `8080`
- `8000`
- `8880`
- `2082`
- `2086`
- `2092`
- `2053–2096` style alternate ports

### Important implication

Xray and management services should **not** rely on public custom ports.  
The only safe public ingress should be standard web ports.

---

## 4) Cloudflare Status

### Intended Cloudflare settings

| Setting | Value |
|---|---|
| SSL/TLS mode | **Full (strict)** |
| WebSocket | Enabled |
| HTTP/2 | On |
| HTTP/3 | On only if stable |
| Proxy | Orange-cloud on production origin |

### Traffic flow

```text
Client → Cloudflare Edge :443 → Origin Nginx :443 → Local Xray
```

### Operational note

Cloudflare should be used as the public edge only.  
The origin should remain simple, predictable, and easy to audit.

---

## 5) Current Software Stack

| Component | Notes |
|---|---|
| Nginx | Public edge on `0.0.0.0:80` and `0.0.0.0:443` |
| X-UI | Xray manager |
| Xray-core | `v26.4.25` |
| X-UI API | Internal only |
| Xray metrics | Internal only |
| WARP / egress proxy | Optional internal component, if still required |

### Core rule

Xray must **never** compete with Nginx for public ports.  
Any Xray config listening on `0.0.0.0:80` or public 443 must be considered invalid in the new architecture.

---

## 6) Visual Presentation Goals

This project is not only about connectivity. The client experience should also feel polished.

### What the user should see in apps

- Clean tier names
- Small, consistent emoji markers
- Clear separation between tiers
- Elegant naming for CDN / TLS variants
- No debug-like text
- No technical clutter in the visible label

### Recommended naming style

Keep each display name short and elegant:

- `🔵 DreamMaker | Starter | CDN`
- `🟢 DreamMaker | Basic | TLS`
- `⚡ DreamMaker | Standard | Hybrid`
- `🚀 DreamMaker | Plus | Premium`
- `💫 DreamMaker | Pro | TLS`
- `🔥 DreamMaker | Elite | CDN`
- `💎 DreamMaker | Unlimited | Priority`

### UX rules for the client list

- One emoji per tier
- One clear speed/value hint per label
- Same naming pattern across all apps
- Use short tier wording
- Keep the list visually calm and premium
- Avoid technical fragments in the title
- Do not show path details in the visible name unless necessary

### Good visual behavior in V2Ray-family apps

When imported into V2RayNG / V2Box / Hiddify / NekoBox / V2RayN:
- the server list should look organized
- premium tiers should feel premium
- test entries should not look like test entries
- the user should be able to identify plans at a glance

---

## 7) Xray Design Rules

### Required rule

All Xray inbounds must listen on:

```text
127.0.0.1 only
```

Never bind public Xray inbounds to `0.0.0.0` in the new model.

### Recommended transport choices

- WebSocket
- gRPC

### Avoid

- public direct listeners
- port collisions with Nginx
- duplicate public inbounds
- exposed panel-driven ports

### Deployment principle

Nginx is the public front door.  
Xray stays hidden behind it.

---

## 8) Nginx Design Rules

### Nginx responsibilities

- TLS termination
- HTTP → HTTPS redirect
- WebSocket / gRPC reverse proxy
- rate limiting
- Cloudflare real-IP restoration
- fail-closed behavior on unknown paths

### Public posture

| Port | Role |
|---|---|
| 80 | Redirect only |
| 443 | Primary entrypoint |

### Security posture

- `server_tokens off`
- minimal error leakage
- strict TLS
- controlled paths
- rate limiting
- Cloudflare headers trusted correctly
- no public Xray bind on shared ports

### Routing pattern

Each public path should route to one local internal inbound:

```nginx
location /some-path {
    proxy_pass http://127.0.0.1:11001;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_read_timeout 300s;
}
```

---

## 9) Tier Registry

### Active tiers

| Tier | UUID | Local Port | Public Path | Limit |
|---|---|---:|---|---:|
| Starter | `7dd47c02-8dce-4b12-9dbc-7cdb95a9e10e` | `11001` | `/api/v1/ping` | 1 GB |
| Basic | `92ebaa01-ec34-4601-a4dc-f6afdf822966` | `11002` | `/cdn/init` | 2 GB |
| Standard | `3d5e3adf-0912-4c78-9ca9-b87db334ce71` | `11003` | `/app/sync` | 5 GB |
| Plus | `e8eb3d74-8e8c-4903-b878-8feb656ebb0c` | `11004` | `/api/v2/feed` | 10 GB |
| Pro | `b3540a54-67dd-452a-b5d8-45d6407b8da5` | `11005` | `/static/bundle.js` | 15 GB |
| Elite | `2680152c-0dc3-4fdb-b366-e936358b121f` | `11006` | `/media/stream` | 20 GB |
| Unlimited | `89c0f294-3f94-4735-96cf-9c1aefdbcbb2` | `11007` | `/v2/content/live` | Unlimited |

### Path disguise rule

Paths should look like legitimate application or CDN endpoints.  
They should not look like obvious VPN paths.

---

## 10) Client Config Format

### General concept

Each tier should be exportable as:
- a VLESS URI
- a base64-encoded subscription entry
- a clean visible label for import into apps

### Display string goals

The visible name should be:
- short
- attractive
- consistent
- easy to compare
- easy to trust

### Suggested label style

- `🔵 DreamMaker | Starter | CDN`
- `🟢 DreamMaker | Basic | TLS`
- `⚡ DreamMaker | Standard | Hybrid`
- `🚀 DreamMaker | Plus | Premium`
- `💫 DreamMaker | Pro | TLS`
- `🔥 DreamMaker | Elite | CDN`
- `💎 DreamMaker | Unlimited | Priority`

### Presentation priority

The visible list should feel:
- neat
- premium
- non-technical
- not overloaded
- pleasant for buyers

---

## 11) Visual Improvements Requested

The subscription and app presentation should be improved beyond raw connectivity.

### Desired visual behavior

- More elegant labels
- Better emoji balance
- Stronger premium feel for higher tiers
- Clear distinction between low / mid / high tiers
- A calm, polished list in apps
- Minimal technical noise

### Suggested visual pattern

| Tier group | Visual character |
|---|---|
| Starter / Basic | simple, clean, low-friction |
| Standard / Plus | balanced, modern |
| Pro / Elite | premium, stronger identity |
| Unlimited | highest-priority visual tier |

### What to avoid

- verbose labels
- duplicate visible names
- overly technical fragments
- debug-style wording
- too much protocol detail in the title

---

## 12) Legacy Customer Data

Old customer records were tied to blocked or retired ports.  
They should not be reused as-is.

### Legacy mapping

| Old Customer | UUID | Old Ports | Previous Path |
|---|---|---|---|
| Customer 1 | `6b529aac-012a-4363-88e7-51b26e6072e8` | 80 | `/api/v2/sync` |
| Customer 2 | `9fd77a9a-08a2-4a8c-88ba-0e0a4a30da66` | 8080, 8000, 2082 | `/cdn/res/bundle` |
| Customer 3 | `75c604fc-8f65-4201-9902-8de1d407edb5` | 8080 | `/app/check` |
| Customer 4 | `85526724-f667-4243-a58d-7cd3cb8b8997` | 2092 | `/v1/feed/list` |
| Customer 5 | `e2a5e62c-4a0b-4d2d-a10a-b4a13d06a0a9` | 8880 | `/static/app.min.js` |
| Customer 6 | `045319fd-9f1d-4d05-b5ad-46949a8b6ea5` | 2086 | `/api/notify/push` |
| Customer 7 | `c4ba6ae4-94be-4752-ae77-76f36154e737` | 2086 | `/media/stream/init` |

### Recommended handling

- retire them
- or migrate them into the new tier system
- do not keep them on dead public ports

---

## 13) Security Principles

- Public Xray listeners should not exist.
- Nginx should be the only public front door.
- Paths are part of the access pattern.
- Unexpected requests should fail closed.
- The panel must not be publicly exposed unless specifically protected.
- Cert renewal should remain automatic.
- Any WARP / outbound proxy component should stay local-only.
- Avoid routing loops.
- Avoid filtering that degrades video playback or CDN behavior.

---

## 14) Routing and DNS Behavior

### Intended DNS chain

- Local / regional resolvers may be used for `.ir` and local-domain routing.
- Cloudflare DoH may be used for external resolution.
- Fallback resolvers may exist.
- Local `localhost` resolution may be part of the chain.

### Routing goals

The routing model should:
- keep private IPs blocked
- keep torrent traffic blocked
- keep ad/tracker traffic conservative
- keep CDN and media playback stable
- avoid breaking YouTube or local video services

### Important caution

If any filtering starts affecting media playback or CDN access, relax the filter rather than making it more aggressive.

---

## 15) Done vs Pending

### Done

- New architecture planned
- Old public bands removed
- Context file prepared
- Branding and tier model defined
- Nginx/Xray direction established

### Pending

- Deploy the final Nginx configuration
- Deploy the final Xray configuration
- Ensure no public Xray listeners remain
- Recreate tier inbounds on localhost only
- Rebuild client subscriptions
- Verify visual labels in apps
- Confirm WARP status if still needed
- Run internal audit from the server console if required

---

## 16) Next Session Tasks

1. Confirm Nginx is the only public listener on 80/443.
2. Confirm Xray listens only on `127.0.0.1`.
3. Rebuild or re-import tier inbounds on internal ports `11001–11007`.
4. Map each Nginx path to its matching local Xray inbound.
5. Re-validate Cloudflare settings.
6. Verify the X-UI panel is either local-only or explicitly protected.
7. Generate clean client bundles and labels.
8. Confirm media and CDN playback remain stable.
9. Avoid aggressive filtering unless absolutely required.
10. Prefer quality and stability over “smart” but fragile optimizations.

---

## 17) Final Product Philosophy

**Quality first. Stability second. Visual polish third. Filtering last.**

The system should feel:
- reliable
- premium
- simple to operate
- visually well-branded
- safe under restrictive network conditions
- easy to resume in future sessions

---

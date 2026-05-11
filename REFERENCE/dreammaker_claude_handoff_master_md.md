# DreamMaker Infrastructure — Professional Master Handoff

> **Purpose:** A polished engineering handoff for future AI sessions.  
> **Mission:** Move the current setup from a fragmented, conflict-prone state into a stable, premium, low-latency infrastructure that survives severe filtering, preserves media/CDN compatibility, and looks clean inside client apps.

---

## 0) Where We Are Going

The current system is being transformed from:

- scattered public listeners
- repeated port conflicts
- fragile transport assumptions
- inconsistent client presentation
- overly complex filtering ideas

into:

- a single public edge on **80/443**
- **Nginx** as the only public entrypoint
- **Xray** bound only to `127.0.0.1`
- conservative routing
- stable fallback behavior
- premium-looking client branding
- minimal breakage under aggressive censorship

### Transformation goal

```text
Current state
  → inconsistent / partially public / conflict-prone

Target state
  → Cloudflare + Nginx + localhost Xray + clean client branding + resilient under heavy filtering
```

### Core principle

**Stability first. Real latency second. Compatibility third. Filtering last.**

---

## 1) Executive Summary

DreamMaker should behave like a premium production system that remains usable under harsh network conditions.

### What the final build must achieve

- keep public exposure minimal
- survive aggressive filtering and DPI
- avoid port conflicts entirely
- preserve YouTube and media playback quality
- keep app subscriptions visually attractive
- remain easy to resume in future sessions

---

## 2) Infrastructure Identity

| Item | Value |
|---|---|
| Main domain | `dreammaker-groupsoft.ir` |
| CDN subdomain | `cdn.dreammaker-groupsoft.ir` |
| Clean subdomain | `clean.dreammaker-groupsoft.ir` |
| Public IP | `82.115.26.105` |
| OS | Ubuntu LTS |
| Reverse proxy | Nginx |
| Panel | X-UI |
| Core | Xray-core `v26.4.25` |
| Edge | Cloudflare |

---

## 3) Current Reality

### Confirmed publicly reachable ports

| Port | Status | Notes |
|---|---:|---|
| 80/tcp | ✅ OPEN | HTTP edge / redirect / compatibility |
| 443/tcp | ✅ OPEN | Main production entrypoint |

### Provider-level behavior

The provider silently drops most non-standard public ports.

Do **not** rely on public reachability for:

- `22`
- `8080`
- `8000`
- `8880`
- `2082`
- `2086`
- `2092`
- `2053–2096` style alternate ports

### Operational consequence

Only **80** and **443** should be treated as reliable public ingress.

---

## 4) Target Architecture

```text
Client
  → Cloudflare Edge :443
  → Nginx :443
  → Local Xray inbound(s)
  → Outbound routing
```

### Required rule

Xray must **never** compete with Nginx for public ports.

Public traffic should always land on Nginx first.

---

## 5) Why Severe Filtering Changes the Design

Under aggressive filtering, the wrong design causes:

- connection drops
- TLS handshake failures
- WebSocket instability
- QUIC throttling
- media buffering
- false latency values
- client reconnect loops
- public port blackholing

### What matters most now

1. **survivability**
2. **real latency**
3. **media/CDN compatibility**
4. **clean fallback behavior**
5. **simple recovery**

### What should stay low priority

- aggressive ad blocking
- deep filtering chains
- over-engineered routing rules
- excessive obfuscation that reduces stability

---

## 6) Cloudflare Strategy

### Intended settings

| Setting | Value |
|---|---|
| SSL/TLS mode | **Full (strict)** |
| WebSocket | Enabled |
| HTTP/2 | Enabled |
| HTTP/3 | Enabled only if stable |
| Proxy | Orange-cloud on production origin |

### Traffic flow

```text
Client → Cloudflare → Nginx → localhost Xray
```

### Operational note

Cloudflare should remain simple:
- edge protection
- TLS fronting
- WebSocket compatibility
- clean origin proxying

The origin should stay predictable and easy to audit.

---

## 7) Nginx Design Rules

### Responsibilities

- TLS termination
- HTTP → HTTPS redirect
- WebSocket / gRPC proxying
- rate limiting
- Cloudflare real IP restoration
- fail-closed behavior on unknown paths

### Public posture

| Port | Role |
|---|---|
| 80 | Redirect only / compatibility |
| 443 | Primary entrypoint |

### Security posture

- `server_tokens off`
- minimal leakage
- strict TLS
- controlled routing
- localhost upstreams only
- no public Xray bind on shared ports

### Reverse-proxy pattern

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

## 8) Xray Design Rules

### Absolute rule

All Xray inbounds must listen on:

```text
127.0.0.1 only
```

Never use `0.0.0.0` for production inbounds.

### Recommended transports

- xhttp
- WebSocket fallback
- gRPC fallback if needed

### Avoid

- public direct listeners
- port collisions with Nginx
- duplicate public inbounds
- exposed panel-driven ports

---

## 9) Transport Strategy

### Current direction

- **Primary:** xhttp
- **Fallback:** websocket
- **Emergency fallback:** gRPC / HTTP2

### Philosophy

The transport stack should optimize for:

- compatibility
- stability
- latency consistency
- survivability under filtering

not unnecessary complexity.

---

## 10) Filtering Strategy

### Current policy

Filtering is intentionally **low priority**.

### Why

Aggressive filtering can break:
- YouTube
- film/series sites
- CDN playback
- login flows
- media chunk delivery
- mobile app telemetry

### Safe policy

Prefer:
- conservative filtering
- minimal false positives
- easy rollback
- no aggressive ad list blocking unless absolutely necessary

### If a filter harms media stability

Rollback it.

### Hard rule

Do **not** build a system that is fast in theory but breaks in the real world.

---

## 11) Visual Branding Goals

The client list inside apps should look:

- premium
- clean
- modern
- balanced
- easy to scan

### What the user should feel

- the plans are organized
- the tiers are distinct
- premium tiers look premium
- the list feels intentionally designed

### What to avoid

- technical clutter
- debug-like names
- repetitive titles
- ugly or inconsistent fragments
- too much protocol detail in the visible label

---

## 12) Recommended Label Style

### Tier labels

- `🔵 DreamMaker | Starter | CDN`
- `🟢 DreamMaker | Basic | TLS`
- `⚡ DreamMaker | Standard | Hybrid`
- `🚀 DreamMaker | Plus | Premium`
- `💫 DreamMaker | Pro | Secure`
- `🔥 DreamMaker | Elite | Priority`
- `💎 DreamMaker | Unlimited | Ultra`

### Good style rules

- short and readable
- one emoji only
- consistent format across all apps
- premium wording for high tiers
- no technical noise in the title

---

## 13) Path Disguise Strategy

Public paths should resemble real application traffic.

### Good examples

- `/api/v1/ping`
- `/cdn/init`
- `/app/sync`
- `/api/v2/feed`
- `/static/bundle.js`
- `/media/stream`
- `/v2/content/live`

### Path design goals

- look like normal API/CDN requests
- avoid obvious VPN naming
- stay consistent with a believable service theme

---

## 14) Tier Registry

| Tier | UUID | Local Port | Public Path | Limit |
|---|---|---|---|---:|
| Starter | `7dd47c02-8dce-4b12-9dbc-7cdb95a9e10e` | `11001` | `/api/v1/ping` | 1GB |
| Basic | `92ebaa01-ec34-4601-a4dc-f6afdf822966` | `11002` | `/cdn/init` | 2GB |
| Standard | `3d5e3adf-0912-4c78-9ca9-b87db334ce71` | `11003` | `/app/sync` | 5GB |
| Plus | `e8eb3d74-8e8c-4903-b878-8feb656ebb0c` | `11004` | `/api/v2/feed` | 10GB |
| Pro | `b3540a54-67dd-452a-b5d8-45d6407b8da5` | `11005` | `/static/bundle.js` | 15GB |
| Elite | `2680152c-0dc3-4fdb-b366-e936358b121f` | `11006` | `/media/stream` | 20GB |
| Unlimited | `89c0f294-3f94-4735-96cf-9c1aefdbcbb2` | `11007` | `/v2/content/live` | Unlimited |

---

## 15) Client Presentation Strategy

The visible client list should be polished enough to feel like a product, not a debug console.

### Recommended look

- use consistent emojis
- keep titles short
- separate entry types visually
- mark premium tiers more elegantly
- keep subscription names friendly

### Better branding examples

- `🚀 DreamMaker Turbo • TLS Edge`
- `🛡 DreamMaker Secure • Stable CDN`
- `⚡ DreamMaker LowPing • H2 Route`
- `🌍 DreamMaker Global • Smart Path`
- `💎 DreamMaker Infinity • Premium Link`

### UX principles

- readable in small app lists
- attractive in V2Ray-family clients
- easy to distinguish at a glance
- no technical overload in visible text

---

## 16) Routing Philosophy

Routing should stay lightweight.

### Priority order

1. stability
2. real throughput
3. low latency
4. compatibility
5. camouflage
6. filtering

### Avoid

- heavy rule chains
- overcomplicated DNS tricks
- wide geo-blocking that breaks services
- unstable optimization attempts

### Safer default

If a rule is not clearly helping stability, do not keep it.

---

## 17) DNS Strategy

The DNS layer should prioritize:

- speed
- stability
- CDN correctness
- media compatibility

### Recommended order conceptually

1. Cloudflare DoH
2. Google DoH
3. Quad9
4. local fallback

### Important

If DNS tuning causes buffering or bad CDN behavior, simplify it.

---

## 18) 3X-UI Deep Review Targets

Research and verify the following inside 3X-UI / Xray management:

- subscription export behavior
- UTF-8 / emoji display consistency
- custom transport support
- fallback transport handling
- per-user inbound mapping
- custom path persistence
- header customization support
- statistics and traffic limit stability
- routing / template behavior

---

## 19) Done / Pending / Risk / Improve

| Area | Status | Notes |
|---|---|---|
| Public port ownership | ⚠️ Needs verification | Nginx should own public 80/443 only |
| Xray localhost binding | ⚠️ Needs verification | Must be 127.0.0.1 only |
| Public public listeners | ✅ Removed conceptually | Old public bands should stay retired |
| Cloudflare edge | ✅ Intended | Full (strict), WS, HTTP/2 |
| Client branding | 🔄 Improve | Make labels more elegant and consistent |
| Filtering policy | 🔄 Keep conservative | Avoid breaking media/CDN playback |
| Path disguise | 🔄 Improve | Make paths look more natural and varied |
| Fallback transport | ⚠️ Needs validation | WS / gRPC fallback should exist |
| WARP / outbound proxy | ⚠️ Needs verification | If used, keep local-only |
| Subscription visuals | 🔄 Improve | Premium feel should be stronger |

---

## 20) Pending Validation Checklist

### Infrastructure

- [ ] confirm Nginx is the only public listener on 80/443
- [ ] confirm Xray listens only on localhost
- [ ] confirm no stale public listeners remain
- [ ] confirm Cloudflare settings are consistent
- [ ] confirm there is no port conflict

### Transport

- [ ] verify xhttp stability
- [ ] verify websocket fallback
- [ ] verify gRPC fallback if needed
- [ ] benchmark reconnect behavior
- [ ] test under heavy filtering conditions

### Branding / UX

- [ ] refine visible tier labels
- [ ] improve emoji hierarchy
- [ ] make premium tiers feel premium
- [ ] keep app list visually clean
- [ ] ensure subscription bundles import cleanly

### Performance

- [ ] measure latency
- [ ] measure packet stability
- [ ] test media playback
- [ ] test CDN access
- [ ] test mobile network behavior

---

## 21) Final Operational Philosophy

Do not over-engineer.

A simple system that stays up is better than a clever system that breaks under pressure.

### Golden rule

If an optimization:
- increases fragility
- worsens playback
- increases reconnect delay
- reduces compatibility
- complicates operations

then it is not a good optimization.

---

## 22) Final Goal

DreamMaker should feel:

- stable
- polished
- premium
- fast
- easy to use
- reliable under restriction

The best architecture is the one that remains usable when the network becomes difficult.


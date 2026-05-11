# DreamMaker Handoff → Implementation Map

This document is the bridge between `DreamMaker_Infrastructure_Handoff_Master_Enriched (1).md` and the deployment bundle in this archive.

## Source of truth

The handoff document defines the final architecture, especially the later sections on DNS resilience, subscription delivery, mobile-network stability, traffic-pattern safety, capacity planning, incident response, and logging policy. Those sections are treated here as operational requirements, not just commentary.

## What is already implemented in this bundle

### Edge / Tier 0
- `edge-worker-tier0.ts`
- `wrangler.toml`

Implements:
- subscription generation at the edge
- tier registry with fixed UUIDs
- XHTTP primary transport plus WebSocket fallback
- health endpoints and cache layers
- per-tier subscription selection
- Cloudflare Worker deployment routing

### Helper / Tier 1
- `helper-ecosystem-tier1.ts`
- generated Tier 1 Wrangler config inside `deploy.sh`

Implements:
- scheduled probing
- edge scoring
- mobile-stability heuristics
- Telegram alerting hooks
- D1 writes for metrics and audit support

### Control plane / Tier 2
- `control-plane-tier2.ts`
- generated Tier 2 Wrangler config inside `deploy.sh`

Implements:
- JWT-based admin access
- configuration CRUD
- helper management
- metrics and audit views
- Telegram notifications for admin actions

### Origin-side files
- `nginx.conf`
- `xray-config.json`
- `schema.sql`
- `.env.example`

Implements:
- localhost-only Xray inbounds
- 80/443 Nginx front door
- route-by-path proxying
- D1 schema for config, helpers, metrics, and audit data
- environment variable template for safe local setup

### Deployment automation
- `deploy.sh`

Implements:
- deployment of Tier 0, Tier 1, and Tier 2
- temporary runtime Wrangler configs for Tier 1 and Tier 2
- optional schema provisioning
- secret injection through `wrangler secret put`
- one-command bootstrap for the three-tier bundle

## Handoff requirements that remain external by design

These items are intentionally not hard-coded into the archive because they depend on your live infrastructure or dashboard settings:

- Cloudflare SSL/TLS mode set to `Full (strict)`
- Cloudflare WebSocket enabled
- Cloudflare HTTP/2 enabled
- DNS records pointing at the correct origin
- Let's Encrypt / certbot renewal on the VPS
- UFW rules on the server
- Provider-level port reachability
- Telegram bot credentials and admin secrets
- D1 database creation and ID wiring

## Key alignment points from the handoff

- Localhost-only Xray is preserved.
- Nginx stays the only public origin listener on 80/443.
- Subscription delivery is split from control-plane concerns.
- DNS is treated as a resilience layer, not a convenience layer.
- Recovery flows are documented, but production behavior still depends on dashboard and origin state.

## Operational contract for `deploy.sh`

`deploy.sh` is designed to be the single entry point for deployment:

- It reads `.env` when present.
- It deploys Tier 0 from the canonical top-level `wrangler.toml`.
- It generates temporary Wrangler files for Tier 1 and Tier 2.
- It can provision schema into D1 before deploy.
- It refuses to deploy Tier 2 unless admin credentials are provided.

## Practical run order

1. Populate `.env` from `.env.example`.
2. Confirm the D1 database exists.
3. Run `./deploy.sh`.
4. Validate Nginx and Xray on the VPS.
5. Check the Cloudflare dashboard settings listed above.

## Notes on the merged sources

- The newer production bundle provided the cleanest deployment path and fixed worker files.
- The earlier package contributed useful architectural notes, guides, and baseline docs.
- The handoff document itself was used as the final authority for which behaviors matter.


## Hot path pressure reduction
- Tier 0 now avoids D1 and external fetches in request handling.
- Subscription generation uses memory cache + optional KV cache only.
- Wranger Tier 0 binding is aligned to DM_KV.


## Deployment fix
- Removed any SSH/VPS dependency from the Cloudflare deploy path.
- Added config.ts as a shared source of truth.
- Replaced placeholder KV namespace IDs with the real handoff namespace.
- Tier 0 hot path stays lean: memory cache + optional KV only.

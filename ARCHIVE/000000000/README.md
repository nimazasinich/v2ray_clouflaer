# DreamMaker Deployment Bundle

This archive is organized around the handoff document and the three-tier deployment model.

## Main entry points

- `deploy.sh` — deploys Tier 0, Tier 1, and Tier 2.
- `wrangler.toml` — canonical Cloudflare Worker config for Tier 0.
- `HANDOFF_IMPLEMENTATION_MAP.md` — maps the handoff requirements to files in this bundle.
- `.env.example` — safe local environment template.

## What the bundle contains

- `edge-worker-tier0.ts`
- `helper-ecosystem-tier1.ts`
- `control-plane-tier2.ts`
- `nginx.conf`
- `xray-config.json`
- `schema.sql`
- `tsconfig.json`
- `worker-stubs.d.ts`
- `FIXES_SUMMARY.md`
- `DEPLOYMENT_NOTES.txt`

## Deployment flow

1. Copy `.env.example` to `.env`.
2. Fill in the values that belong to your environment.
3. Make sure the D1 database exists and its ID is available to the script.
4. Run:

```bash
chmod +x deploy.sh
./deploy.sh
```

## What `deploy.sh` does

- deploys Tier 0 from `wrangler.toml`
- generates temporary configs for Tier 1 and Tier 2
- installs secrets via Wrangler
- applies `schema.sql` to D1 when enabled
- keeps Tier 0, Tier 1, and Tier 2 synchronized

## Important external checks

Some items in the handoff remain outside the archive because they are environment-specific:

- Cloudflare SSL/TLS must be `Full (strict)`
- Cloudflare WebSocket must be enabled
- Cloudflare HTTP/2 must be enabled
- the DNS records must point to the correct origin
- certbot / Let's Encrypt must remain valid on the VPS
- UFW and provider firewall rules must match the origin design


## Hot path note
Tier 0 is intentionally lean: no D1, no external fetches, no metrics sampling in the request path.

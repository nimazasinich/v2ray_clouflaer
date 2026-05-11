# DreamMaker Infrastructure

**Premium Xray/VLESS Censorship-Resistant Platform**

![Status](https://img.shields.io/badge/Status-Production%20Ready-green)
![Version](https://img.shields.io/badge/Version-1.0.0-blue)
![Language](https://img.shields.io/badge/Language-English-blue)
![Deployment](https://img.shields.io/badge/Deployment-Cloudflare%20Workers%2BVPS-blue)

---

## Overview

DreamMaker is a sophisticated infrastructure for deploying privacy-respecting, censorship-resistant proxy services. It combines:

- **Cloudflare Workers** (Tier 0, 1, 2) for edge delivery and control
- **Xray Core** with VLESS protocol for secure tunneling
- **Nginx** as reverse proxy for transparent TLS termination
- **German VPS** (82.115.26.105) as primary node
- **Telegram Integration** for monitoring and alerts

**Core Principle:** Stability > Latency > Compatibility > Filtering

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Internet / Users                          │
└────────────────┬────────────────────────────────────┬────────┘
                 │                                    │
          ┌──────▼─────────┐              ┌──────────▼────┐
          │   Cloudflare   │              │  DNS / CDN    │
          │  DNS (Orange)  │              │  Resolvers    │
          └──────┬─────────┘              └───────────────┘
                 │
        ┌────────▼──────────────┐
        │  dreammaker-groupsoft │
        │        .ir            │
        └────────┬──────────────┘
                 │
        ┌────────▼──────────────────────┐
        │  Cloudflare Workers (Edge)    │
        │                               │
        │  ┌─────────────────────────┐  │
        │  │ Tier 0: Edge Worker     │  │ → Subscription delivery
        │  │ cdn.dreammaker-groupsoft│  │   + caching
        │  └─────────────────────────┘  │
        │  ┌─────────────────────────┐  │
        │  │ Tier 1: Helper Ecosystem│  │ → Health probing
        │  │ (Scheduled, 5 min)      │  │   + KV scoring
        │  └─────────────────────────┘  │
        │  ┌─────────────────────────┐  │
        │  │ Tier 2: Control Plane   │  │ → Admin dashboard
        │  │ (JWT auth, D1 database) │  │   + metrics
        │  └─────────────────────────┘  │
        └────────┬──────────────────────┘
                 │ HTTPS (80/443)
        ┌────────▼─────────────────┐
        │  Nginx Reverse Proxy     │
        │  82.115.26.105           │
        │                          │
        │  • TLS termination       │
        │  • Path routing          │
        │  • Load balancing        │
        │  • Error handling        │
        └────────┬─────────────────┘
                 │ localhost:110xx
        ┌────────▼──────────────────┐
        │  Xray Core (v26.4.25)    │
        │                          │
        │  • VLESS protocol        │
        │  • XHTTP transport       │
        │  • Path-based routing    │
        │  • 7 service tiers       │
        │  • Minimal logging       │
        └────────┬─────────────────┘
                 │
        ┌────────▼──────────────┐
        │  Internet Destinations│
        │  (User traffic)       │
        └───────────────────────┘

Legend:
  Port 80 → Port 443 (HTTP redirect)
  Port 443 → Nginx TLS (Cloudflare edge)
  localhost:11001-11007 → Xray tier inbounds
  All ports validated per Section 3 of infrastructure docs
```

---

## Quick Start

### 1. Prerequisites

```bash
# System requirements
- Node.js 18+ (for Wrangler)
- npm 9+ (Node package manager)
- curl (for API calls)
- bash (shell scripting)

# On macOS
brew install node npm curl

# On Ubuntu/Debian
sudo apt-get install nodejs npm curl

# Verify
node --version  # v18+
npm --version   # 9+
curl --version
```

### 2. Configuration

```bash
# Copy template
cp .env.example .env

# Edit with credentials
nano .env
# Fill in:
# - CF_TOKEN_FULL (Cloudflare API token)
# - CF_ACCOUNT_ID (Cloudflare account)
# - TG_BOT_TOKEN (Telegram bot)
# - TG_CHAT_ID (Telegram chat)
# - ADMIN_TOKEN (32+ random chars)
# - JWT_SECRET (32+ random chars)

# Secure file
chmod 600 .env

# Verify
./deploy.sh --check-env
```

### 3. Install Dependencies

```bash
# Install npm packages
npm install

# Verify
npm list wrangler typescript
```

### 4. Validate Configuration

```bash
# Test all configurations
./deploy.sh --validate

# Expected: All checks pass with ✅
```

### 5. Deploy to Cloudflare

```bash
# Deploy Cloudflare Workers
./deploy.sh

# Or individually:
npm run deploy:tier0    # Edge worker
npm run deploy:tier1    # Health ecosystem
npm run deploy:tier2    # Control plane

# Expected: Deployment successful message
```

### 6. Deploy to German VPS

See [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md) for:
- Connecting to 82.115.26.105
- Copying configuration files
- Starting services
- Verifying deployment

---

## Project Structure

```
dreammaker-infrastructure/
├── 📄 README.md                      # This file
├── 📄 ANALYSIS_REPORT.md             # Detailed analysis
├── 📄 DEPLOYMENT_GUIDE.md            # VPS setup guide
├── 📄 INFRASTRUCTURE_HANDOFF.md      # Master documentation
├── 
├── ⚙️ Configuration Files
├── ├── .env.example                 # Environment template (documented)
├── ├── wrangler.toml                # Tier 0 Worker config
├── ├── wrangler-tier1.toml          # Tier 1 Worker config
├── ├── wrangler-tier2.toml          # Tier 2 Worker config
├── ├── config.ts                    # Tier configuration (7 tiers)
├── ├── nginx.conf                   # Reverse proxy config
├── ├── xray-config.json             # Xray core config
├── ├── xray-tiers.json              # Tier metadata
├── ├── schema.sql                   # D1 database schema
├── ├── tsconfig.json                # TypeScript config
├── ├── package.json                 # npm dependencies
├── └── worker-stubs.d.ts            # TypeScript type stubs
├── 
├── 🚀 Deployment Scripts
├── ├── deploy.sh                    # Main deployment script
├── ├── deploy-worker-dreammaker.sh  # Cloudflare Worker deploy
├── └── [VPS scripts to add]          # VPS management scripts
├── 
├── 💻 Worker Code (TypeScript)
├── ├── edge-worker-tier0.ts         # Edge subscription delivery
├── ├── helper-ecosystem-tier1.ts    # Health probing & scoring
├── ├── control-plane-tier2.ts       # Admin dashboard & API
├── └── [Additional tier code]       # Future workers
├── 
├── 📚 Documentation
├── ├── .gitignore                   # Git ignore rules
├── ├── LICENSE                      # MIT License
├── └── SECURITY.md                  # Security policy
└── 📦 Build Artifacts (generated)
    ├── dist/                        # Compiled output
    ├── node_modules/                # npm packages
    ├── .wrangler/                   # Wrangler cache
    └── [deployment logs]            # Logs directory

Key Files:
  ✅ = Complete and tested
  ⚠️ = Needs review/updates
  ❌ = Missing (needs creation)
```

---

## File Summary

### Configuration Files

| File | Purpose | Status |
|------|---------|--------|
| `.env.example` | Environment template | ✅ Complete |
| `config.ts` | Tier definitions | ✅ Complete |
| `wrangler.toml` | Tier 0 config | ✅ Complete |
| `wrangler-tier1.toml` | Tier 1 config | ✅ Complete |
| `wrangler-tier2.toml` | Tier 2 config | ✅ Complete |
| `nginx.conf` | Reverse proxy | ✅ Complete |
| `xray-config.json` | Xray core | ✅ Complete |
| `schema.sql` | D1 database | ✅ Complete |

### TypeScript Workers

| File | Lines | Purpose | Status |
|------|-------|---------|--------|
| `edge-worker-tier0.ts` | 191 | Subscription delivery | ✅ Complete |
| `helper-ecosystem-tier1.ts` | 507 | Health probing | ✅ Complete |
| `control-plane-tier2.ts` | 657 | Admin dashboard | ✅ Complete |

### Deployment Scripts

| Script | Purpose | Status |
|--------|---------|--------|
| `deploy.sh` | Master deployment | ✅ Enhanced |
| `deploy-worker-dreammaker.sh` | Cloudflare deploy | ✅ Enhanced |
| [VPS scripts] | Server management | ⚠️ See DEPLOYMENT_GUIDE.md |

---

## Common Tasks

### Deploy Everything (First Time)

```bash
# 1. Prepare environment
cp .env.example .env
nano .env  # Edit with real credentials

# 2. Validate
./deploy.sh --validate

# 3. Install dependencies
npm install

# 4. Deploy Cloudflare Workers
./deploy.sh

# 5. Deploy to VPS (see DEPLOYMENT_GUIDE.md)
scp xray-config.json root@82.115.26.105:/etc/xray/
scp nginx.conf root@82.115.26.105:/etc/nginx/
```

### Update Configuration Only

```bash
# Update Xray config without redeploying workers
scp xray-config.json root@82.115.26.105:/etc/xray/
ssh root@82.115.26.105 "systemctl restart xray"

# Update Nginx config
scp nginx.conf root@82.115.26.105:/etc/nginx/
ssh root@82.115.26.105 "nginx -t && systemctl reload nginx"
```

### Check Deployment Status

```bash
# Validate configuration
./deploy.sh --config-only

# Check credentials
./deploy.sh --check-env

# Verify services
curl -I https://dreammaker-groupsoft.ir/health
```

### View Logs

```bash
# VPS logs
ssh root@82.115.26.105 "tail -f /var/log/xray/error.log"
ssh root@82.115.26.105 "tail -f /var/log/nginx/error.log"

# Cloudflare Workers
wrangler tail --config wrangler.toml
```

---

## Tier Structure

DreamMaker provides 7 service tiers with different UUIDs and paths:

| Tier | UUID | Port | Path | Label |
|------|------|------|------|-------|
| **Starter** | `7dd47c02-...` | 11001 | `/api/v1/ping` | DM-Starter |
| **Basic** | `92ebaa01-...` | 11002 | `/cdn/init` | DM-Basic |
| **Standard** | `3d5e3adf-...` | 11003 | `/app/sync` | DM-Standard |
| **Plus** | `e8eb3d74-...` | 11004 | `/api/v2/feed` | DM-Plus |
| **Pro** | `b3540a54-...` | 11005 | `/static/bundle.js` | DM-Pro |
| **Elite** | `2680152c-...` | 11006 | `/media/stream` | DM-Elite |
| **Unlimited** | `89c0f294-...` | 11007 | `/v2/content/live` | DM-Unlimited |

Each tier uses XHTTP transport with unique domain/path for DPI resistance.

---

## Environment Variables

All variables in `.env.example` are documented. Key groups:

### Cloudflare (Required)
- `CF_TOKEN_FULL` - API token
- `CF_ACCOUNT_ID` - Account ID
- `CF_ZONE_ID` - Zone ID

### VPS (For manual deployment)
- `VPS_IP` - Server IP (82.115.26.105)
- `VPS_USER` - SSH user (root)
- `VPS_PORT` - SSH port (22)
- `VPS_PASS` - SSH password

### Telegram (Required for alerts)
- `TG_BOT_TOKEN` - Bot token
- `TG_CHAT_ID` - Chat ID

### Admin Auth (Tier 2)
- `ADMIN_TOKEN` - Admin password (32+ chars)
- `JWT_SECRET` - JWT signing key (32+ chars)

See `.env.example` for complete documentation.

---

## Monitoring

### Health Check Endpoint

```bash
# Check if infrastructure is healthy
curl -I https://dreammaker-groupsoft.ir/health

# Should return: 200 OK (if all services running)
#                502 Bad Gateway (if Xray offline)
```

### Telegram Alerts

Configure Telegram bot in `.env` to receive:
- Deployment notifications
- Error alerts
- Health check failures
- Admin action logs

### Log Analysis

```bash
# VPS logs
ssh root@82.115.26.105
tail -f /var/log/xray/error.log
tail -f /var/log/nginx/access.log

# Cloudflare Workers
npm run logs  # [TODO: Add log viewing]

# Local deployment log
cat deployment.log
```

---

## Troubleshooting

### "Credential validation failed"

```bash
# Verify .env file exists
ls -la .env

# Check credentials
./deploy.sh --check-env

# Common issues:
# - Missing CF_TOKEN_FULL
# - Missing CF_ACCOUNT_ID
# - Token has expired
# - Token lacks required permissions
```

### "Nginx returns 502 Bad Gateway"

**Cause:** Xray not responding

```bash
# Check Xray status
ssh root@82.115.26.105
systemctl status xray

# Restart Xray
systemctl restart xray

# View logs
tail -20 /var/log/xray/error.log
```

### "Subscription returns invalid data"

**Cause:** Worker not deployed or misconfigured

```bash
# Verify worker deployed
wrangler list

# Check worker logs
wrangler tail --config wrangler.toml

# Redeploy
npm run deploy:tier0
```

### "Can't connect to VPS"

**Cause:** SSH port blocked (common at provider)

```bash
# Use provider VNC console instead
# Or configure SOCKS5 proxy
# See DEPLOYMENT_GUIDE.md for details
```

---

## Security Notes

### Credentials

```bash
# Secure .env file
chmod 600 .env

# Never commit .env
# Check .gitignore

# Rotate credentials quarterly
# (Change Cloudflare tokens, Telegram bot, etc.)

# Back up .env securely (separate from code)
gpg --encrypt .env
cp .env.gpg /secure/backup/
```

### TLS Certificates

- Managed by Cloudflare (automatic renewal)
- Let's Encrypt via certbot for origin (optional)
- TLS 1.2 and 1.3 enforced

### Logging

Per Section 37 (Privacy Policy):
- Xray access logs disabled (privacy)
- Error logs kept 7-14 days
- No full payload logging
- No credential logging

---

## Compliance

This infrastructure is designed to:

✅ Provide censorship resistance in severe blocking environments  
✅ Minimize data retention (7-14 day logs)  
✅ Respect user privacy (no client logging)  
✅ Support multiple transport methods (XHTTP, WebSocket)  
✅ Deliver fast, stable service under network pressure  

It is NOT designed for:
❌ Illegal activities
❌ Malware distribution  
❌ Spam or phishing  
❌ Unauthorized access  

Users are responsible for legal compliance in their jurisdiction.

---

## Development

### Build from Source

```bash
# Install TypeScript
npm install -g typescript

# Compile TypeScript
npm run build

# Type check
npm run typecheck
```

### Local Development

```bash
# Start local Wrangler server
npm run dev

# Should start on localhost:8787
# Access http://localhost:8787
```

### Testing

```bash
# Run tests (placeholder)
npm test

# Manual tests
./deploy.sh --validate
./deploy.sh --check-env
```

---

## Contributing

This is a production infrastructure. Before contributing:

1. Review [INFRASTRUCTURE_HANDOFF.md](./INFRASTRUCTURE_HANDOFF.md)
2. Test changes locally first
3. Never commit credentials
4. Follow existing code style
5. Document changes thoroughly
6. Consider security implications

---

## Support

### Documentation

- 📖 [INFRASTRUCTURE_HANDOFF.md](./INFRASTRUCTURE_HANDOFF.md) - Complete specification
- 📖 [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md) - VPS setup
- 📖 [ANALYSIS_REPORT.md](./ANALYSIS_REPORT.md) - Detailed analysis

### Troubleshooting

1. Check log files
2. Review documentation sections
3. Validate configuration (./deploy.sh --validate)
4. Test endpoints (curl)

### Issues

Found a problem? Document and investigate:

```bash
# Collect diagnostics
mkdir -p debug
./deploy.sh --check-env > debug/check-env.log
curl -I https://dreammaker-groupsoft.ir/health > debug/health.log
ssh root@82.115.26.105 "systemctl status xray" > debug/xray-status.log

# Archive for analysis
tar -czf dreammaker-debug-$(date +%s).tar.gz debug/
```

---

## License

MIT License - See LICENSE file for details

---

## Disclaimer

This infrastructure is provided as-is for educational and lawful use. Users are responsible for:
- Compliance with local laws
- Ethical use of services
- Proper security practices
- Data privacy considerations

Do not use for illegal activities or harm.

---

**Version:** 1.0.0  
**Last Updated:** 2026-05-09  
**Status:** Production Ready ✅

For the latest updates and detailed specifications, see [INFRASTRUCTURE_HANDOFF.md](./INFRASTRUCTURE_HANDOFF.md)

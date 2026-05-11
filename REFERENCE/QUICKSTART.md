# 🚀 QUICKSTART GUIDE

**Date:** 2026-05-10  
**Status:** ✅ READY FOR DEPLOYMENT  
**Target:** Cursor AI + Human Developers

---

## ⚡ 30-SECOND OVERVIEW

**What:** Premium Xray/VLESS CDN platform with Cloudflare edge protection  
**Where:** Germany VPS (82.115.26.105) + Cloudflare edge  
**How:** Nginx reverse proxy → 7 Xray tiers → clients  
**Status:** ACTIVE PRODUCTION

---

## 📖 READ THESE FIRST

In this exact order:

1. **DreamMaker_Infrastructure_Handoff_Master_Enriched.md** (5 min read)
   - Complete architecture
   - All credentials in section 0
   - Current audit findings in section 4
   - Critical fixes needed in section 12

2. **TOKENS_AND_SECRETS_REGISTRY.md** (3 min read)
   - Where every token/credential is stored
   - How to use them safely
   - Security checklist

3. **PROJECT_MANIFEST.md** (2 min skim)
   - File index by category
   - What's active vs archived
   - Quick deployment reference

4. **.cursorconfig.json** (auto-loaded by Cursor)
   - Cursor will automatically understand project structure
   - Tier configuration table
   - Port mapping reference

---

## 🎯 WHAT YOU NEED TO KNOW

### The Setup (TL;DR)

```
Clients (v2rayNG, etc.)
        ↓
Cloudflare CDN (TLS termination, DDoS protection)
        ↓
Nginx (82.115.26.105:443 + 82.115.26.105:80)
        ↓
7 Xray Tiers (127.0.0.1:11001-11007)
        ↓
Clients get internet access via Xray
```

### Production Files

| What | Where | Edit? | Deploy? |
|---|---|---|---|
| **nginx.conf** | Local | ✅ Yes | `bash deploy.sh` |
| **xray-config.json** | Local | ✅ Yes | `bash deploy.sh` |
| **worker.js** | Local | ✅ Yes | `npx wrangler deploy` |
| **wrangler.toml** | Local | ⚠️ Config only | `npx wrangler deploy` |
| **.env** | Local (git-ignored) | ✅ Yes | Sourced by scripts |

### Key URLs

```
Domain:           https://dreammaker-groupsoft.ir
CDN Subdomain:    https://cdn.dreammaker-groupsoft.ir
Germany VPS:      82.115.26.105 (via SOCKS5 proxy)
Cloudflare Zone:  7521f025c7660ad0f5ab6c57d787fa6f
Cloudflare Acct:  d902b91f0f1076e0601ffd6e7b4382c0
```

### Key Credentials

**⚠️ See TOKENS_AND_SECRETS_REGISTRY.md for all actual values**

- **Cloudflare Token:** cfut_9X9JcNyxRKrZTwKg8fdQ2ua26ftC6...
- **Germany VPS:** root@82.115.26.105 (SSH via SOCKS5 proxy)
- **Telegram Bot:** @Freqbasterd_bot (alerts + logs)
- **Xray UUIDs:** 7 different per tier (in xray-config.json)

---

## 🔐 CRITICAL SECURITY NOTES

### ❌ DO NOT

```
❌ Commit .env file to Git
❌ Share tokens in messages/logs
❌ Use production tokens in development
❌ Configure anything on port 2053 (provider blocks it)
❌ Use Iran VPS for new deployments (legacy only)
❌ Bind Xray to 0.0.0.0 (must be 127.0.0.1)
```

### ✅ DO

```
✅ Use .env.example as template
✅ Load secrets from environment variables
✅ Rotate CF token every 90 days
✅ Test deployments before going live
✅ Keep .gitignore updated
✅ Verify Xray binds to localhost only
✅ Use SOCKS5 proxy for Germany VPS SSH
```

---

## 🚀 DEPLOYING CHANGES

### Scenario 1: Update Nginx Config

```bash
# 1. Edit locally
# vim nginx.conf

# 2. Test syntax
# nginx -t -c nginx.conf

# 3. Deploy to Germany VPS
bash deploy.sh

# 4. Verify
curl -I https://dreammaker-groupsoft.ir/api/v1/ping
```

### Scenario 2: Update Xray Config

```bash
# 1. Edit locally
# vim xray-config.json

# 2. Validate syntax
# xray test -c xray-config.json

# 3. Deploy to Germany VPS
bash deploy.sh

# 4. Check status
# (SSH into VPS) systemctl status xray
```

### Scenario 3: Update Cloudflare Worker

```bash
# 1. Edit locally
# vim worker.js

# 2. Set CF token
export CLOUDFLARE_API_TOKEN="cfut_9X9JcNyxRKrZTwKg8fdQ2ua26ftC6nk5ltQeurdwbd919108"

# 3. Deploy
npx wrangler deploy

# 4. Verify
curl https://dreammaker-groupsoft.ir/health
```

---

## 🐛 TROUBLESHOOTING

### Problem: "Connection refused" on port 11001

**Cause:** Xray not running or bound to wrong address  
**Fix:**
```bash
# SSH to Germany VPS
ssh -o ProxyCommand="nc -X 5 -x 127.0.0.1:10808 %h %p" root@82.115.26.105

# Check Xray status
systemctl status xray

# Check binding
netstat -tln | grep 11001
# Should show: 127.0.0.1:11001 LISTEN

# Restart if needed
systemctl restart xray
```

### Problem: "403 Forbidden" from Nginx

**Cause:** Nginx location blocks missing or misconfigured  
**Fix:**
- Check `nginx.conf` has all 7 location blocks
- Each should proxy to correct port: /api/v1/ping → 11001, etc.
- Test: `nginx -t`
- Reload: `nginx -s reload`

### Problem: "Port 2053 not responding"

**This is expected!** Port 2053 is **blocked by datacenter provider**. Do NOT try to use it.
- Remove from config
- Cloudflare DNS works fine over HTTPS port 443

### Problem: Cloudflare reports origin error

**Cause:** Nginx not accessible or certificate issue  
**Fix:**
- Check Nginx is running: `systemctl status nginx`
- Verify TLS certificate: `openssl s_client -connect 82.115.26.105:443`
- Check Cloudflare SSL mode is "Full (strict)"
- Verify certificate CN matches domain

---

## 📊 MONITORING

### Quick Health Checks

```bash
# Test Tier 1 (Starter)
curl -I https://dreammaker-groupsoft.ir/api/v1/ping

# Test Tier 2 (Basic)
curl -I https://dreammaker-groupsoft.ir/cdn/init

# Test Tier 3 (Standard)
curl -I https://dreammaker-groupsoft.ir/app/sync

# Get real IP (behind Cloudflare)
curl https://api.ipify.org?format=json

# Check TLS certificate validity
curl -vI https://dreammaker-groupsoft.ir/ 2>&1 | grep "expires"
```

### Log Locations (Germany VPS)

```
Nginx errors:       /var/log/nginx/error.log
Nginx access:       /var/log/nginx/access.log
Xray errors:        /var/log/xray/error.log
Xray access:        /var/log/xray/access.log (disabled for privacy)
Systemd journal:    journalctl -u nginx -u xray -f
```

---

## 🆘 EMERGENCY PROCEDURES

### If Production Breaks

```bash
# 1. SSH to Germany VPS
ssh -o ProxyCommand="nc -X 5 -x 127.0.0.1:10808 %h %p" root@82.115.26.105

# 2. Run emergency fix
bash /root/.wrangler/deploy-fix.sh

# 3. Check services
systemctl status nginx xray

# 4. If still broken, rollback to backup
cd /root/.wrangler
cp xray-config.json xray-config.json.broken
cp 000000000/xray-config.json xray-config.json
systemctl restart xray
```

### If Iran VPS Credentials Exposed

**IMPORTANT:** Iran VPS is NOT in active setup, so no immediate risk from that one being exposed.

For Cloudflare tokens exposed:
1. Regenerate CF_TOKEN_FULL immediately
2. Update all deployment scripts
3. Rotate other tokens (DNS, Workers, legacy)

---

## 📁 IMPORTANT FILES

### Must Read
- ✅ DreamMaker_Infrastructure_Handoff_Master_Enriched.md
- ✅ TOKENS_AND_SECRETS_REGISTRY.md
- ✅ PROJECT_MANIFEST.md
- ✅ PROJECT_STRUCTURE.md

### Always Edit
- ✅ nginx.conf (reverse proxy)
- ✅ xray-config.json (server config)
- ✅ worker.js (edge code)
- ✅ .env (local secrets, git-ignored)

### Never Commit
- ❌ .env (secrets)
- ❌ Actual token values anywhere
- ❌ Private keys
- ❌ Passwords in plain text

### Reference Only
- 📖 FINAL_AUDIT.md (audit results)
- 📖 FIXES_SUMMARY.md (known issues)
- 📖 HANDOFF_IMPLEMENTATION_MAP.md (implementation checklist)

---

## 🎓 LEARNING RESOURCES

### For Nginx Configuration
See `nginx.conf` comments:
- Server blocks (ports 80, 443)
- Location blocks (tier routing)
- WebSocket upgrade headers
- Cloudflare real IP restoration

### For Xray Configuration
See `xray-config.json`:
- 7 inbound definitions (ports 11001-11007)
- Routing rules (direct, WARP, blackhole)
- DNS configuration
- VLESS+XHTTP protocol

### For Cloudflare Integration
See `worker.js`:
- WebSocket relay logic
- Subscription endpoint
- Caching strategy (10-minute TTL)
- Verification logic

---

## ✅ DEPLOYMENT CHECKLIST

Before deploying any changes:

- [ ] Read the relevant section in master handoff doc
- [ ] Check TOKENS_AND_SECRETS_REGISTRY for credential locations
- [ ] Edit file locally
- [ ] Validate syntax (nginx -t, xray test, node -c)
- [ ] Test with `curl` against local services if possible
- [ ] Run `bash deploy.sh` (or `npx wrangler deploy`)
- [ ] Verify with production URL test
- [ ] Check logs for errors
- [ ] Document change in `problem.txt` if it was a fix
- [ ] Backup old version in archive folder

---

## 🆘 SUPPORT

### If Something Is Unclear

1. **Check documentation first:**
   - DreamMaker_Infrastructure_Handoff_Master_Enriched.md
   - TOKENS_AND_SECRETS_REGISTRY.md
   - PROJECT_MANIFEST.md

2. **Check .cursorconfig.json:**
   - Tier table
   - Port mapping
   - Important notes

3. **Review audit results:**
   - FINAL_AUDIT.md
   - FIXES_SUMMARY.md
   - problem.txt

4. **Ask Cursor AI:**
   - Load PROJECT_MANIFEST.md
   - Reference TOKENS_AND_SECRETS_REGISTRY.md
   - Cursor will understand project structure automatically

---

## 🎯 NEXT STEPS

### If You're New To This Project

1. Read DreamMaker_Infrastructure_Handoff_Master_Enriched.md (20 min)
2. Read TOKENS_AND_SECRETS_REGISTRY.md (10 min)
3. Review PROJECT_STRUCTURE.md (5 min)
4. Open Cursor IDE in this folder
5. Cursor will auto-load .cursorconfig.json
6. Ask Cursor: "What does this project do?" or "Show me the tier configuration"

### If You Need To Deploy Something

1. Check what file to edit (see "Always Edit" section above)
2. Make your changes
3. Validate syntax
4. Run appropriate deploy command
5. Verify with curl test
6. Document what you changed

### If There's An Emergency

1. SSH to Germany VPS (via SOCKS5 proxy)
2. Run `bash deploy-fix.sh`
3. Check service status
4. Review logs
5. Contact team if still broken

---

## 🚫 CRITICAL REMINDERS

🔴 **NEVER:**
- Use port 2053 (BLOCKED by provider)
- Deploy using Iran VPS (LEGACY)
- Bind Xray to public IP (use 127.0.0.1 only)
- Commit .env to Git
- Share tokens in Slack/email/logs

🟢 **ALWAYS:**
- Use Germany VPS (82.115.26.105)
- Bind Xray to localhost only (127.0.0.1)
- Test changes before deployment
- Use Cloudflare for DDoS protection
- Rotate tokens every 90 days

---

**Last Updated:** 2026-05-10  
**Ready to Deploy:** ✅ YES  
**Status:** ✅ PRODUCTION  
**Questions?** → See master handoff doc or ask Cursor AI

---

Quick Start End

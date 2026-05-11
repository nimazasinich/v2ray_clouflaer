# DreamMaker Infrastructure — German VPS Deployment Guide

**Target Server:** 82.115.26.105 (Ubuntu LTS ARM64)  
**Date:** 2026-05-09  
**Status:** Complete & Ready  
**Language:** English

---

## Table of Contents

1. [Server Access](#server-access)
2. [Prerequisites](#prerequisites)
3. [VPS Preparation](#vps-preparation)
4. [Configuration Deployment](#configuration-deployment)
5. [Service Setup](#service-setup)
6. [Verification & Testing](#verification--testing)
7. [Monitoring & Maintenance](#monitoring--maintenance)
8. [Emergency Recovery](#emergency-recovery)

---

## Server Access

### IP Address & Connection Details

| Field | Value |
|-------|-------|
| **IP Address** | `82.115.26.105` |
| **Hostname** | `srv6178084723` |
| **OS** | Ubuntu LTS ARM64 |
| **SSH Port** | `22` (may be blocked at provider level) |
| **SSH User** | `root` |
| **SSH Password** | `1111111111` |
| **Access Method** | VNC/KVM console via provider panel |

### Connection Methods

#### Method 1: Direct SSH (if available)
```bash
ssh -p 22 root@82.115.26.105
# Enter password when prompted: 1111111111
```

**Status:** ⚠️ Port 22 is silently dropped at datacenter level (provider firewall)  
**Workaround:** Use VNC console or SOCKS5 proxy if available

#### Method 2: VNC Console (Recommended)
```
1. Log in to provider control panel
2. Find server: srv6178084723
3. Click "VNC Console" or "Remote Console"
4. Open in browser
5. Log in with root credentials
```

#### Method 3: SOCKS5 Proxy (if configured)
```bash
# Configure SSH through proxy
ssh -o ProxyCommand="nc -X 5 -x 127.0.0.1:10808 %h %p" \
    -p 22 root@82.115.26.105
```

---

## Prerequisites

### Local Machine Requirements (before deployment)

```bash
# Install required tools
# macOS
brew install openssh sshpass curl git

# Ubuntu/Debian
sudo apt-get install openssh-client sshpass curl git

# Verify installations
ssh -V
curl --version
git --version
```

### .env File Preparation

```bash
# Create .env from template
cp .env.example .env

# Edit .env with real credentials
nano .env

# Verify all required fields are filled:
# - CF_TOKEN_FULL
# - CF_ACCOUNT_ID
# - TG_BOT_TOKEN
# - ADMIN_TOKEN (32+ random characters)
# - JWT_SECRET (32+ random characters)

# Set secure permissions
chmod 600 .env
```

### Validate Configuration

```bash
# Test credentials
./deploy.sh --check-env

# Expected output:
# [SUCCESS] Environment check passed

# If it fails, review .env for empty or invalid values
```

---

## VPS Preparation

### Initial VPS Setup (First Time Only)

```bash
# 1. Connect to VPS via VNC console

# 2. Update system packages
apt-get update -qq
apt-get upgrade -y

# 3. Install essential packages
apt-get install -y \
    curl wget git unzip nano \
    supervisor htop net-tools \
    certbot python3-certbot-nginx

# 4. Create required directories
mkdir -p /etc/xray
mkdir -p /etc/nginx/conf.d
mkdir -p /var/log/xray
mkdir -p /var/log/nginx
mkdir -p /root/.wrangler

# 5. Set proper permissions
chmod 755 /etc/xray
chmod 755 /var/log/xray
chmod 755 /var/log/nginx

# 6. Create xray user (optional, for security)
useradd -r -s /bin/false xray 2>/dev/null || true

# 7. Verify system info
uname -m  # Should output: aarch64
lsb_release -a  # Should show Ubuntu LTS
```

### Prepare Wrangler Directory

```bash
# 1. Create ~/.wrangler directory
mkdir -p /root/.wrangler
cd /root/.wrangler

# 2. Create placeholder files (will be overwritten)
touch wrangler.toml config.ts

# 3. Set permissions
chmod 755 /root/.wrangler
chmod 600 /root/.wrangler/*
```

---

## Configuration Deployment

### Method 1: Using SCP (Over Network)

```bash
# From your local machine

# 1. Deploy Xray configuration
scp -P 22 xray-config.json root@82.115.26.105:/etc/xray/config.json

# 2. Deploy Nginx configuration
scp -P 22 nginx.conf root@82.115.26.105:/etc/nginx/nginx.conf

# 3. Deploy Wrangler configs (optional)
scp -P 22 wrangler.toml root@82.115.26.105:/root/.wrangler/
scp -P 22 config.ts root@82.115.26.105:/root/.wrangler/

# If SSH blocked, use this alternative with sshpass
sshpass -p "1111111111" scp -P 22 xray-config.json root@82.115.26.105:/etc/xray/config.json
```

**Status:** If port 22 is blocked, proceed with Method 2

### Method 2: Via VNC Console (Manual)

```bash
# 1. Connect via VNC console

# 2. Create files manually
cat > /etc/xray/config.json << 'EOF'
{
  "log": { "access": "none", "loglevel": "warning" },
  ... (paste entire xray-config.json content)
}
EOF

# 3. Similarly for nginx.conf
cat > /etc/nginx/nginx.conf << 'EOF'
user www-data;
... (paste entire nginx.conf content)
EOF

# 4. Verify file creation
ls -la /etc/xray/config.json
ls -la /etc/nginx/nginx.conf
```

### Method 3: Using Git Clone (if repository available)

```bash
# 1. Clone repository to VPS
cd /root
git clone https://github.com/dreammaker/infrastructure.git
cd infrastructure

# 2. Copy configuration files
cp xray-config.json /etc/xray/config.json
cp nginx.conf /etc/nginx/nginx.conf

# 3. Keep repository for future updates
git pull  # Updates when needed
```

### Set Proper Permissions

```bash
# After copying configuration files
chmod 600 /etc/xray/config.json
chmod 644 /etc/nginx/nginx.conf
chown root:root /etc/xray/config.json
chown root:root /etc/nginx/nginx.conf
```

---

## Service Setup

### Install/Update Services

#### 1. Install Xray Core

```bash
# Check if Xray is installed
xray -version

# If not installed, download and install
# Visit: https://github.com/XTLS/Xray-core/releases

# Example for ARM64:
cd /tmp
wget https://github.com/XTLS/Xray-core/releases/download/v26.4.25/Xray-linux-arm64.zip
unzip Xray-linux-arm64.zip
mv xray /usr/local/bin/
chmod +x /usr/local/bin/xray

# Verify installation
xray -version
# Expected: Xray 26.4.25
```

#### 2. Install/Update Nginx

```bash
# Install Nginx
apt-get install -y nginx

# Enable and start service
systemctl enable nginx
systemctl start nginx

# Verify installation
nginx -v
systemctl status nginx
```

### Create Systemd Service Files

#### Create Xray Service

```bash
cat > /etc/systemd/system/xray.service << 'EOF'
[Unit]
Description=DreamMaker Xray Core
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/xray -config /etc/xray/config.json
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

# Performance tuning
LimitNOFILE=65535
LimitNPROC=32768

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd
systemctl daemon-reload

# Enable service
systemctl enable xray

# Start service
systemctl start xray

# Verify
systemctl status xray
```

#### Update Nginx Service (already exists)

```bash
# Nginx service should already exist
# Just verify it's enabled
systemctl is-enabled nginx  # Should output: enabled
systemctl status nginx      # Should show: active (running)
```

### Validate Configurations

#### Test Xray Configuration

```bash
# Validate JSON syntax
xray -c /etc/xray/config.json -test

# Expected output: OK
# If errors appear, review config file for syntax issues
```

#### Test Nginx Configuration

```bash
# Test Nginx configuration
nginx -t

# Expected output:
# nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
# nginx: configuration file /etc/nginx/nginx.conf test is successful
```

### Reload Services

```bash
# Reload Nginx (without stopping)
systemctl reload nginx

# Restart Xray (stops and starts)
systemctl restart xray

# Verify both are running
systemctl status nginx
systemctl status xray

# Both should show: active (running)
```

---

## Verification & Testing

### 1. Port Verification

```bash
# Check which ports are listening
netstat -tlnp | grep LISTEN
# or
ss -tlnp | grep LISTEN

# Expected output:
# - 0.0.0.0:80 (Nginx)
# - 0.0.0.0:443 (Nginx TLS)
# - 127.0.0.1:11001-11007 (Xray tiers)
```

### 2. Network Connectivity

```bash
# Test external connectivity
curl -I https://api.cloudflare.com
# Expected: HTTP/2 200

# Test DNS resolution
dig dreammaker-groupsoft.ir @1.1.1.1
# Expected: Should resolve to Cloudflare IP
```

### 3. Nginx Functionality

```bash
# Test HTTP redirect
curl -I http://82.115.26.105/
# Expected: 301 redirect to HTTPS

# Test HTTPS
curl -I https://dreammaker-groupsoft.ir/health
# Expected: 200 or 502 (if Xray not responding)
```

### 4. Xray Functionality

```bash
# Check Xray process
ps aux | grep xray
# Should show: /usr/local/bin/xray -config /etc/xray/config.json

# Check Xray logs
tail -f /var/log/xray/error.log
# Should show: activity logs or minimal errors

# Test localhost binding (from VPS only)
netstat -tlnp | grep 11001
# Expected: tcp 127.0.0.1:11001
```

### 5. Health Check Endpoint

```bash
# Test health endpoint (through Nginx proxy)
curl -I https://dreammaker-groupsoft.ir/health
curl -I https://cdn.dreammaker-groupsoft.ir/health

# Expected: 200 OK if Xray healthy
#           502 Bad Gateway if Xray offline
```

### 6. Subscription Delivery Test

```bash
# Generate test subscription
curl -s "https://dreammaker-groupsoft.ir/sub/starter" \
  | head -c 100

# Should return VLESS configuration
# Base64-encoded content
```

---

## Monitoring & Maintenance

### Log Monitoring

```bash
# Monitor Nginx access log (live)
tail -f /var/log/nginx/access.log

# Monitor Nginx errors
tail -f /var/log/nginx/error.log

# Monitor Xray errors
tail -f /var/log/xray/error.log

# Full system journal
journalctl -u xray -f
journalctl -u nginx -f
```

### Health Monitoring Script

```bash
#!/bin/bash
# Create file: /root/check-health.sh

echo "=== DreamMaker Health Check ==="
echo ""

echo "Nginx status:"
systemctl status nginx --no-pager | head -3

echo "Xray status:"
systemctl status xray --no-pager | head -3

echo ""
echo "Port listening (80, 443):"
netstat -tlnp 2>/dev/null | grep -E ":80|:443" | grep LISTEN

echo ""
echo "Xray inbound ports (127.0.0.1):"
netstat -tlnp 2>/dev/null | grep -E ":110[0-7]" | grep LISTEN

echo ""
echo "Recent Xray errors (last 5 lines):"
tail -5 /var/log/xray/error.log

echo ""
echo "Health endpoint test:"
curl -s -I https://dreammaker-groupsoft.ir/health | head -1

# Make executable
chmod +x /root/check-health.sh

# Run daily
echo "0 9 * * * /root/check-health.sh | mail -s 'DreamMaker Daily Report' admin@example.com" | crontab -
```

### Backup Strategy

```bash
#!/bin/bash
# Create file: /root/backup-dreammaker.sh

BACKUP_DIR="/root/backups"
DATE=$(date +%Y-%m-%d_%H-%M-%S)

mkdir -p "$BACKUP_DIR"

# Backup configurations
tar -czf "$BACKUP_DIR/xray-config-$DATE.tar.gz" /etc/xray/
tar -czf "$BACKUP_DIR/nginx-config-$DATE.tar.gz" /etc/nginx/

# Keep only last 7 days
find "$BACKUP_DIR" -name "*.tar.gz" -mtime +7 -delete

echo "Backup completed: $BACKUP_DIR"

# Make executable and schedule
chmod +x /root/backup-dreammaker.sh

# Run daily at 1 AM
echo "0 1 * * * /root/backup-dreammaker.sh" | crontab -
```

### Telegram Alerts

```bash
#!/bin/bash
# Create file: /root/send-alert.sh

# Configuration
BOT_TOKEN="YOUR_TG_BOT_TOKEN"
CHAT_ID="YOUR_TG_CHAT_ID"
MESSAGE="$1"

# Send to Telegram
curl -s -X POST \
  "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
  -d "chat_id=$CHAT_ID&text=$MESSAGE" > /dev/null

# Usage: /root/send-alert.sh "Xray restarted successfully"
```

---

## Emergency Recovery

### Service Failed?

```bash
# 1. Check status
systemctl status xray
systemctl status nginx

# 2. View recent logs
journalctl -u xray -n 20
journalctl -u nginx -n 20

# 3. Restart service
systemctl restart xray
systemctl restart nginx

# 4. Force reload
systemctl daemon-reload
systemctl start xray
systemctl start nginx

# 5. Verify
netstat -tlnp | grep LISTEN
```

### Configuration Syntax Error?

```bash
# 1. Validate configuration
xray -c /etc/xray/config.json -test
nginx -t

# 2. Find the error (look at output)

# 3. Restore from backup
tar -xzf /root/backups/xray-config-YYYY-MM-DD_HH-MM-SS.tar.gz -C /

# 4. Restart
systemctl restart xray
```

### Disk Space Issue?

```bash
# Check disk usage
df -h /

# Clear old logs (if safe)
# WARNING: Only if logs are not needed for investigation
rm /var/log/nginx/access.log.*.gz
rm /var/log/xray/error.log.*.gz

# Or use logrotate (recommended)
nano /etc/logrotate.d/nginx
nano /etc/logrotate.d/xray

# Example rotation (daily, keep 7 days):
/var/log/xray/error.log {
    daily
    rotate 7
    compress
    delaycompress
    notifempty
    create 644 root root
    sharedscripts
}
```

### Full System Reset (Extreme)

```bash
# ⚠️  LAST RESORT ONLY

# 1. Stop services
systemctl stop nginx xray

# 2. Clear configurations
rm /etc/xray/config.json
rm /etc/nginx/nginx.conf

# 3. Restore from backup
tar -xzf /root/backups/LATEST_BACKUP.tar.gz -C /

# 4. Restart
systemctl start nginx xray

# 5. Verify
systemctl status nginx xray
```

---

## Maintenance Schedule

### Daily
- Check health endpoint
- Monitor error logs
- Verify process status

### Weekly
- Review access patterns
- Check disk usage
- Backup configuration

### Monthly
- Rotate logs
- Update system packages
- Review security policies

### Quarterly
- Update Xray core
- Update Nginx
- Test recovery procedures

---

## Troubleshooting

### Issue: "Connection refused" to 82.115.26.105:80/443

**Cause:** Nginx not running or firewall blocked

**Solution:**
```bash
# Check Nginx
systemctl status nginx
systemctl restart nginx

# Check firewall
ufw status
ufw allow 80/tcp
ufw allow 443/tcp
```

### Issue: Subscriptions return 502 Bad Gateway

**Cause:** Xray offline or misconfigured

**Solution:**
```bash
# Check Xray
systemctl status xray

# Validate config
xray -c /etc/xray/config.json -test

# Check ports
netstat -tlnp | grep 110

# Restart
systemctl restart xray
```

### Issue: High CPU usage by Xray

**Cause:** Too many connections or resource leak

**Solution:**
```bash
# Monitor connections
netstat -an | grep ESTABLISHED | wc -l

# Restart Xray
systemctl restart xray

# Check logs for errors
tail -50 /var/log/xray/error.log
```

### Issue: Certificate errors in HTTPS

**Cause:** Let's Encrypt certificate expired or misconfigured

**Solution:**
```bash
# Renew certificate
certbot renew --nginx

# Or manual renewal
certbot renew --force-renewal

# Reload Nginx
systemctl reload nginx
```

---

## Support & Escalation

### Check Status Page

```bash
# Quick health check
curl -s https://dreammaker-groupsoft.ir/health | jq .

# Expected response:
# { "status": "healthy", "timestamp": "..." }
```

### Contact Information

- **GitHub:** https://github.com/dreammaker/infrastructure
- **Issues:** Report via GitHub Issues
- **Email:** support@dreammaker-groupsoft.ir
- **Telegram:** [@Freqbasterd_bot](https://t.me/Freqbasterd_bot)

---

**Document Version:** 1.0.0  
**Last Updated:** 2026-05-09  
**Status:** Complete & Production-Ready

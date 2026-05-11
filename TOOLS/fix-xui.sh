#!/usr/bin/env bash
# ============================================================
# DreamMaker — x-ui Fix Script
# Fixes: corrupt inbound in DB + restores valid base config.json
# Run as root on DE VPS
# ============================================================
set -e

CONFIG="/usr/local/x-ui/bin/config.json"
DB="/etc/x-ui/x-ui.db"

echo "==> [1/5] Stopping x-ui..."
systemctl stop x-ui

echo "==> [2/5] Backing up current config and DB..."
cp "$CONFIG" "$CONFIG.bak.$(date +%s)" 2>/dev/null || true
cp "$DB"     "$DB.bak.$(date +%s)"     2>/dev/null || true

echo "==> [3/5] Checking corrupt inbounds in x-ui DB..."
echo "--- Inbounds with empty/null protocol:"
sqlite3 "$DB" "SELECT id, tag, remark, protocol FROM inbounds WHERE protocol = '' OR protocol IS NULL;"

echo "--- Deleting corrupt inbounds..."
sqlite3 "$DB" "DELETE FROM inbounds WHERE protocol = '' OR protocol IS NULL;"

echo "--- Remaining inbounds:"
sqlite3 "$DB" "SELECT id, tag, remark, protocol, port FROM inbounds;"

echo "==> [4/5] Writing clean base config.json..."
# NOTE: x-ui manages VLESS inbounds via DB — do NOT put vless inbounds here
# Add inbounds via x-ui web panel (port 2822) after this script runs
cat > "$CONFIG" << 'JSON'
{
  "log": {
    "access": "none",
    "error": "/var/log/xray/error.log",
    "loglevel": "warning",
    "dnsLog": false,
    "maskAddress": ""
  },
  "api": {
    "tag": "api",
    "services": ["HandlerService", "LoggerService", "StatsService"]
  },
  "stats": {},
  "policy": {
    "levels": {
      "0": {
        "handshake": 4,
        "connIdle": 300,
        "uplinkOnly": 2,
        "downlinkOnly": 5,
        "bufferSize": 256,
        "statsUserUplink": true,
        "statsUserDownlink": true
      }
    },
    "system": {
      "statsInboundUplink": true,
      "statsInboundDownlink": true,
      "statsOutboundUplink": false,
      "statsOutboundDownlink": false
    }
  },
  "dns": {
    "queryStrategy": "UseIPv4",
    "disableCache": false,
    "disableFallback": false,
    "servers": [
      { "address": "https+local://1.1.1.1/dns-query", "skipFallback": true  },
      { "address": "https+local://8.8.8.8/dns-query",  "skipFallback": false },
      "localhost"
    ],
    "tag": "dns_in"
  },
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "domainMatcher": "hybrid",
    "rules": [
      {
        "type": "field",
        "inboundTag": ["api"],
        "outboundTag": "api"
      },
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "blocked"
      },
      {
        "type": "field",
        "protocol": ["bittorrent"],
        "outboundTag": "blocked"
      },
      {
        "type": "field",
        "domain": ["geosite:category-ads-all"],
        "outboundTag": "blocked"
      },
      {
        "type": "field",
        "domain": ["geosite:openai"],
        "outboundTag": "warp"
      }
    ]
  },
  "inbounds": [],
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom",
      "settings": {
        "domainStrategy": "UseIPv4"
      },
      "streamSettings": {
        "sockopt": {
          "tcpFastOpen": true,
          "tcpNoDelay": true,
          "tcpKeepAliveIdle": 120,
          "mark": 255
        }
      }
    },
    {
      "tag": "warp",
      "protocol": "socks",
      "settings": {
        "servers": [{ "address": "127.0.0.1", "port": 40000 }]
      }
    },
    {
      "tag": "blocked",
      "protocol": "blackhole",
      "settings": {}
    },
    {
      "tag": "api",
      "protocol": "dns"
    }
  ]
}
JSON

echo "==> [5/5] Starting x-ui..."
systemctl start x-ui
sleep 3

echo ""
echo "==> Status:"
systemctl is-active x-ui && echo "x-ui: RUNNING" || echo "x-ui: FAILED"

echo ""
echo "==> Last 10 log lines:"
journalctl -u x-ui -n 10 --no-pager

echo ""
echo "============================================================"
echo "NEXT STEPS — Add inbounds via x-ui panel:"
echo "  Panel URL : https://$(hostname -I | awk '{print $1}'):2822"
echo "  OR use the add-inbounds-api.sh script to add all 7 tiers"
echo "============================================================"

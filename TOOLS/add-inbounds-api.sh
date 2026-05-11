#!/usr/bin/env bash
# ============================================================
# DreamMaker — Add 7 VLESS Inbounds via x-ui API
# Run AFTER fix-xui.sh — x-ui must be running
# Edit XUI_USER / XUI_PASS if changed from defaults
# ============================================================

XUI_BASE="http://127.0.0.1:2822"
XUI_USER="admin"
XUI_PASS="admin"
COOKIE_JAR="/tmp/xui-cookies.txt"

echo "==> Logging into x-ui..."
LOGIN=$(curl -s -c "$COOKIE_JAR" -X POST "$XUI_BASE/login" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=$XUI_USER&password=$XUI_PASS")

echo "Login response: $LOGIN"

if ! echo "$LOGIN" | grep -q '"success":true'; then
  echo "ERROR: Login failed — check XUI_USER / XUI_PASS"
  exit 1
fi

add_inbound() {
  local TAG="$1"
  local PORT="$2"
  local UUID="$3"
  local EMAIL="$4"
  local PATH_="$5"
  local REMARK="$6"
  local LIMIT_GB="$7"  # 0 = unlimited

  local LIMIT_BYTES=$(( LIMIT_GB * 1024 * 1024 * 1024 ))
  [ "$LIMIT_GB" = "0" ] && LIMIT_BYTES=0

  PAYLOAD=$(cat << EOF
{
  "remark": "$REMARK",
  "enable": true,
  "expiryTime": 0,
  "listen": "127.0.0.1",
  "port": $PORT,
  "protocol": "vless",
  "settings": "{\"clients\":[{\"id\":\"$UUID\",\"email\":\"$EMAIL\",\"flow\":\"\"}],\"decryption\":\"none\"}",
  "streamSettings": "{\"network\":\"xhttp\",\"security\":\"none\",\"xhttpSettings\":{\"path\":\"$PATH_\",\"host\":\"cdn.dreammaker-groupsoft.ir\",\"mode\":\"auto\",\"xPaddingBytes\":\"100-1000\",\"headers\":{}}}",
  "sniffing": "{\"enabled\":true,\"destOverride\":[\"http\",\"tls\",\"quic\"]}",
  "total": $LIMIT_BYTES
}
EOF
)

  RESULT=$(curl -s -b "$COOKIE_JAR" -X POST "$XUI_BASE/xui/inbound/add" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD")

  if echo "$RESULT" | grep -q '"success":true'; then
    echo "  ✅ Added: $REMARK (port $PORT)"
  else
    echo "  ❌ Failed: $REMARK — $RESULT"
  fi
}

echo ""
echo "==> Adding 7 VLESS inbounds..."

add_inbound \
  "vless-starter" 11001 \
  "7dd47c02-8dce-4b12-9dbc-7cdb95a9e10e" \
  "🔵 DreamMaker | STARTER · 1 GB" \
  "/api/v1/ping" \
  "🔵 STARTER — 1 GB" \
  1

add_inbound \
  "vless-basic" 11002 \
  "92ebaa01-ec34-4601-a4dc-f6afdf822966" \
  "🟢 DreamMaker | BASIC · 2 GB" \
  "/cdn/init" \
  "🟢 BASIC — 2 GB" \
  2

add_inbound \
  "vless-standard" 11003 \
  "3d5e3adf-0912-4c78-9ca9-b87db334ce71" \
  "⚡ DreamMaker | STANDARD · 5 GB" \
  "/app/sync" \
  "⚡ STANDARD — 5 GB" \
  5

add_inbound \
  "vless-plus" 11004 \
  "e8eb3d74-8e8c-4903-b878-8feb656ebb0c" \
  "🚀 DreamMaker | PLUS · 10 GB" \
  "/api/v2/feed" \
  "🚀 PLUS — 10 GB" \
  10

add_inbound \
  "vless-pro" 11005 \
  "b3540a54-67dd-452a-b5d8-45d6407b8da5" \
  "💫 DreamMaker | PRO · 15 GB" \
  "/static/bundle.js" \
  "💫 PRO — 15 GB" \
  15

add_inbound \
  "vless-elite" 11006 \
  "2680152c-0dc3-4fdb-b366-e936358b121f" \
  "🔥 DreamMaker | ELITE · 20 GB" \
  "/media/stream" \
  "🔥 ELITE — 20 GB" \
  20

add_inbound \
  "vless-unlimited" 11007 \
  "89c0f294-3f94-4735-96cf-9c1aefdbcbb2" \
  "💎 DreamMaker | UNLIMITED · ∞" \
  "/v2/content/live" \
  "💎 UNLIMITED — ∞" \
  0

echo ""
echo "==> Verifying inbounds on localhost..."
ss -tlnp | grep -E ":(1100[1-7])" || echo "WARNING: Some ports not listening yet"

echo ""
echo "==> Done. Check x-ui panel: https://82.115.26.105:2822"

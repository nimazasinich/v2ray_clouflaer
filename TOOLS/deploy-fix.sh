#!/bin/bash
# ============================================================
# Deploy edge-ws-relay-v4 (patched v7.1 — CDN loop fix)
# ============================================================

set -e

CF_TOKEN="cfut_dwkZszri1j76LDzWaGSryhQymn4DHeQcY8QXjNZw621e11a8"
CF_ACCOUNT_ID="d902b91f0f1076e0601ffd6e7b4382c0"
WORKER_NAME="edge-ws-relay-v4"
TG_BOT_TOKEN="7437859619:AAH-2MJdlNmNf7ZSlj16zf-g0QJqB-TIxJU"
TG_CHAT_ID="7437859619"

echo "🔧 Deploying patched $WORKER_NAME (v7.1 CDN loop fix)..."

# 1. Install wrangler if needed
if ! command -v npx &>/dev/null; then
  echo "❌ npx not found — install Node.js first"
  exit 1
fi

# 2. Authenticate
export CLOUDFLARE_API_TOKEN="$CF_TOKEN"
export CLOUDFLARE_ACCOUNT_ID="$CF_ACCOUNT_ID"

# 3. Set secrets
echo "Setting secrets..."
echo "$TG_BOT_TOKEN" | npx wrangler secret put TG_BOT_TOKEN --name "$WORKER_NAME"
echo "$TG_CHAT_ID"   | npx wrangler secret put TG_CHAT_ID   --name "$WORKER_NAME"

# 4. Deploy
echo "Deploying worker..."
npx wrangler deploy --name "$WORKER_NAME"

echo ""
echo "✅ Deployed. Verify:"
echo "  curl https://dreammaker-groupsoft.ir/health"
echo "  curl https://dreammaker-groupsoft.ir/ping"
echo "  curl https://dreammaker-groupsoft.ir/worker-info"
echo ""
echo "⚠️  DNS CHECK REQUIRED:"
echo "  direct1.dreammaker-groupsoft.ir → must be GREY CLOUD → 82.115.26.105"
echo "  direct2.dreammaker-groupsoft.ir → must be GREY CLOUD → 82.115.26.105"

#!/bin/bash
set -e

echo "═══════════════════════════════════════════════════════════════════"
echo "DreamMaker Panel Workers — FIXED DEPLOYMENT"
echo "═══════════════════════════════════════════════════════════════════"
echo ""
echo "Changes made:"
echo "  ✗ dreammaker-panel-access: 82.115.26.105:2053 → direct1.dreammaker-groupsoft.ir:2053"
echo "  ✗ dreammaker-panel-edge-v2: 82.115.26.105:18822 → direct1.dreammaker-groupsoft.ir:2053/panel-proxy/"
echo ""

export CLOUDFLARE_API_TOKEN="cfut_9X9JcNyxRKrZTwKg8fdQ2ua26ftC6nk5ltQeurdwbd919108"

# Get the directory where the script is
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[1/2] Deploying dreammaker-panel-access..."
# Assuming you have wrangler.toml in a worker project directory
# This is a placeholder — adjust paths to your actual worker directories

# For dreammaker-panel-access:
# wrangler deploy --name dreammaker-panel-access /path/to/dreammaker-panel-access-fixed.js

# For dreammaker-panel-edge-v2:
# wrangler deploy --name dreammaker-panel-edge-v2 /path/to/dreammaker-panel-edge-v2-fixed.js

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "MANUAL DEPLOYMENT STEPS:"
echo ""
echo "Option A: Using wrangler CLI (recommended)"
echo "─────────────────────────────────────────"
echo ""
echo "1. Replace worker code in your project:"
echo "   cp dreammaker-panel-access-fixed.js /path/to/dreammaker-panel-access/src/index.js"
echo "   cp dreammaker-panel-edge-v2-fixed.js /path/to/dreammaker-panel-edge-v2/src/index.js"
echo ""
echo "2. Deploy:"
echo "   export CLOUDFLARE_API_TOKEN='cfut_9X9JcNyxRKrZTwKg8fdQ2ua26ftC6nk5ltQeurdwbd919108'"
echo "   wrangler deploy"
echo ""
echo "Option B: Using Cloudflare API directly"
echo "────────────────────────────────────────"
echo ""
echo "   curl -X PUT https://api.cloudflare.com/client/v4/accounts/d902b91f0f1076e0601ffd6e7b4382c0/workers/scripts/dreammaker-panel-access \\"
echo "     -H 'Authorization: Bearer cfut_9X9JcNyxRKrZTwKg8fdQ2ua26ftC6nk5ltQeurdwbd919108' \\"
echo "     -F 'metadata=@wrangler.toml' \\"
echo "     -F 'script=@dreammaker-panel-access-fixed.js'"
echo ""
echo "   curl -X PUT https://api.cloudflare.com/client/v4/accounts/d902b91f0f1076e0601ffd6e7b4382c0/workers/scripts/dreammaker-panel-edge-v2 \\"
echo "     -H 'Authorization: Bearer cfut_9X9JcNyxRKrZTwKg8fdQ2ua26ftC6nk5ltQeurdwbd919108' \\"
echo "     -F 'metadata=@wrangler.toml' \\"
echo "     -F 'script=@dreammaker-panel-edge-v2-fixed.js'"
echo ""
echo "═══════════════════════════════════════════════════════════════════"

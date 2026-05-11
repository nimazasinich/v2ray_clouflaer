#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

echo "[DreamMaker] Bootstrapping environment..."

if [ -f .env ]; then
  set -a
  source .env
  set +a
else
  echo "[WARN] .env not found. Using exported environment variables only."
fi

# Accept either the exact handoff names or the standard Cloudflare names.
export CLOUDFLARE_API_TOKEN="${CF_TOKEN_FULL:-${CF_API_TOKEN:-${CLOUDFLARE_API_TOKEN:-}}}"
export CLOUDFLARE_ACCOUNT_ID="${CF_ACCOUNT_ID:-${CLOUDFLARE_ACCOUNT_ID:-}}"

if [ -z "${CLOUDFLARE_API_TOKEN:-}" ]; then
  echo "[ERROR] Missing Cloudflare API token."
  echo "        Set CF_TOKEN_FULL or CF_API_TOKEN, or create .env from .env.example."
  exit 1
fi

if [ -z "${CLOUDFLARE_ACCOUNT_ID:-}" ]; then
  echo "[ERROR] Missing Cloudflare account id."
  echo "        Set CF_ACCOUNT_ID, or create .env from .env.example."
  exit 1
fi

if [ ! -f "config.ts" ]; then
  echo "[ERROR] config.ts missing."
  exit 1
fi

if [ ! -f "wrangler.toml" ]; then
  echo "[ERROR] wrangler.toml missing."
  exit 1
fi

echo "[DreamMaker] Validating local files..."
bash -n deploy-worker-dreammaker.sh
bash -n deploy.sh 2>/dev/null || true

echo "[DreamMaker] Deploying Cloudflare Worker (Tier 0 only)..."
npx wrangler deploy --config wrangler.toml

echo "[DreamMaker] Deployment complete."

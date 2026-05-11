#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

echo "[DreamMaker] Loading environment..."
if [ -f .env ]; then
  set -a
  source .env
  set +a
fi

export CLOUDFLARE_API_TOKEN="${CF_TOKEN_FULL:-${CF_API_TOKEN:-${CLOUDFLARE_API_TOKEN:-}}}"
export CLOUDFLARE_ACCOUNT_ID="${CF_ACCOUNT_ID:-${CLOUDFLARE_ACCOUNT_ID:-}}"

if [ -z "${CLOUDFLARE_API_TOKEN:-}" ]; then
  echo "Missing Cloudflare API token (CF_TOKEN_FULL or CF_API_TOKEN)."
  exit 1
fi

if [ -z "${CLOUDFLARE_ACCOUNT_ID:-}" ]; then
  echo "Missing Cloudflare account id (CF_ACCOUNT_ID)."
  exit 1
fi

echo "[DreamMaker] Deploying Tier0 (hot path)..."
npx wrangler deploy --config wrangler-tier0.toml

if [ "${DEPLOY_ALL:-1}" = "1" ]; then
  echo "[DreamMaker] Deploying Tier1..."
  npx wrangler deploy --config wrangler-tier1.toml

  echo "[DreamMaker] Deploying Tier2..."
  npx wrangler deploy --config wrangler-tier2.toml

  if [ -n "${CF_D1_DATABASE_ID:-}" ]; then
    echo "[DreamMaker] Applying schema..."
    npx wrangler d1 execute dreammaker --file=schema.sql --remote
  fi
fi

echo "[DreamMaker] Done."

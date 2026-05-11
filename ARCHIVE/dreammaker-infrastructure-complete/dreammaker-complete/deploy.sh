#!/usr/bin/env bash
# =============================================================
# DreamMaker — Cloudflare Workers Deploy Script
# Compatible with: wrangler.toml / wrangler-tier1.toml / wrangler-tier2.toml
# Usage:
#   ./deploy.sh              — deploy all tiers
#   ./deploy.sh tier0        — deploy Tier 0 only
#   ./deploy.sh tier1        — deploy Tier 1 only
#   ./deploy.sh tier2        — deploy Tier 2 only
# =============================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

# ── 1. Load .env ────────────────────────────────────────────
if [ -f "$ROOT_DIR/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.env"
  set +a
  echo "[OK] .env loaded"
else
  echo "[WARN] .env not found — using shell environment only"
fi

# ── 2. Map variable names → what wrangler expects ───────────
export CLOUDFLARE_API_TOKEN="cfut_9X9JcNyxRKrZTwKg8fdQ2ua26ftC6nk5ltQeurdwbd919108"

export CLOUDFLARE_ACCOUNT_ID="d902b91f0f1076e0601ffd6e7b4382c0"


# ── 3. Guard: required vars ──────────────────────────────────
if [ -z "${CLOUDFLARE_API_TOKEN}" ]; then
  echo "[ERROR] CF_TOKEN_FULL is not set. Add it to .env or export it."
  exit 1
fi

if [ -z "${CLOUDFLARE_ACCOUNT_ID}" ]; then
  echo "[ERROR] CF_ACCOUNT_ID is not set. Add it to .env or export it."
  exit 1
fi

# ── 4. Guard: required files ─────────────────────────────────
for f in config.ts edge-worker-tier0.ts helper-ecosystem-tier1.ts \
          control-plane-tier2.ts wrangler.toml wrangler-tier1.toml \
          wrangler-tier2.toml; do
  if [ ! -f "$ROOT_DIR/$f" ]; then
    echo "[ERROR] Missing required file: $f"
    exit 1
  fi
done

# ── 5. Install wrangler if missing ───────────────────────────
if ! command -v wrangler &>/dev/null; then
  echo "[INFO] wrangler not found — installing via npm..."
  npm install --prefer-offline --no-audit wrangler
  WRANGLER="npx wrangler"
else
  WRANGLER="wrangler"
fi

echo "[INFO] wrangler: $($WRANGLER --version 2>&1 | head -1)"

# ── 6. Decide what to deploy ─────────────────────────────────
TARGET="${1:-all}"   # first argument or "all"

deploy_tier0() {
  echo ""
  echo "━━━ Tier 0 — Edge Worker ━━━"
  $WRANGLER deploy --config "$ROOT_DIR/wrangler.toml"
  echo "[OK] Tier 0 deployed"
}

deploy_tier1() {
  echo ""
  echo "━━━ Tier 1 — Helper Ecosystem ━━━"
  $WRANGLER deploy --config "$ROOT_DIR/wrangler-tier1.toml"

  # Push Telegram secrets if available
  if [ -n "${TG_BOT_TOKEN:-}" ]; then
    echo "${TG_BOT_TOKEN}" | \
      $WRANGLER secret put TG_BOT_TOKEN \
        --config "$ROOT_DIR/wrangler-tier1.toml" 2>/dev/null || true
  fi
  if [ -n "${TG_CHAT_ID:-}" ]; then
    echo "${TG_CHAT_ID}" | \
      $WRANGLER secret put TG_CHAT_ID \
        --config "$ROOT_DIR/wrangler-tier1.toml" 2>/dev/null || true
  fi
  echo "[OK] Tier 1 deployed"
}

deploy_tier2() {
  echo ""
  echo "━━━ Tier 2 — Control Plane ━━━"

  # D1 database ID must be real before deploying tier2
  if grep -q "REPLACE_D1_ID" "$ROOT_DIR/wrangler-tier2.toml"; then
    if [ -z "${CF_D1_DATABASE_ID:-}" ]; then
      echo "[WARN] CF_D1_DATABASE_ID not set and wrangler-tier2.toml still has"
      echo "       REPLACE_D1_ID placeholder — skipping Tier 2."
      echo "       Create a D1 database first:"
      echo "       wrangler d1 create dreammaker-db"
      echo "       Then add CF_D1_DATABASE_ID to .env and re-run."
      return 0
    fi
    # Patch the placeholder in-place (temp copy, don't touch original)
    TMPTOML="$(mktemp)"
    sed "s/REPLACE_D1_ID/${CF_D1_DATABASE_ID}/g" \
        "$ROOT_DIR/wrangler-tier2.toml" > "$TMPTOML"
    $WRANGLER deploy --config "$TMPTOML"
    rm -f "$TMPTOML"
  else
    $WRANGLER deploy --config "$ROOT_DIR/wrangler-tier2.toml"
  fi

  # Push secrets for tier2
  if [ -n "${ADMIN_TOKEN:-}" ]; then
    echo "${ADMIN_TOKEN}" | \
      $WRANGLER secret put ADMIN_TOKEN \
        --config "$ROOT_DIR/wrangler-tier2.toml" 2>/dev/null || true
  fi
  if [ -n "${JWT_SECRET:-}" ]; then
    echo "${JWT_SECRET}" | \
      $WRANGLER secret put JWT_SECRET \
        --config "$ROOT_DIR/wrangler-tier2.toml" 2>/dev/null || true
  fi
  if [ -n "${TG_BOT_TOKEN:-}" ]; then
    echo "${TG_BOT_TOKEN}" | \
      $WRANGLER secret put TG_BOT_TOKEN \
        --config "$ROOT_DIR/wrangler-tier2.toml" 2>/dev/null || true
  fi
  if [ -n "${TG_CHAT_ID:-}" ]; then
    echo "${TG_CHAT_ID}" | \
      $WRANGLER secret put TG_CHAT_ID \
        --config "$ROOT_DIR/wrangler-tier2.toml" 2>/dev/null || true
  fi
  echo "[OK] Tier 2 deployed"
}

# ── 7. Run ───────────────────────────────────────────────────
case "$TARGET" in
  tier0) deploy_tier0 ;;
  tier1) deploy_tier1 ;;
  tier2) deploy_tier2 ;;
  all)
    deploy_tier0
    deploy_tier1
    deploy_tier2
    ;;
  *)
    echo "[ERROR] Unknown target: $TARGET"
    echo "        Usage: $0 [tier0|tier1|tier2|all]"
    exit 1
    ;;
esac

echo ""
echo "✓ Done."

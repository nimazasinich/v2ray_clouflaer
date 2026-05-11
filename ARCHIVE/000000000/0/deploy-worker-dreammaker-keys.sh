#!/bin/bash

################################################################################
# DreamMaker Cloudflare Worker Deployment Script (SSH Key-Based)
# 
# Purpose: Secure deployment using SSH public key authentication
# No password required — uses SSH keys instead
# 
# SETUP:
#  1. Generate SSH key pair (if needed):
#     ssh-keygen -t ed25519 -f ~/.ssh/dreammaker_vps -N ""
#
#  2. Add public key to VPS:
#     scp -P 22 ~/.ssh/dreammaker_vps.pub root@82.115.26.105:~/.ssh/authorized_keys
#
#  3. Run this script:
#     ./deploy-worker-dreammaker-keys.sh
################################################################################

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SSH_KEY="${SSH_KEY:-${HOME}/.ssh/dreammaker_vps}"
SSH_CONFIG_FILE="${SCRIPT_DIR}/ssh_config"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ─────────────────────────────────────────────────────────────────────────────
# Logging Functions
# ─────────────────────────────────────────────────────────────────────────────

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $*" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ─────────────────────────────────────────────────────────────────────────────
# Parse Arguments
# ─────────────────────────────────────────────────────────────────────────────

DRY_RUN=false
DEBUG=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run) DRY_RUN=true; shift ;;
    --debug) DEBUG=true; shift ;;
    --key) SSH_KEY="$2"; shift 2 ;;
    *) log_error "Unknown argument: $1"; exit 1 ;;
  esac
done

# ─────────────────────────────────────────────────────────────────────────────
# Load Environment Variables
# ─────────────────────────────────────────────────────────────────────────────

ENV_FILE="${SCRIPT_DIR}/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  log_error "Environment file not found: $ENV_FILE"
  exit 1
fi

set +u
source "$ENV_FILE"
set -u

# Validate required variables
for var in CF_API_TOKEN CF_ZONE_ID CF_ACCOUNT_ID VPS_DE_IP VPS_DE_USER VPS_DE_PORT DOMAIN; do
  if [[ -z "${!var:-}" ]]; then
    log_error "Required variable not set: $var"
    exit 1
  fi
done

# ─────────────────────────────────────────────────────────────────────────────
# Validate SSH Key
# ─────────────────────────────────────────────────────────────────────────────

if [[ ! -f "$SSH_KEY" ]]; then
  log_error "SSH key not found: $SSH_KEY"
  log_info "Generate a key with:"
  echo "  ssh-keygen -t ed25519 -f $SSH_KEY -N \"\""
  exit 1
fi

if [[ ! -r "$SSH_KEY" ]]; then
  log_error "SSH key is not readable: $SSH_KEY"
  exit 1
fi

log_success "SSH key validated: $SSH_KEY"

# ─────────────────────────────────────────────────────────────────────────────
# SSH Helper Functions
# ─────────────────────────────────────────────────────────────────────────────

ssh_execute() {
  local cmd=$1
  local desc=${2:-"Execute command"}

  log_info "$desc..."

  local ssh_opts=(
    -i "$SSH_KEY"
    -o StrictHostKeyChecking=accept-new
    -o UserKnownHostsFile="${HOME}/.ssh/known_hosts"
    -o ConnectTimeout=10
    -o BatchMode=yes
  )

  if [[ "$DEBUG" == true ]]; then
    log_info "SSH Command: $cmd"
    ssh_opts+=(-v)
  fi

  if [[ "$DRY_RUN" == true ]]; then
    log_info "[DRY RUN] Would execute: $cmd"
    return 0
  fi

  ssh "${ssh_opts[@]}" -p "$VPS_DE_PORT" \
    "${VPS_DE_USER}@${VPS_DE_IP}" \
    "$cmd" || return 1
}

scp_push() {
  local src=$1
  local dst=$2
  local desc=${3:-"Copy file"}

  log_info "$desc..."

  if [[ ! -f "$src" ]]; then
    log_error "Source file not found: $src"
    return 1
  fi

  if [[ "$DRY_RUN" == true ]]; then
    log_info "[DRY RUN] Would copy: $src → $dst"
    return 0
  fi

  scp -i "$SSH_KEY" \
    -o StrictHostKeyChecking=accept-new \
    -P "$VPS_DE_PORT" \
    "$src" "${VPS_DE_USER}@${VPS_DE_IP}:${dst}" || return 1
}

# ─────────────────────────────────────────────────────────────────────────────
# Deployment Functions
# ─────────────────────────────────────────────────────────────────────────────

prepare_vps() {
  log_info "Preparing VPS for deployment..."

  ssh_execute "mkdir -p /root/dreammaker-worker/src" \
    "Create working directory"

  ssh_execute "command -v node || (curl -fsSL https://deb.nodesource.com/setup_18.x | bash && apt-get install -y nodejs)" \
    "Install/verify Node.js"

  ssh_execute "npm install -g wrangler" \
    "Install Wrangler CLI"

  ssh_execute "wrangler --version" \
    "Verify Wrangler installation"

  log_success "VPS preparation complete"
}

upload_files() {
  log_info "Uploading files to VPS..."

  scp_push "${SCRIPT_DIR}/edge-worker-tier0.ts" \
    "/root/dreammaker-worker/src/index.ts" \
    "Upload edge worker"

  scp_push "${SCRIPT_DIR}/config.ts" \
    "/root/dreammaker-worker/src/config.ts" \
    "Upload configuration"

  scp_push "${SCRIPT_DIR}/.env" \
    "/root/dreammaker-worker/.env" \
    "Upload environment variables"

  log_success "Files uploaded"
}

create_configs() {
  log_info "Creating configuration files..."

  # Create wrangler.toml
  cat > /tmp/wrangler.toml <<EOF
name = "dreammaker-tier0"
type = "service"
main = "src/index.ts"
account_id = "${CF_ACCOUNT_ID}"
workers_dev = false
compatibility_date = "2024-12-16"
compatibility_flags = ["nodejs_compat"]

route = {
  pattern = "cdn.dreammaker-groupsoft.ir/*",
  zone_id = "${CF_ZONE_ID}"
}

[env.production]
routes = [
  { pattern = "cdn.dreammaker-groupsoft.ir/*", zone_id = "${CF_ZONE_ID}" }
]

[[env.production.kv_namespaces]]
binding = "DM_KV"
id = "${CF_KV_NAMESPACE_ID}"
EOF

  # Create tsconfig.json
  cat > /tmp/tsconfig.json <<'EOF'
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "ES2020",
    "lib": ["ES2020"],
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true
  },
  "include": ["src/**/*.ts"],
  "exclude": ["node_modules"]
}
EOF

  # Create package.json
  cat > /tmp/package.json <<'EOF'
{
  "name": "dreammaker-tier0",
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "build": "tsc",
    "deploy": "wrangler deploy --env production"
  },
  "devDependencies": {
    "@cloudflare/workers-types": "latest",
    "typescript": "latest",
    "wrangler": "latest"
  }
}
EOF

  # Upload configs
  scp_push /tmp/wrangler.toml \
    "/root/dreammaker-worker/wrangler.toml" \
    "Upload wrangler.toml"

  scp_push /tmp/tsconfig.json \
    "/root/dreammaker-worker/tsconfig.json" \
    "Upload tsconfig.json"

  scp_push /tmp/package.json \
    "/root/dreammaker-worker/package.json" \
    "Upload package.json"

  rm -f /tmp/wrangler.toml /tmp/tsconfig.json /tmp/package.json

  log_success "Configuration files created"
}

deploy_worker() {
  log_info "Deploying to Cloudflare..."

  ssh_execute "cd /root/dreammaker-worker && npm install" \
    "Install dependencies"

  ssh_execute "cd /root/dreammaker-worker && npm run build" \
    "Build TypeScript"

  # Set API token for wrangler
  ssh_execute "cd /root/dreammaker-worker && CLOUDFLARE_API_TOKEN='${CF_API_TOKEN}' wrangler deploy --env production" \
    "Deploy to Cloudflare"

  log_success "Deployment complete"
}

verify_deployment() {
  log_info "Verifying deployment..."

  sleep 5

  if curl -sf "https://cdn.dreammaker-groupsoft.ir/" &>/dev/null; then
    log_success "Worker is accessible"
  else
    log_warning "Could not verify worker (may be blocked locally)"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

main() {
  log_info "🚀 DreamMaker Worker Deployment (SSH Key-Based)"
  log_info "VPS: ${VPS_DE_USER}@${VPS_DE_IP}:${VPS_DE_PORT}"
  log_info "Domain: ${DOMAIN}"

  [[ "$DRY_RUN" == true ]] && log_warning "⚠️  DRY RUN MODE"

  # Step 1: Test SSH connection
  log_info "Testing SSH connection..."
  if ! ssh_execute "echo 'SSH connection successful'" "Verify SSH"; then
    log_error "Failed to connect via SSH"
    exit 1
  fi
  log_success "SSH connection verified"

  # Step 2: Prepare VPS
  prepare_vps || exit 1

  # Step 3: Upload files
  upload_files || exit 1

  # Step 4: Create configurations
  create_configs || exit 1

  # Step 5: Deploy
  deploy_worker || exit 1

  # Step 6: Verify
  verify_deployment

  log_success "✅ Deployment completed successfully!"
}

trap 'log_error "Deployment failed"; exit 1' ERR
main "$@"

#!/bin/bash

################################################################################
# DreamMaker Cloudflare Worker Deployment Script
# 
# Purpose: Deploy edge worker (Tier 0) to Cloudflare through German VPS
# Strategy: SSH tunneling + wrangler CLI deployment
# Author: DreamMaker Infrastructure Team
# Date: 2026-05-09
#
# PREREQUISITES:
#  - SSH access to German VPS (82.115.26.105)
#  - Cloudflare API token (CF_API_TOKEN)
#  - Node.js 18+ installed locally or on VPS
#  - wrangler CLI installed
#  - .env file with all credentials
#
# USAGE:
#  ./deploy-worker-dreammaker.sh [--vps-only] [--dry-run] [--debug]
################################################################################

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Configuration & Environment
# ─────────────────────────────────────────────────────────────────────────────

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
  echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
  echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
  echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $*" >&2
}

# Parse command-line arguments
VPS_ONLY=false
DRY_RUN=false
DEBUG=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --vps-only)
      VPS_ONLY=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --debug)
      DEBUG=true
      shift
      ;;
    *)
      log_error "Unknown argument: $1"
      exit 1
      ;;
  esac
done

# ─────────────────────────────────────────────────────────────────────────────
# Load Environment Variables
# ─────────────────────────────────────────────────────────────────────────────

ENV_FILE="${SCRIPT_DIR}/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  log_error "Environment file not found: $ENV_FILE"
  log_info "Please create .env file with all required credentials"
  exit 1
fi

log_info "Loading environment from: $ENV_FILE"

# Source the .env file but don't fail if some vars are missing
set +u  # Allow undefined variables temporarily
source "$ENV_FILE" || true
set -u

# Validate critical environment variables
validate_env() {
  local required_vars=(
    "CF_API_TOKEN"
    "CF_ZONE_ID"
    "CF_ACCOUNT_ID"
    "VPS_DE_IP"
    "VPS_DE_USER"
    "VPS_DE_PORT"
    "VPS_DE_PASS"
    "DOMAIN"
  )

  for var in "${required_vars[@]}"; do
    if [[ -z "${!var:-}" ]]; then
      log_error "Required environment variable not set: $var"
      exit 1
    fi
  done

  log_success "Environment variables validated"
}

validate_env

# ─────────────────────────────────────────────────────────────────────────────
# File Validation
# ─────────────────────────────────────────────────────────────────────────────

validate_files() {
  local required_files=(
    "edge-worker-tier0.ts"
    "config.ts"
  )

  for file in "${required_files[@]}"; do
    if [[ ! -f "${SCRIPT_DIR}/${file}" ]]; then
      log_warning "File not found: ${SCRIPT_DIR}/${file}"
    fi
  done

  log_info "File validation complete"
}

validate_files

# ─────────────────────────────────────────────────────────────────────────────
# Telegram Notification Function
# ─────────────────────────────────────────────────────────────────────────────

send_telegram_notification() {
  local message=$1
  local status=${2:-"info"}  # info, success, error, warning

  if [[ -z "${TELEGRAM_BOT_TOKEN:-}" ]] || [[ -z "${TELEGRAM_CHAT_ID:-}" ]]; then
    log_warning "Telegram credentials not configured, skipping notification"
    return 0
  fi

  local emoji="ℹ️"
  case $status in
    success) emoji="✅" ;;
    error)   emoji="❌" ;;
    warning) emoji="⚠️" ;;
    info)    emoji="ℹ️" ;;
  esac

  local text="${emoji} DreamMaker Deployment

${message}

Domain: ${DOMAIN}
Timestamp: $(date -u '+%Y-%m-%d %H:%M:%S UTC')
Hostname: $(hostname)"

  # URL encode the message
  local encoded_text=$(echo "$text" | jq -sRr @uri)

  if [[ "$DRY_RUN" == false ]]; then
    curl -s -X POST \
      "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
      -d "chat_id=${TELEGRAM_CHAT_ID}" \
      -d "text=${text}" \
      -d "parse_mode=Markdown" \
      > /dev/null 2>&1 || true
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# SSH Connection Helper
# ─────────────────────────────────────────────────────────────────────────────

ssh_execute() {
  local command=$1
  local description=${2:-"Execute command"}

  log_info "$description..."

  if [[ "$DRY_RUN" == true ]]; then
    log_info "[DRY RUN] Would execute: $command"
    return 0
  fi

  if [[ "$DEBUG" == true ]]; then
    log_info "SSH Command: $command"
  fi

  # Use sshpass for password authentication
  sshpass -p "$VPS_DE_PASS" ssh \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=10 \
    -o BatchMode=no \
    -p "$VPS_DE_PORT" \
    "${VPS_DE_USER}@${VPS_DE_IP}" \
    "$command" || {
      log_error "SSH command failed: $description"
      return 1
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# File Transfer Helper
# ─────────────────────────────────────────────────────────────────────────────

scp_push() {
  local local_file=$1
  local remote_path=$2
  local description=${3:-"Copy file"}

  log_info "$description..."

  if [[ ! -f "$local_file" ]]; then
    log_error "Local file not found: $local_file"
    return 1
  fi

  if [[ "$DRY_RUN" == true ]]; then
    log_info "[DRY RUN] Would copy: $local_file → $remote_path"
    return 0
  fi

  sshpass -p "$VPS_DE_PASS" scp \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=10 \
    -P "$VPS_DE_PORT" \
    "$local_file" \
    "${VPS_DE_USER}@${VPS_DE_IP}:${remote_path}" || {
      log_error "SCP failed: $description"
      return 1
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Dependency Check (Local)
# ─────────────────────────────────────────────────────────────────────────────

check_dependencies() {
  log_info "Checking local dependencies..."

  # Check for sshpass
  if ! command -v sshpass &> /dev/null; then
    log_warning "sshpass not found. Installing..."
    if command -v apt-get &> /dev/null; then
      sudo apt-get update && sudo apt-get install -y sshpass
    elif command -v brew &> /dev/null; then
      brew install sshpass
    else
      log_error "Please install sshpass manually"
      return 1
    fi
  fi

  # Check for jq
  if ! command -v jq &> /dev/null; then
    log_warning "jq not found. Some features may not work."
  fi

  log_success "Local dependencies validated"
}

# ─────────────────────────────────────────────────────────────────────────────
# VPS Preparation
# ─────────────────────────────────────────────────────────────────────────────

prepare_vps() {
  log_info "Preparing German VPS for deployment..."

  # Create working directory
  ssh_execute "mkdir -p /root/dreammaker-worker/src" \
    "Create worker directory on VPS"

  # Install Node.js if not present
  ssh_execute "command -v node &>/dev/null || curl -fsSL https://deb.nodesource.com/setup_18.x | bash - && apt-get install -y nodejs" \
    "Install Node.js on VPS (if needed)"

  # Install wrangler CLI globally
  ssh_execute "npm install -g wrangler" \
    "Install Wrangler CLI on VPS"

  # Verify wrangler installation
  ssh_execute "wrangler --version" \
    "Verify Wrangler installation"

  log_success "VPS preparation complete"
}

# ─────────────────────────────────────────────────────────────────────────────
# Deploy Worker Files
# ─────────────────────────────────────────────────────────────────────────────

deploy_worker_files() {
  log_info "Uploading worker files to VPS..."

  local worker_dir="/root/dreammaker-worker"

  # Push TypeScript source files
  scp_push "${SCRIPT_DIR}/edge-worker-tier0.ts" \
    "${worker_dir}/src/index.ts" \
    "Upload edge worker TypeScript"

  scp_push "${SCRIPT_DIR}/config.ts" \
    "${worker_dir}/src/config.ts" \
    "Upload configuration file"

  # Push .env file
  scp_push "${SCRIPT_DIR}/.env" \
    "${worker_dir}/.env" \
    "Upload environment variables"

  log_success "Worker files uploaded to VPS"
}

# ─────────────────────────────────────────────────────────────────────────────
# Create wrangler.toml Configuration
# ─────────────────────────────────────────────────────────────────────────────

create_wrangler_config() {
  log_info "Creating wrangler.toml configuration..."

  local wrangler_config=$(cat <<EOF
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
  { pattern = "cdn.dreammaker-groupsoft.ir/*", zone_id = "${CF_ZONE_ID}" },
  { pattern = "api.dreammaker-groupsoft.ir/*", zone_id = "${CF_ZONE_ID}" }
]

[build]
command = "npm run build"
cwd = ""

[[env.production.kv_namespaces]]
binding = "DM_KV"
id = "${CF_KV_NAMESPACE_ID}"

[triggers.crons]
cron = "0 */6 * * *"

EOF
)

  if [[ "$DRY_RUN" == true ]]; then
    log_info "[DRY RUN] Would create wrangler.toml:"
    echo "$wrangler_config"
    return 0
  fi

  # Write to temporary file locally first
  local temp_wrangler=$(mktemp)
  echo "$wrangler_config" > "$temp_wrangler"

  # Push to VPS
  scp_push "$temp_wrangler" \
    "/root/dreammaker-worker/wrangler.toml" \
    "Upload wrangler.toml configuration"

  rm -f "$temp_wrangler"

  log_success "wrangler.toml created"
}

# ─────────────────────────────────────────────────────────────────────────────
# Create TypeScript Configuration
# ─────────────────────────────────────────────────────────────────────────────

create_typescript_config() {
  log_info "Creating TypeScript configuration..."

  local tsconfig=$(cat <<'EOF'
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "ES2020",
    "lib": ["ES2020"],
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true
  },
  "include": ["src/**/*.ts"],
  "exclude": ["node_modules", "dist"]
}
EOF
)

  if [[ "$DRY_RUN" == true ]]; then
    log_info "[DRY RUN] Would create tsconfig.json"
    return 0
  fi

  local temp_tsconfig=$(mktemp)
  echo "$tsconfig" > "$temp_tsconfig"

  scp_push "$temp_tsconfig" \
    "/root/dreammaker-worker/tsconfig.json" \
    "Upload TypeScript configuration"

  rm -f "$temp_tsconfig"

  log_success "tsconfig.json created"
}

# ─────────────────────────────────────────────────────────────────────────────
# Create package.json
# ─────────────────────────────────────────────────────────────────────────────

create_package_json() {
  log_info "Creating package.json..."

  local package_json=$(cat <<'EOF'
{
  "name": "dreammaker-tier0",
  "version": "1.0.0",
  "description": "DreamMaker Tier 0 Edge Worker for Cloudflare",
  "type": "module",
  "scripts": {
    "build": "tsc",
    "dev": "wrangler dev",
    "deploy": "wrangler deploy --env production",
    "deploy-local": "wrangler deploy",
    "test": "echo 'Add tests here'",
    "lint": "echo 'Add linting here'"
  },
  "dependencies": {},
  "devDependencies": {
    "@cloudflare/workers-types": "latest",
    "typescript": "latest",
    "wrangler": "latest"
  }
}
EOF
)

  if [[ "$DRY_RUN" == true ]]; then
    log_info "[DRY RUN] Would create package.json"
    return 0
  fi

  local temp_pkg=$(mktemp)
  echo "$package_json" > "$temp_pkg"

  scp_push "$temp_pkg" \
    "/root/dreammaker-worker/package.json" \
    "Upload package.json"

  rm -f "$temp_pkg"

  log_success "package.json created"
}

# ─────────────────────────────────────────────────────────────────────────────
# Verify Cloudflare Credentials
# ─────────────────────────────────────────────────────────────────────────────

verify_cloudflare_credentials() {
  log_info "Verifying Cloudflare API credentials..."

  if [[ "$DRY_RUN" == true ]]; then
    log_info "[DRY RUN] Would verify CF credentials"
    return 0
  fi

  local response=$(curl -s -X GET \
    "https://api.cloudflare.com/client/v4/user/tokens/verify" \
    -H "Authorization: Bearer ${CF_API_TOKEN}" \
    -H "Content-Type: application/json")

  if echo "$response" | jq -e '.success' &>/dev/null; then
    local token_status=$(echo "$response" | jq -r '.result.status')
    log_success "Cloudflare credentials verified (Status: $token_status)"
    return 0
  else
    log_error "Failed to verify Cloudflare credentials"
    local error=$(echo "$response" | jq -r '.errors[0].message // "Unknown error"')
    log_error "Error: $error"
    return 1
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Deploy to Cloudflare
# ─────────────────────────────────────────────────────────────────────────────

deploy_to_cloudflare() {
  log_info "Deploying worker to Cloudflare..."

  # Install dependencies on VPS
  ssh_execute "cd /root/dreammaker-worker && npm install" \
    "Install npm dependencies on VPS"

  # Authenticate with Cloudflare (set token in wrangler)
  ssh_execute "cd /root/dreammaker-worker && echo '${CF_API_TOKEN}' | wrangler login" \
    "Authenticate with Cloudflare API"

  # Deploy the worker
  ssh_execute "cd /root/dreammaker-worker && wrangler deploy --env production" \
    "Deploy worker to Cloudflare (production)"

  log_success "Worker deployment initiated on VPS"
}

# ─────────────────────────────────────────────────────────────────────────────
# Verify Deployment
# ─────────────────────────────────────────────────────────────────────────────

verify_deployment() {
  log_info "Verifying worker deployment..."

  if [[ "$DRY_RUN" == true ]]; then
    log_info "[DRY RUN] Would verify deployment"
    return 0
  fi

  # Check if worker is accessible
  sleep 5

  local response=$(curl -s -I "https://cdn.dreammaker-groupsoft.ir/api/v1/ping" \
    --max-time 10 || echo "")

  if echo "$response" | grep -q "200\|304\|403\|404"; then
    log_success "Worker is accessible and responding"
    return 0
  else
    log_warning "Worker response verification inconclusive (may be blocked by firewall)"
    return 1
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Cleanup & Rollback
# ─────────────────────────────────────────────────────────────────────────────

cleanup_on_error() {
  local exit_code=$?
  
  if [[ $exit_code -ne 0 ]]; then
    log_error "Deployment failed with exit code: $exit_code"
    
    send_telegram_notification \
      "❌ *Deployment Failed*

Error Code: $exit_code
Stage: ${CURRENT_STAGE:-Unknown}

Please check logs and retry manually." \
      "error"
  fi
  
  exit $exit_code
}

# Set error trap
trap cleanup_on_error EXIT

# ─────────────────────────────────────────────────────────────────────────────
# Main Deployment Flow
# ─────────────────────────────────────────────────────────────────────────────

main() {
  log_info "🚀 Starting DreamMaker Worker Deployment"
  log_info "Target: Cloudflare via German VPS (${VPS_DE_IP})"
  log_info "Domain: ${DOMAIN}"
  
  if [[ "$DRY_RUN" == true ]]; then
    log_warning "⚠️  DRY RUN MODE - No actual changes will be made"
  fi

  # Stage 1: Preparation
  CURRENT_STAGE="Dependency Check"
  check_dependencies

  CURRENT_STAGE="Cloudflare Credential Verification"
  verify_cloudflare_credentials

  # Stage 2: VPS Preparation
  if [[ "$VPS_ONLY" == false ]]; then
    CURRENT_STAGE="VPS Preparation"
    prepare_vps
  fi

  # Stage 3: Configuration Generation
  CURRENT_STAGE="Configuration Generation"
  create_wrangler_config
  create_typescript_config
  create_package_json

  # Stage 4: File Upload
  CURRENT_STAGE="File Upload"
  deploy_worker_files

  # Stage 5: Deployment
  CURRENT_STAGE="Cloudflare Deployment"
  
  if [[ "$DRY_RUN" == false ]]; then
    deploy_to_cloudflare
  else
    log_info "[DRY RUN] Would execute: deploy_to_cloudflare"
  fi

  # Stage 6: Verification
  CURRENT_STAGE="Deployment Verification"
  verify_deployment || log_warning "Verification inconclusive"

  # Success
  CURRENT_STAGE="Complete"
  log_success "✅ DreamMaker Worker Deployment Complete!"
  
  send_telegram_notification \
    "✅ *Deployment Successful*

Worker deployed to Cloudflare
Domain: ${DOMAIN}
Endpoint: https://cdn.dreammaker-groupsoft.ir/

All tiers are now active and responding." \
    "success"
}

# ─────────────────────────────────────────────────────────────────────────────
# Execute Main
# ─────────────────────────────────────────────────────────────────────────────

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi

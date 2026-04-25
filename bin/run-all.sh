#!/usr/bin/env bash
# Orchestrator — run every step of the CF-edge fix in order.
# Must be executed *on the server* as root. See bin/run-remote.sh to kick
# this off over SSH from a workstation.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE"

. "$HERE/lib/common.sh"
load_config
require_root

section "DreamMaker CF Edge Fix — full run"
echo "Target: ${DOMAIN}  (CDN: ${CDN_SUB})"
echo

bash "$HERE/scripts/10-ssl-cert.sh"
bash "$HERE/scripts/43-ssl-expand.sh"
bash "$HERE/scripts/20-nginx-wss.sh"
bash "$HERE/scripts/30-xray-grpc-inbound.sh"
bash "$HERE/scripts/31-nginx-grpc.sh"
bash "$HERE/scripts/40-cloudflare.sh"
# Optional opt-in CF mutations. Both gates must be present.
if [[ "${CF_APPLY_CONFIRM:-}" == "YES" && -n "${CF_API_TOKEN:-}" ]]; then
    section "CF_APPLY_CONFIRM=YES detected — running CF apply pipeline"
    bash "$HERE/scripts/41-cloudflare-apply.sh"        || warn "41-cloudflare-apply.sh exit non-zero"
    bash "$HERE/scripts/44-cloudflare-pagerule-cache.sh" || warn "44-cloudflare-pagerule-cache.sh exit non-zero"
    bash "$HERE/scripts/40-cloudflare.sh"               # post-apply re-verify
fi
bash "$HERE/scripts/50-links.sh"
bash "$HERE/scripts/70-client-config.sh"
bash "$HERE/scripts/60-status.sh"

section "DONE"
echo "Append new links from ${CREDENTIALS_FILE} into your clients."

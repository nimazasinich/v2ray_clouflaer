#!/usr/bin/env bash
# Sync this app to ${SSH_USER}@${SERVER_IP}:/opt/dreammaker-cf-edge-fix and
# execute bin/run-all.sh remotely. Use from a workstation.
#
# Usage:
#   ./bin/run-remote.sh                # full run
#   ./bin/run-remote.sh status         # only run scripts/60-status.sh
#   ./bin/run-remote.sh links          # only run scripts/50-links.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE"

. "$HERE/lib/common.sh"
load_config

REMOTE_DIR="/opt/dreammaker-cf-edge-fix"
TARGET="${SSH_USER}@${SERVER_IP}"

cmd="${1:-all}"

case "$cmd" in
    all|status|links|cf|wss|grpc|probe|cf-apply|cf-mint|ssl-expand|clients) ;;
    *) die "unknown command: $cmd (expected: all|status|links|cf|cf-apply|cf-mint|wss|grpc|ssl-expand|clients|probe)" ;;
esac

require_cmd ssh rsync

log "syncing app to ${TARGET}:${REMOTE_DIR}"
ssh -o StrictHostKeyChecking=accept-new "$TARGET" "mkdir -p ${REMOTE_DIR}"
rsync -az --delete \
    --exclude '.git' --exclude 'tmp/' \
    "$HERE/" "${TARGET}:${REMOTE_DIR}/"

# Also push config.env if the user has created one locally; otherwise the
# remote will fall back to config.env.example.
if [[ -f "$HERE/config.env" ]]; then
    rsync -az "$HERE/config.env" "${TARGET}:${REMOTE_DIR}/config.env"
fi

log "executing on remote: ${cmd}"
case "$cmd" in
    all)    ssh "$TARGET" "bash ${REMOTE_DIR}/bin/run-all.sh" ;;
    status) ssh "$TARGET" "bash ${REMOTE_DIR}/scripts/60-status.sh" ;;
    links)  ssh "$TARGET" "bash ${REMOTE_DIR}/scripts/50-links.sh" ;;
    cf)     ssh "$TARGET" "bash ${REMOTE_DIR}/scripts/40-cloudflare.sh" ;;
    wss)    ssh "$TARGET" "bash ${REMOTE_DIR}/scripts/10-ssl-cert.sh && bash ${REMOTE_DIR}/scripts/20-nginx-wss.sh" ;;
    grpc)   ssh "$TARGET" "bash ${REMOTE_DIR}/scripts/30-xray-grpc-inbound.sh && bash ${REMOTE_DIR}/scripts/31-nginx-grpc.sh" ;;
    probe)  bash "${HERE}/scripts/61-edge-probe.sh" ;;
    cf-apply)
        if [[ "${CF_APPLY_CONFIRM:-}" != "YES" ]]; then
            die "Refusing: set CF_APPLY_CONFIRM=YES in env or config.env to enable Cloudflare apply."
        fi
        # Run on remote so secrets stay on-server-only via SSH.
        ssh "$TARGET" "CF_APPLY_CONFIRM=YES bash ${REMOTE_DIR}/scripts/41-cloudflare-apply.sh" ;;
    cf-mint)
        if [[ "${CF_APPLY_CONFIRM:-}" != "YES" ]]; then
            die "Refusing: set CF_APPLY_CONFIRM=YES in env or config.env to enable Cloudflare mint→apply→revoke."
        fi
        ssh "$TARGET" "CF_APPLY_CONFIRM=YES bash ${REMOTE_DIR}/scripts/42-cloudflare-mint.sh" ;;
    ssl-expand)
        ssh "$TARGET" "bash ${REMOTE_DIR}/scripts/43-ssl-expand.sh" ;;
    clients)
        # Client configs render fine locally; no need to run on the server.
        bash "${HERE}/scripts/70-client-config.sh" ;;
esac

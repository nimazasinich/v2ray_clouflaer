#!/usr/bin/env bash
# SSH-driven remote runner — convenience wrapper for connecting to the
# DreamMaker server and running individual scripts from this app.
#
# Authentication is supplied in ONE of these ways (in priority order):
#
#   1. SSH key (preferred):
#        SSH_KEY=/path/to/key  bin/run-ssh.sh <subcommand>
#      or have the key available via ssh-agent / ~/.ssh/id_*
#
#   2. Password via env (least-bad):
#        SSH_PASSWORD=<password>  bin/run-ssh.sh <subcommand>
#      Requires sshpass; the password is never written to disk.
#
# Subcommands (passed straight through to bin/run-remote.sh on the server):
#   recon         read-only inventory dump (safe; default)
#   probe         multi-protocol edge probe
#   status        services + ports + cert snapshot
#   cf            read-only Cloudflare zone diff
#   cf-apply      ⚠ mutates CF zone; needs CF_APPLY_CONFIRM=YES + CF_API_TOKEN
#   cf-pagerule   ⚠ creates Page Rule cache-bypass; same gating
#   cf-mint       ⚠ mint→apply→revoke; needs CF_BOOTSTRAP_TOKEN
#   shell         drop into an interactive root shell on the server
#
# By default this script never modifies the server. Mutating subcommands
# all require the CF_APPLY_CONFIRM=YES gate from run-remote.sh.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE"

. "$HERE/lib/common.sh"
load_config

cmd="${1:-recon}"
shift || true

ssh_opts=(
    -o StrictHostKeyChecking=accept-new
    -o ConnectTimeout=8
    -o ServerAliveInterval=30
)

# Pick auth method.
if [[ -n "${SSH_KEY:-}" ]]; then
    [[ -f "$SSH_KEY" ]] || die "SSH_KEY=$SSH_KEY does not exist"
    ssh_cmd=(ssh -i "$SSH_KEY" "${ssh_opts[@]}")
    log "auth: ssh key ${SSH_KEY}"
elif [[ -n "${SSH_PASSWORD:-}" ]]; then
    command -v sshpass >/dev/null 2>&1 || \
        die "SSH_PASSWORD set but sshpass is not installed (apt-get install sshpass)"
    export SSHPASS="$SSH_PASSWORD"
    ssh_cmd=(sshpass -e ssh "${ssh_opts[@]}")
    log "auth: password (via sshpass)"
else
    ssh_cmd=(ssh "${ssh_opts[@]}")
    log "auth: ssh-agent / default keys"
fi

target="${SSH_USER}@${SERVER_IP}"

case "$cmd" in
    shell)
        exec "${ssh_cmd[@]}" -t "$target" ;;
    recon)
        "${ssh_cmd[@]}" "$target" 'bash -s' <<'REMOTE'
echo "=== host ==="; hostname; uname -r; uptime
echo
echo "=== services ==="
for s in nginx xray docker certbot.timer; do
    printf "  %-15s %s\n" "$s" "$(systemctl is-active "$s" 2>/dev/null)"
done
echo
echo "=== xray inbound surface ==="
[ -f /usr/local/etc/xray/config.json ] && \
    PYTHONIOENCODING=utf-8 python3 -c '
import json
cfg = json.load(open("/usr/local/etc/xray/config.json"))
print("  port  listen           proto      net        sec        tag")
for ib in cfg.get("inbounds", []):
    ss = ib.get("streamSettings") or {}
    print("  {:>5} {:>14}  {:<10} {:<10} {:<10} {}".format(
        ib.get("port",""), ib.get("listen","0.0.0.0"),
        ib.get("protocol",""), ss.get("network","-"),
        ss.get("security","-"), ib.get("tag","")))
'
echo
echo "=== ports listening ==="
ss -tlnH | awk '{print $4}' | sort -u | head -30
echo
echo "=== certbot ==="
certbot certificates 2>/dev/null | grep -E "Certificate Name|Domains|Expiry" || echo "  (no certbot)"
REMOTE
        ;;
    probe|status|cf|links|wss|grpc|ssl-expand|cf-apply|cf-pagerule|cf-mint|clients)
        # Rsync this app first (so the remote always has the latest scripts).
        require_cmd rsync
        REMOTE_DIR="/opt/dreammaker-cf-edge-fix"
        log "syncing to ${target}:${REMOTE_DIR}"
        if [[ -n "${SSH_KEY:-}" ]]; then
            rsync -e "ssh -i ${SSH_KEY} ${ssh_opts[*]}" -az --delete \
                --exclude '.git' --exclude 'tmp/' \
                "$HERE/" "${target}:${REMOTE_DIR}/"
        elif [[ -n "${SSH_PASSWORD:-}" ]]; then
            export SSHPASS="$SSH_PASSWORD"
            rsync -e "sshpass -e ssh ${ssh_opts[*]}" -az --delete \
                --exclude '.git' --exclude 'tmp/' \
                "$HERE/" "${target}:${REMOTE_DIR}/"
        else
            rsync -e "ssh ${ssh_opts[*]}" -az --delete \
                --exclude '.git' --exclude 'tmp/' \
                "$HERE/" "${target}:${REMOTE_DIR}/"
        fi
        if [[ -f "$HERE/config.env" ]]; then
            log "syncing config.env (gitignored, only on demand)"
            if [[ -n "${SSH_KEY:-}" ]]; then
                rsync -e "ssh -i ${SSH_KEY} ${ssh_opts[*]}" -az "$HERE/config.env" "${target}:${REMOTE_DIR}/config.env"
            elif [[ -n "${SSH_PASSWORD:-}" ]]; then
                export SSHPASS="$SSH_PASSWORD"
                rsync -e "sshpass -e ssh ${ssh_opts[*]}" -az "$HERE/config.env" "${target}:${REMOTE_DIR}/config.env"
            else
                rsync -e "ssh ${ssh_opts[*]}" -az "$HERE/config.env" "${target}:${REMOTE_DIR}/config.env"
            fi
        fi
        log "running on remote: bin/run-remote.sh ${cmd}"
        # Pass through the gating env so it survives the SSH hop.
        env_args="CF_APPLY_CONFIRM=${CF_APPLY_CONFIRM:-} CF_BOOTSTRAP_TOKEN=${CF_BOOTSTRAP_TOKEN:-}"
        "${ssh_cmd[@]}" -t "$target" "cd ${REMOTE_DIR} && ${env_args} bash bin/run-remote.sh ${cmd}"
        ;;
    *)
        die "unknown subcommand: $cmd (try: recon|probe|status|cf|cf-apply|cf-pagerule|cf-mint|shell)"
        ;;
esac

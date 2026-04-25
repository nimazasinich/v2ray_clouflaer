#!/usr/bin/env bash
# shellcheck shell=bash
# Common helpers sourced by every script in this app.
# All scripts are idempotent and safe to re-run.

set -o pipefail

# Resolve the app root no matter where the caller invokes us from.
_COMMON_SELF="${BASH_SOURCE[0]}"
APP_ROOT="$(cd "$(dirname "$_COMMON_SELF")/.." && pwd)"
export APP_ROOT

# ---- Logging -------------------------------------------------------------
_c_reset="\033[0m"; _c_red="\033[31m"; _c_green="\033[32m"
_c_yellow="\033[33m"; _c_blue="\033[34m"; _c_dim="\033[2m"

log()   { printf "${_c_blue}[*]${_c_reset} %s\n"   "$*"; }
ok()    { printf "${_c_green}[OK]${_c_reset} %s\n"  "$*"; }
warn()  { printf "${_c_yellow}[!]${_c_reset} %s\n"  "$*" >&2; }
err()   { printf "${_c_red}[ERR]${_c_reset} %s\n"   "$*" >&2; }
die()   { err "$*"; exit 1; }
hr()    { printf "${_c_dim}%s${_c_reset}\n" "──────────────────────────────────────────────"; }

section() {
    hr
    printf "${_c_green}== %s ==${_c_reset}\n" "$*"
    hr
}

# ---- Config loader -------------------------------------------------------
load_config() {
    local cfg="${APP_ROOT}/config.env"
    if [[ ! -f "$cfg" ]]; then
        if [[ -f "${APP_ROOT}/config.env.example" ]]; then
            warn "config.env not found; falling back to config.env.example"
            cfg="${APP_ROOT}/config.env.example"
        else
            die "No config.env or config.env.example found in ${APP_ROOT}"
        fi
    fi
    # shellcheck disable=SC1090
    set -a; . "$cfg"; set +a
}

# ---- Execution guards ----------------------------------------------------
require_root() {
    if [[ $EUID -ne 0 ]]; then
        die "This script must run as root on the server (use sudo or ssh root@...)"
    fi
}

require_cmd() {
    local miss=0
    for c in "$@"; do
        if ! command -v "$c" >/dev/null 2>&1; then
            warn "missing command: $c"
            miss=1
        fi
    done
    [[ $miss -eq 0 ]] || die "install the missing commands above and re-run"
}

# ---- Safe-file policy ----------------------------------------------------
# Per project rule: never delete user files. Instead, rotate to ./tmp/.
backup_file() {
    local path="$1"
    [[ -f "$path" ]] || return 0
    local stamp; stamp="$(date +%Y%m%d_%H%M%S)"
    local base; base="$(basename "$path")"
    local tmp_dir="${APP_ROOT}/tmp"
    mkdir -p "$tmp_dir"
    cp -a "$path" "${tmp_dir}/${base}.${stamp}.bak"
    log "Backup of ${path} -> tmp/${base}.${stamp}.bak"
}

# Write a file with a pre-write backup of any existing version.
safe_write() {
    local dest="$1"; shift
    if [[ -f "$dest" ]]; then
        backup_file "$dest"
    fi
    mkdir -p "$(dirname "$dest")"
    cat > "$dest"
    ok "wrote ${dest}"
}

# ---- UFW helper (no-op if ufw absent) ------------------------------------
ufw_allow() {
    local port="$1"
    command -v ufw >/dev/null 2>&1 || { log "ufw not installed; skipping allow $port"; return 0; }
    ufw status | grep -q "Status: active" || { log "ufw inactive; skipping allow $port"; return 0; }
    ufw allow "${port}/tcp" >/dev/null 2>&1 || true
    ok "ufw allows ${port}/tcp"
}

# ---- nginx helpers -------------------------------------------------------
nginx_enable_site() {
    local name="$1"
    ln -sf "${NGINX_AVAILABLE}/${name}" "${NGINX_ENABLED}/${name}"
    ok "nginx site enabled: ${name}"
}

nginx_reload() {
    nginx -t >/tmp/nginx-test.log 2>&1 || {
        err "nginx -t failed; see /tmp/nginx-test.log"
        cat /tmp/nginx-test.log >&2
        return 1
    }
    systemctl reload nginx
    ok "nginx reloaded"
}

# ---- Connectivity test helpers ------------------------------------------
test_wss() {
    local host="$1" port="$2"
    local code
    code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 7 \
        -H "Upgrade: websocket" -H "Connection: Upgrade" \
        -H "Sec-WebSocket-Version: 13" \
        -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
        "https://${host}:${port}/" || echo "000")
    printf "%s" "$code"
}

test_grpc() {
    local host="$1" port="$2" svc="$3"
    local code
    code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 7 \
        "https://${host}:${port}/${svc}" || echo "000")
    printf "%s" "$code"
}

# ---- URL encoding --------------------------------------------------------
urlencode_path() {
    # encode only / -> %2F for vless path= arg
    local s="$1"
    printf "%s" "${s//\//%2F}"
}

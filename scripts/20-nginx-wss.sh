#!/usr/bin/env bash
# STEP 1 — Add WSS (TLS) inbound on ${WSS_PUBLIC_PORT} via nginx proxying to
# xray's existing plain-WS backend. Port is in CF-HTTPS group so the
# Cloudflare edge path survives harsher routes.
set -euo pipefail
. "$(dirname "$0")/../lib/common.sh"
load_config
require_root

section "STEP 1 — nginx WSS on :${WSS_PUBLIC_PORT} -> 127.0.0.1:${XRAY_WS_BACKEND_PORT}"

if [[ ! -f "${LE_LIVE_DIR}/fullchain.pem" ]]; then
    die "missing cert at ${LE_LIVE_DIR}; run scripts/10-ssl-cert.sh first"
fi

tpl="${APP_ROOT}/templates/xray-wss.conf.tpl"
[[ -f "$tpl" ]] || die "missing template: $tpl"

dest="${NGINX_AVAILABLE}/xray-wss"
rendered="$(sed \
    -e "s#__WSS_PUBLIC_PORT__#${WSS_PUBLIC_PORT}#g" \
    -e "s#__DOMAIN__#${DOMAIN}#g" \
    -e "s#__CDN_SUB__#${CDN_SUB}#g" \
    -e "s#__LE_LIVE_DIR__#${LE_LIVE_DIR}#g" \
    -e "s#__XRAY_WS_BACKEND_PORT__#${XRAY_WS_BACKEND_PORT}#g" \
    "$tpl")"

if [[ -f "$dest" ]] && diff -q <(printf "%s\n" "$rendered") "$dest" >/dev/null 2>&1; then
    ok "nginx xray-wss already up to date"
else
    printf "%s\n" "$rendered" | safe_write "$dest"
fi

nginx_enable_site "xray-wss"
nginx_reload
ufw_allow "${WSS_PUBLIC_PORT}"

log "probing WSS locally..."
code=$(test_wss "127.0.0.1" "${WSS_PUBLIC_PORT}")
case "$code" in
    101) ok "local WSS handshake returns 101 (WebSocket up)" ;;
    000) warn "local WSS probe timed out (000) — check nginx/xray logs" ;;
    *)   warn "local WSS probe returned HTTP ${code}" ;;
esac

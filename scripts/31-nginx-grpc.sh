#!/usr/bin/env bash
# STEP 2b — Add nginx TLS gRPC fronting on :${GRPC_PUBLIC_PORT} proxying to
# the local xray gRPC inbound.
set -euo pipefail
. "$(dirname "$0")/../lib/common.sh"
load_config
require_root

section "STEP 2b — nginx gRPC on :${GRPC_PUBLIC_PORT} -> 127.0.0.1:${XRAY_GRPC_BACKEND_PORT}"

if [[ ! -f "${LE_LIVE_DIR}/fullchain.pem" ]]; then
    die "missing cert at ${LE_LIVE_DIR}; run scripts/10-ssl-cert.sh first"
fi

tpl="${APP_ROOT}/templates/xray-grpc.conf.tpl"
[[ -f "$tpl" ]] || die "missing template: $tpl"

dest="${NGINX_AVAILABLE}/xray-grpc"
rendered="$(sed \
    -e "s#__GRPC_PUBLIC_PORT__#${GRPC_PUBLIC_PORT}#g" \
    -e "s#__DOMAIN__#${DOMAIN}#g" \
    -e "s#__CDN_SUB__#${CDN_SUB}#g" \
    -e "s#__LE_LIVE_DIR__#${LE_LIVE_DIR}#g" \
    -e "s#__GRPC_SERVICE_NAME__#${GRPC_SERVICE_NAME}#g" \
    -e "s#__XRAY_GRPC_BACKEND_PORT__#${XRAY_GRPC_BACKEND_PORT}#g" \
    "$tpl")"

if [[ -f "$dest" ]] && diff -q <(printf "%s\n" "$rendered") "$dest" >/dev/null 2>&1; then
    ok "nginx xray-grpc already up to date"
else
    printf "%s\n" "$rendered" | safe_write "$dest"
fi

nginx_enable_site "xray-grpc"
nginx_reload
ufw_allow "${GRPC_PUBLIC_PORT}"

log "probing gRPC locally..."
code=$(test_grpc "127.0.0.1" "${GRPC_PUBLIC_PORT}" "${GRPC_SERVICE_NAME}")
case "$code" in
    200|400|415) ok "local gRPC port alive (HTTP ${code})" ;;
    000)         warn "local gRPC probe timed out (000)" ;;
    *)           warn "local gRPC probe returned HTTP ${code}" ;;
esac

#!/usr/bin/env bash
# STEP 6 — Print a human-readable health snapshot: services, ports, SSL,
# connectivity probes for the WSS and gRPC CDN endpoints.
set -uo pipefail
. "$(dirname "$0")/../lib/common.sh"
load_config

svc_status() {
    local s="$1"
    if systemctl is-active --quiet "$s"; then
        printf "  %-8s [OK]\n" "$s"
    else
        printf "  %-8s [FAIL]\n" "$s"
    fi
}

port_status() {
    local p="$1"
    if ss -tlnH 2>/dev/null | awk '{print $4}' | grep -Eq ":${p}$"; then
        printf "  PORT %-6s [OK]\n" "$p"
    else
        printf "  PORT %-6s [FAIL]\n" "$p"
    fi
}

section "SERVICE STATUS"
svc_status xray
svc_status nginx

section "PORT CHECK"
for p in 80 443 "${GRPC_PUBLIC_PORT}" "${WSS_PUBLIC_PORT}" "${XRAY_WS_BACKEND_PORT}" "${XRAY_GRPC_BACKEND_PORT}"; do
    port_status "$p"
done

section "SSL CERT"
if command -v certbot >/dev/null 2>&1; then
    certbot certificates 2>/dev/null | grep -E "Domains:|Expiry" || echo "  (no certs)"
else
    echo "  certbot not installed"
fi

section "CONNECTIVITY PROBES"
for host in "127.0.0.1" "${CDN_SUB}"; do
    code=$(test_wss "$host" "${WSS_PUBLIC_PORT}")
    printf "  WSS  %-35s -> HTTP %s\n" "${host}:${WSS_PUBLIC_PORT}/" "$code"
    code=$(test_grpc "$host" "${GRPC_PUBLIC_PORT}" "${GRPC_SERVICE_NAME}")
    printf "  gRPC %-35s -> HTTP %s\n" "${host}:${GRPC_PUBLIC_PORT}/${GRPC_SERVICE_NAME}" "$code"
done

hr
echo "Legend: WSS=101 (success), gRPC=200/400/415 (port alive), 000 = timeout."

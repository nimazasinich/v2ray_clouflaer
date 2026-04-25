#!/usr/bin/env bash
# Probe every protocol inbound described in the v2.0 deployment guide
# (docs/DEPLOYMENT-GUIDE-v2.md) from the *current host's* perspective.
#
# Run from a workstation outside Iran to verify the edge path; run from
# inside the server to verify the local pipeline. The script never touches
# the configuration — purely connectivity probes.
set -uo pipefail
. "$(dirname "$0")/../lib/common.sh"
load_config

section "Multi-protocol edge probe — ${DOMAIN}"

# Helpers ------------------------------------------------------------------
fmt() { printf "  %-32s %-20s -> %s\n" "$1" "$2" "$3"; }

probe_tcp() {
    local host="$1" port="$2" label="$3"
    local out
    if out=$(timeout 5 bash -c "</dev/tcp/${host}/${port}" 2>&1); then
        fmt "$label" "${host}:${port}" "OK (TCP open)"
    else
        fmt "$label" "${host}:${port}" "FAIL (TCP closed/filtered)"
    fi
}

probe_https_code() {
    local url="$1" label="$2"
    local code
    code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 7 "$url" || echo "000")
    fmt "$label" "$url" "HTTP $code"
}

probe_wss() {
    local url="$1" label="$2" host_hdr="$3"
    local code
    code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 7 \
        -H "Host: ${host_hdr}" \
        -H "Upgrade: websocket" -H "Connection: Upgrade" \
        -H "Sec-WebSocket-Version: 13" \
        -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
        "$url" || echo "000")
    case "$code" in
        101) fmt "$label" "$url" "HTTP 101 (WebSocket up)" ;;
        000) fmt "$label" "$url" "TIMEOUT" ;;
        *)   fmt "$label" "$url" "HTTP $code (no WS upgrade)" ;;
    esac
}

probe_tls_sni() {
    local host="$1" port="$2" sni="$3" label="$4"
    if ! command -v openssl >/dev/null 2>&1; then
        fmt "$label" "${host}:${port}" "openssl not installed"; return
    fi
    local out
    out=$(echo "Q" | timeout 7 openssl s_client \
        -connect "${host}:${port}" -servername "${sni}" \
        -alpn h2,http/1.1 2>/dev/null | head -50)
    if printf '%s' "$out" | grep -q "BEGIN CERTIFICATE"; then
        local subj
        subj=$(printf '%s' "$out" | awk -F'subject=' '/subject=/{print $2; exit}' | head -c 80)
        fmt "$label" "${host}:${port} sni=${sni}" "TLS handshake OK (subj=${subj})"
    else
        fmt "$label" "${host}:${port} sni=${sni}" "TLS handshake FAIL"
    fi
}

# 1) Direct TCP liveness ---------------------------------------------------
section "TCP liveness (direct to ${SERVER_IP})"
probe_tcp "${SERVER_IP}" 22    "SSH"
probe_tcp "${SERVER_IP}" 80    "VLESS WS+CDN (origin :80)"
probe_tcp "${SERVER_IP}" 443   "VLESS Reality"
probe_tcp "${SERVER_IP}" 2052  "VMess WS"
probe_tcp "${SERVER_IP}" 2053  "nginx gRPC :2053"
probe_tcp "${SERVER_IP}" 2083  "nginx WSS :2083"
probe_tcp "${SERVER_IP}" 2096  "VLESS XHTTP"
probe_tcp "${SERVER_IP}" 8443  "Trojan TLS"
probe_tcp "${SERVER_IP}" 16936 "Outline API"
probe_tcp "${SERVER_IP}" 44778 "Outline Shadowsocks"

# 2) Cloudflare edge -------------------------------------------------------
section "Cloudflare edge (via ${CDN_SUB})"
probe_tcp "${CDN_SUB}" 443  "CF edge :443"
probe_tcp "${CDN_SUB}" 80   "CF edge :80"
probe_tcp "${CDN_SUB}" 2053 "CF edge :2053"
probe_tcp "${CDN_SUB}" 2083 "CF edge :2083"

# 3) TLS handshake checks --------------------------------------------------
section "TLS handshake"
probe_tls_sni "${CDN_SUB}"   443  "${CDN_SUB}"  "CDN HTTPS"
probe_tls_sni "${CDN_SUB}"   2083 "${CDN_SUB}"  "CDN WSS:2083"
probe_tls_sni "${CDN_SUB}"   2053 "${CDN_SUB}"  "CDN gRPC:2053"
probe_tls_sni "${SERVER_IP}" 443  "digikala.com" "Reality SNI=digikala.com"
probe_tls_sni "${SERVER_IP}" 8443 "${DOMAIN}"   "Trojan TLS:8443"
probe_tls_sni "${SERVER_IP}" 2096 "${DOMAIN}"   "XHTTP TLS:2096"

# 4) WebSocket upgrade probes ---------------------------------------------
section "WebSocket upgrade"
probe_wss "https://${CDN_SUB}:2083/" "WSS via nginx :2083"     "${CDN_SUB}"
probe_wss "https://${CDN_SUB}/cdn"   "WSS via CDN :443 /cdn"   "${CDN_SUB}"
probe_wss "http://${SERVER_IP}/cdn"  "Plain WS origin :80 /cdn" "${DOMAIN}"
probe_wss "http://${SERVER_IP}:2052/vmess" "VMess WS :2052 /vmess" "${DOMAIN}"

# 5) gRPC / XHTTP basic responses -----------------------------------------
section "gRPC / XHTTP probes"
probe_https_code "https://${CDN_SUB}:2053/${GRPC_SERVICE_NAME:-dreammaker-grpc}" "gRPC :2053"
probe_https_code "https://${CDN_SUB}:2096/xhttp" "XHTTP :2096 via CDN"
probe_https_code "https://${SERVER_IP}:2096/xhttp" "XHTTP :2096 direct"

hr
cat <<EOF
Legend:
  HTTP 101            → WebSocket upgrade succeeded (good)
  HTTP 200/400/415    → port alive, gRPC/XHTTP path is reachable
  HTTP 000 / TIMEOUT  → edge path filtered or origin port closed from this host
  TLS subj=...        → TLS terminator answered (CN may be Cloudflare or Let's Encrypt)
EOF
hr

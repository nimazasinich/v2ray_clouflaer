#!/usr/bin/env bash
# Render every clients/*.tpl.json into a real, ready-to-use v2ray client
# config under tmp/clients/. Each generated file inlines the values from
# config.env so the user never has to hand-edit YOUR_DOMAIN / YOUR_UUID
# anywhere.
#
# Output:
#   tmp/clients/reality.json       — v2.0 Reality 443 (direct to IP)
#   tmp/clients/vless-ws-cdn.json  — v2.0 VLESS WS+CDN 80
#   tmp/clients/vmess-ws.json      — v2.0 VMess WS 2052
#   tmp/clients/trojan.json        — v2.0 Trojan TLS 8443
#   tmp/clients/xhttp.json         — v2.0 XHTTP 2096
#   tmp/clients/wss-cdn.json       — CF-edge-fix WSS via cdn.*:2083
#   tmp/clients/grpc-cdn.json      — CF-edge-fix gRPC via cdn.*:2053
#   tmp/clients/links.txt          — vless:// / vmess:// / trojan:// links
set -euo pipefail
. "$(dirname "$0")/../lib/common.sh"
load_config

section "Rendering client configs from config.env"

OUT="${APP_ROOT}/tmp/clients"
mkdir -p "$OUT"

# Map of template -> output filename.
declare -A files=(
    ["v2ray-reality.tpl.json"]="reality.json"
    ["v2ray-vless-ws-cdn.tpl.json"]="vless-ws-cdn.json"
    ["v2ray-vmess-ws.tpl.json"]="vmess-ws.json"
    ["v2ray-trojan.tpl.json"]="trojan.json"
    ["v2ray-xhttp.tpl.json"]="xhttp.json"
    ["v2ray-wss-cdn.tpl.json"]="wss-cdn.json"
    ["v2ray-grpc-cdn.tpl.json"]="grpc-cdn.json"
)

# All placeholder -> value substitutions in one place.
substitute() {
    sed \
        -e "s#__SERVER_IP__#${SERVER_IP}#g" \
        -e "s#__DOMAIN__#${DOMAIN}#g" \
        -e "s#__CDN_SUB__#${CDN_SUB}#g" \
        -e "s#__UUID__#${UUID}#g" \
        -e "s#__V2_UUID__#${V2_UUID:-${UUID}}#g" \
        -e "s#__V2_REALITY_PUB_KEY__#${V2_REALITY_PUB_KEY:-${PUB_KEY}}#g" \
        -e "s#__V2_REALITY_SHORT_ID__#${V2_REALITY_SHORT_ID:-}#g" \
        -e "s#__V2_REALITY_SNI__#${V2_REALITY_SNI:-www.google.com}#g" \
        -e "s#__V2_TROJAN_PASSWORD__#${V2_TROJAN_PASSWORD:-CHANGE_ME}#g" \
        -e "s#__V2_WS_PATH__#${V2_WS_PATH:-/cdn}#g" \
        -e "s#__V2_VMESS_PATH__#${V2_VMESS_PATH:-/vmess}#g" \
        -e "s#__V2_XHTTP_PATH__#${V2_XHTTP_PATH:-/xhttp}#g" \
        -e "s#__WSS_PUBLIC_PORT__#${WSS_PUBLIC_PORT:-2083}#g" \
        -e "s#__GRPC_PUBLIC_PORT__#${GRPC_PUBLIC_PORT:-2053}#g" \
        -e "s#__GRPC_SERVICE_NAME__#${GRPC_SERVICE_NAME:-dreammaker-grpc}#g"
}

for tpl in "${!files[@]}"; do
    src="${APP_ROOT}/clients/${tpl}"
    dst="${OUT}/${files[$tpl]}"
    [[ -f "$src" ]] || { warn "missing template: $src"; continue; }
    substitute < "$src" > "$dst"
    if command -v python3 >/dev/null 2>&1; then
        if ! python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$dst" 2>/dev/null; then
            err "rendered ${dst} is invalid JSON"
            exit 1
        fi
    fi
    ok "rendered ${dst}"
done

# vless:// / vmess:// / trojan:// share links --------------------------------
links_file="${OUT}/links.txt"
{
    echo "# DreamMaker — generated $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    echo

    # Reality 443
    echo "## VLESS Reality (port 443, direct to IP)"
    echo "vless://${V2_UUID:-${UUID}}@${SERVER_IP}:443?security=reality&type=tcp&flow=xtls-rprx-vision&sni=${V2_REALITY_SNI:-www.google.com}&fp=chrome&pbk=${V2_REALITY_PUB_KEY:-${PUB_KEY}}&sid=${V2_REALITY_SHORT_ID:-}#Reality-443"
    echo

    # WS + CDN 80
    echo "## VLESS WS + CDN (port 80)"
    echo "vless://${V2_UUID:-${UUID}}@${DOMAIN}:80?type=ws&security=none&path=${V2_WS_PATH:-/cdn}&host=${DOMAIN}#CDN-WS-80"
    echo

    # VMess 2052 (base64-encoded JSON)
    echo "## VMess WS (port 2052)"
    vmess_json=$(printf '{"v":"2","ps":"VMess-WS-2052","add":"%s","port":"2052","id":"%s","aid":"0","scy":"auto","net":"ws","type":"none","host":"%s","path":"%s","tls":""}' \
        "${DOMAIN}" "${V2_UUID:-${UUID}}" "${DOMAIN}" "${V2_VMESS_PATH:-/vmess}")
    echo "vmess://$(printf '%s' "$vmess_json" | base64 -w0)"
    echo

    # Trojan 8443
    echo "## Trojan TLS (port 8443)"
    echo "trojan://${V2_TROJAN_PASSWORD:-CHANGE_ME}@${SERVER_IP}:8443?security=tls&sni=${DOMAIN}&type=tcp#Trojan-8443"
    echo

    # XHTTP 2096
    echo "## VLESS XHTTP (port 2096)"
    echo "vless://${V2_UUID:-${UUID}}@${SERVER_IP}:2096?security=tls&sni=${DOMAIN}&type=xhttp&path=${V2_XHTTP_PATH:-/xhttp}&host=${DOMAIN}#XHTTP-2096"
    echo

    # CF Edge Fix WSS 2083
    echo "## CF-Edge-Fix WSS via nginx (port ${WSS_PUBLIC_PORT:-2083})"
    echo "vless://${UUID}@${CDN_SUB}:${WSS_PUBLIC_PORT:-2083}?encryption=none&security=tls&sni=${CDN_SUB}&type=ws&path=%2F#DM-CF-WSS-${WSS_PUBLIC_PORT:-2083}"
    echo

    # CF Edge Fix gRPC 2053
    echo "## CF-Edge-Fix gRPC via nginx (port ${GRPC_PUBLIC_PORT:-2053})"
    echo "vless://${UUID}@${CDN_SUB}:${GRPC_PUBLIC_PORT:-2053}?encryption=none&security=tls&sni=${CDN_SUB}&type=grpc&serviceName=${GRPC_SERVICE_NAME:-dreammaker-grpc}&mode=gun#DM-CF-gRPC-${GRPC_PUBLIC_PORT:-2053}"
    echo
} > "$links_file"
ok "wrote ${links_file}"

hr
echo "All rendered configs are in: ${OUT}"
ls -la "$OUT"
hr
echo "To use a config:"
echo "  v2ray run -c ${OUT}/reality.json"
echo "Then: curl -x socks5://127.0.0.1:10808 https://ipinfo.io"

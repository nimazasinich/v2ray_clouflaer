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
    ["v2ray-trojan-ws.tpl.json"]="trojan-ws.json"
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
        -e "s#__V2_WS_PATH__#${V2_WS_PATH:-/ws-vless}#g" \
        -e "s#__V2_WS_PORT__#${V2_WS_PORT:-2086}#g" \
        -e "s#__V2_VMESS_PATH__#${V2_VMESS_PATH:-/ws-vmess}#g" \
        -e "s#__V2_VMESS_PORT__#${V2_VMESS_PORT:-2082}#g" \
        -e "s#__V2_TROJAN_PATH__#${V2_TROJAN_PATH:-/ws-trojan}#g" \
        -e "s#__V2_TROJAN_PORT__#${V2_TROJAN_PORT:-2052}#g" \
        -e "s#__V2_XHTTP_PATH__#${V2_XHTTP_PATH:-/xhttp-cdn}#g" \
        -e "s#__V2_XHTTP_PORT__#${V2_XHTTP_PORT:-8880}#g" \
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

    cdn="${CDN_SUB}"
    uuid="${V2_UUID:-${UUID}}"

    # Reality 443 — direct to IP, NOT through CF
    echo "## VLESS Reality (port 443, direct to IP, SNI=${V2_REALITY_SNI:-www.digikala.com})"
    echo "vless://${uuid}@${SERVER_IP}:443?security=reality&type=tcp&flow=xtls-rprx-vision&sni=${V2_REALITY_SNI:-www.digikala.com}&fp=chrome&pbk=${V2_REALITY_PUB_KEY:-${PUB_KEY}}&sid=${V2_REALITY_SHORT_ID:-}#DM-Reality-443"
    echo

    # CDN: VLESS WS via CF :2086 (CF-HTTP, plaintext to origin)
    echo "## VLESS WS via CDN (cdn.*:${V2_WS_PORT:-2086}, no TLS — CF terminates)"
    ws_path_enc="$(urlencode_path "${V2_WS_PATH:-/ws-vless}")"
    echo "vless://${uuid}@${cdn}:${V2_WS_PORT:-2086}?type=ws&security=none&path=${ws_path_enc}&host=${cdn}#DM-CDN-VLESS-WS"
    echo

    # CDN: VMess WS via CF :2082
    echo "## VMess WS via CDN (cdn.*:${V2_VMESS_PORT:-2082}, no TLS — CF terminates)"
    vmess_json=$(printf '{"v":"2","ps":"DM-CDN-VMess-WS","add":"%s","port":"%s","id":"%s","aid":"0","scy":"auto","net":"ws","type":"none","host":"%s","path":"%s","tls":""}' \
        "${cdn}" "${V2_VMESS_PORT:-2082}" "${uuid}" "${cdn}" "${V2_VMESS_PATH:-/ws-vmess}")
    echo "vmess://$(printf '%s' "$vmess_json" | base64 -w0)"
    echo

    # CDN: Trojan WS via CF :2052
    echo "## Trojan WS via CDN (cdn.*:${V2_TROJAN_PORT:-2052}, no TLS — CF terminates)"
    trojan_path_enc="$(urlencode_path "${V2_TROJAN_PATH:-/ws-trojan}")"
    echo "trojan://${V2_TROJAN_PASSWORD:-CHANGE_ME}@${cdn}:${V2_TROJAN_PORT:-2052}?type=ws&security=none&path=${trojan_path_enc}&host=${cdn}#DM-CDN-Trojan-WS"
    echo

    # CDN: VLESS XHTTP via CF :8880
    echo "## VLESS XHTTP via CDN (cdn.*:${V2_XHTTP_PORT:-8880}, no TLS — CF terminates)"
    xhttp_path_enc="$(urlencode_path "${V2_XHTTP_PATH:-/xhttp-cdn}")"
    echo "vless://${uuid}@${cdn}:${V2_XHTTP_PORT:-8880}?type=xhttp&security=none&path=${xhttp_path_enc}&host=${cdn}&mode=auto#DM-CDN-VLESS-XHTTP"
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

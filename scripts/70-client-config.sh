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
    # 5 direct (Reality) variants
    ["v2ray-reality.tpl.json"]="reality-443.json"
    ["v2ray-reality-grpc.tpl.json"]="reality-grpc-8443.json"
    ["v2ray-reality-xhttp.tpl.json"]="reality-xhttp-2095.json"
    ["v2ray-trojan-reality.tpl.json"]="trojan-reality-2087.json"
    # 4 CDN-fronted (plaintext through Cloudflare)
    ["v2ray-vless-ws-cdn.tpl.json"]="cdn-vless-ws-2086.json"
    ["v2ray-vmess-ws.tpl.json"]="cdn-vmess-ws-2082.json"
    ["v2ray-trojan-ws.tpl.json"]="cdn-trojan-ws-2052.json"
    ["v2ray-xhttp.tpl.json"]="cdn-xhttp-8880.json"
    # 1 Shadowsocks
    ["v2ray-shadowsocks.tpl.json"]="shadowsocks-8388.json"
    # Legacy CF-edge-fix templates (not deployed but kept for completeness)
    ["v2ray-wss-cdn.tpl.json"]="legacy-wss-cdn.json"
    ["v2ray-grpc-cdn.tpl.json"]="legacy-grpc-cdn.json"
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
        -e "s#__V2_REALITY_SNI__#${V2_REALITY_SNI:-www.digikala.com}#g" \
        -e "s#__V2_REALITY_2095_PATH__#${V2_REALITY_2095_PATH:-/r}#g" \
        -e "s#__V2_TROJAN_PASSWORD__#${V2_TROJAN_PASSWORD:-CHANGE_ME}#g" \
        -e "s#__V2_WS_PATH__#${V2_WS_PATH:-/ws-vless}#g" \
        -e "s#__V2_WS_PORT__#${V2_WS_PORT:-2086}#g" \
        -e "s#__V2_VMESS_PATH__#${V2_VMESS_PATH:-/ws-vmess}#g" \
        -e "s#__V2_VMESS_PORT__#${V2_VMESS_PORT:-2082}#g" \
        -e "s#__V2_TROJAN_PATH__#${V2_TROJAN_PATH:-/ws-trojan}#g" \
        -e "s#__V2_TROJAN_PORT__#${V2_TROJAN_PORT:-2052}#g" \
        -e "s#__V2_XHTTP_PATH__#${V2_XHTTP_PATH:-/xhttp-cdn}#g" \
        -e "s#__V2_XHTTP_PORT__#${V2_XHTTP_PORT:-8880}#g" \
        -e "s#__V2_SS_METHOD__#${V2_SS_METHOD:-2022-blake3-aes-128-gcm}#g" \
        -e "s#__V2_SS_PASSWORD__#${V2_SS_PASSWORD:-CHANGE_ME}#g" \
        -e "s#__V2_SS_PORT__#${V2_SS_PORT:-8388}#g" \
        -e "s#__V2_GRPC_SERVICE_NAME__#${V2_GRPC_SERVICE_NAME:-dreammaker-grpc}#g" \
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
    pbk="${V2_REALITY_PUB_KEY:-${PUB_KEY}}"
    sid="${V2_REALITY_SHORT_ID:-}"
    sni="${V2_REALITY_SNI:-www.digikala.com}"

    echo "# === DIRECT (Reality) — bypass Cloudflare; use server IP ==="
    echo

    echo "## VLESS Reality TCP (port 443, SNI rotation incl. ${sni})"
    echo "vless://${uuid}@${SERVER_IP}:443?security=reality&type=tcp&flow=xtls-rprx-vision&sni=${sni}&fp=chrome&pbk=${pbk}&sid=${sid}#DM-Reality-443"
    echo

    echo "## VLESS Reality TCP (port 2096, speedtest SNI)"
    echo "vless://${uuid}@${SERVER_IP}:2096?security=reality&type=tcp&flow=xtls-rprx-vision&sni=www.speedtest.net&fp=chrome&pbk=${pbk}&sid=${sid}#DM-Reality-2096-Speedtest"
    echo

    echo "## VLESS Reality gRPC (port 8443, serviceName=${V2_GRPC_SERVICE_NAME:-dreammaker-grpc})"
    echo "vless://${uuid}@${SERVER_IP}:8443?security=reality&type=grpc&serviceName=${V2_GRPC_SERVICE_NAME:-dreammaker-grpc}&mode=gun&sni=${sni}&fp=chrome&pbk=${pbk}&sid=${sid}#DM-Reality-gRPC-8443"
    echo

    echo "## VLESS Reality XHTTP (port 2095, path=${V2_REALITY_2095_PATH:-/r})"
    xhttp_2095_enc="$(urlencode_path "${V2_REALITY_2095_PATH:-/r}")"
    echo "vless://${uuid}@${SERVER_IP}:2095?security=reality&type=xhttp&path=${xhttp_2095_enc}&mode=auto&sni=${sni}&fp=chrome&pbk=${pbk}&sid=${sid}#DM-Reality-XHTTP-2095"
    echo

    echo "## Trojan Reality TCP (port 2087, SNI=www.aparat.com)"
    echo "trojan://${V2_TROJAN_PASSWORD:-CHANGE_ME}@${SERVER_IP}:2087?security=reality&type=tcp&sni=www.aparat.com&fp=chrome&pbk=${pbk}&sid=${sid}#DM-Trojan-Reality-2087"
    echo

    echo "# === CDN (plaintext via Cloudflare on CF-HTTP-group ports) ==="
    echo

    echo "## VLESS WS via CDN (cdn.*:${V2_WS_PORT:-2086}, plaintext + CF TLS)"
    ws_path_enc="$(urlencode_path "${V2_WS_PATH:-/ws-vless}")"
    echo "vless://${uuid}@${cdn}:${V2_WS_PORT:-2086}?type=ws&security=none&path=${ws_path_enc}&host=${cdn}#DM-CDN-VLESS-WS"
    echo

    echo "## VMess WS via CDN (cdn.*:${V2_VMESS_PORT:-2082})"
    vmess_json=$(printf '{"v":"2","ps":"DM-CDN-VMess-WS","add":"%s","port":"%s","id":"%s","aid":"0","scy":"auto","net":"ws","type":"none","host":"%s","path":"%s","tls":""}' \
        "${cdn}" "${V2_VMESS_PORT:-2082}" "${uuid}" "${cdn}" "${V2_VMESS_PATH:-/ws-vmess}")
    echo "vmess://$(printf '%s' "$vmess_json" | base64 -w0)"
    echo

    echo "## Trojan WS via CDN (cdn.*:${V2_TROJAN_PORT:-2052})"
    trojan_path_enc="$(urlencode_path "${V2_TROJAN_PATH:-/ws-trojan}")"
    echo "trojan://${V2_TROJAN_PASSWORD:-CHANGE_ME}@${cdn}:${V2_TROJAN_PORT:-2052}?type=ws&security=none&path=${trojan_path_enc}&host=${cdn}#DM-CDN-Trojan-WS"
    echo

    echo "## VLESS XHTTP via CDN (cdn.*:${V2_XHTTP_PORT:-8880})"
    xhttp_path_enc="$(urlencode_path "${V2_XHTTP_PATH:-/xhttp-cdn}")"
    echo "vless://${uuid}@${cdn}:${V2_XHTTP_PORT:-8880}?type=xhttp&security=none&path=${xhttp_path_enc}&host=${cdn}&mode=auto#DM-CDN-VLESS-XHTTP"
    echo

    echo "# === Shadowsocks (direct) ==="
    echo

    echo "## Shadowsocks 2022 (port ${V2_SS_PORT:-8388}, ${V2_SS_METHOD:-2022-blake3-aes-128-gcm})"
    ss_userinfo=$(printf '%s:%s' "${V2_SS_METHOD:-2022-blake3-aes-128-gcm}" "${V2_SS_PASSWORD:-CHANGE_ME}" | base64 -w0)
    echo "ss://${ss_userinfo}@${SERVER_IP}:${V2_SS_PORT:-8388}#DM-Shadowsocks-8388"
    echo

    echo "# === Notes ==="
    echo "# - Reality endpoints connect DIRECTLY to ${SERVER_IP} (NOT via Cloudflare)."
    echo "# - CDN endpoints connect via cdn.dreammaker-groupsoft.ir (Cloudflare proxied)."
    echo "# - All clients share the same UUID: ${uuid}"
    echo "# - Reality public key: ${pbk}"
    echo "# - Reality short id: ${sid}"
    echo "# - Trojan password (shared between :2087 Reality and :2052 CDN): ${V2_TROJAN_PASSWORD:-CHANGE_ME}"
    echo "# - Shadowsocks method: ${V2_SS_METHOD:-2022-blake3-aes-128-gcm}, password shared with Trojan."

} > "$links_file"
ok "wrote ${links_file}"

hr
echo "All rendered configs are in: ${OUT}"
ls -la "$OUT"
hr
echo "To use a config:"
echo "  v2ray run -c ${OUT}/reality.json"
echo "Then: curl -x socks5://127.0.0.1:10808 https://ipinfo.io"

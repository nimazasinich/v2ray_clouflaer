#!/usr/bin/env bash
# Generate TWO variants of every protocol (different SNI / different
# entrypoint) so the operator can A/B-test TCP ping in v2rayN and pick
# whichever route their ISP happens to route best.
#
# Output:
#   tmp/clients/two-variants.txt — one big text block, copy-paste friendly
set -euo pipefail
. "$(dirname "$0")/../lib/common.sh"
load_config

OUT_DIR="${APP_ROOT}/tmp/clients"
mkdir -p "$OUT_DIR"
out="${OUT_DIR}/two-variants.txt"

uuid="${V2_UUID}"
pbk="${V2_REALITY_PUB_KEY}"
sid="${V2_REALITY_SHORT_ID}"
trojan_pwd="${V2_TROJAN_PASSWORD}"
ss_method="${V2_SS_METHOD}"
ss_pwd="${V2_SS_PASSWORD}"
ip="${SERVER_IP}"
domain="${DOMAIN}"
cdn="${CDN_SUB}"
grpc_svc="${V2_GRPC_SERVICE_NAME:-dreammaker-grpc}"

ws_path_enc="$(urlencode_path "${V2_WS_PATH}")"
vmess_path_enc="$(urlencode_path "${V2_VMESS_PATH}")"
trojan_path_enc="$(urlencode_path "${V2_TROJAN_PATH}")"
xhttp_path_enc="$(urlencode_path "${V2_XHTTP_PATH}")"
reality_2095_path_enc="$(urlencode_path "${V2_REALITY_2095_PATH:-/r}")"

# Helper: emit a vmess:// link from JSON params
mk_vmess() {
    local ps="$1" add="$2" port="$3" id="$4" host="$5" path="$6"
    local j
    j=$(printf '{"v":"2","ps":"%s","add":"%s","port":"%s","id":"%s","aid":"0","scy":"auto","net":"ws","type":"none","host":"%s","path":"%s","tls":""}' \
        "$ps" "$add" "$port" "$id" "$host" "$path")
    printf 'vmess://%s\n' "$(printf '%s' "$j" | base64 -w0)"
}

mk_ss() {
    local ps="$1" add="$2" port="$3"
    local userinfo
    userinfo=$(printf '%s:%s' "$ss_method" "$ss_pwd" | base64 -w0)
    printf 'ss://%s@%s:%s#%s\n' "$userinfo" "$add" "$port" "$ps"
}

{
cat <<HEADER
════════════════════════════════════════════════════════════════════════════════
DreamMaker — TWO-VARIANT CLIENT BUNDLE  (generated $(date -u +'%Y-%m-%dT%H:%M:%SZ'))
════════════════════════════════════════════════════════════════════════════════

How to use this:
  1. Open v2rayN  →  Servers  →  "Import bulk URL from clipboard"
  2. Paste the entire block below (v2rayN ignores the comment lines).
  3. Right-click each entry  →  "TCP Ping (single)" (or Ctrl+R for Real Delay).
  4. Pick whichever variant pings fastest from your network.

The two variants for each protocol use the SAME credentials but DIFFERENT
network paths (different SNI for direct, or origin-IP vs CDN-proxied for CDN).
TCP ping varies by which CF edge or local route your ISP happens to use.

NOTE: Reality endpoints are DIRECT to ${ip} — they bypass Cloudflare entirely.
      CDN endpoints go through Cloudflare's nearest edge to your client.

════════════════════════════════════════════════════════════════════════════════
DIRECT — Reality protocol family (no CDN; 5 ports, 2 variants each)
════════════════════════════════════════════════════════════════════════════════

# ── VLESS Reality TCP :443 ───────────────────────────────────────────
# Variant A: SNI=www.digikala.com (Iran-domestic, often best ping)
vless://${uuid}@${ip}:443?security=reality&type=tcp&flow=xtls-rprx-vision&sni=www.digikala.com&fp=chrome&pbk=${pbk}&sid=${sid}#A-Reality-443-digikala

# Variant B: SNI=www.filimo.com (Iran-domestic; alternate path)
vless://${uuid}@${ip}:443?security=reality&type=tcp&flow=xtls-rprx-vision&sni=www.filimo.com&fp=chrome&pbk=${pbk}&sid=${sid}#B-Reality-443-filimo


# ── VLESS Reality TCP :2096 (speedtest-themed SNI list) ──────────────
# Variant A: SNI=www.speedtest.net (intl, usually low jitter)
vless://${uuid}@${ip}:2096?security=reality&type=tcp&flow=xtls-rprx-vision&sni=www.speedtest.net&fp=chrome&pbk=${pbk}&sid=${sid}#A-Reality-2096-speedtest

# Variant B: SNI=www.cloudflare.com (might route via CF backbone)
vless://${uuid}@${ip}:2096?security=reality&type=tcp&flow=xtls-rprx-vision&sni=www.cloudflare.com&fp=chrome&pbk=${pbk}&sid=${sid}#B-Reality-2096-cloudflare


# ── VLESS Reality gRPC :8443 ─────────────────────────────────────────
# Variant A: SNI=www.digikala.com
vless://${uuid}@${ip}:8443?security=reality&type=grpc&serviceName=${grpc_svc}&mode=gun&sni=www.digikala.com&fp=chrome&pbk=${pbk}&sid=${sid}#A-Reality-gRPC-8443-digikala

# Variant B: SNI=www.snapp.ir (different Iranian SNI)
vless://${uuid}@${ip}:8443?security=reality&type=grpc&serviceName=${grpc_svc}&mode=gun&sni=www.snapp.ir&fp=chrome&pbk=${pbk}&sid=${sid}#B-Reality-gRPC-8443-snapp


# ── VLESS Reality XHTTP :2095 (path=${V2_REALITY_2095_PATH:-/r}) ──────────────
# Variant A: SNI=www.digikala.com
vless://${uuid}@${ip}:2095?security=reality&type=xhttp&path=${reality_2095_path_enc}&mode=auto&sni=www.digikala.com&fp=chrome&pbk=${pbk}&sid=${sid}#A-Reality-XHTTP-2095-digikala

# Variant B: SNI=www.aparat.com
vless://${uuid}@${ip}:2095?security=reality&type=xhttp&path=${reality_2095_path_enc}&mode=auto&sni=www.aparat.com&fp=chrome&pbk=${pbk}&sid=${sid}#B-Reality-XHTTP-2095-aparat


# ── Trojan Reality TCP :2087 ─────────────────────────────────────────
# Variant A: SNI=www.aparat.com
trojan://${trojan_pwd}@${ip}:2087?security=reality&type=tcp&sni=www.aparat.com&fp=chrome&pbk=${pbk}&sid=${sid}#A-Trojan-Reality-2087-aparat

# Variant B: SNI=www.filimo.com
trojan://${trojan_pwd}@${ip}:2087?security=reality&type=tcp&sni=www.filimo.com&fp=chrome&pbk=${pbk}&sid=${sid}#B-Trojan-Reality-2087-filimo


════════════════════════════════════════════════════════════════════════════════
CDN — plaintext through Cloudflare (4 protocols, 2 variants each)
════════════════════════════════════════════════════════════════════════════════

# Variant A pattern: through cdn.dreammaker-groupsoft.ir (Cloudflare proxied → nearest edge)
# Variant B pattern: same xray inbound, but via apex/IP directly (no CF; lower hop count)

# ── VLESS WS :2086 ───────────────────────────────────────────────────
# Variant A (CDN — through Cloudflare nearest edge)
vless://${uuid}@${cdn}:2086?type=ws&security=none&path=${ws_path_enc}&host=${cdn}#A-CDN-VLESS-WS-2086

# Variant B (direct to origin IP, Host header preserved — bypasses CF, lower RTT but no IP masking)
vless://${uuid}@${ip}:2086?type=ws&security=none&path=${ws_path_enc}&host=${cdn}#B-Direct-VLESS-WS-2086


# ── VMess WS :2082 ───────────────────────────────────────────────────
# Variant A (CDN)
$(mk_vmess "A-CDN-VMess-WS-2082" "$cdn" "2082" "$uuid" "$cdn" "${V2_VMESS_PATH}")

# Variant B (direct origin IP)
$(mk_vmess "B-Direct-VMess-WS-2082" "$ip" "2082" "$uuid" "$cdn" "${V2_VMESS_PATH}")


# ── Trojan WS :2052 ──────────────────────────────────────────────────
# Variant A (CDN)
trojan://${trojan_pwd}@${cdn}:2052?type=ws&security=none&path=${trojan_path_enc}&host=${cdn}#A-CDN-Trojan-WS-2052

# Variant B (direct origin IP)
trojan://${trojan_pwd}@${ip}:2052?type=ws&security=none&path=${trojan_path_enc}&host=${cdn}#B-Direct-Trojan-WS-2052


# ── VLESS XHTTP :8880 ────────────────────────────────────────────────
# Variant A (CDN)
vless://${uuid}@${cdn}:8880?type=xhttp&security=none&path=${xhttp_path_enc}&host=${cdn}&mode=auto#A-CDN-VLESS-XHTTP-8880

# Variant B (direct origin IP)
vless://${uuid}@${ip}:8880?type=xhttp&security=none&path=${xhttp_path_enc}&host=${cdn}&mode=auto#B-Direct-VLESS-XHTTP-8880


════════════════════════════════════════════════════════════════════════════════
SHADOWSOCKS (only one variant — no SNI rotation possible)
════════════════════════════════════════════════════════════════════════════════

# Direct to ${ip} (no CDN; SS doesn't go through Cloudflare)
$(mk_ss "DM-Shadowsocks-2022" "$ip" "8388")


════════════════════════════════════════════════════════════════════════════════
SUMMARY — what to do
════════════════════════════════════════════════════════════════════════════════
  • Total: 19 entries  =  10 Reality variants  +  8 CDN variants  +  1 SS
  • All share the same UUID:           ${uuid}
  • All Reality use the same pubkey:   ${pbk}
  • All Reality use the same shortId:  ${sid}
  • Trojan password (shared 2087+2052): ${trojan_pwd}

For best TCP ping:
  1. Run "TCP Ping" in v2rayN on every entry.
  2. The fastest variant in each group becomes your primary.
  3. Reality direct (:443/2096/etc.) usually pings best — no CDN hop.
  4. CDN Variant A is best for IP masking; Variant B is for raw speed
     when Iran's route to ${ip} is fast that day.
  5. If CDN A pings ≫ B (>200ms gap), Cloudflare is routing you through
     a far edge — the issue is on CF, not your ISP.

────────────────────────────────────────────────────────────────────────────────
HEADER
} > "$out"

ok "wrote ${out}"
echo
echo "── Preview (first 60 lines) ──"
head -60 "$out"
echo "..."
echo "── Total entries (vless/vmess/trojan/ss links) ──"
grep -cE '^(vless|vmess|trojan|ss)://' "$out" || true

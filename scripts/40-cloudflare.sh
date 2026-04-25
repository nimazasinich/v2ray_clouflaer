#!/usr/bin/env bash
# STEP 3 + 4 — Cloudflare API: verify/enable WebSocket zone setting and add a
# cache-bypass rule for the CDN hostname. Skipped silently if the token or
# zone id is missing in config.env.
set -euo pipefail
. "$(dirname "$0")/../lib/common.sh"
load_config

section "STEP 3+4 — Cloudflare WebSocket + cache rule"

# Try to auto-discover a token if config.env does not set one.
if [[ -z "${CF_API_TOKEN:-}" ]]; then
    log "CF_API_TOKEN not set in config.env; attempting environment discovery"
    for v in CLOUDFLARE_API_TOKEN CF_TOKEN CLOUDFLARE_TOKEN; do
        val="${!v-}"
        if [[ -n "$val" ]]; then CF_API_TOKEN="$val"; break; fi
    done
fi

if [[ -z "${CF_API_TOKEN:-}" ]]; then
    warn "No Cloudflare API token available — skipping."
    warn "Enable WebSockets manually: Dashboard → Network → WebSockets → On."
    warn "Add Cache Rule manually:"
    warn "  When: http.host eq \"${CDN_SUB}\""
    warn "  Then: Cache Status = Bypass"
    exit 0
fi

require_cmd curl python3

cf() {
    local method="$1"; shift
    local path="$1"; shift
    curl -sS -X "$method" "https://api.cloudflare.com/client/v4${path}" \
        -H "Authorization: Bearer ${CF_API_TOKEN}" \
        -H "Content-Type: application/json" "$@"
}

# Resolve zone id if not provided.
if [[ -z "${CF_ZONE_ID:-}" ]]; then
    log "resolving zone id for ${DOMAIN}"
    CF_ZONE_ID="$(cf GET "/zones?name=${DOMAIN}" \
        | python3 -c 'import sys,json;d=json.load(sys.stdin);print((d.get("result") or [{}])[0].get("id",""))')"
    [[ -n "$CF_ZONE_ID" ]] || die "could not resolve CF zone id for ${DOMAIN} (token scope?)"
    ok "zone id: ${CF_ZONE_ID}"
fi

# --- WebSocket setting ----------------------------------------------------
log "reading WebSocket setting..."
ws_json="$(cf GET "/zones/${CF_ZONE_ID}/settings/websockets")"
ws_value="$(printf '%s' "$ws_json" | python3 -c 'import sys,json;d=json.load(sys.stdin);print((d.get("result") or {}).get("value",""))')"

case "$ws_value" in
    on)
        ok "WebSocket already ON"
        ;;
    off|"")
        log "enabling WebSocket zone setting..."
        cf PATCH "/zones/${CF_ZONE_ID}/settings/websockets" \
            --data '{"value":"on"}' >/dev/null
        ok "WebSocket set to ON"
        ;;
    *)
        warn "unexpected WebSocket value: ${ws_value}"
        printf '%s\n' "$ws_json"
        ;;
esac

# --- Cache bypass rule ---------------------------------------------------
log "ensuring cache-bypass rule for ${CDN_SUB}"
payload=$(cat <<JSON
{
  "rules": [{
    "action": "set_cache_settings",
    "action_parameters": {"cache": false},
    "expression": "http.host eq \"${CDN_SUB}\"",
    "description": "Bypass cache for Xray CDN (${CDN_SUB})",
    "enabled": true
  }]
}
JSON
)

rule_resp="$(cf PUT \
    "/zones/${CF_ZONE_ID}/rulesets/phases/http_request_cache_settings/entrypoint" \
    --data "$payload" || true)"

if printf '%s' "$rule_resp" | grep -q '"success":true'; then
    ok "cache-bypass rule applied via PUT"
else
    log "PUT failed; trying POST to entrypoints..."
    rule_resp="$(cf POST \
        "/zones/${CF_ZONE_ID}/rulesets/phases/http_request_cache_settings/entrypoints" \
        --data "$payload" || true)"
    if printf '%s' "$rule_resp" | grep -q '"success":true'; then
        ok "cache-bypass rule applied via POST"
    else
        warn "could not apply cache-bypass rule automatically:"
        printf '%s\n' "$rule_resp" >&2
    fi
fi

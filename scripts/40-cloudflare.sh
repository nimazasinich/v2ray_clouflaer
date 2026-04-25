#!/usr/bin/env bash
# STEP 3 + 4 — Cloudflare (READ-ONLY verification).
#
# Per operator policy this script NEVER changes Cloudflare settings. It only:
#   * resolves the zone id for the configured domain
#   * reads the current WebSocket zone setting
#   * lists existing cache rules on the zone and checks whether one already
#     bypasses cache for the CDN hostname
# Any required changes are printed as manual dashboard instructions.
#
# See docs/CLOUDFLARE-MANUAL.md for the full click-through.
set -euo pipefail
. "$(dirname "$0")/../lib/common.sh"
load_config

section "STEP 3+4 — Cloudflare verification (read-only)"

# Auto-discover a token from the environment if not set in config.env.
if [[ -z "${CF_API_TOKEN:-}" ]]; then
    for v in CLOUDFLARE_API_TOKEN CF_TOKEN CLOUDFLARE_TOKEN; do
        val="${!v-}"
        if [[ -n "$val" ]]; then CF_API_TOKEN="$val"; break; fi
    done
fi

print_manual_checklist() {
    hr
    warn "Apply these steps manually in the Cloudflare Dashboard:"
    cat <<MANUAL

  1. Network → WebSockets → ensure the toggle is ON.
  2. Caching → Cache Rules → Create rule:
        Name       : Bypass Xray WebSocket
        When       : Hostname equals ${CDN_SUB}
        Then       : Cache Status = Bypass
  3. SSL/TLS → Overview → mode: Full (or Full (strict) if available).
  4. DNS → ${CDN_SUB} record → Proxy status = Proxied (orange cloud).

  Full walkthrough: docs/CLOUDFLARE-MANUAL.md
MANUAL
    hr
}

if [[ -z "${CF_API_TOKEN:-}" ]]; then
    warn "No CF_API_TOKEN provided — skipping API read checks."
    print_manual_checklist
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

# --- Token sanity check ---------------------------------------------------
log "verifying token (GET /user/tokens/verify)..."
tok_resp="$(cf GET /user/tokens/verify)"
if ! printf '%s' "$tok_resp" | grep -q '"success":true'; then
    warn "token verification failed:"
    printf '%s\n' "$tok_resp" >&2
    print_manual_checklist
    exit 0
fi
ok "token is valid"

# --- Resolve zone ---------------------------------------------------------
if [[ -z "${CF_ZONE_ID:-}" ]]; then
    log "resolving zone id for ${DOMAIN}..."
    CF_ZONE_ID="$(cf GET "/zones?name=${DOMAIN}" \
        | python3 -c 'import sys,json;d=json.load(sys.stdin);r=d.get("result") or [];print(r[0]["id"] if r else "")')"
    if [[ -z "$CF_ZONE_ID" ]]; then
        warn "could not resolve zone id for ${DOMAIN} (token scope?)"
        print_manual_checklist
        exit 0
    fi
    ok "zone id: ${CF_ZONE_ID}"
fi

# --- Read WebSocket setting ----------------------------------------------
log "reading WebSocket zone setting..."
ws_json="$(cf GET "/zones/${CF_ZONE_ID}/settings/websockets")"

ws_parsed="$(CF_JSON="$ws_json" python3 <<'PY'
import json, os
raw = os.environ["CF_JSON"]
try:
    d = json.loads(raw)
except Exception:
    print("PARSE_ERROR"); raise SystemExit(0)
if d.get("success"):
    print("VALUE=" + str((d.get("result") or {}).get("value", "")))
else:
    errs = d.get("errors") or []
    print("ERROR=" + "; ".join(f"{e.get('code')}: {e.get('message')}" for e in errs))
PY
)"
case "$ws_parsed" in
    VALUE=on)   ok "WebSocket setting is ON" ;;
    VALUE=off)  warn "WebSocket setting is OFF — enable it manually in Dashboard → Network → WebSockets." ;;
    VALUE=*)    warn "unexpected WebSocket value: ${ws_parsed#VALUE=}" ;;
    ERROR=*)    warn "cannot read WebSocket setting — ${ws_parsed#ERROR=}"
                warn "(token likely lacks 'Zone Settings:Read' scope — verify manually in the dashboard instead)" ;;
    *)          warn "could not parse WebSocket API response" ;;
esac

# --- Read cache rules -----------------------------------------------------
log "reading cache rules for zone..."
rules_json="$(cf GET "/zones/${CF_ZONE_ID}/rulesets/phases/http_request_cache_settings/entrypoint" || true)"

CF_JSON="$rules_json" CF_CDN="$CDN_SUB" python3 <<'PY'
import json, os
raw = os.environ["CF_JSON"]
cdn = os.environ["CF_CDN"]
try:
    d = json.loads(raw)
except Exception:
    print("   (could not parse cache rules response)")
    raise SystemExit(0)

if not d.get("success"):
    errs = d.get("errors") or []
    msg = "; ".join(f"{e.get('code')}: {e.get('message')}" for e in errs) or "unknown error"
    print(f"   cannot read cache rules — {msg}")
    print("   (token likely lacks 'Zone Cache Rules:Read' scope — verify manually)")
    raise SystemExit(0)

result = d.get("result") or {}
rules = result.get("rules") or []
if not rules:
    print("   no cache rules configured on this zone")
    print(f"   -> Action: add 'Bypass cache for host={cdn}' in Dashboard → Caching → Cache Rules.")
    raise SystemExit(0)

print(f"   found {len(rules)} cache rule(s):")
hit = False
for r in rules:
    expr = r.get("expression", "")
    action = r.get("action", "")
    params = r.get("action_parameters", {}) or {}
    desc = r.get("description", "")
    enabled = r.get("enabled", True)
    tag = "ENABLED " if enabled else "DISABLED"
    print(f"     [{tag}] action={action} expr={expr!s:.120}")
    if desc:
        print(f"               description: {desc}")
    bypass = (action == "set_cache_settings" and params.get("cache") is False)
    if cdn in expr and bypass and enabled:
        hit = True

if hit:
    print(f"   OK: cache-bypass rule already covers host={cdn}")
else:
    print(f"   -> Action: add a Bypass rule for host={cdn} (none of the existing rules cover it).")
PY

echo
print_manual_checklist

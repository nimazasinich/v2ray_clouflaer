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

declare -a MANUAL_TODO=()

manual_add() {
    MANUAL_TODO+=("$1")
}

print_manual_checklist() {
    hr
    if [[ ${#MANUAL_TODO[@]} -eq 0 ]]; then
        printf "${_c_green}[OK]${_c_reset} All readable Cloudflare settings look correct.\n"
        printf "     Full walkthrough: docs/CLOUDFLARE-MANUAL.md\n"
        hr
        return
    fi
    printf "${_c_yellow}[!]${_c_reset} Apply these items manually in the Cloudflare Dashboard:\n"
    local i=1
    local item
    for item in "${MANUAL_TODO[@]}"; do
        printf "  %d. %s\n" "$i" "$item"
        i=$((i + 1))
    done
    echo
    printf "     Full walkthrough: docs/CLOUDFLARE-MANUAL.md\n"
    hr
}

if [[ -z "${CF_API_TOKEN:-}" ]]; then
    warn "No CF_API_TOKEN provided — skipping API read checks."
    manual_add "Network → WebSockets → toggle ON."
    manual_add "SSL/TLS → Overview → mode Full (or Full (strict))."
    manual_add "DNS → ${CDN_SUB} record → Proxy status = Proxied (orange cloud)."
    manual_add "Caching → Cache Rules → Bypass for host=${CDN_SUB}."
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
    manual_add "Network → WebSockets → toggle ON."
    manual_add "SSL/TLS → Overview → mode Full (or Full (strict))."
    manual_add "DNS → ${CDN_SUB} record → Proxy status = Proxied (orange cloud)."
    manual_add "Caching → Cache Rules → Bypass for host=${CDN_SUB}."
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
        manual_add "Network → WebSockets → toggle ON."
        manual_add "SSL/TLS → Overview → mode Full (or Full (strict))."
        manual_add "DNS → ${CDN_SUB} record → Proxy status = Proxied (orange cloud)."
        manual_add "Caching → Cache Rules → Bypass for host=${CDN_SUB}."
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
    VALUE=off)  warn "WebSocket setting is OFF."
                manual_add "Network → WebSockets → toggle ON." ;;
    VALUE=*)    warn "unexpected WebSocket value: ${ws_parsed#VALUE=}"
                manual_add "Network → WebSockets → confirm toggle is ON." ;;
    ERROR=*)    warn "cannot read WebSocket setting — ${ws_parsed#ERROR=}"
                warn "(token likely lacks 'Zone Settings:Read' scope)"
                manual_add "Network → WebSockets → confirm toggle is ON." ;;
    *)          warn "could not parse WebSocket API response"
                manual_add "Network → WebSockets → confirm toggle is ON." ;;
esac

# --- Read SSL/TLS mode ---------------------------------------------------
log "reading SSL/TLS mode..."
ssl_json="$(cf GET "/zones/${CF_ZONE_ID}/settings/ssl")"
ssl_parsed="$(CF_JSON="$ssl_json" python3 <<'PY'
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
case "$ssl_parsed" in
    VALUE=full|VALUE=strict) ok "SSL/TLS mode is ${ssl_parsed#VALUE=} (good)" ;;
    VALUE=flexible)          warn "SSL/TLS mode is FLEXIBLE."
                             manual_add "SSL/TLS → Overview → switch mode to Full (or Full (strict))." ;;
    VALUE=off)               warn "SSL/TLS mode is OFF."
                             manual_add "SSL/TLS → Overview → set mode to Full (or Full (strict))." ;;
    VALUE=*)                 warn "SSL/TLS mode: ${ssl_parsed#VALUE=}"
                             manual_add "SSL/TLS → Overview → confirm mode is Full (or Full (strict))." ;;
    ERROR=*)                 warn "cannot read SSL/TLS mode — ${ssl_parsed#ERROR=}"
                             manual_add "SSL/TLS → Overview → confirm mode is Full (or Full (strict))." ;;
    *)                       warn "could not parse SSL/TLS response"
                             manual_add "SSL/TLS → Overview → confirm mode is Full (or Full (strict))." ;;
esac

# --- Read DNS record for CDN subdomain -----------------------------------
log "reading DNS record for ${CDN_SUB}..."
dns_json="$(cf GET "/zones/${CF_ZONE_ID}/dns_records?name=${CDN_SUB}")"
dns_report="$(CF_JSON="$dns_json" CF_CDN="$CDN_SUB" python3 <<'PY'
import json, os
raw = os.environ["CF_JSON"]
cdn = os.environ["CF_CDN"]
try:
    d = json.loads(raw)
except Exception:
    print("PARSE_ERROR"); raise SystemExit(0)
if not d.get("success"):
    errs = d.get("errors") or []
    print("ERROR=" + "; ".join(f"{e.get('code')}: {e.get('message')}" for e in errs))
    raise SystemExit(0)
rs = d.get("result") or []
if not rs:
    print(f"MISSING={cdn}")
    raise SystemExit(0)
r = rs[0]
print("OK={}|{}|{}|proxied={}".format(
    r.get("type"), r.get("name"), r.get("content"), r.get("proxied")))
PY
)"
case "$dns_report" in
    OK=*)
        det="${dns_report#OK=}"
        if [[ "$det" == *"proxied=True"* ]]; then
            ok "DNS ${CDN_SUB}: ${det%|proxied=*} (proxied / orange cloud)"
        else
            warn "DNS ${CDN_SUB}: ${det%|proxied=*} — proxy is OFF (grey cloud)."
            manual_add "DNS → ${CDN_SUB} → enable Proxy (orange cloud)."
        fi ;;
    MISSING=*) warn "no DNS record found for ${CDN_SUB}"
               manual_add "DNS → add A record ${CDN_SUB} → ${SERVER_IP}, Proxied." ;;
    ERROR=*)   warn "cannot read DNS records — ${dns_report#ERROR=}"
               manual_add "DNS → ${CDN_SUB} record → confirm A → ${SERVER_IP}, Proxied." ;;
    *)         warn "could not parse DNS records response"
               manual_add "DNS → ${CDN_SUB} record → confirm A → ${SERVER_IP}, Proxied." ;;
esac

# --- Read cache rules -----------------------------------------------------
log "reading cache rules for zone..."
rules_json="$(cf GET "/zones/${CF_ZONE_ID}/rulesets/phases/http_request_cache_settings/entrypoint" || true)"

cache_result="$(CF_JSON="$rules_json" CF_CDN="$CDN_SUB" python3 <<'PY'
import json, os, sys
raw = os.environ["CF_JSON"]
cdn = os.environ["CF_CDN"]
def say(msg):  sys.stdout.write("SAY " + msg + "\n")
def sig(tok):  sys.stdout.write("SIG " + tok + "\n")
try:
    d = json.loads(raw)
except Exception:
    say("(could not parse cache rules response)")
    sig("UNKNOWN")
    raise SystemExit(0)

if not d.get("success"):
    errs = d.get("errors") or []
    msg = "; ".join(f"{e.get('code')}: {e.get('message')}" for e in errs) or "unknown error"
    say(f"cannot read cache rules — {msg}")
    say("(token likely lacks 'Zone Cache Rules:Read' scope — verify manually)")
    sig("UNREADABLE")
    raise SystemExit(0)

result = d.get("result") or {}
rules = result.get("rules") or []
if not rules:
    say("no cache rules configured on this zone")
    sig("MISSING")
    raise SystemExit(0)

say(f"found {len(rules)} cache rule(s):")
hit = False
for r in rules:
    expr    = r.get("expression", "")
    action  = r.get("action", "")
    params  = r.get("action_parameters", {}) or {}
    desc    = r.get("description", "")
    enabled = r.get("enabled", True)
    tag     = "ENABLED " if enabled else "DISABLED"
    say(f"  [{tag}] action={action} expr={expr!s:.120}")
    if desc:
        say(f"            description: {desc}")
    bypass = (action == "set_cache_settings" and params.get("cache") is False)
    if cdn in expr and bypass and enabled:
        hit = True

sig("COVERED" if hit else "MISSING")
PY
)"

# Echo messages and collect signal.
cache_signal=""
while IFS= read -r line; do
    case "$line" in
        "SAY "*) printf "   %s\n" "${line#SAY }" ;;
        "SIG "*) cache_signal="${line#SIG }" ;;
    esac
done <<< "$cache_result"

case "$cache_signal" in
    COVERED)    ok "cache-bypass rule already covers host=${CDN_SUB}" ;;
    MISSING)    warn "no cache-bypass rule covers host=${CDN_SUB}"
                manual_add "Caching → Cache Rules → add rule: Hostname equals ${CDN_SUB} → Cache Status = Bypass." ;;
    UNREADABLE) manual_add "Caching → Cache Rules → confirm Bypass rule for host=${CDN_SUB} (not readable with current token scope)." ;;
    *)          manual_add "Caching → Cache Rules → confirm Bypass rule for host=${CDN_SUB}." ;;
esac

echo
print_manual_checklist

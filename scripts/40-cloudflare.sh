#!/usr/bin/env bash
# STEP 3 + 4 — Cloudflare verification (READ-ONLY).
#
# Per operator policy this script NEVER changes Cloudflare settings. It only
# performs GET requests to the Cloudflare API and compares results against
# the expected state declared in config.env (CF_EXPECT_*). Any mismatch is
# surfaced as a manual dashboard action in the final checklist.
#
# See docs/CLOUDFLARE-MANUAL.md and docs/DEPLOYMENT-GUIDE-v2.md.
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
manual_add() { MANUAL_TODO+=("$1"); }

print_manual_checklist() {
    hr
    if [[ ${#MANUAL_TODO[@]} -eq 0 ]]; then
        printf "${_c_green}[OK]${_c_reset} All readable Cloudflare settings match expected state.\n"
        printf "     Full walkthrough: docs/CLOUDFLARE-MANUAL.md\n"
        hr
        return
    fi
    printf "${_c_yellow}[!]${_c_reset} Apply these items manually in the Cloudflare Dashboard:\n"
    local i=1 item
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
    manual_add "Network → HTTP/3 (QUIC) → toggle ON."
    manual_add "Network → 0-RTT Connection Resumption → toggle ON."
    manual_add "SSL/TLS → Overview → mode Full (or Full (strict))."
    manual_add "SSL/TLS → Edge Certificates → Minimum TLS Version = 1.2."
    manual_add "SSL/TLS → Edge Certificates → TLS 1.3 = On."
    manual_add "SSL/TLS → Edge Certificates → Always Use HTTPS = Off."
    manual_add "SSL/TLS → Edge Certificates → Automatic HTTPS Rewrites = Off."
    manual_add "DNS → ${CDN_SUB} → A ${SERVER_IP}, Proxied (orange cloud)."
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

# Parse a zone-setting JSON response into "VALUE=<v>" or "ERROR=<msg>".
parse_setting() {
    CF_JSON="$1" python3 <<'PY'
import json, os
raw = os.environ["CF_JSON"]
try:
    d = json.loads(raw)
except Exception:
    print("ERROR=parse error"); raise SystemExit(0)
if d.get("success"):
    print("VALUE=" + str((d.get("result") or {}).get("value", "")))
else:
    errs = d.get("errors") or []
    print("ERROR=" + "; ".join(f"{e.get('code')}: {e.get('message')}" for e in errs))
PY
}

# Generic "read-and-compare" check: name | api-path | expected | dashboard-fix
check_setting() {
    local label="$1" path="$2" expected="$3" fix="$4"
    log "reading ${label}..."
    local resp parsed val
    resp="$(cf GET "$path")"
    parsed="$(parse_setting "$resp")"
    case "$parsed" in
        VALUE=*)
            val="${parsed#VALUE=}"
            if [[ "$val" == "$expected" ]]; then
                ok "${label} = ${val} (expected)"
            else
                warn "${label} = ${val}  (expected ${expected})"
                manual_add "${fix} (currently: ${val}, want: ${expected})"
            fi ;;
        ERROR=*)
            warn "cannot read ${label} — ${parsed#ERROR=}"
            manual_add "${fix} (token cannot read this; verify manually)" ;;
    esac
}

# --- Token sanity check ---------------------------------------------------
log "verifying token (GET /user/tokens/verify)..."
tok_resp="$(cf GET /user/tokens/verify)"
if ! printf '%s' "$tok_resp" | grep -q '"success":true'; then
    warn "token verification failed:"
    printf '%s\n' "$tok_resp" >&2
    manual_add "Cloudflare API token invalid — verify the entire zone state by hand."
    print_manual_checklist
    exit 0
fi
ok "token is valid"

# --- Resolve zone --------------------------------------------------------
if [[ -z "${CF_ZONE_ID:-}" ]]; then
    log "resolving zone id for ${DOMAIN}..."
    CF_ZONE_ID="$(cf GET "/zones?name=${DOMAIN}" \
        | python3 -c 'import sys,json;d=json.load(sys.stdin);r=d.get("result") or [];print(r[0]["id"] if r else "")')"
    if [[ -z "$CF_ZONE_ID" ]]; then
        warn "could not resolve zone id for ${DOMAIN} (token scope?)"
        manual_add "Verify zone ${DOMAIN} exists and is active in Cloudflare."
        print_manual_checklist
        exit 0
    fi
    ok "zone id: ${CF_ZONE_ID}"
fi

# --- Zone settings (Network + SSL/TLS) -----------------------------------
check_setting "WebSocket setting"        "/zones/${CF_ZONE_ID}/settings/websockets" \
    "${CF_EXPECT_WEBSOCKETS:-on}" \
    "Network → WebSockets → toggle ON"

check_setting "HTTP/3 (QUIC)"            "/zones/${CF_ZONE_ID}/settings/http3" \
    "${CF_EXPECT_HTTP3:-on}" \
    "Network → HTTP/3 (QUIC) → toggle ON"

check_setting "0-RTT Connection Resumption" "/zones/${CF_ZONE_ID}/settings/0rtt" \
    "${CF_EXPECT_0RTT:-on}" \
    "Network → 0-RTT Connection Resumption → toggle ON"

check_setting "SSL/TLS encryption mode"  "/zones/${CF_ZONE_ID}/settings/ssl" \
    "${CF_EXPECT_SSL_MODE:-full}" \
    "SSL/TLS → Overview → set mode to Full (or Full (strict))"

check_setting "Minimum TLS Version"      "/zones/${CF_ZONE_ID}/settings/min_tls_version" \
    "${CF_EXPECT_MIN_TLS:-1.2}" \
    "SSL/TLS → Edge Certificates → Minimum TLS Version = 1.2"

check_setting "TLS 1.3"                  "/zones/${CF_ZONE_ID}/settings/tls_1_3" \
    "${CF_EXPECT_TLS_1_3:-on}" \
    "SSL/TLS → Edge Certificates → TLS 1.3 = On"

check_setting "Always Use HTTPS"         "/zones/${CF_ZONE_ID}/settings/always_use_https" \
    "${CF_EXPECT_ALWAYS_USE_HTTPS:-off}" \
    "SSL/TLS → Edge Certificates → Always Use HTTPS = Off"

check_setting "Automatic HTTPS Rewrites" "/zones/${CF_ZONE_ID}/settings/automatic_https_rewrites" \
    "${CF_EXPECT_AUTO_HTTPS_REWRITES:-off}" \
    "SSL/TLS → Edge Certificates → Automatic HTTPS Rewrites = Off"

# --- DNS records ---------------------------------------------------------
log "reading DNS record for ${CDN_SUB}..."
dns_json="$(cf GET "/zones/${CF_ZONE_ID}/dns_records?name=${CDN_SUB}")"
dns_report="$(CF_JSON="$dns_json" CF_CDN="$CDN_SUB" CF_IP="$SERVER_IP" python3 <<'PY'
import json, os
raw = os.environ["CF_JSON"]
cdn = os.environ["CF_CDN"]
ip  = os.environ["CF_IP"]
try:
    d = json.loads(raw)
except Exception:
    print("ERROR=parse error"); raise SystemExit(0)
if not d.get("success"):
    errs = d.get("errors") or []
    print("ERROR=" + "; ".join(f"{e.get('code')}: {e.get('message')}" for e in errs))
    raise SystemExit(0)
rs = d.get("result") or []
if not rs:
    print(f"MISSING={cdn}"); raise SystemExit(0)
r = rs[0]
print("OK=type={} name={} content={} proxied={} match_ip={}".format(
    r.get("type"), r.get("name"), r.get("content"),
    r.get("proxied"), str(r.get("content")) == ip))
PY
)"
case "$dns_report" in
    OK=*)
        det="${dns_report#OK=}"
        proxied="false"; [[ "$det" == *"proxied=True"* ]] && proxied="true"
        ip_ok="false";   [[ "$det" == *"match_ip=True"* ]] && ip_ok="true"
        if [[ "$proxied" == "${CF_EXPECT_CDN_PROXIED:-true}" && "$ip_ok" == "true" ]]; then
            ok "DNS ${CDN_SUB}: ${det}"
        else
            warn "DNS ${CDN_SUB} mismatch: ${det}"
            manual_add "DNS → ${CDN_SUB} → A ${SERVER_IP}, Proxied (orange cloud)."
        fi ;;
    MISSING=*) warn "no DNS record for ${CDN_SUB}"
               manual_add "DNS → add A record ${CDN_SUB} → ${SERVER_IP}, Proxied (orange cloud)." ;;
    ERROR=*)   warn "cannot read DNS records — ${dns_report#ERROR=}"
               manual_add "DNS → confirm ${CDN_SUB} → A ${SERVER_IP}, Proxied." ;;
esac

# Apex (informational only unless CF_EXPECT_APEX_PROXIED is set).
if [[ "${CF_EXPECT_APEX_PROXIED:-any}" != "any" ]]; then
    log "reading DNS record for apex ${DOMAIN}..."
    apex_json="$(cf GET "/zones/${CF_ZONE_ID}/dns_records?name=${DOMAIN}&type=A")"
    apex_report="$(CF_JSON="$apex_json" CF_HOST="$DOMAIN" python3 <<'PY'
import json, os
raw = os.environ["CF_JSON"]
host = os.environ["CF_HOST"]
try:
    d = json.loads(raw)
except Exception:
    print("ERROR=parse"); raise SystemExit(0)
if not d.get("success"):
    print("ERROR=cf"); raise SystemExit(0)
rs = d.get("result") or []
if not rs:
    print("MISSING"); raise SystemExit(0)
r = rs[0]
print("OK=proxied={}".format(r.get("proxied")))
PY
)"
    case "$apex_report" in
        OK=proxied=True)
            if [[ "${CF_EXPECT_APEX_PROXIED}" == "true" ]]; then
                ok "apex ${DOMAIN}: proxied (as expected)"
            else
                warn "apex ${DOMAIN}: proxied — Reality on port 443 needs DNS-only"
                manual_add "DNS → ${DOMAIN} (apex A record) → toggle proxy OFF (grey cloud) for Reality."
            fi ;;
        OK=proxied=False)
            if [[ "${CF_EXPECT_APEX_PROXIED}" == "false" ]]; then
                ok "apex ${DOMAIN}: DNS-only (as expected)"
            else
                warn "apex ${DOMAIN}: DNS-only — expected proxied"
                manual_add "DNS → ${DOMAIN} (apex A record) → toggle proxy ON (orange cloud)."
            fi ;;
    esac
fi

# --- Cache rules ---------------------------------------------------------
log "reading cache rules for zone..."
rules_json="$(cf GET "/zones/${CF_ZONE_ID}/rulesets/phases/http_request_cache_settings/entrypoint" || true)"
cache_result="$(CF_JSON="$rules_json" CF_CDN="$CDN_SUB" python3 <<'PY'
import json, os, sys
raw = os.environ["CF_JSON"]; cdn = os.environ["CF_CDN"]
def say(m): sys.stdout.write("SAY " + m + "\n")
def sig(t): sys.stdout.write("SIG " + t + "\n")
try:
    d = json.loads(raw)
except Exception:
    say("(could not parse cache rules response)"); sig("UNKNOWN"); raise SystemExit(0)
if not d.get("success"):
    errs = d.get("errors") or []
    msg = "; ".join(f"{e.get('code')}: {e.get('message')}" for e in errs) or "unknown error"
    say(f"cannot read cache rules — {msg}")
    say("(token likely lacks 'Zone Cache Rules:Read' scope — verify manually)")
    sig("UNREADABLE"); raise SystemExit(0)
rules = (d.get("result") or {}).get("rules") or []
if not rules:
    say("no cache rules configured on this zone"); sig("MISSING"); raise SystemExit(0)
say(f"found {len(rules)} cache rule(s):"); hit = False
for r in rules:
    expr = r.get("expression",""); action = r.get("action","")
    params = r.get("action_parameters",{}) or {}
    enabled = r.get("enabled", True)
    say(f"  [{'EN ' if enabled else 'DIS'}] action={action} expr={expr!s:.110}")
    if action == "set_cache_settings" and params.get("cache") is False and cdn in expr and enabled:
        hit = True
sig("COVERED" if hit else "MISSING")
PY
)"
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
                manual_add "Caching → Cache Rules → add: Hostname equals ${CDN_SUB} → Cache Status = Bypass." ;;
    UNREADABLE) manual_add "Caching → Cache Rules → confirm Bypass rule for host=${CDN_SUB} (token cannot read; verify manually)." ;;
    *)          manual_add "Caching → Cache Rules → confirm Bypass rule for host=${CDN_SUB}." ;;
esac

echo
print_manual_checklist

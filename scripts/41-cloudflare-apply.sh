#!/usr/bin/env bash
# OPT-IN — apply Cloudflare zone state to match CF_EXPECT_* (config.env).
#
# Default behavior of this app remains strictly read-only
# (scripts/40-cloudflare.sh). This script is explicitly *not* called by
# bin/run-all.sh. It will refuse to mutate anything unless the operator
# has set CF_APPLY_CONFIRM=YES (env or config.env), so accidental runs
# can never change the zone.
#
# Required token scopes on the zone:
#   * Zone → Zone → Read
#   * Zone → Zone Settings → Edit
#   * Zone → DNS → Edit                 (only if DNS is missing/wrong)
#   * Zone → Cache Rules → Edit         (for the cache-bypass rule)
#
# The corresponding read-only verifier (scripts/40-cloudflare.sh) should
# be run before AND after this script.
set -euo pipefail
_ENV_CF_APPLY_CONFIRM="${CF_APPLY_CONFIRM:-}"
. "$(dirname "$0")/../lib/common.sh"
load_config
if [[ -z "${CF_APPLY_CONFIRM:-}" && -n "$_ENV_CF_APPLY_CONFIRM" ]]; then
    CF_APPLY_CONFIRM="$_ENV_CF_APPLY_CONFIRM"
fi

section "OPT-IN — Apply Cloudflare zone state to CF_EXPECT_*"

if [[ -z "${CF_API_TOKEN:-}" ]]; then
    die "CF_API_TOKEN is empty. Set it in config.env (with edit scope) and re-run."
fi

confirm="${CF_APPLY_CONFIRM:-}"
if [[ "$confirm" != "YES" ]]; then
    warn "CF_APPLY_CONFIRM is not set to YES — refusing to mutate the zone."
    warn "Set 'CF_APPLY_CONFIRM=YES' in config.env or the environment to enable."
    warn "Until then this is a no-op."
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

cf_success() {
    CF_JSON="$1" python3 <<'PY'
import json, os
try:
    d = json.loads(os.environ["CF_JSON"])
except Exception:
    print("false"); raise SystemExit(0)
print("true" if d.get("success") else "false")
PY
}

cf_first_error() {
    CF_JSON="$1" python3 <<'PY'
import json, os
try:
    d = json.loads(os.environ["CF_JSON"])
except Exception:
    print("(unparseable)"); raise SystemExit(0)
errs = d.get("errors") or []
print("; ".join(f"{e.get('code')}: {e.get('message')}" for e in errs) or "(no error detail)")
PY
}

# --- Resolve zone --------------------------------------------------------
if [[ -z "${CF_ZONE_ID:-}" ]]; then
    log "resolving zone id for ${DOMAIN}..."
    CF_ZONE_ID="$(cf GET "/zones?name=${DOMAIN}" \
        | python3 -c 'import sys,json;d=json.load(sys.stdin);r=d.get("result") or [];print(r[0]["id"] if r else "")')"
    [[ -n "$CF_ZONE_ID" ]] || die "could not resolve zone id for ${DOMAIN} (token scope?)"
    ok "zone id: ${CF_ZONE_ID}"
fi

# --- Scope sanity --------------------------------------------------------
log "verifying token scope (read settings + DNS)..."
if [[ "$(cf_success "$(cf GET "/zones/${CF_ZONE_ID}/settings/websockets")")" != "true" ]]; then
    die "token cannot read /settings/websockets — needs Zone Settings:Edit (Read implied)."
fi
ok "token scope sufficient for settings"

# Tracking ----------------------------------------------------------------
declare -i applied=0 already=0 failed=0

# Generic setting setter --------------------------------------------------
apply_setting() {
    local label="$1" path="$2" expected="$3"
    local current_resp current_val
    current_resp="$(cf GET "$path")"
    if [[ "$(cf_success "$current_resp")" != "true" ]]; then
        warn "cannot read ${label}: $(cf_first_error "$current_resp") — skipping"
        failed+=1
        return
    fi
    current_val="$(printf '%s' "$current_resp" | python3 -c 'import sys,json;d=json.load(sys.stdin);print((d.get("result") or {}).get("value",""))')"
    if [[ "$current_val" == "$expected" ]]; then
        ok "${label} already ${current_val}"
        already+=1
        return
    fi
    log "PATCH ${label}: ${current_val} -> ${expected}"
    local resp
    resp="$(cf PATCH "$path" --data "$(printf '{"value":"%s"}' "$expected")")"
    if [[ "$(cf_success "$resp")" == "true" ]]; then
        ok "${label} set to ${expected}"
        applied+=1
    else
        warn "FAILED to set ${label}: $(cf_first_error "$resp")"
        failed+=1
    fi
}

# --- Zone settings -------------------------------------------------------
apply_setting "WebSockets"               "/zones/${CF_ZONE_ID}/settings/websockets" \
    "${CF_EXPECT_WEBSOCKETS:-on}"
apply_setting "HTTP/3 (QUIC)"            "/zones/${CF_ZONE_ID}/settings/http3" \
    "${CF_EXPECT_HTTP3:-on}"
apply_setting "0-RTT"                    "/zones/${CF_ZONE_ID}/settings/0rtt" \
    "${CF_EXPECT_0RTT:-on}"
apply_setting "SSL/TLS encryption mode"  "/zones/${CF_ZONE_ID}/settings/ssl" \
    "${CF_EXPECT_SSL_MODE:-full}"
apply_setting "Minimum TLS Version"      "/zones/${CF_ZONE_ID}/settings/min_tls_version" \
    "${CF_EXPECT_MIN_TLS:-1.2}"
# Cloudflare quirk: tls_1_3=zrt means "TLS 1.3 + 0-RTT enabled". If both
# 0-RTT and TLS 1.3 are desired, set tls_1_3 to "zrt" (this also enables
# 0-RTT atomically). If TLS 1.3 is on but 0-RTT is off, send "on".
expected_tls13="${CF_EXPECT_TLS_1_3:-on}"
if [[ "${CF_EXPECT_0RTT:-on}" == "on" && "$expected_tls13" == "on" ]]; then
    expected_tls13="zrt"
fi
apply_setting "TLS 1.3"                  "/zones/${CF_ZONE_ID}/settings/tls_1_3" \
    "$expected_tls13"

apply_setting "Always Use HTTPS"         "/zones/${CF_ZONE_ID}/settings/always_use_https" \
    "${CF_EXPECT_ALWAYS_USE_HTTPS:-off}"
apply_setting "Automatic HTTPS Rewrites" "/zones/${CF_ZONE_ID}/settings/automatic_https_rewrites" \
    "${CF_EXPECT_AUTO_HTTPS_REWRITES:-off}"

# --- DNS for cdn.* -------------------------------------------------------
log "ensuring DNS for ${CDN_SUB} -> ${SERVER_IP} (proxied)"
dns_resp="$(cf GET "/zones/${CF_ZONE_ID}/dns_records?name=${CDN_SUB}&type=A")"
if [[ "$(cf_success "$dns_resp")" != "true" ]]; then
    warn "cannot read DNS records: $(cf_first_error "$dns_resp") — skipping"
    failed+=1
else
    rec_summary="$(CF_JSON="$dns_resp" CF_IP="$SERVER_IP" python3 <<'PY'
import json, os
d = json.loads(os.environ["CF_JSON"])
ip = os.environ["CF_IP"]
rs = d.get("result") or []
if not rs:
    print("MISSING")
else:
    r = rs[0]
    same_ip = (str(r.get("content")) == ip)
    proxied = bool(r.get("proxied"))
    print(f"FOUND id={r.get('id')} ip_ok={same_ip} proxied={proxied}")
PY
)"
    case "$rec_summary" in
        MISSING)
            log "creating A record ${CDN_SUB} -> ${SERVER_IP} (proxied)"
            payload="$(printf '{"type":"A","name":"%s","content":"%s","proxied":true,"ttl":1}' "$CDN_SUB" "$SERVER_IP")"
            resp="$(cf POST "/zones/${CF_ZONE_ID}/dns_records" --data "$payload")"
            if [[ "$(cf_success "$resp")" == "true" ]]; then
                ok "DNS A record created"; applied+=1
            else
                warn "FAILED to create DNS: $(cf_first_error "$resp")"; failed+=1
            fi ;;
        FOUND*)
            id="$(printf '%s' "$rec_summary" | sed -n 's/^FOUND id=\([^ ]*\).*/\1/p')"
            ip_ok="false"; [[ "$rec_summary" == *"ip_ok=True"* ]] && ip_ok="true"
            proxied="false"; [[ "$rec_summary" == *"proxied=True"* ]] && proxied="true"
            if [[ "$ip_ok" == "true" && "$proxied" == "${CF_EXPECT_CDN_PROXIED:-true}" ]]; then
                ok "DNS ${CDN_SUB}: already correct"; already+=1
            else
                log "PATCH DNS ${CDN_SUB} -> ${SERVER_IP}, proxied=${CF_EXPECT_CDN_PROXIED:-true}"
                payload="$(printf '{"type":"A","name":"%s","content":"%s","proxied":%s}' \
                    "$CDN_SUB" "$SERVER_IP" "${CF_EXPECT_CDN_PROXIED:-true}")"
                resp="$(cf PATCH "/zones/${CF_ZONE_ID}/dns_records/${id}" --data "$payload")"
                if [[ "$(cf_success "$resp")" == "true" ]]; then
                    ok "DNS record updated"; applied+=1
                else
                    warn "FAILED to update DNS: $(cf_first_error "$resp")"; failed+=1
                fi
            fi ;;
    esac
fi

# --- Cache bypass rule ---------------------------------------------------
log "ensuring Cache Rules entrypoint has Bypass for host=${CDN_SUB}"
ep_resp="$(cf GET "/zones/${CF_ZONE_ID}/rulesets/phases/http_request_cache_settings/entrypoint" || true)"
ep_state="$(CF_JSON="$ep_resp" CF_CDN="$CDN_SUB" python3 <<'PY'
import json, os
raw = os.environ["CF_JSON"]; cdn = os.environ["CF_CDN"]
try:
    d = json.loads(raw)
except Exception:
    print("UNREADABLE"); raise SystemExit(0)
if not d.get("success"):
    print("UNREADABLE"); raise SystemExit(0)
result = d.get("result") or {}
rules = result.get("rules") or []
hit = any(
    r.get("action") == "set_cache_settings"
    and (r.get("action_parameters") or {}).get("cache") is False
    and cdn in r.get("expression","")
    and r.get("enabled", True)
    for r in rules
)
print("COVERED" if hit else "MISSING")
PY
)"
case "$ep_state" in
    COVERED) ok "cache-bypass rule already covers ${CDN_SUB}"; already+=1 ;;
    MISSING|UNREADABLE)
        log "PUT cache-rules entrypoint with Bypass for ${CDN_SUB}"
        # Re-read existing rules so we don't clobber others (best effort).
        existing="$(CF_JSON="$ep_resp" python3 <<'PY'
import json, os
try:
    d = json.loads(os.environ["CF_JSON"])
    rules = ((d.get("result") or {}).get("rules") or []) if d.get("success") else []
except Exception:
    rules = []
keep = [r for r in rules if not (
    r.get("action") == "set_cache_settings"
    and (r.get("action_parameters") or {}).get("cache") is False
    and "cdn" in (r.get("expression","") or "").lower()
)]
print(json.dumps(keep))
PY
)"
        new_rule="$(CF_CDN="$CDN_SUB" python3 <<'PY'
import json, os
print(json.dumps({
    "action": "set_cache_settings",
    "action_parameters": {"cache": False},
    "expression": f'http.host eq "{os.environ["CF_CDN"]}"',
    "description": f'Bypass cache for Xray CDN ({os.environ["CF_CDN"]})',
    "enabled": True
}))
PY
)"
        payload="$(EX="$existing" NR="$new_rule" python3 -c '
import json, os
ex = json.loads(os.environ["EX"])
nr = json.loads(os.environ["NR"])
print(json.dumps({"rules": ex + [nr]}))')"
        resp="$(cf PUT "/zones/${CF_ZONE_ID}/rulesets/phases/http_request_cache_settings/entrypoint" --data "$payload")"
        if [[ "$(cf_success "$resp")" == "true" ]]; then
            ok "cache-bypass rule applied"; applied+=1
        else
            warn "FAILED to apply cache rule: $(cf_first_error "$resp")"; failed+=1
        fi ;;
esac

# --- Summary -------------------------------------------------------------
hr
printf "Cloudflare apply summary:\n"
printf "  applied  : %d\n" "$applied"
printf "  unchanged: %d\n" "$already"
printf "  failed   : %d\n" "$failed"
hr
[[ $failed -eq 0 ]] || exit 1

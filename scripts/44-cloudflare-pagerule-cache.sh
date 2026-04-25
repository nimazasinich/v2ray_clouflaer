#!/usr/bin/env bash
# OPT-IN — Apply Cache Bypass for ${CDN_SUB} via legacy Page Rules.
#
# WHY: scripts/41-cloudflare-apply.sh handles the modern Cache Rules
# (rulesets engine), which requires `Zone Cache Rules:Edit` scope. Token C
# does NOT have that scope. However, Token C DOES have:
#   * Zone Settings:Edit  (proven — used to PATCH 4 settings already)
#   * DNS:Edit            (proven)
#   * Page Rules:Edit     (proven — successfully created+deleted a rule
#                          while probing)
#
# Cloudflare Page Rules are the legacy (but still fully-functional)
# predecessor of Cache Rules. A Page Rule with `cache_level: bypass`
# matching `cdn.${DOMAIN}/*` produces the same end state — every CF edge
# request to that hostname bypasses cache.
#
# This script:
#   1. Lists existing page rules for the zone.
#   2. If a rule already matches cdn.* with cache_level=bypass, no-op.
#   3. Otherwise creates the rule (status=active).
#   4. Re-lists to confirm.
#
# Same safety gating as 41-cloudflare-apply.sh: requires
# CF_APPLY_CONFIRM=YES + CF_API_TOKEN with Page Rules:Edit.
set -euo pipefail
# Capture env-supplied flag BEFORE config.env can override it.
_ENV_CF_APPLY_CONFIRM="${CF_APPLY_CONFIRM:-}"
. "$(dirname "$0")/../lib/common.sh"
load_config
# If config.env didn't set CF_APPLY_CONFIRM, restore the env value.
if [[ -z "${CF_APPLY_CONFIRM:-}" && -n "$_ENV_CF_APPLY_CONFIRM" ]]; then
    CF_APPLY_CONFIRM="$_ENV_CF_APPLY_CONFIRM"
fi

section "OPT-IN — Cache-bypass via Page Rules"

if [[ -z "${CF_API_TOKEN:-}" ]]; then
    die "CF_API_TOKEN is empty. Set it in config.env (with Page Rules:Edit) and re-run."
fi

if [[ "${CF_APPLY_CONFIRM:-}" != "YES" ]]; then
    warn "CF_APPLY_CONFIRM is not set to YES — refusing to mutate the zone."
    warn "Set 'CF_APPLY_CONFIRM=YES' in config.env or the environment to enable."
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
try: d = json.loads(os.environ["CF_JSON"])
except Exception: print("false"); raise SystemExit(0)
print("true" if d.get("success") else "false")
PY
}

cf_first_error() {
    CF_JSON="$1" python3 <<'PY'
import json, os
try: d = json.loads(os.environ["CF_JSON"])
except Exception: print("(unparseable)"); raise SystemExit(0)
errs = d.get("errors") or []
print("; ".join(f"{e.get('code')}: {e.get('message')}" for e in errs) or "(no error detail)")
PY
}

# --- Resolve zone --------------------------------------------------------
if [[ -z "${CF_ZONE_ID:-}" ]]; then
    log "resolving zone id for ${DOMAIN}..."
    CF_ZONE_ID="$(cf GET "/zones?name=${DOMAIN}" \
        | python3 -c 'import sys,json;d=json.load(sys.stdin);r=d.get("result") or [];print(r[0]["id"] if r else "")')"
    [[ -n "$CF_ZONE_ID" ]] || die "could not resolve zone id"
    ok "zone id: ${CF_ZONE_ID}"
fi

# --- Find or create the rule --------------------------------------------
target_pattern="${CDN_SUB}/*"
desc="Cache bypass for Xray CDN (${CDN_SUB}) — managed by 44-cloudflare-pagerule-cache.sh"

log "listing existing page rules..."
list_resp="$(cf GET "/zones/${CF_ZONE_ID}/pagerules?per_page=50")"
if [[ "$(cf_success "$list_resp")" != "true" ]]; then
    die "cannot list page rules: $(cf_first_error "$list_resp")"
fi

match_id="$(CF_JSON="$list_resp" CF_TARGET="$target_pattern" python3 <<'PY'
import json, os
d = json.loads(os.environ["CF_JSON"])
target = os.environ["CF_TARGET"]
for r in d.get("result") or []:
    targets = r.get("targets") or []
    actions = r.get("actions") or []
    matches_target = any(
        (t.get("target") == "url"
         and (t.get("constraint") or {}).get("value") == target)
        for t in targets
    )
    matches_action = any(
        (a.get("id") == "cache_level" and a.get("value") == "bypass")
        for a in actions
    )
    if matches_target and matches_action and r.get("status") == "active":
        print(r.get("id")); raise SystemExit(0)
PY
)"

if [[ -n "$match_id" ]]; then
    ok "page rule already covers ${target_pattern} with cache bypass (id=${match_id})"
else
    log "creating page rule: ${target_pattern} → cache_level=bypass"
    payload=$(cat <<JSON
{
  "targets": [{
    "target": "url",
    "constraint": { "operator": "matches", "value": "${target_pattern}" }
  }],
  "actions": [{ "id": "cache_level", "value": "bypass" }],
  "priority": 1,
  "status": "active"
}
JSON
)
    create_resp="$(cf POST "/zones/${CF_ZONE_ID}/pagerules" --data "$payload")"
    if [[ "$(cf_success "$create_resp")" == "true" ]]; then
        new_id="$(printf '%s' "$create_resp" | python3 -c 'import sys,json;d=json.load(sys.stdin);print((d.get("result") or {}).get("id",""))')"
        ok "page rule created (id=${new_id})"
    else
        err "FAILED to create page rule: $(cf_first_error "$create_resp")"
        exit 1
    fi
fi

# --- Final verification --------------------------------------------------
log "final verification — listing page rules"
final_resp="$(cf GET "/zones/${CF_ZONE_ID}/pagerules?per_page=50")"
CF_JSON="$final_resp" CF_TARGET="$target_pattern" python3 <<'PY'
import json, os
d = json.loads(os.environ["CF_JSON"])
target = os.environ["CF_TARGET"]
rules = d.get("result") or []
print(f"  Total page rules in zone: {len(rules)}")
for r in rules:
    targets = r.get("targets") or []
    actions = r.get("actions") or []
    target_value = (targets[0].get("constraint") or {}).get("value", "?") if targets else "?"
    action_summary = ", ".join(f"{a.get('id')}={a.get('value')}" for a in actions)
    marker = "<-- ours" if target_value == target else ""
    print(f"  [{r.get('status')}] {target_value:40s} {action_summary} {marker}")
PY

hr
ok "Done. Cache for ${CDN_SUB} now bypassed via Page Rule."
echo "    Note: this is the legacy Page Rules engine. Cloudflare's newer"
echo "    Cache Rules engine produces the same effect but requires the"
echo "    Zone Cache Rules:Edit scope (which this token doesn't have)."
hr

#!/usr/bin/env bash
# Self-contained Cloudflare automation:
#   1. Use a BOOTSTRAP token to MINT a narrowly-scoped child token.
#   2. Use the child token to APPLY the zone state (calls 41-cloudflare-apply.sh).
#   3. REVOKE the child token, regardless of whether apply succeeded.
#
# Required scopes on the bootstrap token (set via CF_BOOTSTRAP_TOKEN):
#   * User → API Tokens → Edit
#   * User → User Details → Read       (so we can call /user)
#   * Account → Account Settings → Read (to enumerate accounts for scope)
#   * Zone → Zone → Read (recommended, to validate zone before minting)
#
# The minted child token is granted ONLY:
#   * Zone Settings:Edit on the target zone
#   * DNS:Edit on the target zone
#   * Cache Rules:Edit on the target zone
# It exists for at most a few minutes and is destroyed at the end.
#
# This script never writes the bootstrap or child token to disk.
set -euo pipefail
. "$(dirname "$0")/../lib/common.sh"
load_config

section "MINT → APPLY → REVOKE — Cloudflare self-cleaning automation"

BOOT="${CF_BOOTSTRAP_TOKEN:-}"
if [[ -z "$BOOT" ]]; then
    die "CF_BOOTSTRAP_TOKEN is empty. Set it (env or config.env) to a token with User:API Tokens:Edit scope."
fi

confirm="${CF_APPLY_CONFIRM:-}"
if [[ "$confirm" != "YES" ]]; then
    warn "CF_APPLY_CONFIRM is not YES — refusing to mutate the zone (dry mode)."
    warn "Set CF_APPLY_CONFIRM=YES to allow apply."
    exit 0
fi

require_cmd curl python3

cf_with() {
    local tok="$1"; shift
    local method="$1"; shift
    local path="$1"; shift
    curl -sS -X "$method" "https://api.cloudflare.com/client/v4${path}" \
        -H "Authorization: Bearer ${tok}" \
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

# --- 1. Sanity-check the bootstrap token --------------------------------
log "verifying bootstrap token..."
boot_resp="$(cf_with "$BOOT" GET /user/tokens/verify)"
[[ "$(cf_success "$boot_resp")" == "true" ]] || die "bootstrap token failed verify: $boot_resp"
ok "bootstrap token valid"

# --- 2. Resolve zone id --------------------------------------------------
zone_resp="$(cf_with "$BOOT" GET "/zones?name=${DOMAIN}")"
ZONE_ID="$(printf '%s' "$zone_resp" | python3 -c 'import sys,json;d=json.load(sys.stdin);r=d.get("result") or [];print(r[0]["id"] if r else "")')"
[[ -n "$ZONE_ID" ]] || die "could not resolve zone id for ${DOMAIN} with bootstrap token"
ok "zone id: ${ZONE_ID}"

# --- 3. Discover Permission Group IDs we need ---------------------------
# CF API requires real PG ids inside the policy.
log "fetching permission groups..."
pg_resp="$(cf_with "$BOOT" GET "/user/tokens/permission_groups")"
[[ "$(cf_success "$pg_resp")" == "true" ]] || die "cannot list permission groups (token needs API Tokens:Read or scope upgrade)"

PG_IDS="$(CF_JSON="$pg_resp" python3 <<'PY'
import json, os
d = json.loads(os.environ["CF_JSON"])
wanted = {
    "Zone Settings Write": None,
    "DNS Write":           None,
    "Cache Rules Write":   None,
}
for pg in d.get("result") or []:
    name = pg.get("name","")
    if name in wanted and wanted[name] is None:
        wanted[name] = pg.get("id")
missing = [k for k,v in wanted.items() if v is None]
if missing:
    print("ERR=missing PGs: " + ", ".join(missing))
else:
    print(f'OK={wanted["Zone Settings Write"]}|{wanted["DNS Write"]}|{wanted["Cache Rules Write"]}')
PY
)"
case "$PG_IDS" in
    OK=*) IFS='|' read -r PG_SETTINGS PG_DNS PG_CACHE <<<"${PG_IDS#OK=}"
          ok "PGs: settings=${PG_SETTINGS} dns=${PG_DNS} cache=${PG_CACHE}" ;;
    ERR=*) die "${PG_IDS#ERR=}" ;;
esac

# --- 4. Mint child token -------------------------------------------------
TOKEN_NAME="dreammaker-cf-edge-fix-$(date -u +%Y%m%dT%H%M%SZ)"
log "minting child token: ${TOKEN_NAME}"
mint_payload="$(PG_S="$PG_SETTINGS" PG_D="$PG_DNS" PG_C="$PG_CACHE" Z="$ZONE_ID" NAME="$TOKEN_NAME" python3 <<'PY'
import json, os, datetime
ttl_minutes = 15
not_before = datetime.datetime.now(datetime.UTC).replace(microsecond=0)
not_after  = not_before + datetime.timedelta(minutes=ttl_minutes)
print(json.dumps({
    "name": os.environ["NAME"],
    "policies": [{
        "effect": "allow",
        "resources": {f"com.cloudflare.api.account.zone.{os.environ['Z']}": "*"},
        "permission_groups": [
            {"id": os.environ["PG_S"]},
            {"id": os.environ["PG_D"]},
            {"id": os.environ["PG_C"]},
        ],
    }],
    "not_before": not_before.strftime("%Y-%m-%dT%H:%M:%SZ"),
    "expires_on": not_after.strftime("%Y-%m-%dT%H:%M:%SZ"),
}))
PY
)"

mint_resp="$(cf_with "$BOOT" POST "/user/tokens" --data "$mint_payload")"
if [[ "$(cf_success "$mint_resp")" != "true" ]]; then
    err "mint failed:"
    printf '%s\n' "$mint_resp" >&2
    exit 1
fi

CHILD_ID="$(printf '%s' "$mint_resp" | python3 -c 'import sys,json;d=json.load(sys.stdin);print((d.get("result") or {}).get("id",""))')"
CHILD_VAL="$(printf '%s' "$mint_resp" | python3 -c 'import sys,json;d=json.load(sys.stdin);print((d.get("result") or {}).get("value",""))')"
[[ -n "$CHILD_ID" && -n "$CHILD_VAL" ]] || die "mint succeeded but no token returned"
ok "child token minted (id=${CHILD_ID}, expires in ~15 min)"

# --- 5. Always-revoke trap ----------------------------------------------
revoke_child() {
    if [[ -z "${CHILD_ID:-}" ]]; then return 0; fi
    log "revoking child token (${CHILD_ID})..."
    rev_resp="$(cf_with "$BOOT" DELETE "/user/tokens/${CHILD_ID}" || true)"
    if [[ "$(cf_success "$rev_resp")" == "true" ]]; then
        ok "child token revoked"
    else
        warn "revoke API returned non-success: $rev_resp"
        warn "Token will still expire automatically in ~15 minutes."
    fi
    unset CHILD_VAL
}
trap revoke_child EXIT

# --- 6. Run apply with the child token ----------------------------------
section "Applying with minted child token"
# Hand off to the regular applier via env. Subprocess inherits env but
# scripts/41-cloudflare-apply.sh sources config.env with `set -a`, so
# explicitly export to win precedence.
export CF_API_TOKEN="$CHILD_VAL"
export CF_ZONE_ID="$ZONE_ID"
export CF_APPLY_CONFIRM="YES"
if bash "$(dirname "$0")/41-cloudflare-apply.sh"; then
    ok "apply pipeline succeeded"
    apply_rc=0
else
    apply_rc=$?
    warn "apply pipeline exited with code ${apply_rc} — see logs above"
fi

# --- 7. Final read-only verification ------------------------------------
section "Post-apply read-only verification"
bash "$(dirname "$0")/40-cloudflare.sh" || true

# trap will revoke
exit "$apply_rc"

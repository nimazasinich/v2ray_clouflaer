#!/usr/bin/env bash
# task2-clean-domain-fix.sh
set -euo pipefail

if [[ -t 1 ]]; then
  RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RESET=$'\033[0m'
else
  RED=""; GREEN=""; YELLOW=""; RESET=""
fi
ok()   { echo "${GREEN}OK${RESET} $*"; }
warn() { echo "${YELLOW}WARN${RESET} $*"; }
err()  { echo "${RED}ERR${RESET} $*" >&2; }
die()  { err "$*"; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }
need curl
need sed
need grep

ENV_FILE="/root/.env"
[[ -f "$ENV_FILE" ]] || die "Missing $ENV_FILE"
# shellcheck disable=SC1090
source "$ENV_FILE"

: "${CF_TOKEN_FULL:?Missing CF_TOKEN_FULL in /root/.env}"
: "${CF_ZONE_ID:?Missing CF_ZONE_ID in /root/.env}"
: "${CF_ACCOUNT_ID:?Missing CF_ACCOUNT_ID in /root/.env}"
: "${CLEAN_SUBDOMAIN:?Missing CLEAN_SUBDOMAIN in /root/.env (e.g. clean.dreammaker-groupsoft.ir)}"

CF_API="https://api.cloudflare.com/client/v4"
AUTH_HEADER=("Authorization: Bearer ${CF_TOKEN_FULL}")
JSON_HEADER=("Content-Type: application/json")

cf_get() {
  local path="$1"
  curl -fsS "${CF_API}${path}" -H "${AUTH_HEADER[@]}"
}

cf_post() {
  local path="$1" data="$2"
  curl -fsS -X POST "${CF_API}${path}" -H "${AUTH_HEADER[@]}" -H "${JSON_HEADER[@]}" --data "$data"
}

json_first() {
  local re="$1"
  sed -nE "s/${re}/\\1/p" | head -n 1
}

ok "DreamMaker Task2: Fix clean domain 403 via Cloudflare"

TARGET_WORKER="dreammaker-tier0"
HOST="${CLEAN_SUBDOMAIN}"

ok "Verifying worker script exists in account."
scripts_json="$(cf_get "/accounts/${CF_ACCOUNT_ID}/workers/scripts")" || die "Failed to list Worker scripts"
if ! echo "$scripts_json" | grep -Fq "\"id\":\"${TARGET_WORKER}\""; then
  die "Worker script '${TARGET_WORKER}' not found in account ${CF_ACCOUNT_ID}"
fi
ok "Found Worker script: ${TARGET_WORKER}"

ok "Ensuring DNS record exists for clean subdomain (A -> 82.115.26.105, proxied)."
dns_list="$(cf_get "/zones/${CF_ZONE_ID}/dns_records?name=${HOST}")" || die "Failed to list DNS records"

existing_id="$(echo "$dns_list" | json_first '.*"id":"([^"]+)".*')"
existing_type="$(echo "$dns_list" | json_first '.*"type":"([^"]+)".*')"

desired_ip="82.115.26.105"
dns_payload="$(printf '{\"type\":\"A\",\"name\":\"clean\",\"content\":\"%s\",\"proxied\":true}' \"$desired_ip\")"

if [[ -z "${existing_id:-}" ]]; then
  ok "Creating DNS record for clean."
  cf_post "/zones/${CF_ZONE_ID}/dns_records" "$dns_payload" >/dev/null || die "Failed to create DNS record"
  ok "DNS record created."
else
  if [[ "${existing_type:-}" != "A" ]]; then
    warn "Existing DNS record for ${HOST} is type '${existing_type}'. Not modifying automatically."
  else
    ok "DNS record exists for ${HOST} (id=${existing_id}). Leaving as-is."
  fi
fi

ok "Listing existing Worker routes for zone."
routes_json="$(cf_get "/zones/${CF_ZONE_ID}/workers/routes")" || die "Failed to list worker routes"

route_pattern_exists() {
  local pattern="$1"
  echo "$routes_json" | grep -Fq "\"pattern\":\"${pattern}\""
}

route_pattern_points_to_target() {
  local pattern="$1"
  echo "$routes_json" | sed -n "/\"pattern\":\"${pattern//\//\\/}\"/,/}/p" | grep -Fq "\"script\":\"${TARGET_WORKER}\""
}

create_route() {
  local pattern="$1"
  local payload; payload="$(printf '{\"pattern\":\"%s\",\"script\":\"%s\"}' \"$pattern\" \"$TARGET_WORKER\")"
  cf_post "/zones/${CF_ZONE_ID}/workers/routes" "$payload" >/dev/null
}

PATTERNS=(
  "${HOST}/health"
  "${HOST}/ping"
  "${HOST}/sub*"
)

changed=0
for pat in "${PATTERNS[@]}"; do
  if route_pattern_exists "$pat"; then
    if route_pattern_points_to_target "$pat"; then
      ok "Route already correct: ${pat} -> ${TARGET_WORKER}"
    else
      warn "Route pattern exists but points elsewhere: ${pat}"
      warn "Resolve this conflict in Cloudflare (delete/adjust), then rerun."
      exit 1
    fi
  else
    ok "Creating route: ${pat} -> ${TARGET_WORKER}"
    create_route "$pat" || die "Failed to create route: ${pat}"
    changed=1
  fi
done

if [[ "$changed" -eq 0 ]]; then
  ok "No route changes needed (idempotent)."
else
  ok "Routes created/updated."
fi

echo
ok "Post-change test:"
echo "curl -skI \"https://${HOST}/health\" | head -n 20"
warn "If still 403 with 'server: cloudflare', check zone WAF/security events for that hostname."

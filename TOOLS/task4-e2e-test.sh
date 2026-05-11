#!/usr/bin/env bash
# task4-e2e-test.sh
set -euo pipefail

if [[ -t 1 ]]; then
  RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RESET=$'\033[0m'
else
  RED=""; GREEN=""; YELLOW=""; RESET=""
fi
pass() { echo "${GREEN}PASS${RESET} $*"; }
fail() { echo "${RED}FAIL${RESET} $*"; }
warn() { echo "${YELLOW}WARN${RESET} $*"; }

need() { command -v "$1" >/dev/null 2>&1 || { echo "ERR missing $1" >&2; exit 1; }; }
need curl

if [[ -f /root/.env ]]; then
  # shellcheck disable=SC1090
  source /root/.env
fi

MAIN_DOMAIN="${DOMAIN:-dreammaker-groupsoft.ir}"
CDN_DOMAIN="${CDN_SUBDOMAIN:-cdn.dreammaker-groupsoft.ir}"
CLEAN_DOMAIN="${CLEAN_SUBDOMAIN:-clean.dreammaker-groupsoft.ir}"

XHTTP_PATHS=(/api/v1/ping /cdn/init /app/sync /api/v2/feed /static/bundle.js /media/stream /v2/content/live)
WS_SUFFIX="-ws"

curl_code() {
  local url="$1"; shift
  curl -sk -o /dev/null -w "%{http_code}" "$@" "$url" || echo "000"
}

curl_head_code() {
  local url="$1"; shift
  curl -skI -o /dev/null -w "%{http_code}" "$@" "$url" || echo "000"
}

not_404_rule() {
  local label="$1" code="$2"
  if [[ "$code" == "404" || "$code" == "000" ]]; then
    fail "${label} -> ${code} (must NOT be 404/000)"
    return 1
  fi
  pass "${label} -> ${code}"
  return 0
}

expect_200_rule() {
  local label="$1" code="$2"
  if [[ "$code" == "200" ]]; then
    pass "${label} -> 200"
    return 0
  fi
  fail "${label} -> ${code} (expected 200)"
  return 1
}

TOTAL=0
FAILED=0

run_check() {
  local mode="$1" label="$2" code="$3"
  TOTAL=$((TOTAL+1))
  if [[ "$mode" == "expect200" ]]; then
    if ! expect_200_rule "$label" "$code"; then FAILED=$((FAILED+1)); fi
  else
    if ! not_404_rule "$label" "$code"; then FAILED=$((FAILED+1)); fi
  fi
}

echo "=== DreamMaker E2E Matrix ==="
echo "Main:  ${MAIN_DOMAIN}"
echo "CDN:   ${CDN_DOMAIN}"
echo "Clean: ${CLEAN_DOMAIN}"
echo

echo "=== Local bypass (bypass Cloudflare, hits Nginx on 127.0.0.1:443) ==="
RESOLVE_FLAG=(--resolve "${MAIN_DOMAIN}:443:127.0.0.1")
for p in "${XHTTP_PATHS[@]}"; do
  code="$(curl_code "https://${MAIN_DOMAIN}${p}" "${RESOLVE_FLAG[@]}" --max-time 6)"
  run_check "not404" "LOCAL ${p}" "$code"
done
for p in "${XHTTP_PATHS[@]}"; do
  code="$(curl_code "https://${MAIN_DOMAIN}${p}${WS_SUFFIX}" "${RESOLVE_FLAG[@]}" --max-time 6 --http1.1 \
    -H "Connection: Upgrade" -H "Upgrade: websocket" \
    -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: SGVsbG9Xb3JsZA==")"
  run_check "not404" "LOCAL ${p}${WS_SUFFIX}" "$code"
done
echo

echo "=== Via Cloudflare (public HTTPS) ==="
for host in "$MAIN_DOMAIN" "$CDN_DOMAIN"; do
  for p in /health /ping; do
    code="$(curl_head_code "https://${host}${p}" --max-time 8)"
    run_check "expect200" "CF ${host}${p}" "$code"
  done
done

for host in "$MAIN_DOMAIN" "$CDN_DOMAIN"; do
  for p in "${XHTTP_PATHS[@]}"; do
    code="$(curl_head_code "https://${host}${p}" --max-time 8)"
    run_check "not404" "CF ${host}${p}" "$code"
  done
done
echo

echo "=== Clean domain ==="
code="$(curl_head_code "https://${CLEAN_DOMAIN}/health" --max-time 8)"
run_check "expect200" "CLEAN https://${CLEAN_DOMAIN}/health" "$code"
echo

echo "=== Summary ==="
echo "Total checks: ${TOTAL}"
echo "Failed: ${FAILED}"

if [[ "$FAILED" -eq 0 ]]; then
  pass "All checks passed."
else
  fail "Some checks failed."
  warn "Key signal for Task1: LOCAL XHTTP paths must stop returning 404."
  warn "Key signal for Task2: CLEAN /health must be 200 (not 403)."
fi

[[ "$FAILED" -eq 0 ]]

#!/usr/bin/env bash
# task1-nginx-fix.sh
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

need nginx
need curl
need awk
need sed
need grep
need date

CONF="/etc/nginx/conf.d/dreammaker.conf"
DEFAULT_SITE="/etc/nginx/sites-enabled/default"

DOMAIN_PRIMARY="dreammaker-groupsoft.ir"
SERVER_NAMES=(
  "dreammaker-groupsoft.ir"
  "cdn.dreammaker-groupsoft.ir"
  "clean.dreammaker-groupsoft.ir"
  "panel.dreammaker-groupsoft.ir"
)

XHTTP_PATHS=(/api/v1/ping /cdn/init /app/sync /api/v2/feed /static/bundle.js /media/stream /v2/content/live)
WS_SUFFIX="-ws"
BASE_PORT=11001

backup_file() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  local ts; ts="$(date +%Y%m%d-%H%M%S)"
  local bak="${f}.bak.${ts}"
  cp -a "$f" "$bak"
  ok "Backed up $f -> $bak"
}

nginx_dump() { nginx -T 2>&1; }

conf_is_included() { nginx_dump | grep -Fq "$CONF"; }

loaded_has_location() {
  local out; out="$(nginx_dump)"
  local p
  for p in "${XHTTP_PATHS[@]}"; do
    if echo "$out" | grep -Eq "location[[:space:]]+${p//\//\\/}[[:space:]]*\\{" ; then
      return 0
    fi
  done
  return 1
}

find_ssl_pair() {
  # Prefer what's already present, else default LE paths.
  local cert="" key=""
  if [[ -f "$CONF" ]]; then
    cert="$(awk '$1=="ssl_certificate" {gsub(/;/,"",$2); print $2; exit}' "$CONF" 2>/dev/null || true)"
    key="$(awk '$1=="ssl_certificate_key" {gsub(/;/,"",$2); print $2; exit}' "$CONF" 2>/dev/null || true)"
  fi
  if [[ -z "${cert:-}" || -z "${key:-}" ]]; then
    cert="/etc/letsencrypt/live/${DOMAIN_PRIMARY}/fullchain.pem"
    key="/etc/letsencrypt/live/${DOMAIN_PRIMARY}/privkey.pem"
  fi
  [[ -f "$cert" ]] || die "ssl_certificate not found: $cert"
  [[ -f "$key"  ]] || die "ssl_certificate_key not found: $key"
  echo "${cert}|${key}"
}

write_conf() {
  local cert="$1" key="$2"
  local sn; sn="$(printf "%s " "${SERVER_NAMES[@]}")"; sn="${sn% }"
  local tmp; tmp="$(mktemp)"

  cat >"$tmp" <<EOF
# Managed by task1-nginx-fix.sh

server {
    listen 80;
    listen [::]:80;
    server_name ${sn};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${sn};

    ssl_certificate ${cert};
    ssl_certificate_key ${key};

    # Minimal safe defaults for proxying XHTTP/WS to localhost
    proxy_buffering off;
    proxy_request_buffering off;

    # Default: keep behavior explicit
    location = / { return 200 "ok\n"; add_header Content-Type text/plain; }

EOF

  local i p port
  for i in "${!XHTTP_PATHS[@]}"; do
    p="${XHTTP_PATHS[$i]}"
    port=$((BASE_PORT + i))
    cat >>"$tmp" <<EOF
    # XHTTP -> local Xray ${port}
    location ${p} {
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Connection "";
        proxy_read_timeout 310s;
        proxy_send_timeout 310s;
        proxy_pass http://127.0.0.1:${port};
    }

    # WebSocket fallback -> same port (client may use WS)
    location ${p}${WS_SUFFIX} {
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 310s;
        proxy_send_timeout 310s;
        proxy_pass http://127.0.0.1:${port};
    }

EOF
  done

  cat >>"$tmp" <<'EOF'
    location / {
        return 444;
    }
}
EOF

  backup_file "$CONF"
  install -m 0644 "$tmp" "$CONF"
  rm -f "$tmp"
  ok "Wrote $CONF"
}

curl_code() {
  local url="$1"; shift
  curl -sk -o /dev/null -w "%{http_code}" "$@" "$url" || echo "000"
}

test_local_bypass() {
  ok "Testing local bypass (must NOT be 404; 502 acceptable)."
  local base="https://${DOMAIN_PRIMARY}"
  local rflag=(--resolve "${DOMAIN_PRIMARY}:443:127.0.0.1")
  local failures=0
  local p code

  for p in "${XHTTP_PATHS[@]}"; do
    code="$(curl_code "${base}${p}" "${rflag[@]}")"
    if [[ "$code" == "404" || "$code" == "000" ]]; then
      err "LOCAL ${p} -> ${code}"
      failures=$((failures+1))
    else
      ok "LOCAL ${p} -> ${code}"
    fi
  done

  for p in "${XHTTP_PATHS[@]}"; do
    code="$(curl_code "${base}${p}${WS_SUFFIX}" "${rflag[@]}" --http1.1 \
      -H "Connection: Upgrade" -H "Upgrade: websocket" \
      -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: SGVsbG9Xb3JsZA==")"
    if [[ "$code" == "404" || "$code" == "000" ]]; then
      err "LOCAL ${p}${WS_SUFFIX} -> ${code}"
      failures=$((failures+1))
    else
      ok "LOCAL ${p}${WS_SUFFIX} -> ${code}"
    fi
  done

  if [[ "$failures" -gt 0 ]]; then
    warn "Some endpoints still failing. If they are 404, Nginx is still not matching locations."
    return 1
  fi
  ok "All local bypass endpoints returned non-404."
}

ok "DreamMaker Task1: Fix Nginx 404 on XHTTP paths"

ok "Checking for competing default site."
if [[ -f "$DEFAULT_SITE" ]]; then
  ts="$(date +%Y%m%d-%H%M%S)"
  mv "$DEFAULT_SITE" "${DEFAULT_SITE}.disabled.${ts}" || die "Failed to disable $DEFAULT_SITE"
  ok "Disabled $DEFAULT_SITE"
else
  ok "No $DEFAULT_SITE present."
fi

ok "Checking whether $CONF is included and locations are loaded."
if conf_is_included; then
  ok "$CONF appears in nginx -T."
else
  warn "$CONF not found in nginx -T output. Nginx may not include conf.d/*.conf."
fi

if loaded_has_location; then
  ok "Required location blocks are present in loaded config."
else
  warn "Required location blocks not found in loaded config. Rewriting $CONF."
  ssl_pair="$(find_ssl_pair)"
  SSL_CERT="${ssl_pair%%|*}"
  SSL_KEY="${ssl_pair##*|*}"
  write_conf "$SSL_CERT" "$SSL_KEY"
fi

ok "Validating Nginx config."
nginx -t >/dev/null 2>&1 || die "nginx -t failed. Run: nginx -T"
ok "nginx -t succeeded."

ok "Reloading Nginx."
nginx -s reload >/dev/null 2>&1 || die "nginx reload failed."
ok "nginx reload succeeded."

test_local_bypass
ok "Done."

#!/usr/bin/env bash
# v2rayN base64 subscription file for Nginx to serve at /sub (or custom path).
#
# Reads VLESS one-liners from URILIST, writes a single file:
#   ${WEBROOT}/${SUB_BASENAME}
# whose content is: base64( "uri1\nuri2\n..." ) on one line (v2rayN sub format).
#
# Nginx: add to your port-443 server for the same domain as the CDN, e.g.:
#   include /etc/nginx/snippets/cleanip-subscription.conf;
# or see scripts/cleanip/nginx-cleanip-subscription.conf.example
#
# Idempotent. No tokens. env: URILIST, WEBROOT, SUB_BASENAME, DOMAIN, WRITE_NGINX_SNIP, NGINX_SNIPPET_PATH

set -euo pipefail

: "${URILIST:=/root/FINAL-CONFIGS-CLEANIP.txt}"
: "${WEBROOT:=/var/www/cleanip-subscription}"
: "${SUB_BASENAME:=sub}"
: "${DOMAIN:=}"
: "${NGINX_SNIPPET_PATH:=/etc/nginx/snippets/cleanip-subscription.conf}"
: "${WRITE_NGINX_SNIP:=0}"

if ! [[ -f "$URILIST" && -s "$URILIST" ]]; then
  echo "error: missing or empty $URILIST" >&2
  exit 1
fi

SUB_TMP="$(mktemp)"
B64_TMP="$(mktemp)"
trap 'rm -f "$SUB_TMP" "$B64_TMP"' EXIT

awk '/^[[:space:]]*vless:\/\// { gsub(/^[[:space:]]+|[[:space:]]+$/,""); if (length) print }' \
  "$URILIST" > "$SUB_TMP"

if [[ ! -s "$SUB_TMP" ]]; then
  echo "error: no vless:// lines in $URILIST" >&2
  exit 1
fi

if base64 -w0 < "$SUB_TMP" > "$B64_TMP" 2>/dev/null; then
  : ok
else
  openssl base64 -A -in "$SUB_TMP" -out "$B64_TMP" 2>/dev/null
fi
if [[ ! -s "$B64_TMP" ]]; then
  echo "error: base64 encode failed" >&2
  exit 1
fi

if [[ ! -d "$WEBROOT" ]]; then
  if ! mkdir -p -m 0755 "$WEBROOT" 2>/dev/null; then
    echo "error: cannot create $WEBROOT (run as root) or set WEBROOT" >&2
    exit 1
  fi
fi
OUT_PATH="${WEBROOT}/${SUB_BASENAME}"
install -m 0644 "$B64_TMP" "$OUT_PATH"
echo "Wrote $OUT_PATH" >&2

if [[ "${WRITE_NGINX_SNIP}" = "1" && "${EUID:-0}" = "0" ]]; then
  D="${DOMAIN:-<cdn-fqdn>}"
  if ! [[ -f "$NGINX_SNIPPET_PATH" ]]; then
    mkdir -p -m 0755 "$(dirname "$NGINX_SNIPPET_PATH")"
    umask 022
    cat > "$NGINX_SNIPPET_PATH" <<EOF
# v2rayN: https://${D}/sub
location = /${SUB_BASENAME} {
  default_type text/plain;
  charset utf-8;
  add_header X-Content-Type-Options nosniff;
  add_header Content-Disposition inline;
  alias ${OUT_PATH};
}
EOF
    echo "Wrote $NGINX_SNIPPET_PATH — add 'include $NGINX_SNIPPET_PATH;' in server { }" >&2
  else
    echo "Note: $NGINX_SNIPPET_PATH exists; not overwritten" >&2
  fi
  echo "Run: nginx -t && systemctl reload nginx" >&2
fi

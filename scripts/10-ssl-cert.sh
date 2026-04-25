#!/usr/bin/env bash
# Ensure a Let's Encrypt certificate exists covering both DOMAIN and CDN_SUB.
# Idempotent: skips work if cert is already present.
set -euo pipefail
. "$(dirname "$0")/../lib/common.sh"
load_config
require_root

section "SSL cert for ${DOMAIN} + ${CDN_SUB}"

if [[ -f "${LE_LIVE_DIR}/fullchain.pem" && -f "${LE_LIVE_DIR}/privkey.pem" ]]; then
    ok "cert already exists at ${LE_LIVE_DIR}"
    # Verify both names are covered.
    if command -v openssl >/dev/null 2>&1; then
        if openssl x509 -in "${LE_LIVE_DIR}/fullchain.pem" -noout -text 2>/dev/null \
           | grep -q "${CDN_SUB}"; then
            ok "cert already covers ${CDN_SUB}"
            exit 0
        else
            warn "cert does not cover ${CDN_SUB}; re-issuing with --expand"
        fi
    else
        exit 0
    fi
fi

if ! command -v certbot >/dev/null 2>&1; then
    log "installing certbot..."
    apt-get update -qq
    apt-get install -y certbot python3-certbot-nginx -qq
fi

log "requesting certificate via certbot --nginx ..."
if ! certbot certonly --nginx \
        -d "${DOMAIN}" -d "${CDN_SUB}" \
        --non-interactive --agree-tos --expand \
        -m "${ADMIN_EMAIL}"; then
    warn "certbot --nginx failed; retrying with --standalone (nginx will be paused)"
    systemctl stop nginx || true
    certbot certonly --standalone \
        -d "${DOMAIN}" -d "${CDN_SUB}" \
        --non-interactive --agree-tos --expand \
        -m "${ADMIN_EMAIL}"
    systemctl start nginx || true
fi

ok "certificate ready at ${LE_LIVE_DIR}"

#!/usr/bin/env bash
# Expand the Let's Encrypt certificate at LE_LIVE_DIR so its SAN list
# covers BOTH the apex DOMAIN and the CDN_SUB. Without this, every
# Cloudflare-fronted endpoint (WSS:2083, gRPC:2053, port 443 via /cdn)
# returns HTTP 525 because CF cannot TLS-handshake the origin.
#
# Idempotent: if both names are already in the cert SAN list this is a
# no-op. Otherwise it re-issues with --expand. Falls back to --standalone
# if certbot's nginx plugin can't bind :80.
#
# Always reloads nginx after a successful expansion so the new cert is
# served immediately. Probes Cloudflare-fronted endpoints before AND
# after to make the impact visible in the run log.
set -euo pipefail
. "$(dirname "$0")/../lib/common.sh"
load_config
require_root

section "Expand LE cert: ${DOMAIN} + ${CDN_SUB}"

require_cmd openssl

cert_covers() {
    local cert="$1" name="$2"
    [[ -f "$cert" ]] || return 1
    openssl x509 -in "$cert" -noout -text 2>/dev/null \
        | grep -A1 "Subject Alternative Name" \
        | grep -qE "DNS:${name}([[:space:],]|$)"
}

probe_pre_post() {
    local label="$1"
    log "[$label] HTTPS probes (expect 525 before, non-525 after if CF cert path was the only issue):"
    for ep in \
        "https://${CDN_SUB}/cdn|cdn /cdn" \
        "https://${CDN_SUB}:2083/|cdn:2083 /" \
        "https://${CDN_SUB}:2053/${GRPC_SERVICE_NAME:-dreammaker-grpc}|cdn:2053 grpc"; do
        url="${ep%|*}"; tag="${ep#*|}"
        code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 7 "$url" || echo "000")
        printf "    %-25s %s -> HTTP %s\n" "$tag" "$url" "$code"
    done
}

cert_path="${LE_LIVE_DIR}/fullchain.pem"
need_expand="false"

if [[ -f "$cert_path" ]]; then
    log "current SAN list:"
    openssl x509 -in "$cert_path" -noout -ext subjectAltName 2>/dev/null \
        | grep -E "DNS:" | sed 's/^/    /'
    if cert_covers "$cert_path" "$DOMAIN" && cert_covers "$cert_path" "$CDN_SUB"; then
        ok "cert already covers both ${DOMAIN} and ${CDN_SUB}"
    else
        warn "cert is missing one of the SANs we need"
        need_expand="true"
    fi
else
    warn "no existing cert at ${cert_path}"
    need_expand="true"
fi

if [[ "$need_expand" != "true" ]]; then
    log "skipping certbot run; running probes for visibility"
    probe_pre_post "post"
    systemctl reload nginx 2>/dev/null || true
    exit 0
fi

probe_pre_post "before"

if ! command -v certbot >/dev/null 2>&1; then
    log "installing certbot..."
    apt-get update -qq
    apt-get install -y certbot python3-certbot-nginx -qq
fi

attempt_certbot_nginx() {
    log "attempting: certbot certonly --nginx --expand -d ${DOMAIN} -d ${CDN_SUB}"
    certbot certonly --nginx \
        -d "${DOMAIN}" -d "${CDN_SUB}" \
        --non-interactive --agree-tos --expand \
        -m "${ADMIN_EMAIL}"
}

attempt_certbot_standalone() {
    log "stopping nginx so certbot can bind :80 in standalone mode"
    systemctl stop nginx || true
    log "attempting: certbot certonly --standalone --expand -d ${DOMAIN} -d ${CDN_SUB}"
    certbot certonly --standalone \
        -d "${DOMAIN}" -d "${CDN_SUB}" \
        --non-interactive --agree-tos --expand \
        -m "${ADMIN_EMAIL}"
    log "starting nginx back up"
    systemctl start nginx || true
}

if ! attempt_certbot_nginx; then
    warn "nginx-plugin route failed; falling back to standalone"
    attempt_certbot_standalone
fi

# Re-validate.
if cert_covers "$cert_path" "$DOMAIN" && cert_covers "$cert_path" "$CDN_SUB"; then
    ok "cert now covers both ${DOMAIN} and ${CDN_SUB}"
else
    err "certbot completed but the new cert still does not cover both names"
    openssl x509 -in "$cert_path" -noout -ext subjectAltName 2>/dev/null | sed 's/^/    /'
    exit 1
fi

# Reload nginx (and xray, since trojan/xhttp inbounds reference the cert).
systemctl reload nginx
ok "nginx reloaded"
if systemctl is-active --quiet xray; then
    systemctl restart xray
    ok "xray restarted (trojan/xhttp inbounds re-read cert)"
fi

probe_pre_post "after"

hr
ok "Done. If CDN-fronted endpoints still return non-101 codes, check:"
echo "    - Cloudflare SSL/TLS mode = Full (or Full (strict))"
echo "    - Cloudflare cache rule: Bypass for host=${CDN_SUB}"
echo "    - Origin cert chain validates (run: openssl s_client -connect ${SERVER_IP}:443 -servername ${CDN_SUB} -showcerts)"
hr

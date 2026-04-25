#!/usr/bin/env bash
# STEP 5 — Generate new vless:// links for the WSS+gRPC CDN inbounds and
# APPEND them to /root/dreammaker-credentials.txt (never overwrite).
set -euo pipefail
. "$(dirname "$0")/../lib/common.sh"
load_config

section "STEP 5 — generate CDN links and append to ${CREDENTIALS_FILE}"

path_enc="$(urlencode_path "/")"

WSS_LINK="vless://${UUID}@${CDN_SUB}:${WSS_PUBLIC_PORT}?encryption=none&security=tls&sni=${CDN_SUB}&type=ws&path=${path_enc}#DM-CF-WSS-${WSS_PUBLIC_PORT}"
GRPC_LINK="vless://${UUID}@${CDN_SUB}:${GRPC_PUBLIC_PORT}?encryption=none&security=tls&sni=${CDN_SUB}&type=grpc&serviceName=${GRPC_SERVICE_NAME}&mode=gun#DM-CF-gRPC-${GRPC_PUBLIC_PORT}"

stamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# Build the block to append.
block="$(cat <<EOF

# ── NEW CDN LINKS (CF-Edge Fix @ ${stamp}) ─────────────────────────────

## WSS via nginx TLS :${WSS_PUBLIC_PORT}
${WSS_LINK}

## gRPC via nginx TLS :${GRPC_PUBLIC_PORT}
${GRPC_LINK}

EOF
)"

if [[ -f "${CREDENTIALS_FILE}" ]]; then
    if grep -qF "${WSS_LINK}" "${CREDENTIALS_FILE}" \
       && grep -qF "${GRPC_LINK}" "${CREDENTIALS_FILE}"; then
        ok "credentials file already contains both new links — not re-appending"
    else
        backup_file "${CREDENTIALS_FILE}"
        printf "%s\n" "$block" >> "${CREDENTIALS_FILE}"
        ok "appended new CDN links to ${CREDENTIALS_FILE}"
    fi
else
    warn "${CREDENTIALS_FILE} did not exist; creating it"
    printf "%s\n" "$block" > "${CREDENTIALS_FILE}"
    chmod 600 "${CREDENTIALS_FILE}" || true
    ok "created ${CREDENTIALS_FILE}"
fi

echo
echo "WSS  : ${WSS_LINK}"
echo "gRPC : ${GRPC_LINK}"

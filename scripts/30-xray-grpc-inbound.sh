#!/usr/bin/env bash
# STEP 2a — Patch Xray config.json to add a local gRPC CDN inbound on
# 127.0.0.1:${XRAY_GRPC_BACKEND_PORT}. Never touches existing Reality inbounds.
set -euo pipefail
. "$(dirname "$0")/../lib/common.sh"
load_config
require_root

section "STEP 2a — xray gRPC CDN inbound 127.0.0.1:${XRAY_GRPC_BACKEND_PORT}"

[[ -f "${XRAY_CONFIG}" ]] || die "xray config not found: ${XRAY_CONFIG}"
require_cmd python3 xray

# Backup xray config to app tmp/ (safe-file policy).
backup_file "${XRAY_CONFIG}"

python3 - "$XRAY_CONFIG" "$XRAY_GRPC_BACKEND_PORT" "$UUID" "$GRPC_SERVICE_NAME" <<'PY'
import json, sys
cfg_path, port_s, uuid, svc = sys.argv[1:5]
port = int(port_s)
with open(cfg_path) as f:
    cfg = json.load(f)

inbounds = cfg.get("inbounds", [])
tag = f"vless-grpc-cdn-{port}"

existing = None
for ib in inbounds:
    if ib.get("tag") == tag or (
        ib.get("port") == port and ib.get("listen") == "127.0.0.1"
    ):
        existing = ib
        break

new_inbound = {
    "tag": tag,
    "port": port,
    "listen": "127.0.0.1",
    "protocol": "vless",
    "settings": {
        "clients": [{"id": uuid}],
        "decryption": "none",
    },
    "streamSettings": {
        "network": "grpc",
        "security": "none",
        "grpcSettings": {"serviceName": svc, "multiMode": False},
    },
}

ports_used = {ib.get("port") for ib in inbounds if ib is not existing}
if port in ports_used:
    print(f"ERR: port {port} is already in use by another inbound")
    sys.exit(2)

if existing is None:
    inbounds.append(new_inbound)
    print(f"ADDED gRPC CDN inbound on 127.0.0.1:{port}")
else:
    inbounds[inbounds.index(existing)] = new_inbound
    print(f"REFRESHED gRPC CDN inbound on 127.0.0.1:{port}")

cfg["inbounds"] = inbounds
with open(cfg_path, "w") as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
PY

log "validating xray config..."
if ! xray -test -config "${XRAY_CONFIG}"; then
    die "xray config validation failed — check backup in tmp/"
fi

systemctl restart xray
sleep 1
if systemctl is-active --quiet xray; then
    ok "xray restarted and active"
else
    die "xray failed to start after config update"
fi

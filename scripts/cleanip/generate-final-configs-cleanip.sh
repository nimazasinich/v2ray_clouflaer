#!/usr/bin/env bash
# Build /root/FINAL-CONFIGS-CLEANIP.txt from /root/clean-ips.txt (VLESS one-liners).
# For each working CF edge IP, emits two lines: WS+none:80, WS+tls:443.
# Idempotent. No secrets. Env: DOMAIN, UUID, CLEAN_IPS, OUTFILE

set -euo pipefail

: "${DOMAIN:=cdn.dreammaker-groupsoft.ir}"
: "${UUID:=a959df86-fce5-474f-a94c-049e24746713}"
: "${CLEAN_IPS:=/root/clean-ips.txt}"
: "${OUTFILE:=/root/FINAL-CONFIGS-CLEANIP.txt}"

if [[ ! -f "$CLEAN_IPS" ]]; then
  echo "error: missing $CLEAN_IPS (run scan-cf-ws-clean-ips.sh first)" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "error: python3 required" >&2
  exit 1
fi

export DOMAIN UUID
export CLEAN_IPS
OUT_TMP="$(mktemp)"
trap 'rm -f "$OUT_TMP"' EXIT

# shellcheck disable=SC2016
python3 - >"$OUT_TMP" <<'PY'
import os, urllib.parse, ipaddress, sys
from pathlib import Path
domain = os.environ.get("DOMAIN", "")
u = os.environ.get("UUID", "").strip()
f = os.environ.get("CLEAN_IPS", "/root/clean-ips.txt")
lines = []
if not u:
    print("error: empty UUID in env", file=sys.stderr)
    raise SystemExit(1)
for line in Path(f).read_text().splitlines():
    ip = line.split("#", 1)[0].strip()
    if not ip or ip.startswith("#"):
        continue
    try:
        ipaddress.IPv4Address(ip)
    except Exception:
        continue
    p80 = {
        "type": "ws",
        "encryption": "none",
        "security": "none",
        "host": domain,
        "path": "/ws80",
    }
    q1 = urllib.parse.urlencode(p80, quote_via=urllib.parse.quote, safe="")
    name80 = urllib.parse.quote(f"WS80 {ip}", safe="")
    lines.append(
        f"vless://{u}@{ip}:80?{q1}#{name80}"
    )
    p44 = {
        "type": "ws",
        "encryption": "none",
        "security": "tls",
        "sni": domain,
        "host": domain,
        "path": "/ws-vless",
    }
    q2 = urllib.parse.urlencode(p44, quote_via=urllib.parse.quote, safe="")
    name443 = urllib.parse.quote(f"WSTLS443 {ip}", safe="")
    lines.append(
        f"vless://{u}@{ip}:443?{q2}#{name443}"
    )
sys.stdout.write("\n".join(lines) + ("\n" if lines else ""))
PY

if [[ -s "$OUT_TMP" ]]; then
  install -m 0600 "$OUT_TMP" "$OUTFILE"
  n=$(wc -l < "$OUTFILE" | tr -d ' ')
  echo "Wrote $OUTFILE ($n line(s))" >&2
else
  install -m 0600 /dev/null "$OUTFILE" 2>/dev/null || : > "$OUTFILE"
  chmod 600 "$OUTFILE" || true
  echo "warning: no VLESS lines generated; empty $OUTFILE" >&2
fi

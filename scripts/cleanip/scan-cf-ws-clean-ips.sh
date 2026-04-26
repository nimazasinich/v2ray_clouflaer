#!/usr/bin/env bash
# Cloudflare "clean IP" WebSocket prober — run on the German Ubuntu VPS.
# Fetches https://www.cloudflare.com/ips-v4, builds candidate IPv4s, probes
# WebSocket HTTP Upgrade on :80 (path /ws80) and :443 (path /ws-vless) with
# Host: DOMAIN. Writes IPs for which BOTH return HTTP/1.1 101 to /root/clean-ips.txt.
#
# The published CF IPv4 list is CIDRs (often large /14 etc.). It is not feasible to
# test "every" host in a range. This script samples a few host addresses per CIDR
# (SAMPLES_PER_CIDR), current A record(s) of DOMAIN, and optional EXTRA_IPS.
#
# No secrets. Idempotent. Uses curl + python3 + openssl. TLS verify uses the cert
# presented to DOMAIN on that connection (SNI/Host: DOMAIN, connect via --resolve).
#
# env: DOMAIN, CF_IPS_V4_URL, TIMEOUT, CURL, SAMPLES_PER_CIDR, OUTFILE, EXTRA_IPS

set -euo pipefail

: "${DOMAIN:=cdn.dreammaker-groupsoft.ir}"
: "${CF_IPS_V4_URL:=https://www.cloudflare.com/ips-v4}"
: "${TIMEOUT:=5}"
: "${CURL:=curl}"
: "${SAMPLES_PER_CIDR:=3}"
: "${OUTFILE:=/root/clean-ips.txt}"
: "${EXTRA_IPS:=}"

if ! command -v "$CURL" >/dev/null 2>&1; then
  echo "error: $CURL not in PATH" >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "error: python3 required" >&2
  exit 1
fi
if ! command -v openssl >/dev/null 2>&1; then
  echo "error: openssl required (for Sec-WebSocket-Key)" >&2
  exit 1
fi
if ! command -v dig >/dev/null 2>&1; then
  echo "warning: dig not found — install bind9-dnsutils for A-record candidates" >&2
fi

TMP_DIR="${TMP_DIR:-/tmp/cf-ws-probe-$$}"
mkdir -p "$TMP_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT

CF_RAW="$($CURL -sS -m "$TIMEOUT" -L "$CF_IPS_V4_URL")" || {
  echo "error: could not fetch $CF_IPS_V4_URL" >&2
  exit 1
}
export CF_RAW DOMAIN SAMPLES_PER_CIDR
export EXTRA_IPS
python3 - >"$TMP_DIR/candidates" <<'PY'
import os, re, ipaddress, subprocess, shutil
domain = os.environ.get("DOMAIN", "")
cf = os.environ.get("CF_RAW", "")
try:
  n = max(1, int(os.environ.get("SAMPLES_PER_CIDR", "3") or 3))
except Exception:
  n = 3
candidates = set()

def add_s(s):
  s = str(s).strip()
  if not s:
    return
  try:
    ipaddress.IPv4Address(s)
  except Exception:
    return
  candidates.add(s)


def sample_cidr_line(line):
  line = line.split("#", 1)[0].strip()
  if not line or "/" not in line:
    return
  try:
    net = ipaddress.ip_network(line, False)
  except Exception:
    return
  if net.version != 4:
    return
  a = int(net.network_address)
  b = int(net.broadcast_address) if net.num_addresses > 1 else a
  if net.num_addresses <= 0:
    return
  if net.num_addresses == 1 or net.prefixlen == 32:
    add_s(str(net.network_address))
    return
  if net.num_addresses == 2:
    for x in (a, b):
      add_s(str(ipaddress.IPv4Address(x)))
    return
  first = a + 1
  last = b - 1
  if first > last:
    return
  span = last - first + 1
  for off in (0, span // 2, min(span - 1, max(0, 7)), min(span - 1, 42))[:n]:
    if 0 <= off < span:
      add_s(str(ipaddress.IPv4Address(first + off)))


# A records of DOMAIN
if domain and shutil.which("dig"):
  try:
    out = subprocess.check_output(
      ["dig", "+short", "A", domain],
      stderr=subprocess.DEVNULL, timeout=5, text=True
    )
    for line in out.splitlines():
      line = line.strip()
      if re.match(r"^(\d{1,3}\.){3}\d{1,3}$", line):
        add_s(line)
  except Exception:
    pass
extra = os.environ.get("EXTRA_IPS", "") or ""
for t in extra.split():
  add_s(t)
for line in cf.splitlines():
  sample_cidr_line(line)
for a in sorted(candidates, key=lambda s: [int(p) for p in s.split(".")]):
  print(a)
PY

# --- first response line: expect HTTP/1.1 101
ws_get_first_line() {
  local port="$1"
  local rpath="$2"
  local ip="${3:-}"
  local key
  key="$(
    printf '%s' "$(openssl rand -base64 16 2>/dev/null)" | tr -d '=\n' 2>/dev/null || true
  )"
  [[ -z "$key" ]] && key="dGhlIHNhbXBsZSBub25jZQ=="
  if [[ "$port" == "80" ]]; then
    "$CURL" -g -sS -D - -o /dev/null \
      --connect-timeout "$TIMEOUT" -m "$TIMEOUT" --http1.1 \
      --resolve "${DOMAIN}:80:${ip}" \
      "http://${DOMAIN}${rpath}" \
      -H "Host: ${DOMAIN}" \
      -H "User-Agent: cf-ws-probe/1" \
      -H "Connection: Upgrade" \
      -H "Upgrade: websocket" \
      -H "Sec-WebSocket-Key: ${key}" \
      -H "Sec-WebSocket-Version: 13" 2>/dev/null | { IFS= read -r fl || true; echo "$fl"; } || true
  else
    "$CURL" -g -sS -D - -o /dev/null \
      --connect-timeout "$TIMEOUT" -m "$TIMEOUT" --http1.1 \
      --resolve "${DOMAIN}:443:${ip}" \
      "https://${DOMAIN}${rpath}" \
      -H "Host: ${DOMAIN}" \
      -H "User-Agent: cf-ws-probe/1" \
      -H "Connection: Upgrade" \
      -H "Upgrade: websocket" \
      -H "Sec-WebSocket-Key: ${key}" \
      -H "Sec-WebSocket-Version: 13" 2>/dev/null | { IFS= read -r fl || true; echo "$fl"; } || true
  fi
}

is_101() { [[ "$1" == *" 101 "* || "$1" == *" 101"*$'\r' ]]; }

count=$(wc -l <"$TMP_DIR/candidates" | tr -d ' ')
echo "candidates: $count (domain=$DOMAIN, samples_per_cidr~${SAMPLES_PER_CIDR})" >&2
: >"$TMP_DIR/ok"
while read -r ip; do
  [[ -z "$ip" ]] && continue
  a=$(ws_get_first_line 80 "/ws80" "$ip")
  b=$(ws_get_first_line 443 "/ws-vless" "$ip")
  a101=0; b101=0
  is_101 "$a" && a101=1
  is_101 "$b" && b101=1
  if [[ "$a101" -eq 1 && "$b101" -eq 1 ]]; then
    echo "$ip" >>"$TMP_DIR/ok"
    echo "  OK: $ip" >&2
  else
    if [[ "${DEBUG:-0}" == "1" ]]; then
      echo "  --: $ip  (80: $a101  443: $b101)  line80=[$a] line443=[$b]" >&2
    else
      echo "  --: $ip  (80: $a101  443: $b101)" >&2
    fi
  fi
done <"$TMP_DIR/candidates"

install -m 0644 "$TMP_DIR/ok" "$OUTFILE"
echo "Wrote $OUTFILE ($(wc -l <"$OUTFILE" | tr -d ' ') line(s))" >&2

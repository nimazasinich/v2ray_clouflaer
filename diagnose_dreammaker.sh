#!/usr/bin/env bash
# ==============================================================================
#  DreamMaker — Full Server Diagnostic Script
#  Run: bash /root/diagnose_dreammaker.sh
# ==============================================================================

set -uo pipefail
export LANG=C.UTF-8 LC_ALL=C.UTF-8

RED='\033[0;31m'; GRN='\033[0;32m'; YEL='\033[1;33m'
CYN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RST='\033[0m'

CFG="/usr/local/etc/xray/config.json"
XRAY="/usr/local/bin/xray"
LOG="/root/dreammaker-diagnose-$(date +%Y%m%d_%H%M%S).txt"
echo "$LOG" > /root/.last_dreammaker_diagnose_path.txt

exec > >(tee "$LOG") 2>&1

sep()  { echo -e "\n${BOLD}${CYN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}"; }
sect() { sep; echo -e "${BOLD}${CYN}  $*${RST}"; sep; }
ok()   { echo -e "  ${GRN}[OK]${RST}  $*"; }
fail() { echo -e "  ${RED}[FAIL]${RST} $*"; }
warn() { echo -e "  ${YEL}[WARN]${RST} $*"; }
info() { echo -e "  ${DIM}[...]${RST} $*"; }

echo ""
echo -e "${BOLD}${CYN}╔══════════════════════════════════════════════════════════════╗"
echo -e "║        DreamMaker — Full Server Diagnostic                   ║"
echo -e "╚══════════════════════════════════════════════════════════════╝${RST}"
echo -e "  Date : $(date -u)"
echo -e "  Host : $(hostname) / $(hostname -I | awk '{print $1}')"
echo -e "  Log  : $LOG"

# ==============================================================================
sect "SECTION 1 — Xray Process & Config"
# ==============================================================================
XRAY_PID=$(pgrep -x xray 2>/dev/null | head -1 || true)
if [[ -n "$XRAY_PID" ]]; then
    ok "Xray running — PID=$XRAY_PID"
    XRAY_CMD=$(cat /proc/"$XRAY_PID"/cmdline 2>/dev/null | tr '\0' ' ')
    info "Command: $XRAY_CMD"
    ACTIVE_CFG=$(cat /proc/"$XRAY_PID"/cmdline 2>/dev/null | tr '\0' '\n' | grep '\.json' | head -1)
    if [[ -n "$ACTIVE_CFG" ]]; then
        ok "Active config: $ACTIVE_CFG"
        CFG="$ACTIVE_CFG"
    else
        warn "Could not detect config path from cmdline, using $CFG"
    fi
else
    fail "Xray is NOT running"
    systemctl status xray --no-pager 2>/dev/null | head -10 || true
fi

if [[ -f "$CFG" ]]; then
    SIZE=$(wc -c < "$CFG")
    ok "Config file exists: $CFG ($SIZE bytes)"
else
    fail "Config file NOT found: $CFG"
    exit 1
fi
export DIAG_XRAY_CONFIG="$CFG"

# ==============================================================================
sect "SECTION 2 — Extract Real Credentials from Config"
# ==============================================================================
python3 << 'PYEOF'
import json, os, subprocess, sys
cfg_path = os.environ.get("DIAG_XRAY_CONFIG", "/usr/local/etc/xray/config.json")
try:
    c = json.load(open(cfg_path))
except Exception as e:
    print(f"  [FAIL] Cannot parse config: {e}")
    sys.exit(1)
inbounds = c.get("inbounds", [])
print(f"  [OK]  Total inbounds: {len(inbounds)}")

uuids, passwords, privkeys = set(), set(), set()
shortids_all = []
reality_ports, ws_ports, xhttp_ports, grpc_ports, tcp_ports = [], [], [], [], []
all_ports = []
for i in inbounds:
    port = i.get("port")
    proto = i.get("protocol", "?")
    all_ports.append(port)
    ss = i.get("streamSettings", {})
    net = ss.get("network", "tcp")
    sec = ss.get("security", "none")
    rs = ss.get("realitySettings", {})
    for cl in i.get("settings", {}).get("clients", []):
        if "id" in cl: uuids.add(cl["id"])
        if "password" in cl: passwords.add(cl["password"])
    if rs.get("privateKey"): privkeys.add(rs["privateKey"])
    for sid in rs.get("shortIds", []):
        if sid: shortids_all.append((port, sid))
    if sec == "reality" or (rs and rs.get("serverNames") is not None and rs.get("privateKey")):
        if sec == "reality" or (rs and rs.get("dest")): reality_ports.append((port, proto, net, sec))
    if net == "ws": ws_ports.append(port)
    if net == "xhttp": xhttp_ports.append(port)
    if net == "grpc": grpc_ports.append(port)
    if net == "tcp": tcp_ports.append(port)
print(f"\n  ── Ports ──")
print(f"  All ports    : {sorted([p for p in all_ports if p is not None])}")
print(f"  Reality rows : {reality_ports}")
print(f"  WS ports     : {ws_ports}")
print(f"  XHTTP ports  : {xhttp_ports}")
print(f"  gRPC ports   : {grpc_ports}")
print(f"\n  ── UUIDs found ──")
for u in uuids: print(f"  UUID: {u}")
print(f"\n  ── Passwords (Trojan/SS) [truncated] ──")
for p in passwords: print(f"  PASS: {p[:4]}...{p[-2:] if len(p)>6 else p}")
print(f"\n  ── ShortIDs (port → sid) ──")
for t in shortids_all[:12]: print(f"  port={t[0]} sid={t[1]}")
print(f"\n  ── Private Keys (masked) ──")
for pk in privkeys:
    print(f"  PRIVKEY: {pk[:8]}...{pk[-8:]}")
    r = subprocess.run(["/usr/local/bin/xray", "x25519", "-i", pk], capture_output=True, text=True, timeout=5)
    for line in r.stdout.splitlines():
        if "Public" in line: print(f"  PUBKEY : {line.split(':')[-1].strip()}")
print(f"\n  ── Inbound detail (short) ──")
for i in inbounds:
    port, proto = i.get("port"), i.get("protocol")
    ss = i.get("streamSettings", {})
    print(f"  PORT {port} | {proto} | {ss.get('network')} | sec={ss.get('security','none')}")
PYEOF

# ==============================================================================
sect "SECTION 3 — Port Listening Status"
# ==============================================================================
info "Checking which ports xray / others own..."
ALL_PORTS_IN_CFG=$(python3 -c "import json,os;c=json.load(open(os.environ['DIAG_XRAY_CONFIG']));print(' '.join(str(i['port']) for i in c['inbounds'] if 'port' in i))" 2>/dev/null)
for port in $ALL_PORTS_IN_CFG; do
    if ss -tlnp 2>/dev/null | grep -qE ":${port} .*"; then
        owner=$(ss -tlnp 2>/dev/null | grep -E ":${port} " | head -1)
        if echo "$owner" | grep -qi xray; then ok "Port $port — xray"
        else warn "Port $port — $owner"
        fi
    else
        fail "Port $port — NOT LISTENING"
    fi
done

# ==============================================================================
sect "SECTION 4 — Nginx Status"
# ==============================================================================
if systemctl is-active nginx &>/dev/null; then
    ok "nginx is running"
    info "nginx listening:"; ss -tlnp 2>/dev/null | grep nginx | sed 's/^/    /' || true
    info "sites-enabled:"; ls -la /etc/nginx/sites-enabled/ 2>/dev/null | sed 's/^/    /' || true
    if [[ -f /etc/nginx/sites-enabled/cdn-proxy ]]; then info "cdn-proxy head (first 50 lines):"; head -50 /etc/nginx/sites-enabled/cdn-proxy | sed 's/^/    /'; fi
else warn "nginx is NOT running"
fi

# ==============================================================================
sect "SECTION 5 — Firewall (UFW)"
# ==============================================================================
if command -v ufw &>/dev/null; then ufw status 2>/dev/null | head -50; else warn "ufw not found"; fi

# ==============================================================================
sect "SECTION 6 — TCP loopback per config port"
# ==============================================================================
# Raw /dev/tcp connect to a REALITY inbound can complete TCP but then drop with no
# TLS; Xray may log "TLS handshake error... unexpectedEOF". Skip raw probe for
# those ports; SECTION 3 already proves xray is listening.
REALITY_PORTS_6=$(python3 -c "
import json, os
c = json.load(open(os.environ.get('DIAG_XRAY_CONFIG', '/usr/local/etc/xray/config.json')))
out=set()
for i in c.get('inbounds',[]):
    ss = i.get('streamSettings') or {}
    p = i.get('port')
    if not p: continue
    if ss.get('security') == 'reality' or (ss.get('realitySettings') or {}).get('privateKey'):
        out.add(p)
print(' '.join(str(x) for x in sorted(out)))
" 2>/dev/null)

for port in $ALL_PORTS_IN_CFG; do
    is_re=0
    for rp in $REALITY_PORTS_6; do
        if [[ "$port" == "$rp" ]]; then is_re=1; break; fi
    done
    if [[ $is_re -eq 1 ]]; then
        if ss -tlnp 2>/dev/null | grep -qE ":${port} .*[Xx]ray|xray"; then
            ok "127.0.0.1:$port (Reality) — xray listen OK (raw /dev/tcp skipped; avoids TLS noise in logs)"
        else
            warn "127.0.0.1:$port (Reality) — expected xray, check SECTION 3"
        fi
        continue
    fi
    if timeout 2 bash -c "echo > /dev/tcp/127.0.0.1/${port}" 2>/dev/null; then
        ok "127.0.0.1:$port TCP open"
    else
        fail "127.0.0.1:$port TCP fail"
    fi
done

# ==============================================================================
sect "SECTION 7 — TLS to Reality dest (host:443)"
# ==============================================================================
info "Using Python ssl (verifies cert chain) — not a bare openssl pipe/head (avoids false [FAIL])"
python3 << 'PYTLS'
import json, os, socket, ssl, sys

def main():
    path = os.environ.get("DIAG_XRAY_CONFIG", "/usr/local/etc/xray/config.json")
    with open(path) as f:
        c = json.load(f)
    snis = set()
    for i in c.get("inbounds", []):
        d = (i.get("streamSettings") or {}).get("realitySettings", {}) or {}
        dest = d.get("dest", "") or ""
        if not dest:
            continue
        h = dest.split(":", 1)[0] if ":" in dest else dest
        if h:
            snis.add(h)
    if not snis:
        print("  (no dest hosts in realitySettings)")
        return
    any_fail = 0
    for sni in sorted(snis):
        try:
            ctx = ssl.create_default_context()
            with socket.create_connection((sni, 443), timeout=12) as raw:
                with ctx.wrap_socket(raw, server_hostname=sni) as ss:
                    ciph = (ss.cipher() or ("?",))[0]
            print(f"  [OK]  TLS to {sni}:443  cipher={ciph}  (chain verified by ssl)")
        except Exception as e:
            print(f"  [FAIL]  TLS to {sni}:443  {e}")
            any_fail = 1
    return 1 if any_fail else 0

if __name__ == "__main__":
    sys.exit(main() or 0)
PYTLS

# ==============================================================================
sect "SECTION 8 — xray -test"
# ==============================================================================
info "Deprecation lines from xray (gRPC, Trojan+no Flow, SS, VMess, WS) come from the binary when those inbounds exist — remove or replace those inbounds in config to silence."
$XRAY -test -config "$CFG" 2>&1

# ==============================================================================
sect "SECTION 9 — Last 25 journal lines (xray)"
# ==============================================================================
journalctl -u xray -n 25 --no-pager 2>/dev/null

# ==============================================================================
sect "SECTION 10 — Full links (from config + pubkey)"
# ==============================================================================
python3 << 'PY2'
import json, os, subprocess, base64
from urllib.parse import quote
cfg = json.load(open(os.environ.get("DIAG_XRAY_CONFIG", "/usr/local/etc/xray/config.json")))
IP = "82.115.26.105"

def get_pubkey(priv: str) -> str:
    r = subprocess.run(["/usr/local/bin/xray", "x25519", "-i", priv], capture_output=True, text=True, timeout=5)
    for line in (r.stdout or "").splitlines():
        if "Public" in line:
            return line.split(":", 1)[-1].strip()
    return ""

pub = ""
for i in cfg["inbounds"]:
    r = (i.get("streamSettings") or {}).get("realitySettings", {})
    if r.get("privateKey"):
        pub = get_pubkey(r["privateKey"])
        break
print("REAL_PUBKEY =", pub)
for ib in cfg["inbounds"]:
    port, proto = ib.get("port"), ib.get("protocol")
    if not isinstance(port, int):
        continue
    ss = ib.get("streamSettings") or {}
    net, sec = ss.get("network", "tcp"), ss.get("security", "none")
    rs, ws, xhs, gs = (ss.get("realitySettings") or {}), (ss.get("wsSettings") or {}), (ss.get("xhttpSettings") or {}), (ss.get("grpcSettings") or {})
    cl = (ib.get("settings") or {}).get("clients") or [{}]
    uid, pw = (cl[0].get("id") or ""), (cl[0].get("password") or "")
    sni1 = (rs.get("serverNames") or [""])[0] if rs else ""
    sids = [s for s in (rs.get("shortIds") or []) if s]
    sid0 = sids[0] if sids else ""
    path = (ws.get("path") or xhs.get("path") or "/")
    hosth = (ws.get("headers") or {}).get("Host") or xhs.get("host") or "cdn.dreammaker-groupsoft.ir"
    P = int(port)
    if sec == "reality" and proto == "vless" and net == "tcp" and uid:
        print(f"vless://{uid}@{IP}:{P}?security=reality&encryption=none&fp=chrome&pbk={quote(pub)}&sid={quote(sid0)}&flow=xtls-rprx-vision&type=tcp&sni={quote(sni1)}#REALITY-TCP-{P}")
    if sec == "reality" and proto == "vless" and net == "grpc" and uid:
        sm = gs.get("serviceName", "gm")
        print(f"vless://{uid}@{IP}:{P}?security=reality&flow=&type=grpc&mode=gun&serviceName={quote(sm)}&sni={quote(sni1)}&fp=chrome&pbk={quote(pub)}&sid={quote(sid0)}#REALITY-gRPC-{P}")
    if sec == "reality" and proto == "vless" and net == "xhttp" and uid:
        pth = path or "/r"
        print(f"vless://{uid}@{IP}:{P}?security=reality&encryption=none&flow=&type=xhttp&path={quote(pth, safe='')}&sni={quote(sni1)}&fp=chrome&pbk={quote(pub)}&sid={quote(sid0)}#REALITY-xHTTP-{P}")
    if sec == "reality" and proto == "trojan" and net == "tcp" and pw:
        print(f"trojan://{quote(pw)}@{IP}:{P}?security=reality&fp=chrome&pbk={quote(pub)}&sid={quote(sid0)}&sni={quote(sni1)}&type=tcp&headerType=none#REALITY-Trojan-{P}")
    if net == "ws" and str(sec).lower() in ("none",) and proto == "vless" and uid:
        print(f"vless://{uid}@{hosth}:{P}?encryption=none&security=none&type=ws&path={quote(path)}#WS-{P}")
    if net == "ws" and sec == "none" and proto == "vmess" and uid:
        o = {"v":"2","ps":f"VM-{P}","add":hosth,"port":str(P),"id":uid,"aid":"0","scy":"auto",
             "net":"ws","type":"none","host":hosth,"path":path,"tls":"none","sni":""}
        print("vmess://"+base64.b64encode(json.dumps(o, separators=(",", ":")).encode()).decode()+"#VMess-"+str(P))
    if net == "ws" and sec == "none" and proto == "trojan" and pw:
        print(f"trojan://{quote(pw)}@{hosth}:{P}?type=ws&path={quote(path)}&host={quote(hosth)}&security=none#T-WS-{P}")
    if net == "xhttp" and str(sec).lower() in ("none",) and proto == "vless" and uid:
        print(f"vless://{uid}@{hosth}:{P}?encryption=none&flow=&security=none&type=xhttp&path={quote(xhs.get('path', '/'))}#XHTTP-{P}")
    if proto == "shadowsocks" and (ib.get("settings") or {}).get("password"):
        m, ssp = ib["settings"]["method"], ib["settings"]["password"]
        b = base64.b64encode(f"{m}:{ssp}".encode()).decode().rstrip("=")
        print(f"ss://{b}@{IP}:{P}#SS-{P}")
    if net == "ws" and str(sec).lower() == "tls" and proto == "vless" and uid:
        print(f"vless://{uid}@{hosth}:{P}?encryption=none&flow=&security=tls&type=ws&path={quote(path)}&sni={quote(hosth)}&host={quote(hosth)}#WS-TLS-{P}")
    if net == "xhttp" and str(sec).lower() == "tls" and proto == "vless" and uid:
        print(f"vless://{uid}@{hosth}:{P}?encryption=none&flow=&security=tls&type=xhttp&path={quote(xhs.get('path', '/'))}&sni={quote(hosth)}#XHTTP-TLS-{P}")
PY2

sect "FINISH"
ok "Log file: $LOG"
echo "Path also in /root/.last_dreammaker_diagnose_path.txt"
exit 0

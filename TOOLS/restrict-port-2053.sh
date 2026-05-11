#!/bin/bash
# ============================================================================
# Restrict Port 2053 to Cloudflare IPs Only - DreamMaker VPS
# ============================================================================
# Blocks all non-Cloudflare traffic on port 2053
# Prevents direct VPS discovery
# ============================================================================

set -e

echo "=========================================="
echo "Port 2053 Firewall Restriction"
echo "=========================================="

# Cloudflare IPv4 ranges (2026)
CF_IPV4_RANGES=(
    "173.245.48.0/20"
    "103.21.244.0/22"
    "103.22.200.0/22"
    "103.31.4.0/22"
    "141.101.64.0/18"
    "108.162.192.0/18"
    "190.93.240.0/20"
    "188.114.96.0/20"
    "197.234.240.0/22"
    "198.41.128.0/17"
    "162.158.0.0/15"
    "104.16.0.0/13"
    "104.24.0.0/14"
    "172.64.0.0/13"
    "131.0.72.0/22"
)

# Cloudflare IPv6 ranges
CF_IPV6_RANGES=(
    "2400:cb00::/32"
    "2606:4700::/32"
    "2803:f800::/32"
    "2405:b500::/32"
    "2405:8100::/32"
    "2a06:98c0::/29"
    "2c0f:f248::/32"
)

# Backup current iptables rules
echo "Backing up current iptables rules..."
iptables-save > /root/iptables-backup-$(date +%Y%m%d-%H%M%S).rules
ip6tables-save > /root/ip6tables-backup-$(date +%Y%m%d-%H%M%S).rules

# Clear existing rules for port 2053
echo "Clearing existing rules for port 2053..."
iptables -D INPUT -p tcp --dport 2053 -j DROP 2>/dev/null || true
ip6tables -D INPUT -p tcp --dport 2053 -j DROP 2>/dev/null || true

for ip in "${CF_IPV4_RANGES[@]}"; do
    iptables -D INPUT -p tcp --dport 2053 -s "$ip" -j ACCEPT 2>/dev/null || true
done

for ip in "${CF_IPV6_RANGES[@]}"; do
    ip6tables -D INPUT -p tcp --dport 2053 -s "$ip" -j ACCEPT 2>/dev/null || true
done

# Add Cloudflare IPv4 ranges
echo "Adding Cloudflare IPv4 ranges..."
for ip in "${CF_IPV4_RANGES[@]}"; do
    iptables -I INPUT -p tcp --dport 2053 -s "$ip" -j ACCEPT
    echo "  ✅ $ip"
done

# Add Cloudflare IPv6 ranges
echo "Adding Cloudflare IPv6 ranges..."
for ip in "${CF_IPV6_RANGES[@]}"; do
    ip6tables -I INPUT -p tcp --dport 2053 -s "$ip" -j ACCEPT
    echo "  ✅ $ip"
done

# Block all other traffic on port 2053
echo "Blocking all other traffic on port 2053..."
iptables -A INPUT -p tcp --dport 2053 -j DROP
ip6tables -A INPUT -p tcp --dport 2053 -j DROP

# Save rules
echo "Saving iptables rules..."
if command -v netfilter-persistent &>/dev/null; then
    netfilter-persistent save
elif command -v iptables-save &>/dev/null; then
    iptables-save > /etc/iptables/rules.v4
    ip6tables-save > /etc/iptables/rules.v6
else
    echo "⚠️  Warning: Could not persist rules. Install iptables-persistent"
fi

echo ""
echo "=========================================="
echo "Firewall Configuration Complete"
echo "=========================================="
echo "Port 2053 is now restricted to Cloudflare IPs only"
echo ""
echo "Active rules for port 2053:"
iptables -L INPUT -n --line-numbers | grep 2053

echo ""
echo "To remove restrictions (emergency):"
echo "  iptables -D INPUT -p tcp --dport 2053 -j DROP"
echo "  # Then remove ACCEPT rules individually"

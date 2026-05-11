#!/bin/bash
# ============================================================================
# Enable BBR Congestion Control - DreamMaker VPS
# ============================================================================
# Run this on the Germany VPS (82.115.26.105) via VNC console
# Requires: Linux kernel 4.9+ (BBRv1) or 5.18+ (BBRv3)
# ============================================================================

set -e

echo "=========================================="
echo "BBR Congestion Control Setup"
echo "=========================================="

# Check current kernel version
KERNEL_VERSION=$(uname -r)
echo "Current kernel: $KERNEL_VERSION"

# Check if BBR module exists
if ! modinfo tcp_bbr &>/dev/null; then
    echo "ERROR: BBR module not found in kernel"
    echo "Your kernel may be too old (< 4.9)"
    exit 1
fi

# Check current congestion control
CURRENT_CC=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')
echo "Current congestion control: $CURRENT_CC"

if [ "$CURRENT_CC" = "bbr" ]; then
    echo "BBR is already enabled!"
    exit 0
fi

# Backup current sysctl.conf
echo "Backing up /etc/sysctl.conf..."
cp /etc/sysctl.conf /etc/sysctl.conf.backup-$(date +%Y%m%d-%H%M%S)

# Enable BBR
echo "Enabling BBR..."
cat >> /etc/sysctl.conf <<EOF

# BBR Congestion Control (added by DreamMaker setup $(date +%Y-%m-%d))
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF

# Apply changes
sysctl -p

# Verify
NEW_CC=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')
NEW_QDISC=$(sysctl net.core.default_qdisc | awk '{print $3}')

echo ""
echo "=========================================="
echo "BBR Setup Complete"
echo "=========================================="
echo "Congestion Control: $NEW_CC"
echo "Queue Discipline: $NEW_QDISC"

if [ "$NEW_CC" = "bbr" ]; then
    echo "✅ BBR successfully enabled!"
else
    echo "⚠️  BBR not active. Check kernel support."
    exit 1
fi

# Optional: Advanced TCP tuning for BBR
echo ""
echo "Would you like to apply advanced TCP tuning? (y/n)"
read -r APPLY_ADVANCED

if [ "$APPLY_ADVANCED" = "y" ]; then
    echo "Applying advanced TCP tuning..."
    cat >> /etc/sysctl.conf <<EOF

# Advanced TCP tuning for BBR
net.core.rmem_max=134217728
net.core.wmem_max=134217728
net.ipv4.tcp_rmem=4096 87380 67108864
net.ipv4.tcp_wmem=4096 65536 67108864
net.ipv4.tcp_mtu_probing=1
net.ipv4.tcp_slow_start_after_idle=0
EOF
    sysctl -p
    echo "✅ Advanced tuning applied!"
fi

echo ""
echo "Done. Xray will use BBR after restart."
echo "Restart Xray: systemctl restart xray"

#!/bin/bash
# ============================================================================
# Update Xray GeoIP and GeoSite Files - DreamMaker VPS
# ============================================================================
# Updates geoip.dat and geosite.dat with latest Iran routing rules
# Source: Loyalsoldier/v2ray-rules-dat (daily builds)
# ============================================================================

set -e

XRAY_DIR="/usr/local/share/xray"
BACKUP_DIR="/root/xray-geo-backups"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

echo "=========================================="
echo "Xray Geo Files Update"
echo "=========================================="

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Backup current files
if [ -f "$XRAY_DIR/geoip.dat" ]; then
    echo "Backing up current geoip.dat..."
    cp "$XRAY_DIR/geoip.dat" "$BACKUP_DIR/geoip.dat.$TIMESTAMP"
fi

if [ -f "$XRAY_DIR/geosite.dat" ]; then
    echo "Backing up current geosite.dat..."
    cp "$XRAY_DIR/geosite.dat" "$BACKUP_DIR/geosite.dat.$TIMESTAMP"
fi

# Download latest geoip.dat
echo "Downloading latest geoip.dat..."
curl -L -o "$XRAY_DIR/geoip.dat.tmp" \
    https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat

if [ $? -eq 0 ] && [ -s "$XRAY_DIR/geoip.dat.tmp" ]; then
    mv "$XRAY_DIR/geoip.dat.tmp" "$XRAY_DIR/geoip.dat"
    echo "✅ geoip.dat updated"
else
    echo "⚠️  geoip.dat download failed, keeping old version"
    rm -f "$XRAY_DIR/geoip.dat.tmp"
fi

# Download latest geosite.dat
echo "Downloading latest geosite.dat..."
curl -L -o "$XRAY_DIR/geosite.dat.tmp" \
    https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat

if [ $? -eq 0 ] && [ -s "$XRAY_DIR/geosite.dat.tmp" ]; then
    mv "$XRAY_DIR/geosite.dat.tmp" "$XRAY_DIR/geosite.dat"
    echo "✅ geosite.dat updated"
else
    echo "⚠️  geosite.dat download failed, keeping old version"
    rm -f "$XRAY_DIR/geosite.dat.tmp"
fi

# Set permissions
chmod 644 "$XRAY_DIR/geoip.dat" "$XRAY_DIR/geosite.dat"

# Show file info
echo ""
echo "Updated files:"
ls -lh "$XRAY_DIR/geoip.dat" "$XRAY_DIR/geosite.dat"

echo ""
echo "=========================================="
echo "Update Complete"
echo "=========================================="
echo "Backups saved to: $BACKUP_DIR"
echo ""
echo "To apply changes, restart Xray:"
echo "  systemctl restart xray"
echo "  systemctl status xray"

# Optional: Restart Xray automatically
echo ""
echo "Restart Xray now? (y/n)"
read -r RESTART_NOW

if [ "$RESTART_NOW" = "y" ]; then
    systemctl restart xray
    sleep 2
    systemctl status xray --no-pager
fi

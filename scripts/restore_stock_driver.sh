#!/usr/bin/env bash
# restore_stock_driver.sh - Dedicated script to restore official stock Mesa/NVIDIA drivers
# Usage: sudo ./restore_stock_driver.sh

set -euo pipefail

GALLIUM_TARGET="/usr/lib/x86_64-linux-gnu/libgallium-25.2.8-0ubuntu0.24.04.2.so"
GALLIUM_BAK="${GALLIUM_TARGET}.orig_bak"

DRI_TARGET="/usr/lib/x86_64-linux-gnu/dri/libdril_dri.so"
DRI_BAK="${DRI_TARGET}.orig_bak"

echo "======================================================="
echo "   Restoring Official Stock Mesa / Nouveau GPU Driver"
echo "======================================================="

if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] This script must be run as root (e.g. sudo $0)."
    exit 1
fi

if [ -f "$GALLIUM_BAK" ]; then
    cp "$GALLIUM_BAK" "$GALLIUM_TARGET"
    echo "[SUCCESS] Restored stock libgallium binary ($(stat -c%s "$GALLIUM_TARGET") bytes)."
else
    echo "[ERROR] Stock backup not found at $GALLIUM_BAK!"
    exit 1
fi

if [ -f "$DRI_BAK" ]; then
    cp "$DRI_BAK" "$DRI_TARGET"
    echo "[SUCCESS] Restored stock libdril_dri binary ($(stat -c%s "$DRI_TARGET") bytes)."
fi

echo "0" > /var/lib/nouveau_boot_attempts 2>/dev/null || true
echo "stock" > /var/lib/nouveau_driver_tier 2>/dev/null || true
rm -f /var/run/driver_fallback_triggered /tmp/driver_fallback_triggered 2>/dev/null || true
sync

echo "======================================================="
echo "[COMPLETE] Stock driver successfully restored and active!"
echo "You can now reboot or restart GDM safely."
echo "======================================================="

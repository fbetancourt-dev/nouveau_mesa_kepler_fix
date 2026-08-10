#!/usr/bin/env bash
# deploy_5patch_systemwide_safe.sh - Safe systemwide 5-patch Mesa driver deployment script
# Target: /usr/lib/x86_64-linux-gnu/libgallium-25.2.8-0ubuntu0.24.04.2.so

set -euo pipefail

REPO_DIR="/home/fbetancourt/Gemini/nouveau_mesa_kepler_fix"
SOURCE_BIN="${REPO_DIR}/drivers/libdril_dri_both_patches.so"
TARGET_GALLIUM="/usr/lib/x86_64-linux-gnu/libgallium-25.2.8-0ubuntu0.24.04.2.so"
BAK_GALLIUM="${TARGET_GALLIUM}.orig_bak"
DEPLOY_MARKER="/var/lib/nouveau_driver_deployed_at"
BOOT_COUNTER="/var/lib/nouveau_boot_attempts"
WATCHDOG_SCRIPT="/usr/local/bin/check-nouveau-driver-fallback.sh"

echo "======================================================="
echo "   Nouveau Mesa Kepler - 5-Patch Safe Deployment Script"
echo "======================================================="

# 1. Root permission check
if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] This script must be run as root (use: sudo $0)."
    exit 1
fi

# 2. Source binary check
if [ ! -f "${SOURCE_BIN}" ]; then
    echo "[ERROR] Compiled 5-patch binary not found at ${SOURCE_BIN}!"
    exit 1
fi

# 3. Backup file check
if [ ! -f "${BAK_GALLIUM}" ]; then
    echo "[ERROR] Stock driver backup file missing at ${BAK_GALLIUM}!"
    echo "        Cannot proceed without a verified stock backup."
    exit 1
fi

# 4. Watchdog script syntax check
if [ ! -x "${WATCHDOG_SCRIPT}" ] || ! bash -n "${WATCHDOG_SCRIPT}" &>/dev/null; then
    echo "[ERROR] Watchdog script at ${WATCHDOG_SCRIPT} is missing or has syntax errors!"
    exit 1
fi

echo "[INFO] Source binary verified: $(stat -c%s "${SOURCE_BIN}") bytes."
echo "[INFO] Stock backup verified: $(stat -c%s "${BAK_GALLIUM}") bytes."

# 5. Prepare watchdog state markers
echo "[INFO] Setting up fail-safe watchdog boot markers..."
touch "${DEPLOY_MARKER}"
echo "0" > "${BOOT_COUNTER}"
echo "5patch" > /var/lib/nouveau_driver_tier
rm -f /var/run/driver_fallback_triggered /tmp/driver_fallback_triggered 2>/dev/null || true

# 6. Perform systemwide deployment
echo "[INFO] Copying 5-patch Mesa driver to ${TARGET_GALLIUM}..."
cp "${SOURCE_BIN}" "${TARGET_GALLIUM}"

echo "[SUCCESS] 5-patch Mesa driver deployed systemwide successfully!"
echo "======================================================="
echo "   Watchdog Protection: ACTIVE"
echo "   Boot Attempts Counter: Reset to 1"
echo "   Fallback Target: Stock driver (${BAK_GALLIUM})"
echo "======================================================="
echo "INSTRUCTIONS TO RESTART GDM / DESKTOP SESSION:"
echo "1. If running from TTY (Ctrl+Alt+F3), execute:"
echo "   sudo systemctl restart gdm"
echo ""
echo "2. If a boot failure occurs, the fallback watchdog will"
echo "   AUTOMATICALLY restore stock drivers on the next reboot."
echo "======================================================="

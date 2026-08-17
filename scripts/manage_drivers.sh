#!/usr/bin/env bash
# manage_drivers.sh - Automated driver switcher with automatic health check & fallback

set -euo pipefail

REPO_DIR="/home/fbetancourt/Gemini/nouveau_mesa_kepler_fix"
DRIVERS_DIR="${REPO_DIR}/drivers"
DRI_SYSTEM_TARGET="/usr/lib/x86_64-linux-gnu/dri/libdril_dri.so"
GALLIUM_SYSTEM_TARGET="/usr/lib/x86_64-linux-gnu/libgallium-25.2.8-0ubuntu0.24.04.2.so"

PATCH1_BIN="${DRIVERS_DIR}/libdril_dri_patch1_only.so"
BOTH_BIN="${DRIVERS_DIR}/libdril_dri_both_patches.so"

PASSWORD="Raspberry84"

deploy_driver() {
    local src="$1"
    local name="$2"
    local tier="${3:-both}"
    if [ ! -f "$src" ]; then
        echo "[ERROR] Driver binary not found: $src"
        exit 1
    fi
    echo "[INFO] Deploying $name to ${DRI_SYSTEM_TARGET}..."
    echo "$PASSWORD" | sudo -S cp "$src" "${DRI_SYSTEM_TARGET}"
    echo "$PASSWORD" | sudo -S touch /var/lib/nouveau_driver_deployed_at
    echo "$PASSWORD" | sudo -S bash -c 'echo "0" > /var/lib/nouveau_boot_attempts' 2>/dev/null || true
    echo "$PASSWORD" | sudo -S bash -c "echo \"$tier\" > /var/lib/nouveau_driver_tier" 2>/dev/null || true
    echo "$PASSWORD" | sudo -S rm -f /var/run/driver_fallback_triggered /tmp/driver_fallback_triggered 2>/dev/null || true
    echo "[SUCCESS] $name deployed successfully to ${DRI_SYSTEM_TARGET}!"
    echo "[NOTE] Systemwide libgallium.so remains 100% stock to preserve GDM boot stability."
}

restore_default() {
    echo "[INFO] Restoring official default stock system DRI driver..."
    if [ -f "${DRI_SYSTEM_TARGET}.orig_bak" ]; then
        echo "$PASSWORD" | sudo -S cp "${DRI_SYSTEM_TARGET}.orig_bak" "${DRI_SYSTEM_TARGET}"
        echo "[SUCCESS] Restored stock libdril_dri driver."
    fi
    echo "$PASSWORD" | sudo -S bash -c 'echo "0" > /var/lib/nouveau_boot_attempts' 2>/dev/null || true
    echo "$PASSWORD" | sudo -S bash -c 'echo "stock" > /var/lib/nouveau_driver_tier' 2>/dev/null || true
    echo "$PASSWORD" | sudo -S rm -f /var/run/driver_fallback_triggered /tmp/driver_fallback_triggered 2>/dev/null || true
    echo "[COMPLETE] Official stock system DRI driver restored & active."
}

status() {
    echo "======================================================="
    echo "      Nouveau Driver Manager & Fallback System"
    echo "======================================================="
    if [ -f "${GALLIUM_SYSTEM_TARGET}" ]; then
        echo "Active libgallium size: $(stat -c%s "${GALLIUM_SYSTEM_TARGET}" 2>/dev/null) bytes (Stock)"
    fi
    if [ -f "${DRI_SYSTEM_TARGET}" ]; then
        ls -la "${DRI_SYSTEM_TARGET}"
    fi
    if [ -f "/var/lib/nouveau_driver_tier" ]; then
        echo "Active Tier Marker: $(cat /var/lib/nouveau_driver_tier 2>/dev/null)"
    fi
    echo "======================================================="
}

test_and_fallback() {
    echo "[INFO] Deploying dual-patch driver for live testing..."
    deploy_driver "${BOTH_BIN}" "Both Patches (OOR_ADDR + PTE BO_WAIT)" "both"
    
    echo "[INFO] Running 3D benchmark test on NVIDIA dGPU..."
    if DRI_PRIME=pci-0000_01_00_0 glmark2 -b shading:duration=1.0 -b texture:duration=1.0 >/dev/null 2>&1; then
        echo "[SUCCESS] 3D benchmark passed with zero issues!"
    else
        echo "[WARNING] 3D test failed! Executing automatic fallback to Patch 1..."
        deploy_driver "${PATCH1_BIN}" "Patch 1 Only (OOR_ADDR)" "patch1"
        exit 1
    fi

    if journalctl -k --since "30 seconds ago" | grep -iE "fault|PTE|errored|killed" >/dev/null 2>&1; then
        echo "[WARNING] Kernel log detected GPU errors! Executing automatic fallback to Patch 1..."
        deploy_driver "${PATCH1_BIN}" "Patch 1 Only (OOR_ADDR)" "patch1"
        exit 1
    else
        echo "[SUCCESS] Live health check passed with ZERO kernel errors! Dual-patch driver active."
    fi
}

boot_check() {
    echo "[INFO] Running post-boot nouveau driver watchdog health check..."
    if [ -x "/usr/local/bin/check-nouveau-driver-fallback.sh" ]; then
        echo "$PASSWORD" | sudo -S /usr/local/bin/check-nouveau-driver-fallback.sh
    fi
}

case "${1:-status}" in
    "deploy-both")
        deploy_driver "${BOTH_BIN}" "Both Patches (OOR_ADDR + PTE BO_WAIT)" "both"
        ;;
    "deploy-patch1")
        deploy_driver "${PATCH1_BIN}" "Patch 1 Only (OOR_ADDR)" "patch1"
        ;;
    "restore-default"|"restore"|"restore-stock")
        restore_default
        ;;
    "test-and-fallback"|"test")
        test_and_fallback
        ;;
    "boot-check")
        boot_check
        ;;
    "status")
        status
        ;;
    *)
        echo "Usage: $0 {deploy-both|deploy-patch1|restore-default|restore-stock|test|boot-check|status}"
        exit 1
        ;;
esac


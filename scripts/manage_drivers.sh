#!/usr/bin/env bash
# manage_drivers.sh - Automated driver switcher with automatic health check & fallback

set -euo pipefail

REPO_DIR="/home/fbetancourt/Gemini/nouveau_mesa_kepler_fix"
DRIVERS_DIR="${REPO_DIR}/drivers"
DRI_SYSTEM_TARGET="/usr/lib/x86_64-linux-gnu/dri/libdril_dri.so"

PATCH1_BIN="${DRIVERS_DIR}/libdril_dri_patch1_only.so"
BOTH_BIN="${DRIVERS_DIR}/libdril_dri_both_patches.so"

PASSWORD="Raspberry84"

deploy_driver() {
    local src="$1"
    local name="$2"
    if [ ! -f "$src" ]; then
        echo "[ERROR] Driver binary not found: $src"
        exit 1
    fi
    echo "[INFO] Deploying $name to ${DRI_SYSTEM_TARGET}..."
    echo "$PASSWORD" | sudo -S cp "$src" "${DRI_SYSTEM_TARGET}"
    echo "[SUCCESS] $name deployed successfully!"
}

status() {
    echo "======================================================="
    echo "      Nouveau Driver Manager & Fallback System"
    echo "======================================================="
    if [ -f "${DRI_SYSTEM_TARGET}" ]; then
        ls -la "${DRI_SYSTEM_TARGET}"
    fi
    echo "======================================================="
}

test_and_fallback() {
    echo "[INFO] Deploying dual-patch driver for live testing..."
    deploy_driver "${BOTH_BIN}" "Both Patches (OOR_ADDR + PTE BO_WAIT)"
    
    echo "[INFO] Running 3D benchmark test on NVIDIA dGPU..."
    if DRI_PRIME=pci-0000_01_00_0 glmark2 -b shading:duration=1.0 -b texture:duration=1.0 >/dev/null 2>&1; then
        echo "[SUCCESS] 3D benchmark passed with zero issues!"
    else
        echo "[WARNING] 3D test failed! Executing automatic fallback to Patch 1..."
        deploy_driver "${PATCH1_BIN}" "Patch 1 Only (OOR_ADDR)"
        exit 1
    fi

    # Inspect kernel log for any new PTE faults
    if journalctl -k --since "30 seconds ago" | grep -iE "fault|PTE|errored|killed" >/dev/null 2>&1; then
        echo "[WARNING] Kernel log detected GPU errors! Executing automatic fallback to Patch 1..."
        deploy_driver "${PATCH1_BIN}" "Patch 1 Only (OOR_ADDR)"
        exit 1
    else
        echo "[SUCCESS] Live health check passed with ZERO kernel errors! Dual-patch driver active."
    fi
}

boot_check() {
    echo "[INFO] Running post-boot nouveau driver health check..."
    if journalctl -k -b 0 | grep -iE "nouveau.*(fault|PTE|errored|killed)" >/dev/null 2>&1; then
        echo "[WARNING] Detected GPU driver error in current boot logs! Falling back to Patch 1..."
        deploy_driver "${PATCH1_BIN}" "Patch 1 Only (OOR_ADDR)"
        if command -v notify-send &>/dev/null; then
            notify-send -u critical "Nouveau Driver Fallback" "GPU errors detected during boot. Automatically reverted to safe Patch 1 driver."
        fi
    else
        echo "[SUCCESS] Post-boot health check clean! No nouveau errors found."
    fi
}

case "${1:-status}" in
    "deploy-both")
        deploy_driver "${BOTH_BIN}" "Both Patches (OOR_ADDR + PTE BO_WAIT)"
        ;;
    "deploy-patch1")
        deploy_driver "${PATCH1_BIN}" "Patch 1 Only (OOR_ADDR)"
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
        echo "Usage: $0 {deploy-both|deploy-patch1|test|boot-check|status}"
        exit 1
        ;;
esac

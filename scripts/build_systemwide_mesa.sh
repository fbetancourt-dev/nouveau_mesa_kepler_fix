#!/usr/bin/env bash
# build_systemwide_mesa.sh - Build & install systemwide Ubuntu 24.04 Mesa 25.2.8 with nouveau fixes

set -euo pipefail

REPO_DIR="/home/fbetancourt/Gemini/nouveau_mesa_kepler_fix"
MESA_SRC="${REPO_DIR}/mesa_25.2.8/mesa-25.2.8"
BUILD_DIR="${MESA_SRC}/build"

if [ ! -d "${MESA_SRC}" ]; then
    echo "[ERROR] Mesa 25.2.8 source directory not found at ${MESA_SRC}"
    exit 1
fi

echo "[INFO] Configuring Mesa 25.2.8 build for Ubuntu 24.04 ABI compatibility..."
mkdir -p "${BUILD_DIR}"

meson setup "${BUILD_DIR}" "${MESA_SRC}" \
    -Dgallium-drivers=nouveau,iris,i915,zink,virgl,softpipe \
    -Dvulkan-drivers= \
    -Dglx=dri \
    -Dplatforms=x11,wayland \
    -Dbuildtype=debugoptimized \
    --reconfigure || true

echo "[INFO] Compiling Mesa 25.2.8 DRI driver and system libgallium..."
ninja -C "${BUILD_DIR}"

DRI_TARGET=$(find "${BUILD_DIR}/src/gallium/targets/dri/" -name "libgallium-*.so" -o -name "libdril_dri.so" | head -n 1)

if [ -f "${DRI_TARGET}" ]; then
    echo "[INFO] Found compiled Mesa 25.2.8 driver at ${DRI_TARGET}"
    if [ "$(id -u)" -eq 0 ]; then
        SYSTEM_GALLIUM="/usr/lib/x86_64-linux-gnu/libgallium-25.2.8-0ubuntu0.24.04.2.so"
        SYSTEM_DRI="/usr/lib/x86_64-linux-gnu/dri/libdril_dri.so"
        
        if [ ! -f "${SYSTEM_GALLIUM}.orig_bak" ]; then
            echo "[INFO] Backing up original system libgallium..."
            cp "${SYSTEM_GALLIUM}" "${SYSTEM_GALLIUM}.orig_bak"
        fi

        echo "[INFO] Installing systemwide to ${SYSTEM_GALLIUM}..."
        cp "${DRI_TARGET}" "${SYSTEM_GALLIUM}"

        echo "[SUCCESS] Patched Mesa 25.2.8 driver successfully deployed systemwide!"
    else
        echo "[NOTE] To install systemwide, run with sudo:"
        echo "sudo $0"
    fi
fi

echo "[INFO] Build script finished execution."

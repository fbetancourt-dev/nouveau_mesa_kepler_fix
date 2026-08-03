#!/usr/bin/env bash
# build_nouveau_mesa.sh - Build custom Mesa nouveau DRI megadriver
# Target: nouveau_dri.so (Kepler GT 750M)

set -euo pipefail

REPO_DIR="/home/fbetancourt/Gemini/nouveau_mesa_kepler_fix"
MESA_DIR="${REPO_DIR}/mesa"
BUILD_DIR="${MESA_DIR}/build"

if [ ! -d "${MESA_DIR}" ]; then
    echo "[ERROR] Mesa source directory not found at ${MESA_DIR}"
    exit 1
fi

echo "[INFO] Configuring Mesa build for nouveau DRI megadriver..."
mkdir -p "${BUILD_DIR}"

if command -v meson &>/dev/null; then
    meson setup "${BUILD_DIR}" "${MESA_DIR}" \
        -Dgallium-drivers=nouveau \
        -Dvulkan-drivers= \
        -Dglx=dri \
        -Dplatforms=x11 \
        -Dbuildtype=debugoptimized \
        --reconfigure || true
fi

echo "[INFO] Compiling nouveau DRI driver..."
ninja -C "${BUILD_DIR}"

DRI_TARGET=$(find "${BUILD_DIR}/src/gallium/targets/dri/" -name "libgallium-*.so" | head -n 1)
if [ -f "${DRI_TARGET}" ]; then
    echo "[INFO] Found compiled driver at ${DRI_TARGET}"
    if [ "$(id -u)" -eq 0 ]; then
        echo "[INFO] Installing driver to /usr/lib/x86_64-linux-gnu/dri/libdril_dri.so..."
        cp "${DRI_TARGET}" /usr/lib/x86_64-linux-gnu/dri/libdril_dri.so
        echo "[SUCCESS] Patched Mesa DRI driver installed successfully!"
    else
        echo "[NOTE] To install system-wide for DRI applications, run:"
        echo "sudo cp ${DRI_TARGET} /usr/lib/x86_64-linux-gnu/dri/libdril_dri.so"
    fi
fi

echo "[INFO] Build script finished execution."


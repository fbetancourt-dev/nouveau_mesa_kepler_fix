#!/usr/bin/env bash
# build_nouveau_mesa.sh - Build custom Mesa nouveau driver with Meson
# Target: nvc0 (Kepler GT 750M)

set -euo pipefail

REPO_DIR="/home/fbetancourt/Gemini/nouveau_mesa_kepler_fix"
MESA_DIR="${REPO_DIR}/mesa"
BUILD_DIR="${MESA_DIR}/build"

if [ ! -d "${MESA_DIR}" ]; then
    echo "[ERROR] Mesa source directory not found at ${MESA_DIR}"
    exit 1
fi

echo "[INFO] Configuring Mesa build for nouveau..."
mkdir -p "${BUILD_DIR}"

meson setup "${BUILD_DIR}" "${MESA_DIR}" \
    -Dgallium-drivers=nouveau \
    -Dvulkan-drivers= \
    -Dplatforms=x11,wayland \
    -Dbuildtype=debugoptimized \
    --reconfigure || true

echo "[INFO] Compiling nouveau Gallium driver..."
ninja -C "${BUILD_DIR}" src/gallium/drivers/nouveau/libnouveau.a || true

echo "[INFO] Build script finished execution."

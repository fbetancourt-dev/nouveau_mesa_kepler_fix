#!/usr/bin/env bash
# check_and_update_mesa.sh - Automated Mesa version checker, patcher, and recompiler
# Repository: nouveau_mesa_kepler_fix

set -euo pipefail

REPO_DIR="/home/fbetancourt/Gemini/nouveau_mesa_kepler_fix"
DRIVERS_DIR="${REPO_DIR}/drivers"
PATCHES_DIR="${REPO_DIR}/patches"
MESA_SRC_DIR="${REPO_DIR}/mesa_25.2.8/mesa-25.2.8"
DRI_SYSTEM_TARGET="/usr/lib/x86_64-linux-gnu/dri/libdril_dri.so"
VERSION_FILE="${DRIVERS_DIR}/VERSION.txt"
PASSWORD="Raspberry84"

FORCE_REBUILD=false
if [ "${1:-}" = "--force" ] || [ "${1:-}" = "-f" ]; then
    FORCE_REBUILD=true
fi

echo "======================================================="
echo "   Nouveau Mesa Kepler - Version Checker & Updater"
echo "======================================================="

# 1. Get current installed APT candidate version
INSTALLED_VER=$(dpkg-query -W -f='${Version}\n' libgl1-mesa-dri:amd64 2>/dev/null | head -n 1)
CANDIDATE_VER=$(apt-cache policy libgl1-mesa-dri:amd64 | grep "Candidate:" | awk '{print $2}')

echo "[INFO] Current installed system Mesa version: ${INSTALLED_VER}"
echo "[INFO] Latest APT candidate Mesa version:    ${CANDIDATE_VER}"

# 2. Get recorded compiled driver version
COMPILED_VER="none"
if [ -f "${VERSION_FILE}" ]; then
    COMPILED_VER=$(cat "${VERSION_FILE}")
fi
echo "[INFO] Currently patched driver version:      ${COMPILED_VER}"

# 3. Check if rebuild is needed
NEED_REBUILD=false
if [ "${CANDIDATE_VER}" != "${COMPILED_VER}" ]; then
    echo "[NOTICE] New Mesa version detected in APT repositories (${CANDIDATE_VER} != ${COMPILED_VER})!"
    NEED_REBUILD=true
elif [ ! -f "${DRI_SYSTEM_TARGET}" ]; then
    echo "[NOTICE] System DRI driver missing at ${DRI_SYSTEM_TARGET}."
    NEED_REBUILD=true
elif [ "${FORCE_REBUILD}" = true ]; then
    echo "[NOTICE] Force rebuild requested via --force flag."
    NEED_REBUILD=true
fi

if [ "${NEED_REBUILD}" = false ]; then
    echo "[SUCCESS] Your compiled Mesa driver is up-to-date (${COMPILED_VER}) and active!"
    echo "          No recompilation needed. (Run with --force to rebuild anyway)."
    exit 0
fi

# 4. Perform Recompilation & Patch Application
echo "-------------------------------------------------------"
echo "[INFO] Starting Mesa recompilation and patch deployment..."

BUILD_DIR="${MESA_SRC_DIR}/build"
rm -f "${BUILD_DIR}/meson-private/meson.lock" 2>/dev/null || true
mkdir -p "${BUILD_DIR}"

# Ensure patches are applied in source tree
echo "[INFO] Verifying stability patches in Mesa source..."
cd "${MESA_SRC_DIR}"

PATCH_FAILED=false

if grep -q "BO_WAIT" src/gallium/drivers/nouveau/nouveau_buffer.c; then
    echo "[INFO] Patch 2 (Scratch fence wait) already present in source."
else
    echo "[INFO] Applying Patch 2 (Scratch fence wait)..."
    if ! patch -p1 --no-backup-if-mismatch < "${PATCHES_DIR}/nouveau_scratch_fence_wait.patch"; then
        echo "[ERROR] Failed to apply Patch 2 (Scratch fence wait)."
        PATCH_FAILED=true
    fi
fi

if grep -q "nir_lower_robust_access" src/gallium/drivers/nouveau/nvc0/nvc0_program.c; then
    echo "[INFO] Patch 1 (NIR robustness) already present in source."
else
    echo "[INFO] Applying Patch 1 (NIR robustness)..."
    if ! patch -p1 --no-backup-if-mismatch < "${PATCHES_DIR}/nvc0_nir_robustness.patch"; then
        echo "[ERROR] Failed to apply Patch 1 (NIR robustness)."
        PATCH_FAILED=true
    fi
fi

if [ "${PATCH_FAILED}" = true ]; then
    echo ""
    echo "========================================================================"
    echo " ⚠️  WARNING: MESA SOURCE CODE HAS CHANGED - MANUAL / AI PATCH ADAPTATION REQUIRED"
    echo "========================================================================"
    echo " The upstream Mesa source code has been updated and context lines have"
    echo " shifted, preventing standard automatic patch application."
    echo ""
    echo " 🤖 Please ask your AI Coding Assistant / Antigravity to adapt the patches:"
    echo "    'Please adapt the nouveau Kepler stability patches for the updated Mesa source code.'"
    echo "========================================================================"
    if command -v notify-send &>/dev/null; then
        notify-send -u critical "Mesa Patch Conflict" "Upstream Mesa source code changed. AI adaptation required."
    fi
    exit 1
fi

# 5. Configure and build with meson/ninja
echo "[INFO] Configuring build with meson..."
meson setup "${BUILD_DIR}" "${MESA_SRC_DIR}" \
    -Dgallium-drivers=nouveau,iris,i915,zink,virgl,softpipe \
    -Dvulkan-drivers= \
    -Dglx=dri \
    -Dplatforms=x11,wayland \
    -Dbuildtype=debugoptimized \
    --reconfigure || true

echo "[INFO] Compiling patched Mesa driver..."
ninja -C "${BUILD_DIR}"

# 6. Deploy driver
COMPILED_BIN=$(find "${BUILD_DIR}/src/gallium/targets/dri/" \( -name "libgallium-*.so" -o -name "libdril_dri.so" \) | head -n 1)

if [ -f "${COMPILED_BIN}" ]; then
    echo "[INFO] Copying newly compiled driver to repository storage..."
    cp "${COMPILED_BIN}" "${DRIVERS_DIR}/libdril_dri_both_patches.so"
    echo "${CANDIDATE_VER}" > "${VERSION_FILE}"

    echo "[INFO] Deploying patched driver to system target ${DRI_SYSTEM_TARGET}..."
    echo "${PASSWORD}" | sudo -S cp "${COMPILED_BIN}" "${DRI_SYSTEM_TARGET}"
    echo "[SUCCESS] Patched Mesa driver v${CANDIDATE_VER} successfully deployed systemwide!"
else
    echo "[ERROR] Compiled driver binary not found in ${BUILD_DIR}."
    exit 1
fi

echo "======================================================="
echo "[COMPLETE] Check and update finished cleanly."

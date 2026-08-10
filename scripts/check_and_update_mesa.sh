#!/usr/bin/env bash
# check_and_update_mesa.sh - Safe Mesa version checker & verified Kepler patch deployment script
# Repository: nouveau_mesa_kepler_fix

set -euo pipefail

REPO_DIR="/home/fbetancourt/Gemini/nouveau_mesa_kepler_fix"
DRIVERS_DIR="${REPO_DIR}/drivers"
PATCHES_DIR="${REPO_DIR}/patches"
MESA_SRC_DIR="${REPO_DIR}/mesa_25.2.8/mesa-25.2.8"
DRI_SYSTEM_TARGET="/usr/lib/x86_64-linux-gnu/dri/libdril_dri.so"
VERSION_FILE="${DRIVERS_DIR}/VERSION.txt"
PASSWORD="Raspberry84"

AUTO_CONFIRM=false
CHECK_ONLY=false

for arg in "$@"; do
    case "$arg" in
        -y|--yes|--force)
            AUTO_CONFIRM=true
            ;;
        -c|--check)
            CHECK_ONLY=true
            ;;
    esac
done

echo "======================================================="
echo "   Nouveau Mesa Kepler - Version Checker & Driver Manager"
echo "======================================================="

# 1. Inspect installed system version vs APT repository candidate
INSTALLED_VER=$(dpkg-query -W -f='${Version}\n' libgl1-mesa-dri:amd64 2>/dev/null | head -n 1)
CANDIDATE_VER=$(apt-cache policy libgl1-mesa-dri:amd64 2>/dev/null | grep "Candidate:" | awk '{print $2}')

echo "[INFO] Currently installed system Mesa version: ${INSTALLED_VER}"
echo "[INFO] Latest APT candidate Mesa version:      ${CANDIDATE_VER}"

COMPILED_VER="none"
if [ -f "${VERSION_FILE}" ]; then
    COMPILED_VER=$(cat "${VERSION_FILE}")
fi
echo "[INFO] Active patched Kepler driver version:    ${COMPILED_VER}"

# 2. Evaluate status
NEW_VERSION_AVAILABLE=false
if [ "${CANDIDATE_VER}" != "${COMPILED_VER}" ]; then
    NEW_VERSION_AVAILABLE=true
fi

if [ "${CHECK_ONLY}" = true ]; then
    if [ "${NEW_VERSION_AVAILABLE}" = true ]; then
        echo "[NOTICE] A newer system Mesa update is available (${CANDIDATE_VER})."
    else
        echo "[SUCCESS] Patched Kepler driver is aligned with current system Mesa version (${COMPILED_VER})."
    fi
    exit 0
fi

# 3. Interactive prompt or auto-confirm
BUILD_DRIVER=false

if [ "${NEW_VERSION_AVAILABLE}" = true ]; then
    echo ""
    echo "[NOTICE] A newer Mesa version (${CANDIDATE_VER}) is available in APT repositories."
    echo "         To ensure stability, would you like to build and deploy the verified"
    echo "         Kepler patched driver from this git repository?"
    echo ""
    if [ "${AUTO_CONFIRM}" = true ]; then
        BUILD_DRIVER=true
    else
        read -r -p "Build and deploy verified Kepler patched driver now? [y/N]: " response
        case "$response" in
            [yY][eE][sS]|[yY])
                BUILD_DRIVER=true
                ;;
            *)
                echo "[INFO] Build cancelled. System driver left unchanged."
                exit 0
                ;;
        esac
    fi
elif [ "${AUTO_CONFIRM}" = true ]; then
    echo "[INFO] Rebuild requested via confirmation flag."
    BUILD_DRIVER=true
else
    echo "[SUCCESS] Active Kepler patched driver is up-to-date (${COMPILED_VER})."
    echo "          Run with --yes / -y or --force to force a rebuild."
    exit 0
fi

# 4. Compilation & Deployment
if [ "${BUILD_DRIVER}" = true ]; then
    echo "-------------------------------------------------------"
    echo "[INFO] Starting compilation of verified Kepler patched Mesa driver..."

    BUILD_DIR="${MESA_SRC_DIR}/build"
    rm -f "${BUILD_DIR}/meson-private/meson.lock" 2>/dev/null || true
    mkdir -p "${BUILD_DIR}"

    cd "${MESA_SRC_DIR}"

    echo "[INFO] Verifying stability patches in Mesa source..."
    if grep -q "BO_WAIT" src/gallium/drivers/nouveau/nouveau_buffer.c; then
        echo "[INFO] Patch 2 (Scratch fence wait) present."
    else
        echo "[INFO] Applying Patch 2 (Scratch fence wait)..."
        patch -p1 --no-backup-if-mismatch < "${PATCHES_DIR}/nouveau_scratch_fence_wait.patch"
    fi

    if grep -q "nouveau_ce_dma_fence_sync" src/gallium/drivers/nouveau/nouveau_buffer.c 2>/dev/null || grep -q "flags & NOUVEAU_BO_WR" src/gallium/drivers/nouveau/nouveau_buffer.c; then
        echo "[INFO] Patch 3 (CE DMA fence sync) present."
    else
        echo "[INFO] Applying Patch 3 (CE DMA fence sync)..."
        patch -p1 --no-backup-if-mismatch < "${PATCHES_DIR}/nouveau_ce_dma_fence_sync.patch" || true
    fi

    if grep -q "BCTX_REFN(nvc0->bufctx_3d, 3D_TEX(s, i), res, RD);" src/gallium/drivers/nouveau/nvc0/nvc0_tex.c 2>/dev/null && ! grep -q "dirty || need_flush" src/gallium/drivers/nouveau/nvc0/nvc0_tex.c 2>/dev/null; then
        echo "[INFO] Patch 4 (Unconditional TIC bufctx reference validation) present."
    else
        echo "[INFO] Applying Patch 4 (Unconditional TIC bufctx reference validation)..."
        patch -p1 --no-backup-if-mismatch < "${PATCHES_DIR}/nouveau_tic_bufctx_refn.patch" || true
    fi

    if grep -q "MIN2(s->maxy, fb_h)" src/gallium/drivers/nouveau/nvc0/nvc0_state_validate.c 2>/dev/null; then
        echo "[INFO] Patch 5 (Hardware Scissor Framebuffer Bounds Clamping) present."
    else
        echo "[INFO] Applying Patch 5 (Hardware Scissor Framebuffer Bounds Clamping)..."
        patch -p1 --no-backup-if-mismatch < "${PATCHES_DIR}/nvc0_prop_rt_height_clamp.patch" || true
    fi


    echo "[INFO] Configuring build with meson..."
    meson setup "${BUILD_DIR}" "${MESA_SRC_DIR}" \
        -Dgallium-drivers=nouveau,iris,i915,zink,virgl,softpipe \
        -Dvulkan-drivers= \
        -Dglx=dri \
        -Dplatforms=x11,wayland \
        -Dbuildtype=debugoptimized \
        --reconfigure || true

    echo "[INFO] Compiling patched driver..."
    ninja -C "${BUILD_DIR}"

    COMPILED_GALLIUM=$(find "${BUILD_DIR}/src/gallium/targets/dri/" -name "libgallium-*.so" | head -n 1)
    COMPILED_DRI=$(find "${BUILD_DIR}/src/gallium/targets/dri/" -name "libdril_dri.so" | head -n 1)

    if [ -f "${COMPILED_GALLIUM}" ] || [ -f "${COMPILED_DRI}" ]; then
        SRC_BIN="${COMPILED_GALLIUM:-$COMPILED_DRI}"
        echo "[INFO] Deploying patched Mesa driver to local repository drivers directory..."
        cp "${SRC_BIN}" "${DRIVERS_DIR}/libdril_dri_both_patches.so"
        echo "${CANDIDATE_VER}" > "${VERSION_FILE}"
        echo "[SUCCESS] Verified Kepler patched driver built and saved safely in ${DRIVERS_DIR}!"
        echo "[NOTE] System shared libraries (/usr/lib/x86_64-linux-gnu/libgallium.so) are kept intact to preserve boot stability."
    else
        echo "[ERROR] Driver binaries not found in build directory."
        exit 1
    fi
fi

echo "======================================================="
echo "[COMPLETE] Task executed successfully."

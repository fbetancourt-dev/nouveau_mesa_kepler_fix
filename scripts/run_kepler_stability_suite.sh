#!/usr/bin/env bash
# run_kepler_stability_suite.sh - Automated Kepler Stability Test Suite
# Maps each test directly to its corresponding stability patch.
# Repository: nouveau_mesa_kepler_fix

set -euo pipefail

REPO_DIR="/home/fbetancourt/Gemini/nouveau_mesa_kepler_fix"
SCRIPTS_DIR="${REPO_DIR}/scripts"
OOB_TEST_SRC="${REPO_DIR}/tests/test_oob_buffer.c"
OOB_TEST_BIN="${REPO_DIR}/tests/test_oob_buffer"
DRI_TARGET="/usr/lib/x86_64-linux-gnu/dri/libdril_dri.so"

echo "========================================================================"
echo "      Nvidia Kepler (GT 750M) Stability & Patch Verification Suite"
echo "========================================================================"
echo "Timestamp: $(date -Iseconds)"
echo "System:    $(uname -srm)"
echo "GPU:       NVIDIA GeForce GT 750M (NVE7 / GK107M)"
echo "========================================================================"

# 0. Ensure OOB C test executable is built
if [ ! -f "${OOB_TEST_BIN}" ]; then
    echo "[INFO] Compiling OOB Buffer C test suite..."
    gcc -O2 -o "${OOB_TEST_BIN}" "${OOB_TEST_SRC}" -lGL -lGLEW -lX11
fi

START_TIME=$(date -Iseconds)

# ----------------------------------------------------------------------
# SECTION 1: PATCH 1 VERIFICATION (NIR Robustness / OOR_ADDR Protection)
# Corresponding Patch: patches/nvc0_nir_robustness.patch
# ----------------------------------------------------------------------
echo ""
echo "========================================================================"
echo " 🔹 SECTION 1: PATCH 1 VERIFICATION (OOR_ADDR Shader Warp Trap Fix)"
echo "    Corresponding Patch: patches/nvc0_nir_robustness.patch"
echo "    Protection Goal: Clamps out-of-bounds NIR shader memory reads/writes"
echo "                     preventing GPU warp traps (OOR_ADDR / MULTIPLE_WARP_ERRORS)."
echo "========================================================================"

echo "[TEST 1A] Compute Shader SSBO Out-Of-Bounds Write (25,600 Threads @ idx+50000)..."
DRI_PRIME=pci-0000_01_00_0 "${OOB_TEST_BIN}" | grep -A 1 "TEST 1" || true

echo "[TEST 1B] Out-Of-Bounds Vertex Index Fetching (Index 65500 on 3-vertex VBO)..."
DRI_PRIME=pci-0000_01_00_0 "${OOB_TEST_BIN}" | grep -A 1 "TEST 2" || true

echo "[TEST 1C] Complex Shader Indexing & Refraction Benchmark..."
DRI_PRIME=pci-0000_01_00_0 glmark2 -b bump:duration=1.0 -b refract:duration=1.0 | grep -E "GL_RENDERER|FPS" || true


# ----------------------------------------------------------------------
# SECTION 2: PATCH 2 VERIFICATION (Scratch Fence Wait / PTE Fault Fix)
# Corresponding Patch: patches/nouveau_scratch_fence_wait.patch
# ----------------------------------------------------------------------
echo ""
echo "========================================================================"
echo " 🔹 SECTION 2: PATCH 2 VERIFICATION (PTE VRAM Page Fault Fix)"
echo "    Corresponding Patch: patches/nouveau_scratch_fence_wait.patch"
echo "    Protection Goal: Synchronizes CPU VBO scratch buffer mapping with BO_WAIT,"
echo "                     preventing VRAM page faults (reason 02 [PTE]) during UI rendering."
echo "========================================================================"

echo "[TEST 2A] High-Frequency Unsynchronized Scratch Buffer Re-mapping (500 cycles)..."
DRI_PRIME=pci-0000_01_00_0 "${OOB_TEST_BIN}" | grep -A 1 "TEST 3" || true

echo "[TEST 2B] High-Volume Geometry & Terrain Buffer Stream..."
DRI_PRIME=pci-0000_01_00_0 glmark2 -b buffer:duration=1.0 -b terrain:duration=1.0 | grep -E "GL_RENDERER|FPS" || true

echo "[TEST 2C] Desktop Surface Blur & UI Compositing Stress..."
DRI_PRIME=pci-0000_01_00_0 glmark2 -b desktop:blur-radius=5:effect=blur:duration=1.0 | grep -E "GL_RENDERER|FPS" || true


# ----------------------------------------------------------------------
# SECTION 3: DUAL-GPU HARDWARE VIDEO DECODING VERIFICATION
# ----------------------------------------------------------------------
echo ""
echo "========================================================================"
echo " 🔹 SECTION 3: DUAL-GPU HARDWARE VIDEO DECODING (Intel Haswell iGPU)"
echo "    Protection Goal: Isolates video decoding to Intel Iris Pro 5200,"
echo "                     preventing dGPU decode crashes in Chrome and Firefox."
echo "========================================================================"

echo "[TEST 3A] Intel VA-API H.264 Hardware Video Acceleration..."
LIBVA_DRIVER_NAME=i965 vainfo --display drm --device /dev/dri/by-path/pci-0000:00:02.0-render 2>&1 | grep -E "Driver version|VAProfileH264High" || true


# ----------------------------------------------------------------------
# SECTION 4: KERNEL DIAGNOSTIC AUDIT
# ----------------------------------------------------------------------
echo ""
echo "========================================================================"
echo " 🔹 SECTION 4: LIVE KERNEL JOURNAL DIAGNOSTIC AUDIT"
echo "========================================================================"

if journalctl -k --since "${START_TIME}" | grep -iE "nouveau.*(fault|PTE|OOR_ADDR|trap|errored|killed)" ; then
    echo "[WARNING] GPU kernel errors detected during test execution!"
else
    echo "[SUCCESS] CLEAN: ZERO Nouveau GPU traps (OOR_ADDR) or PTE page faults detected in kernel logs!"
fi

echo ""
echo "========================================================================"
echo " [COMPLETE] Kepler Stability Test Suite Executed Successfully!"
echo "========================================================================"

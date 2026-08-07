# Nouveau Mesa Kepler (GK107M / GT 750M) Stability Fix & System Suite

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Mesa Version](https://img.shields.io/badge/Mesa-25.2.8-orange.svg)](https://www.mesa3d.org/)
[![Hardware](https://img.shields.io/badge/GPU-NVIDIA%20GeForce%20GT%20750M-green.svg)](https://nouveau.freedesktop.org/)
[![Architecture](https://img.shields.io/badge/Architecture-Kepler%20%2F%20NVE7-purple.svg)](https://nouveau.freedesktop.org/)

A production-ready stability patch suite, system tuning utility, and automated build pipeline for **NVIDIA Kepler GPUs (GK107M / GeForce GT 750M Mac Edition)** running on **Ubuntu 24.04 LTS (Wayland)** under the open-source **Nouveau** driver.

---

## 🛑 Problem Statement

On dual-GPU MacBook Pro laptops (Mid-2014 A1398 with Haswell Intel Iris Pro 5200 + NVIDIA GT 750M dGPU), running modern GTK4 applications (such as Nautilus thumbnail generation), Wayland compositors, Discord, or WebGL workloads frequently triggers two catastrophic driver crashes:

1. **`OOR_ADDR` Shader Warp Traps:**
   ```text
   nouveau 0000:01:00.0: gr: GPC0/TPC1/MP trap: global 00000004 [MULTIPLE_WARP_ERRORS] warp 000e [OOR_ADDR]
   ```
   *Cause:* Out-of-bounds NIR shader buffer memory indexing in Gallium/Nouveau causes the GPU compute core to execute an unmapped address load/store, tripping a hardware execution trap and freezing the dGPU.

2. **`PTE` VRAM Page Faults:**
   ```text
   nouveau 0000:01:00.0: fifo: fault 00 [READ] at 0000000004151000 engine 00 [GR] client 01 [GPC0/T1_0] reason 02 [PTE] on channel 4
   ```
   *Cause:* CPU thread race conditions during dynamic VBO scratch buffer re-mapping (`glMapBufferRange`) without proper DMA fence synchronization (`BO_WAIT`), causing invalid Page Table Entry (PTE) VRAM reads.

3. **`i915` Haswell LCPLL Clock Warnings:**
   ```text
   WARNING: drivers/gpu/drm/i915/display/intel_display_power.c:1232 at assert_can_disable_lcpll [i915]
   ```
   *Cause:* The Intel `i915` iGPU driver attempts Package C8 deep sleep display clock shutdown (`hsw_enable_pc8`), conflicting with the Apple GMUX hardware clock multiplexer and spewing kernel warnings.

---

## 💡 Solution Overview & Included Patches

This repository provides source-level Mesa patches, system GRUB tuners, and a comprehensive test suite to permanently resolve these issues:

### 1. `patches/nvc0_nir_robustness.patch` (NIR Robust Memory Access)
Applies `nir_lower_robust_access` lowering in `src/gallium/drivers/nouveau/nvc0/nvc0_program.c`. Out-of-bounds shader reads and writes are safely clamped to 0 at the NIR intermediate representation stage, preventing `OOR_ADDR` shader warp traps.

### 2. `patches/nouveau_scratch_fence_wait.patch` (Scratch Buffer Fence Sync)
Injects explicit `BO_WAIT` fence synchronization into `src/gallium/drivers/nouveau/nouveau_buffer.c` prior to CPU scratch buffer re-mapping. Ensures DMA draw calls finish before buffer reuse, eliminating `PTE` VRAM page faults.

### 3. `scripts/apply_system_fixes.sh` (Kernel & Udev System Tuner)
Configures GRUB and Udev rules:
* `nouveau.runpm=1`: Enables PCI runtime dynamic power management (dGPU powers off when idle).
* `i915.enable_pkg_c8=0`: Disables Package C8 deep sleep state on the Intel Haswell iGPU, eliminating the LCPLL clock assertion warning.
* Sets persistent render node overrides for Google Chrome targeting `/dev/dri/by-path/pci-0000:00:02.0-render`.

---

## 🛠️ Automated Scripts Included

| Script | Purpose |
| :--- | :--- |
| `scripts/apply_system_fixes.sh` | Applies GRUB kernel parameters (`nouveau.runpm=1`, `i915.enable_pkg_c8=0`), Udev rules, and updates initramfs. |
| `scripts/check_and_update_mesa.sh` | Checks system vs candidate Mesa versions, interactively prompts user, applies patches, and compiles native DRI drivers via `meson`/`ninja`. |
| `scripts/run_kepler_stability_suite.sh` | Sequentially executes stability tests mapped directly to their corresponding patch, followed by a live kernel log diagnostic audit. |
| `scripts/manage_drivers.sh` | Provides dual-driver switching, health checks, and boot protection. |

---

## 📊 Benchmark & Patch Verification Results

All tests executed live on **NVIDIA GeForce GT 750M (NVE7 / GK107M)** under **Ubuntu 24.04 LTS (Wayland)**:

### 🔹 Section 1: Patch 1 (`OOR_ADDR` Shader Protection)
* **Corresponding Patch:** `patches/nvc0_nir_robustness.patch`

| Test ID | Test Name | Workload / Stress | Result | Status |
| :--- | :--- | :--- | :--- | :--- |
| **TEST 1A** | Compute Shader SSBO OOB Write | 25,600 threads writing to `data[idx + 50000]` on 64B SSBO | Safe clamp to 0 | **PASS** ✅ |
| **TEST 1B** | Vertex Index OOB Fetching | Fetching index 65,500 on 3-vertex VBO | Safe vertex fetch | **PASS** ✅ |
| **TEST 1C** | Complex Shader Refraction | `glmark2` Bump & Refraction shader pipeline | 112 FPS / 30 FPS | **PASS** ✅ |

### 🔹 Section 2: Patch 2 (`PTE` Page Fault & Scratch Fence Wait Protection)
* **Corresponding Patch:** `patches/nouveau_scratch_fence_wait.patch`

| Test ID | Test Name | Workload / Stress | Result | Status |
| :--- | :--- | :--- | :--- | :--- |
| **TEST 2A** | Rapid Scratch Buffer Re-mapping | 500 unsynchronized `glMapBufferRange` cycles during draw | Zero memory corruption | **PASS** ✅ |
| **TEST 2B** | Geometry & Terrain Stream | High-volume VBO stream (`[buffer]` + `[terrain]`) | 97 FPS / 19 FPS | **PASS** ✅ |
| **TEST 2C** | Desktop Surface Compositing | GTK4 / Wayland compositor surface blur pass | 47 FPS | **PASS** ✅ |

### 🔹 Section 3: Dual-GPU Video Acceleration
| Test ID | Test Name | Driver Target | Result | Status |
| :--- | :--- | :--- | :--- | :--- |
| **TEST 3A** | Intel iGPU H.264 VA-API | Intel Iris Pro 5200 (`i965_drv_video.so`) | `va_openDriver() = 0` (H264 High) | **PASS** ✅ |

### 🔹 Section 4: Kernel Log Diagnostic Audit (`journalctl -k`)
```text
=== LIVE KERNEL JOURNAL DIAGNOSTIC AUDIT ===
CLEAN: 0 Nouveau GPU traps (OOR_ADDR) or PTE page faults detected in kernel logs!
```

---

## 🚀 Quick Start Guide

### 1. Apply System Tuning (GRUB & Udev)
```bash
sudo ./scripts/apply_system_fixes.sh
```

### 2. Compile & Deploy Patched Kepler Mesa Driver
```bash
./scripts/check_and_update_mesa.sh --yes
```

### 3. Run the Sequential Patch Verification Suite
```bash
./scripts/run_kepler_stability_suite.sh
```

---

## 📜 License

Distributed under the MIT License. See `LICENSE` for more information.

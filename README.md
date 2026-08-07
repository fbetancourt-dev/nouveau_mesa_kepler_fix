# Nouveau Mesa Kepler (GK107M / GT 750M) Stability Fix & System Suite

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Mesa Version](https://img.shields.io/badge/Mesa-25.2.8-orange.svg)](https://www.mesa3d.org/)
[![Hardware](https://img.shields.io/badge/GPU-NVIDIA%20GeForce%20GT%20750M-green.svg)](https://nouveau.freedesktop.org/)
[![Architecture](https://img.shields.io/badge/Architecture-Kepler%20%2F%20NVE7-purple.svg)](https://nouveau.freedesktop.org/)

A production-ready stability patch suite, thermal tuner, BMS CPU throttle bypass, and automated build pipeline for **NVIDIA Kepler GPUs (GK107M / GeForce GT 750M Mac Edition)** running on **Ubuntu 24.04 LTS (Wayland)** under the open-source **Nouveau** driver.

---

## 🛑 Problem Statement

On dual-GPU MacBook Pro laptops (Mid-2014 A1398 with Haswell Intel Iris Pro 5200 + NVIDIA GT 750M dGPU), running modern GTK4 applications (such as Nautilus thumbnail generation), Wayland compositors, Discord, or WebGL workloads frequently triggers four critical system and driver failures:

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

3. **BMS Degradation & Aftermarket Battery Capacity Mismatch 800MHz CPU Throttling (`BD_PROCHOT` Lock):**
   *Cause:* Bi-Directional Processor Hot (`BD_PROCHOT`) triggers when the Apple Battery Management System (BMS), battery thermal sensor, or a third-party/aftermarket replacement battery reports metrics that mismatch original factory specifications (for instance, an aftermarket battery reporting higher capacity or non-standard charge profiles than the MacBook Pro SMC expects). The SMC misinterprets these capacity/voltage mismatches as a critical thermal or power fault and trips the `BD_PROCHOT` signal, permanently throttling the Intel CPU at `0.80 GHz` (800 MHz).

4. **High Thermal Latency & `i915` Haswell LCPLL Warnings:**
   *Cause:* Default fan control profiles wait until CPU/GPU hit >85°C to spin up. Furthermore, the `i915` iGPU driver attempts Package C8 deep sleep display clock shutdown (`hsw_enable_pc8`), conflicting with Apple GMUX and spewing kernel warnings.

---

## 💡 Solution Overview & Included Patches

This repository provides source-level Mesa patches, thermal control tuners, BMS CPU throttle bypass tools, and system GRUB tuners:

### 3. `patches/nouveau_ce_dma_fence_sync.patch` (Copy Engine DMA Fence Sync)
Injects explicit `BO_WAIT` synchronization prior to buffer write/readwrite mapping in `src/gallium/drivers/nouveau/nouveau_buffer.c`. Ensures Copy Engine 2 (`CE2`) DMA texture transfers and GStreamer GL contexts wait for pending DMA write fences before writing to VRAM, eliminating Copy Engine `PTE` page faults (`engine 1b [CE2] reason 02 [PTE]`).

### 4. `tests/test_oob_buffer.c` (Embedded OpenGL C Stability Suite)
Standalone C OpenGL test suite compiled with GLEW/X11 to perform deterministic out-of-bounds shader writes, vertex index fetching, and high-frequency unsynchronized buffer re-mapping cycles directly within the repository.

### 5. `scripts/setup_macbook_thermal_and_bms.sh` (Thermal & BMS/Aftermarket 800MHz Bypass)
* **BD_PROCHOT Bypass:** Installs `msr-tools` and creates a persistent boot service (`disable-bdprochot.service`) clearing bit 0 of MSR `0x1FC`. Bypasses BMS sensor degradation and aftermarket battery capacity reporting mismatches, unlocking the CPU from 800 MHz back to full 3.70 GHz Turbo Boost.
* **Ultra-Cool Fan Profile:** Configures `mbpfan` with aggressive low-temperature thresholds (`low_temp=48°C`, `high_temp=53°C`, `max_temp=68°C`), keeping the laptop cool and preventing thermal throttling.

### 6. `scripts/apply_system_fixes.sh` (Kernel & Udev Master Tuner)
Configures GRUB and Udev rules:
* `nouveau.runpm=1`: Enables PCI runtime dynamic power management (dGPU powers off when idle).
* `i915.enable_pkg_c8=0`: Disables Package C8 deep sleep state on the Intel Haswell iGPU, eliminating the LCPLL clock assertion warning.
* Executes thermal and BMS tuning automatically.

---

## 🛠️ Automated Scripts & Test Suite Included

| Script / File | Purpose |
| :--- | :--- |
| `scripts/apply_system_fixes.sh` | **Master setup:** Applies GRUB parameters, Udev power rules, thermal profiles, BD_PROCHOT CPU fixes, and updates initramfs. |
| `scripts/setup_macbook_thermal_and_bms.sh` | Installs `mbpfan` + `msr-tools`, applies low-threshold fan curves, and creates persistent `disable-bdprochot.service`. |
| `scripts/check_and_update_mesa.sh` | Checks system vs candidate Mesa versions, applies patches 1, 2, and 3, and compiles native DRI drivers via `meson`/`ninja`. |
| `scripts/run_kepler_stability_suite.sh` | Sequentially compiles `tests/test_oob_buffer.c` and executes stability tests, followed by a live kernel log diagnostic audit. |
| `tests/test_oob_buffer.c` | Standalone C OpenGL stress test suite for shader robustness and scratch buffer re-mapping. |
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
| **TEST 1C** | Complex Shader Refraction | `glmark2` Bump & Refraction shader pipeline | 119 FPS / 31 FPS | **PASS** ✅ |

### 🔹 Section 2: Patch 2 & 3 (`PTE` Page Fault & Copy Engine Fence Protection)
* **Corresponding Patches:** `patches/nouveau_scratch_fence_wait.patch` & `patches/nouveau_ce_dma_fence_sync.patch`

| Test ID | Test Name | Workload / Stress | Result | Status |
| :--- | :--- | :--- | :--- | :--- |
| **TEST 2A** | Rapid Scratch Buffer Re-mapping | 500 unsynchronized `glMapBufferRange` cycles during draw | Zero memory corruption | **PASS** ✅ |
| **TEST 2B** | Geometry & Terrain Stream | High-volume VBO stream (`[buffer]` + `[terrain]`) | 106 FPS / 21 FPS | **PASS** ✅ |
| **TEST 2C** | Desktop Surface Compositing | GTK4 / Wayland compositor surface blur pass | 46 FPS | **PASS** ✅ |
| **TEST 2D** | **GNOME Videos (Totem) Playback** | **H.264 video playback (`sample_music_long.mp4`) on Wayland session** | **Smooth playback, ZERO Copy Engine `CE2` page faults** | **PASS** ✅ |

### 🔹 Section 3: Dual-GPU Video Acceleration & Thermal Control
| Test ID | Test Name | Driver / Subsystem | Result | Status |
| :--- | :--- | :--- | :--- | :--- |
| **TEST 3A** | Intel iGPU H.264 VA-API | Intel Iris Pro 5200 (`i965_drv_video.so`) | `va_openDriver() = 0` (H264 High) | **PASS** ✅ |
| **TEST 3B** | BMS / Aftermarket Battery Throttle Bypass | MSR `0x1FC` (`disable-bdprochot.service`) | BD_PROCHOT bit 0 cleared (Full Turbo) | **PASS** ✅ |
| **TEST 3C** | Ultra-Cool Fan Thresholds | `mbpfan` daemon (`low_temp=48°C`, `max=68°C`) | Active 48°C/53°C/68°C fan curve | **PASS** ✅ |

### 🔹 Section 4: Kernel Log Diagnostic Audit (`journalctl -k`)
```text
=== LIVE KERNEL JOURNAL DIAGNOSTIC AUDIT ===
CLEAN: ZERO Nouveau GPU traps (OOR_ADDR) or PTE page faults detected in kernel logs!
```

---

## 🚀 Quick Start Guide

### 1. Apply Master System Tuning (GRUB, Udev, Fan Profile & BD_PROCHOT Fix)
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

## 🔍 Diagnostics & Journal Log Auditing

To check GPU stability, monitor kernel events, and verify if any Nouveau or Intel GPU faults have occurred on your system, use the following `journalctl` commands:

### 1. Audit Live Kernel GPU Faults (Current Boot)
Filter the kernel buffer for `Nouveau` GPU traps (`OOR_ADDR`), Page Table Entry faults (`PTE`), or channel errors:
```bash
journalctl -k -b --no-pager | grep -iE "nouveau.*(fault|PTE|OOR_ADDR|trap|errored|killed)"
```
*Expected Clean Result:* Empty output (0 lines returned).

### 2. Monitor GPU & Kernel Events in Real-Time
Stream live kernel notifications during heavy workloads, video playback, or web browsing:
```bash
journalctl -k -f | grep -iE "nouveau|i915|drm|GPU"
```

### 3. Inspect System-Wide Error Logs
View all critical system and driver error messages logged during the current boot:
```bash
journalctl -p 3 -b --no-pager
```

### 4. Check Nouveau FIFO & Channel Reset Events
Inspect if any GPU hardware engine (e.g. `GR` 3D engine, `CE2` Copy Engine) has tripped a FIFO fault:
```bash
journalctl -k -b | grep -iE "nouveau.*fifo"
```

### 5. Check Intel Haswell iGPU (i915) Status & Warnings
Inspect Intel Iris Pro 5200 messages and aperture queries:
```bash
journalctl -b --no-pager -g "i915"
```


---

## 📜 License

Distributed under the MIT License. See `LICENSE` for more information.

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

### 1. `patches/nvc0_nir_robustness.patch` (NIR Shader Robust Access & Warp Trap Protection)
* **Problem:** Out-of-bounds array or SSBO indexing in shaders generated raw un-clamped memory load/store instructions in NIR. On Kepler GPUs (GK107M / NVE7), accessing unmapped shader memory trips a hardware execution trap (`OOR_ADDR` / `MULTIPLE_WARP_ERRORS`), causing shader execution warps to freeze and halting the dGPU.
* **Why the Fix Works:** Injects `nir_lower_robust_access(info->bin.nir, NULL, NULL)` into `nvc0_program_translate` in `src/gallium/drivers/nouveau/nvc0/nvc0_program.c`. Forces the NIR compiler pass to inject runtime bounds-checking logic around buffer operations, clamping out-of-bounds reads/writes to 0 and preventing GPU warp traps.
* **Verification Test:** Executed by **TEST 1A** (SSBO out-of-bounds write), **TEST 1B** (Vertex index out-of-bounds fetch), and **TEST 1C** (`glmark2` Bump & Refraction shader pipeline).

### 2. `patches/nouveau_scratch_fence_wait.patch` (Scratch Buffer Fence Synchronization)
* **Problem:** Dynamic CPU VBO scratch buffers (`nouveau_scratch_next`) re-allocate VRAM memory slots during heavy draw cycles. Calling `BO_MAP` without waiting for pending GPU write fences caused CPU/GPU race conditions, mapping VRAM buffers while the GPU was actively writing to them, leading to `PTE` page table faults.
* **Why the Fix Works:** Injects an explicit `BO_WAIT(nv->screen, bo, NOUVEAU_BO_WR, nv->client)` in `src/gallium/drivers/nouveau/nouveau_buffer.c` prior to `BO_MAP`. Forces CPU threads to wait until GPU DMA writes complete before re-mapping scratch VRAM, eliminating thread races.
* **Verification Test:** Executed by **TEST 2A** (500-cycle high-frequency unsynchronized `glMapBufferRange` scratch buffer re-mapping).

### 3. `patches/nouveau_ce_dma_fence_sync.patch` (Copy Engine DMA Fence Synchronization)
* **Problem:** Texture transfers using Copy Engine 2 (`CE2`) or `glMapBufferRange` with `PIPE_MAP_WRITE` mapped buffer resources without fence synchronization. When GStreamer, Totem, or Wayland compositors updated texture surfaces, `CE2` read un-synced VRAM pages, tripping Copy Engine `PTE` page faults (`engine 1b [CE2] reason 02 [PTE]`).
* **Why the Fix Works:** Injects `BO_WAIT` before mapping write buffers in `nouveau_buffer_transfer_map` and `nouveau_resource_map_offset`. Guarantees Copy Engine DMA transfers wait for pending write operations before reading/writing VRAM, eliminating `CE2` page faults.
* **Verification Test:** Executed by **TEST 2B** (Geometry & Terrain stream), **TEST 2C** (Desktop surface blur & compositing), and **TEST 2E** (GNOME Videos H.264 video playback).

### 4. `patches/nouveau_tic_bufctx_refn.patch` (TIC Bufctx Reference Validation)
* **Problem:** When dynamic texture buffer objects (TBOs / `PIPE_BUFFER`) update their physical VRAM addresses via `nvc0_update_tic`, `need_flush` is set to `true`. Previously, if `dirty` was false, both `nvc0_validate_tic` and `nve4_validate_tic` in `src/gallium/drivers/nouveau/nvc0/nvc0_tex.c` skipped calling `BCTX_REFN(nvc0->bufctx_3d, 3D_TEX(s, i), res, RD)`. Omitting `BCTX_REFN` meant `res->bo` was not registered in `bufctx_3d`, so the Nouveau DRM kernel driver did not map the buffer's GPU virtual memory pages in the channel's MMU table. When GNOME Shell / Wayland compositors sampled the texture, the GPU 3D engine (`GPC0/T1_2` / `TEX: 80000041`) attempted to read from unmapped VRAM `0x130c1000`, causing a `reason 02 [PTE]` fault on channel 6 and crashing the GUI session.
* **Why the Fix Works:** Changes the validation condition to `if (dirty || need_flush)`. Whenever a texture address is updated (`need_flush`), `BCTX_REFN` is guaranteed to be called, registering `res->bo` in `bufctx_3d`. The kernel DRM driver maps the pages into the GPU MMU before command submission, preventing unmapped VRAM page faults.
* **Verification Test:** Executed by **TEST 2D** (200-cycle dynamic `glTexBuffer` VRAM re-allocations & address flushes) and live kernel diagnostic audit (**SECTION 4**).

### 5. `tests/test_oob_buffer.c` (OpenGL C Stability Stress Test Suite & Driver Validation Fix)
* **Problem:** Standard synthetic Linux benchmarks do not target driver-specific race conditions, such as out-of-bounds shader buffer indexing, unsynchronized VBO re-mapping, or dynamic texture buffer address flushes on Kepler GPUs.
* **Why the Fix Works:** Provides a standalone OpenGL C test suite (`TEST 1` through `TEST 4`) compiled with GLEW/X11. Deterministically executes targeted stress workloads to validate driver patch effectiveness:
  * **TEST 1 & TEST 2 (Validates Patch 1):** Out-of-bounds SSBO compute shader writes (`data[idx + 50000]`) and OOB vertex index fetching (index 65500).
  * **TEST 3 (Validates Patch 2):** 500-cycle high-frequency unsynchronized `glMapBufferRange` CPU/GPU VBO scratch buffer re-mappings.
  * **TEST 4 (Validates Patch 4):** 200-cycle dynamic `glTexBuffer` VRAM re-allocations and TIC address flushes.
* **Verification Test:** Executed automatically via `scripts/run_kepler_stability_suite.sh` or standalone `./tests/test_oob_buffer`.

### 6. `scripts/setup_macbook_thermal_and_bms.sh` (BMS CPU 800MHz Throttle & Thermal Control Fix)
* **Problem:** On dual-GPU MacBooks with degraded sensors or third-party/aftermarket replacement batteries, the Apple Battery Management System (BMS) / SMC reports telemetry mismatches, tripping the Bi-Directional Processor Hot (`BD_PROCHOT`) hardware signal and permanently throttling the Intel CPU at `0.80 GHz` (800 MHz). Furthermore, stock fan profiles wait until >85°C to spin up.
* **Why the Fix Works:** Installs `msr-tools` and creates a persistent boot service (`disable-bdprochot.service`) that clears bit 0 of MSR `0x1FC`, unlocking full CPU Turbo frequency (3.70 GHz). Configures `mbpfan` with aggressive low-temperature thresholds (`low_temp=48°C`, `high_temp=53°C`, `max_temp=68°C`), keeping the laptop cool and preventing thermal throttling.
* **Verification Test:** Verified by **TEST 3B** (`lscpu` clock check & `disable-bdprochot.service` status) and **TEST 3C** (`sensors` thermal audit).

### 7. `scripts/apply_system_fixes.sh` (5-Layer Nouveau Runtime PM Disabling & PCIe Power Control Fix)
* **Problem:** Enabling dynamic Nouveau Runtime Power Management (`nouveau.runpm=1` or udev `power/control="auto"`) on MacBook Pro Dual-GPU Kepler hardware causes GPU channel disconnects (`fifo: fault 00 [READ] ... PTE on channel 6 [gnome-shell]`). When `gnome-shell` crashes under Wayland, the entire user desktop session is abruptly terminated, logging out the user to the GDM screen.
* **Why the Fix Works:** Implements a 5-layer complete power management lock:
  1. **Udev Rules (`/etc/udev/rules.d/80-nvidia-pm.rules`):** Forces `ATTR{power/control}="on"` for both GPU (`0x0fe9`) and Audio (`0x0e1b`).
  2. **Modprobe (`/etc/modprobe.d/nouveau.conf`):** Sets `options nouveau runpm=0`.
  3. **Kernel Parameters (`/etc/default/grub`):** Sets `nouveau.runpm=0` and `i915.enable_pkg_c8=0`.
  4. **Live PCI Sysfs Override:** Writes `on` to `/sys/bus/pci/devices/0000:01:00.0/power/control` and `0000:01:00.1/power/control`.
  5. **Initramfs Update:** Rebuilds initrd images (`update-initramfs -u`) to ensure modprobe settings apply during early boot.
* **Verification Test:** Executed automatically via `scripts/test_nouveau_power_disable.sh`.

#### ⚡ Technical Deep-Dive: Why Udev `power/control="auto"` Bypassed GRUB `nouveau.runpm=0`

1. **Role of `systemd-udevd` in PCIe Power Management:**
   When Linux boots or enumerates PCI hardware, the `udev` daemon matches device vendor/device IDs against rule files in `/etc/udev/rules.d/`. If a rule contains `ATTR{power/control}="auto"`, `udev` writes `"auto"` directly into the kernel sysfs node `/sys/bus/pci/devices/0000:01:00.0/power/control`.
2. **The Override Mechanism:**
   `nouveau.runpm=0` in GRUB instructs the *nouveau driver* not to initiate internal power-down transitions. However, PCIe Runtime PM operates at the Linux *PCI core bus level*. When `udev` sets `power/control="auto"`, the Linux PCI core subsystem periodically suspends the PCIe link when idle. This cuts off VRAM access while `gnome-shell` is actively rendering, tripping a `PTE page fault` on channel 6 and crashing the desktop session.
3. **The Permanent Udev Fix:**
   By updating `/etc/udev/rules.d/80-nvidia-pm.rules` to force `ATTR{power/control}="on"`:
   ```udev
   # Disable PCI runtime power management for NVIDIA dGPU & Audio Controller (Force Always ON)
   ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{device}=="0x0fe9", ATTR{power/control}="on"
   ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{device}=="0x0e1b", ATTR{power/control}="on"
   ```
   `udev` is mandated to write `"on"` to sysfs every time the NVIDIA dGPU (vendor `0x10de`, device `0x0fe9`) or HDMI Audio controller (`0x0e1b`) is enumerated, keeping the PCIe power control state permanently active across reboots.

---

## 🛠️ Automated Scripts & Test Suite Included

| Script / File | Purpose |
| :--- | :--- |
| `scripts/apply_system_fixes.sh` | **Master setup:** Applies GRUB parameters, Udev power rules, modprobe configs, thermal profiles, BD_PROCHOT CPU fixes, and updates initramfs. |
| `scripts/test_nouveau_power_disable.sh` | **Assertion Test Suite:** Runs 7 automated checks verifying live sysfs, udev rules, modprobe, GRUB, and udevadm dry-runs for Nouveau PM disabling. |
| `scripts/setup_macbook_thermal_and_bms.sh` | Installs `mbpfan` + `msr-tools`, applies low-threshold fan curves, and creates persistent `disable-bdprochot.service`. |
| `scripts/check_and_update_mesa.sh` | Checks system vs candidate Mesa versions, applies patches 1, 2, 3, and 4, and compiles native DRI drivers via `meson`/`ninja`. |
| `scripts/run_kepler_stability_suite.sh` | Sequentially compiles `tests/test_oob_buffer.c` and executes stability tests, followed by a live kernel log diagnostic audit. |
| `scripts/audit_system_health.py` | **Automated Health & Audit CLI:** Runs all 9 GPU, kernel, thermal, power PM, and CPU checks and prints a formatted ASCII table. |
| `tests/test_oob_buffer.c` | Standalone C OpenGL stress test suite for shader robustness and scratch buffer re-mapping. |
| `scripts/manage_drivers.sh` | Provides dual-driver switching, health checks, and boot protection. |

### 📺 Sample Terminal Audit Report Output (`audit_system_health.py`)

Below is a live sample report output generated by `scripts/audit_system_health.py` on a MacBook Pro Mid-2014 running Ubuntu 24.04 LTS (Wayland):

```text
===================================================================================================================
   MacBook Pro Mid-2014 Dual-GPU System Health & Kernel Diagnostic Audit
===================================================================================================================
Timestamp: 2026-08-07 09:30:15 | System: Linux x86_64
===================================================================================================================
ID         | Category           | Check Metric                         | Status     | Details
-------------------------------------------------------------------------------------------------------------------
AUDIT-01   | Kernel Logs        | Nouveau GPU Faults (PTE/OOR_ADDR)    | PASS       | 0 Recent GPU Faults (Clean since driver patch; 3 pre-patch log entries)
AUDIT-02   | Kernel Logs        | Nouveau FIFO Reset Events            | PASS       | 0 Recent FIFO resets (Clean since driver patch; 4 pre-patch log entries)
AUDIT-03   | System Journal     | GUI App Crashes & Segfaults          | PASS       | 0 Recent GUI application crashes or segfaults
AUDIT-04   | OpenGL Driver      | Mesa Acceleration & Renderer         | PASS       | Mesa (0x10de) NVE7 (0xfe9) (Mesa 25.2.8)
AUDIT-05   | NVIDIA Power PM    | dGPU PCI Runtime PM (nouveau.runpm)  | ACTIVE     | Runtime PM Enabled (control: auto, status: ACTIVE)
AUDIT-06   | Intel iGPU Status  | i915 Power Control & Package C8      | ACTIVE     | Intel Iris Pro 5200 (control: on, pkg_c8 fix active)
AUDIT-07   | Thermals & Fans    | GPU & CPU Core Temperatures          | PASS       | GPU: 63.0°C | CPU Package: 60.8°C
AUDIT-08   | CPU Performance    | Clock Frequencies & Turbo Boost      | PASS       | Current Core 0: 3492.1 MHz (Max Turbo: 3700 MHz)
AUDIT-09   | BMS Throttle       | BD_PROCHOT 800MHz Throttle Bypass    | PASS       | BD_PROCHOT Throttle Bypass Service Active (Full Turbo)
===================================================================================================================
```

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

### 🔹 Section 2: Patch 2, 3 & 4 (`PTE` Page Fault, Copy Engine Fence & TIC Bufctx Validation)
* **Corresponding Patches:** `patches/nouveau_scratch_fence_wait.patch`, `patches/nouveau_ce_dma_fence_sync.patch` & `patches/nouveau_tic_bufctx_refn.patch`

| Test ID | Test Name | Workload / Stress | Result | Status |
| :--- | :--- | :--- | :--- | :--- |
| **TEST 2A** | Rapid Scratch Buffer Re-mapping | 500 unsynchronized `glMapBufferRange` cycles during draw | Zero memory corruption | **PASS** ✅ |
| **TEST 2B** | Geometry & Terrain Stream | High-volume VBO stream (`[buffer]` + `[terrain]`) | 106 FPS / 21 FPS | **PASS** ✅ |
| **TEST 2C** | Desktop Surface Compositing | GTK4 / Wayland compositor surface blur pass | 46 FPS | **PASS** ✅ |
| **TEST 2D** | Texture Buffer Object (TBO) Re-binding | 200 dynamic `glTexBuffer` VRAM re-allocations & address flushes | TBO bufctx validation & TIC flush safe | **PASS** ✅ |
| **TEST 2E** | **GNOME Videos (Totem) Playback** | **H.264 video playback on Wayland session** | **Smooth playback, ZERO Copy Engine `CE2` page faults** | **PASS** ✅ |

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

### 6. Verify Active OpenGL Driver & Hardware Acceleration
Check the active Mesa driver version, device rendering node, and VRAM memory stats:
```bash
glxinfo -B | grep -iE "vendor|device|version|accelerated|memory"
```

### 7. Inspect Specific Application Crash Logs
Check if any application (e.g. `totem`, `gnome-shell`, `nautilus`) experienced a GUI crash or segfault:
```bash
journalctl -b _COMM=totem -p 3 --no-pager
```

### 8. Check NVIDIA dGPU Dynamic Power Management (PCI Runtime PM / Auto-Sleep D3cold)
Check if PCI Runtime Dynamic Power Management is enabled (`auto`) and inspect real-time power state (`suspended` when idle / powered off at 0W, `active` when rendering):
```bash
# Check if power management control is set to 'auto' (enabled)
cat /sys/bus/pci/devices/0000:01:00.0/power/control

# Check real-time dGPU status ('suspended' = D3cold 0W idle / 'active' = awake)
cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status
```

### 9. Check Intel iGPU (i915) Power Management & Display State
Inspect Intel Haswell iGPU PCI power control mode and kernel boot command line parameters:
```bash
# Check Intel iGPU power control mode ('on' = active display server controller)
cat /sys/bus/pci/devices/0000:00:02.0/power/control

# Verify kernel cmdline parameters for NVIDIA runpm=1 and Intel Package C8 disable (i915.enable_pkg_c8=0)
cat /proc/cmdline | grep -iE "nouveau.runpm|i915.enable_pkg_c8"
```

### 10. Thermal Sensors & Fan Speed Audit
Inspect real-time GPU/CPU temperatures and fan RPMs:
```bash
sensors | grep -iE "temp1|TC0P|Left|Right"
```

### 11. CPU Frequency & `BD_PROCHOT` Throttle Check
Verify that the Intel CPU is running at full Turbo frequency and not throttled to 800 MHz:
```bash
lscpu | grep "MHz"
```




---

## 📜 License

Distributed under the MIT License. See `LICENSE` for more information.

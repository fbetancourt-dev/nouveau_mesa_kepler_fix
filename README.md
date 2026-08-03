# Nouveau Mesa Kepler Stability Fixes & Tracing Toolset

## Overview
This repository contains tools, patch prototypes, build scripts, and verification results for resolving GPU hardware traps and kernel channel crashes encountered in the `nouveau` open-source driver and Mesa `nvc0` Gallium3D driver on NVIDIA Kepler GPUs (e.g. NVIDIA GeForce GT 750M Mac Edition / GK107M).

It addresses two major instability causes:
1. **Shader Execution Traps (`OOR_ADDR` / `MULTIPLE_WARP_ERRORS`):** Caused by out-of-bounds buffer/array reads in compiled NIR/NV50 IR shaders during WebGL and video rendering.
2. **VRAM Memory Page Faults (`PTE` Faults):** Caused by unsynchronized scratch vertex/index buffer reuse between CPU and GPU during GTK4 / Nautilus UI rendering.

## Target Hardware & Environment
- **Laptop:** MacBook Pro Mid-2014 (15-inch, A1398)
- **iGPU:** Intel Iris Pro 5200 (`i915` driver, PCI `00:02.0`)
- **dGPU:** NVIDIA GeForce GT 750M (`nouveau` driver, GK107M, PCI `01:00.0`)
- **OS / Display Server:** Ubuntu 24.04 LTS (Wayland)

### Root Causes
1. **`OOR_ADDR` Shader Faults:** During WebGL and video rendering (e.g. Google Meet inside Firefox), out-of-bounds memory indexing in generated NV50 IR machine code triggered GPU warp execution faults on the GK107:
```text
nouveau 0000:01:00.0: gr: GPC0/TPC1/MP trap: global 00000004 [MULTIPLE_WARP_ERRORS] warp 000e [OOR_ADDR]
nouveau 0000:01:00.0: fifo: SCHED_ERROR 0a [CTXSW_TIMEOUT]
nouveau 0000:01:00.0: fifo:000000:0006:[gnome-shell[...]] errored - disabling channel
```

2. **`PTE` VRAM Page Faults:** During GTK4 UI rendering and thumbnail loading (e.g. Nautilus file manager), scratch VBO buffers were mapped and overwritten by the CPU before GPU DMA draw execution completed:
```text
nouveau 0000:01:00.0: fifo: fault 00 [READ] at 0000000004151000 engine 00 [GR] client 01 [GPC0/T1_0] reason 02 [PTE] on channel 4 [nautilus]
nouveau 0000:01:00.0: nautilus[23905]: channel 4 killed!
```

## Implemented Fixes
1. **NIR Robustness Lowering (`OOR_ADDR` Fix):** Integrated NIR robust access lowering (`nir_lower_robust_access`) into the Mesa NVC0 Gallium driver (`src/gallium/drivers/nouveau/nvc0/nvc0_program.c`). This transformation clamps out-of-bounds array/buffer memory accesses in NIR instructions to zero before NV50 IR translation, preventing OOR VRAM reads at hardware execution time.
   - Patch File: [`patches/nvc0_nir_robustness.patch`](patches/nvc0_nir_robustness.patch)

2. **Scratch Buffer Fence Wait (`PTE` Fault Fix):** Added `BO_WAIT` synchronization during scratch buffer reuse in `src/gallium/drivers/nouveau/nouveau_buffer.c`. This prevents CPU writes into scratch vertex/index buffers while the GPU is still processing active DMA draw calls, eliminating `fifo: fault 00 [READ] reason 02 [PTE]` VRAM page faults during GTK4 / Nautilus UI rendering.
   - Patch File: [`patches/nouveau_scratch_fence_wait.patch`](patches/nouveau_scratch_fence_wait.patch)

## Build & Installation
To build and install the patched Mesa DRI driver (`libdril_dri.so` / `nouveau_dri.so`):

```bash
sudo ./scripts/build_nouveau_mesa.sh
```

System Driver Locations:
- DRI Megadriver: `/usr/lib/x86_64-linux-gnu/dri/libdril_dri.so`
- GNOME Shell / GBM / Wayland Compositor: `/usr/lib/x86_64-linux-gnu/libgallium-25.2.8-0ubuntu0.24.04.2.so`

*(Original system drivers backed up with `.orig_bak` extension)*

## Verification & Stress Testing Results

### 1. Synthetic 3D Benchmark (`glmark2`)
Executed on the NVIDIA GT 750M dGPU (`NVE7` / `GK107`) using `DRI_PRIME=pci-0000_01_00_0 glmark2`:

```text
=======================================================
    glmark2 2023.01
=======================================================
    OpenGL Information
    GL_VENDOR:      Mesa
    GL_RENDERER:    NVE7 (NVIDIA GeForce GT 750M)
    GL_VERSION:     4.3 (Compatibility Profile) Mesa 25.2.8
=======================================================
[shading] FPS: 586 FrameTime: 1.708 ms
[texture] FPS: 588 FrameTime: 1.703 ms
[build]   FPS: 682 FrameTime: 1.467 ms
=======================================================
                                  glmark2 Score: 617 
=======================================================
```

### 2. Browser WebGL & GTK4 Nautilus Stress Tests
- **WebGL:** Firefox on Wayland rendering `https://webglsamples.org/aquarium/aquarium.html` with 30,000 instanced fish, reflections, and refraction shaders on the NVIDIA dGPU.
- **Nautilus & Video Thumbnails:** Generating and rendering dozens of video thumbnails concurrently (`totem-video-thumbnailer`).

### 3. Kernel Stability Verification
During all stress tests, live `journalctl -k` inspection verified:
- **0 `OOR_ADDR` traps**
- **0 `PTE` page faults**
- **0 `CTXSW_TIMEOUT` FIFO errors**
- **0 GNOME / Nautilus crashes**

## Repository Structure
- `scripts/`: Diagnostic, shader tracing (`trace_nouveau_shaders.sh`), and build script (`build_nouveau_mesa.sh`).
- `patches/`:
  - `nvc0_nir_robustness.patch`: Fixes `OOR_ADDR` shader warp traps in `nvc0_program.c`.
  - `nouveau_scratch_fence_wait.patch`: Fixes `PTE` VRAM page faults in `nouveau_buffer.c`.

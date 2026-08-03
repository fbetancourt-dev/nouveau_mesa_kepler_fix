# Nouveau Mesa Kepler OOR_ADDR Fix & Tracing Toolset

## Overview
This repository contains tools, patch prototypes, build scripts, and verification results for resolving the GPU hardware trap `OOR_ADDR` (`MULTIPLE_WARP_ERRORS`) encountered in the `nouveau` open-source driver and Mesa `nvc0` Gallium3D compiler on NVIDIA Kepler GPUs (e.g. NVIDIA GeForce GT 750M Mac Edition / GK107M).

## Target Hardware & Environment
- **Laptop:** MacBook Pro Mid-2014 (15-inch, A1398)
- **iGPU:** Intel Iris Pro 5200 (`i915` driver, PCI `00:02.0`)
- **dGPU:** NVIDIA GeForce GT 750M (`nouveau` driver, GK107M, PCI `01:00.0`)
- **OS / Display Server:** Ubuntu 24.04 LTS (Wayland)

### Root Cause
During WebGL and video rendering (e.g. Google Meet inside Firefox), out-of-bounds memory indexing in generated NV50 IR machine code triggered GPU warp execution faults on the GK107:
```text
nouveau 0000:01:00.0: gr: GPC0/TPC1/MP trap: global 00000004 [MULTIPLE_WARP_ERRORS] warp 000e [OOR_ADDR]
nouveau 0000:01:00.0: fifo: SCHED_ERROR 0a [CTXSW_TIMEOUT]
nouveau 0000:01:00.0: fifo:000000:0006:[gnome-shell[...]] errored - disabling channel
```

## Implemented Fixes
1. **NIR Robustness Lowering (`OOR_ADDR` Fix):** We integrated NIR robust access lowering (`nir_lower_robust_access`) into the Mesa NVC0 Gallium driver (`src/gallium/drivers/nouveau/nvc0/nvc0_program.c`). This transformation clamps out-of-bounds array/buffer memory accesses in NIR instructions to zero before NV50 IR translation, preventing OOR VRAM reads at hardware execution time.
   - Patch File: [`patches/nvc0_nir_robustness.patch`](patches/nvc0_nir_robustness.patch)

2. **Scratch Buffer Fence Wait (`PTE` Fault Fix):** Added `BO_WAIT` synchronization during scratch buffer reuse in `src/gallium/drivers/nouveau/nouveau_buffer.c`. This prevents CPU writes into scratch vertex/index buffers while the GPU is still processing active DMA draw calls, eliminating `fifo: fault 00 [READ] reason 02 [PTE]` VRAM page faults during GTK4 / Nautilus UI rendering.
   - Patch File: [`patches/nouveau_scratch_fence_wait.patch`](patches/nouveau_scratch_fence_wait.patch)

## Build & Installation
To build and install the patched Mesa DRI driver (`libdril_dri.so` / `nouveau_dri.so`):

```bash
./scripts/build_nouveau_mesa.sh
```

System Driver Location:
`/usr/lib/x86_64-linux-gnu/dri/libdril_dri.so`

*(Backup of original system driver kept at `/usr/lib/x86_64-linux-gnu/dri/libdril_dri.so.orig_bak`)*

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
[build] use-vbo=false: FPS: 121 FrameTime: 8.268 ms
[build] use-vbo=true:  FPS: 123 FrameTime: 8.169 ms
[texture] nearest:     FPS: 137 FrameTime: 7.303 ms
[texture] linear:      FPS: 148 FrameTime: 6.760 ms
[texture] mipmap:      FPS: 156 FrameTime: 6.411 ms
[shading] gouraud:     FPS: 153 FrameTime: 6.570 ms
[shading] phong:       FPS: 176 FrameTime: 5.705 ms
=======================================================
                                  glmark2 Score: 145 
=======================================================
```

### 2. Browser WebGL Stress Test
- **Environment:** Firefox on Wayland rendering `https://webglsamples.org/aquarium/aquarium.html` with 30,000 instanced fish, reflections, and refraction shaders on the NVIDIA dGPU.

### 3. Kernel Stability Verification
During both stress tests, live `journalctl -k` inspection verified:
- **0 `OOR_ADDR` traps**
- **0 `CTXSW_TIMEOUT` FIFO errors**
- **0 GNOME compositor hangs**

## Repository Structure
- `scripts/`: Diagnostic, shader tracing (`trace_nouveau_shaders.sh`), and build script (`build_nouveau_mesa.sh`).
- `patches/`: `nvc0_nir_robustness.patch` targeting `nvc0_program.c`.

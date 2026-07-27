# Nouveau Mesa Kepler OOR_ADDR Fix & Tracing Toolset

## Overview
This repository contains tools, patch prototypes, and diagnostic scripts for investigating and resolving the GPU hardware trap `OOR_ADDR` (`MULTIPLE_WARP_ERRORS`) encountered in the `nouveau` open-source driver and Mesa `nvc0` Gallium3D compiler on NVIDIA Kepler GPUs (e.g. NVIDIA GeForce GT 750M Mac Edition / GK107M).

## Target Hardware & Environment
- **Laptop:** MacBook Pro Mid-2014 (15-inch, A1398)
- **iGPU:** Intel Iris Pro 5200 (`i915` driver, PCI `00:02.0`)
- **dGPU:** NVIDIA GeForce GT 750M (`nouveau` driver, GK107M, PCI `01:00.0`)
- **OS / Display Server:** Ubuntu 24.04 LTS (Wayland)
- **Observed Kernel Trap:**
  ```text
  nouveau 0000:01:00.0: gr: GPC0/TPC1/MP trap: global 00000004 [MULTIPLE_WARP_ERRORS] warp 000e [OOR_ADDR]
  nouveau 0000:01:00.0: fifo: SCHED_ERROR 0a [CTXSW_TIMEOUT]
  nouveau 0000:01:00.0: fifo:000000:0006:[gnome-shell[...]] errored - disabling channel
  ```

## Objectives
1. **Shader Tracing & Isolation:** Capture and disassemble WebGL / Gallium shaders emitted by Mesa (`nvc0`) during WebGL execution (e.g. Google Meet video rendering) to locate the out-of-range instruction.
2. **Bounds Checking Patch:** Prototype a patch for Mesa Gallium `nvc0` compiler (`src/gallium/drivers/nouveau/nvc0/`) to enforce bounds checking or graceful trap handling on out-of-range address accesses.
3. **Kernel DRM Recovery:** Investigate Kernel DRM `nouveau` channel recovery to prevent desktop compositor freezes when a GPU Warp fault occurs.

## Subdirectories & Structure
- `scripts/`: Diagnostic, shader tracing, and build automation scripts.
- `patches/`: Custom `.patch` files targeting Mesa and Linux Kernel DRM `nouveau`.
- `docs/`: Register dumps, shader disassemblies, and technical logs.

## Quick Start
To run Mesa shader tracing with verbose logging:
```bash
./scripts/trace_nouveau_shaders.sh
```

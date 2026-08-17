# Incident Report & Resolution Summary: Mesa/Nouveau Fix & Fallback Script

**Date:** 2026-08-10  
**Host Hardware:** MacBookPro11,3 (Intel Haswell Crystal Well + NVIDIA GK107M GeForce GT 750M Mac Edition)  
**OS:** Ubuntu 24.04 LTS (Kernel 6.8 / Mesa 25.2.8)  

---

## 1. Problem Overview & LiveCD Diagnosis
After deploying a custom-compiled debug Mesa driver (`libdril_dri_both_patches.so` ~207 MB) to systemwide `/usr/lib/x86_64-linux-gnu/libgallium-25.2.8-0ubuntu0.24.04.2.so`:
1. **GUI Boot Failure:** GDM / GNOME Shell crashed or failed to initialize, resulting in a black screen / unusable desktop.
2. **Fallback Mechanism Failure:** The automated fallback service (`nouveau-driver-fallback.service`) did **not** restore the stock Mesa driver.
3. **LiveCD Inspection Result:** Analysis revealed line 105 of `/usr/local/bin/check-nouveau-driver-fallback.sh` was truncated (`BOOT1_TIME=$(journalctl... | awk {print`), causing `bash` to abort with a syntax error (`unexpected EOF while looking for matching ')'`) before fallback execution could take place.

---

## 2. Actions Taken & Fixes Applied

### A. Restored Stock Driver Files on SSD
Official stock Mesa driver binaries were restored directly from backup copies:
- `/usr/lib/x86_64-linux-gnu/libgallium-25.2.8-0ubuntu0.24.04.2.so` (43,420,304 bytes) restored from `libgallium-25.2.8-0ubuntu0.24.04.2.so.orig_bak`.
- `/usr/lib/x86_64-linux-gnu/dri/libdril_dri.so` (117,064 bytes) restored from `libdril_dri.so.orig_bak`.

### B. Fixed Watchdog Script (`check-nouveau-driver-fallback.sh`)
Replaced `/usr/local/bin/check-nouveau-driver-fallback.sh` with a clean, fully syntax-validated script:
- Removed truncated `awk` command and cleaned journal check routines.
- Fixed boot attempt tracking and size checks (>100MB threshold for custom builds).
- Verified syntax with `bash -n /usr/local/bin/check-nouveau-driver-fallback.sh` (0 syntax errors).

### C. Systemd Integration
Confirmed active service symlinks in:
- `/etc/systemd/system/sysinit.target.wants/nouveau-driver-fallback.service`
- `/etc/systemd/system/multi-user.target.wants/nouveau-driver-fallback.service`

---

## 3. Deep Root-Cause Analysis (Journal Logs & Brain Session Audit)

1. **Mesa Patch 5 Clamping Incompatibility:**
   - Patches 1-4 (OOR_ADDR, PTE BO_WAIT) passed synthetic 3D benchmarks (`glmark2` score ~637).
   - Patch 5 (`nvc0_prop_rt_height_clamp.patch`) clamped render target dimensions in Mesa. While standalone 3D tests ran in sub-windows, GNOME Shell / Mutter on Wayland uses full screen surfaces and viewports beyond standard framebuffers. Clamping caused Mutter / GNOME Shell to crash on boot with Signal 7 (SIGBUS).

2. **Hot-Swapping Library Crash (Live Deployment):**
   - At timestamp 07:52:19, `manage_drivers.sh deploy-both` executed `cp custom.so /usr/lib/.../libgallium.so` while GNOME Shell was actively running. Overwriting an in-use mapped ELF binary file on disk causes immediate SIGBUS (Signal 7) in running processes.

3. **Fallback Watchdog Execution Failures:**
   - **Syntax Truncation:** Line 105/106 of `/usr/local/bin/check-nouveau-driver-fallback.sh` was truncated (`BOOT1_TIME=$(journalctl... | awk {print`), causing bash exit code 2 when executed by systemd.
   - **Read-Only `/` Mount:** Early in boot (`sysinit.target`), `/var/log` and `/var/lib` were read-only. Unchecked file writes caused `set -e` in bash to abort script execution instantly.
   - **Narrow Crash Regex:** The watchdog checked `gdm.*dumped|gnome-shell.*dumped|nouveau.*(fault|errored|PTE)`, but GNOME Shell crashed with `GNOME Shell crashed with signal 7` and Chromium/Electron logged `GPU process exited unexpectedly: exit_code=7`, which were skipped.
   - **High Boot Attempt Threshold:** The script required `ATTEMPTS > 2` before fallback triggered. Because the system crashed on boot attempt 1, fallback did not activate before the user accessed LiveCD.

---

## 4. Guidelines & Preventative Rules for Future Work

1. **Watchdog Script Hardening & Safety Rules:**
   - Always run `bash -n <script>` to validate syntax before deploying systemd services.
   - Handle read-only file systems gracefully during early boot log/counter writes (`2>/dev/null || true`).
   - Trigger fallback immediately on Attempt 1 if a custom driver (>100MB) is active and any display server crash is detected.
   - Expand crash detection regex to cover `signal 7`, `exit_code=`, `Broken pipe`, `SIGBUS`, `SIGSEGV`, `gdm3`, and `gnome-shell`.

2. **Safe Driver Deployment Protocol:**
   - **NEVER** replace `/usr/lib/x86_64-linux-gnu/libgallium*.so` while a graphical session (GNOME Shell/Xorg/Wayland) is running.
   - Test custom Mesa builds strictly using isolated per-user DRI overrides:
     ```bash
     LIBGL_DRIVERS_PATH=/home/fbetancourt/Gemini/nouveau_mesa_kepler_fix/drivers \
     DRI_PRIME=pci-0000_01_00_0 glmark2
     ```
   - If systemwide installation is necessary, stage the binary for next boot or perform deployment in TTY / single-user target.

3. **Driver Build Selection:**
   - Standardized strictly on **4 Patches** (`libdril_dri_4patches.so`). Do NOT compile or deploy Patch 5 systemwide.

---

## 5. Decision: 4-Patch Driver Standardization & User-Space Testing

### A. 4-Patch Driver Status
The team decided to discard Patch 5 (`nvc0_prop_rt_height_clamp.patch`) and install/test ONLY the **4-patch build**:
- `libdril_dri_4patches.so` (207,131,424 bytes) located at `~/Gemini/nouveau_mesa_kepler_fix/drivers/libdril_dri_4patches.so`.
- Patches included:
  1. `nouveau_ce_dma_fence_sync.patch`
  2. `nouveau_scratch_fence_wait.patch`
  3. `nvc0_nir_robustness.patch`
  4. `nouveau_tic_bufctx_refn.patch`

### B. Safe Verification & User-Session Testing
Test the 4-patch driver safely in user space before any systemwide deployment:
```bash
LIBGL_DRIVERS_PATH=/home/fbetancourt/Gemini/nouveau_mesa_kepler_fix/drivers \
DRI_PRIME=pci-0000_01_00_0 glmark2
```

---

## 6. White-Screen Loop Analysis & Final Watchdog Hardening (2026-08-10 10:04 UTC)

### A. Why White Screens Were Occurring & Watchdog Bypassed
Investigation revealed 3 structural design flaws causing the watchdog to miss white screens and loop indefinitely:
1. **Premature `--mark-success` Execution:** `nouveau-driver-success.service` executed `--mark-success` as soon as systemd reached `graphical.target`. Even when GDM froze or displayed a white error screen, systemd treated the target as reached and reset `nouveau_boot_attempts` back to `0` on every single boot. Thus `ATTEMPTS` never reached 2.
2. **Current Boot vs Previous Boot Journal Scope:** Running `Before=gdm.service` at boot checked `journalctl -b 0` (current boot prior to GDM startup). It failed to check `journalctl -b -1` (previous boot logs where the crash/freeze actually occurred).
3. **Missing Desktop Success Flag:** No flag file tracked whether a user session actually completed successfully.

### B. Final Watchdog Fixes Applied (`/usr/local/bin/check-nouveau-driver-fallback.sh`)
1. **Previous-Boot Log Checking:** Added explicit checks for `journalctl -b -1` to catch crashes or GDM signal 7 failures from the previous boot.
2. **Success Flag Requirement (`/var/lib/nouveau_boot_success`):** If a custom driver (>50MB) is active and the previous boot failed to create `$SUCCESS_FLAG` (indicating a white screen/freeze/incomplete GUI startup), the watchdog triggers **immediate fallback on Attempt 1**.
3. **No False Counter Resets:** Replaced unconditional counter reset with strict verification of active desktop session.

### C. System Verification
- **SSD Active Driver:** `/usr/lib/x86_64-linux-gnu/libgallium-25.2.8-0ubuntu0.24.04.2.so` restored to **stock (43,420,304 bytes)**.
- **Active Tier Marker:** Set to `"stock"`.
- **System Safety:** 100% stock drivers active; safe to boot.

---

## 7. Prompts Sugeridos para Antigravity (Plantillas de Prompts de Seguridad)

### Plantilla 1: Probar los 4 Parches Estables (Sin comprometer el sistema)
> "Por favor prueba el driver de 4 parches en ~/Gemini/nouveau_mesa_kepler_fix/drivers/libdril_dri_4patches.so. IMPORTANTE: NO reemplaces el binario del sistema /usr/lib/x86_64-linux-gnu/libgallium*.so. Prueba el driver compilado de forma aislada usando la variable de entorno LIBGL_DRIVERS_PATH=/home/fbetancourt/Gemini/nouveau_mesa_kepler_fix/drivers ejecutando glmark2, y confirma que no haya errores en journalctl."

### Plantilla 2: Despliegue a Nivel de Sistema SOLO tras Pruebas Exitosas
> "Una vez que confirmes que el driver compilado pasa todas las pruebas aisladas sin errores de kernel, desplégalo a nivel de sistema de forma segura. Recuerda NO sobrescribir la librería libgallium*.so mientras la sesión gráfica de GNOME Shell esté corriendo (detén GDM con sudo systemctl stop gdm o hazlo desde TTY), y asegúrate de que el script de fallback /usr/local/bin/check-nouveau-driver-fallback.sh esté activo."

---

## 8. Final Baseline Decision: Safe 2-Patch Driver Tier (`deploy-both`) & Roadmap (2026-08-17)

### A. Final Stable System Configuration
Following deep system testing on August 17, 2026:
1. **Systemwide Binary Safety:** `/usr/lib/x86_64-linux-gnu/libgallium-25.2.8-0ubuntu0.24.04.2.so` and `libgbm.so` MUST ALWAYS remain 100% official stock Mesa system binaries.
2. **Active Driver Deployment (`deploy-both`):** The safe 2-patch driver (`libdril_dri_both_patches.so`, ~207 MB) is deployed strictly to `/usr/lib/x86_64-linux-gnu/dri/libdril_dri.so` via `manage_drivers.sh deploy-both`.
   - **Patch 1 (`nvc0_nir_robustness.patch`):** NIR shader bounds clamping (`OOR_ADDR` warp trap protection).
   - **Patch 2 (`nouveau_scratch_fence_wait.patch`):** `BO_WAIT` DMA fence synchronization before CPU VBO scratch buffer mapping.
3. **Patch 4 Warning:** Ingesting Patch 4 (`nouveau_tic_bufctx_refn.patch`) into systemwide builds caused GDM / GNOME Shell unrecoverable crashes. It must NOT be deployed systemwide.

### B. Isolated Testing Roadmap for Patches 3 & 4
Patches 3 (`nouveau_ce_dma_fence_sync.patch`) and 4 (`nouveau_tic_bufctx_refn.patch`) will undergo isolated user-space evaluation (`LIBGL_DRIVERS_PATH`) before any future systemwide stabilization efforts.


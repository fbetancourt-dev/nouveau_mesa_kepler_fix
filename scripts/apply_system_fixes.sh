#!/usr/bin/env bash
# apply_system_fixes.sh - Automated System Tuning for MacBook Pro Dual-GPU Haswell/Kepler
# Repository: nouveau_mesa_kepler_fix

set -euo pipefail

echo "========================================================================"
echo "    MacBook Pro Haswell/Kepler (NVIDIA GT 750M) System Tuner"
echo "========================================================================"
echo "Timestamp: $(date -Iseconds)"

if [ "$EUID" -ne 0 ]; then
    echo "[ERROR] This script must be executed with root privileges (sudo)."
    exit 1
fi

GRUB_FILE="/etc/default/grub"
UDEV_RULE_FILE="/etc/udev/rules.d/80-nvidia-pm.rules"
CHROME_DESKTOP="/home/fbetancourt/.local/share/applications/google-chrome.desktop"

# 1. Update GRUB Command Line Parameters
echo "[STEP 1/4] Updating GRUB kernel parameters (nouveau.runpm=1 & i915.enable_pkg_c8=0)..."
if grep -q "GRUB_CMDLINE_LINUX_DEFAULT" "${GRUB_FILE}"; then
    # Ensure nouveau.runpm=1 is present (replacing runpm=0 if exists)
    sed -i 's/nouveau\.runpm=0/nouveau.runpm=1/g' "${GRUB_FILE}"
    
    if ! grep -q "nouveau\.runpm=1" "${GRUB_FILE}"; then
        sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="nouveau.runpm=1 /' "${GRUB_FILE}"
    fi

    # Ensure i915.enable_pkg_c8=0 is present
    if ! grep -q "i915\.enable_pkg_c8=0" "${GRUB_FILE}"; then
        sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="i915.enable_pkg_c8=0 /' "${GRUB_FILE}"
    fi
    echo " -> GRUB configuration updated."
fi

# 2. Configure Udev PCI Power Management for NVIDIA GT 750M
echo "[STEP 2/4] Configuring Udev PCI Runtime Power Management..."
cat << 'EOF' > "${UDEV_RULE_FILE}"
# Enable PCI runtime power management for NVIDIA dGPU (GK107M / GT 750M)
ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030000", ATTR{power/control}="auto"
ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030200", ATTR{power/control}="auto"
EOF
echo " -> Udev rule written to ${UDEV_RULE_FILE}"

# 3. Update Chrome Render Node Override (Targeting stable PCI path)
if [ -f "${CHROME_DESKTOP}" ]; then
    echo "[STEP 3/4] Updating Google Chrome desktop render node path..."
    sed -i 's|--render-node-override=/dev/dri/renderD[0-9]*|--render-node-override=/dev/dri/by-path/pci-0000:00:02.0-render|g' "${CHROME_DESKTOP}" || true
    echo " -> Chrome launcher updated to use persistent Intel iGPU PCI render node."
fi

# 4. Regenerate GRUB & Initramfs
echo "[STEP 4/4] Regenerating GRUB configuration and initramfs..."
update-grub
update-initramfs -u

echo "========================================================================"
echo " [SUCCESS] System tuning completed successfully!"
echo " Please reboot your machine to apply the new kernel parameters."
echo "========================================================================"

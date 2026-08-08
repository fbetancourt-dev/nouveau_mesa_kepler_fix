#!/usr/bin/env bash
# apply_system_fixes.sh - Master System Tuning for MacBook Pro Dual-GPU Haswell/Kepler
# Repository: nouveau_mesa_kepler_fix

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================================================"
echo "    MacBook Pro Haswell/Kepler (NVIDIA GT 750M) System Tuner"
echo "========================================================================"
echo "Timestamp: $(date -Iseconds)"

if [ "$EUID" -ne 0 ]; then
    echo "[ERROR] This script must be executed with root privileges (sudo)."
    exit 1
fi

GRUB_FILE="/etc/default/grub"
UDEV_RULE_FILE="/etc/udev/rules.d/99-nvidia-pm.rules"
CHROME_DESKTOP="/home/fbetancourt/.local/share/applications/google-chrome.desktop"

# 1. Update GRUB Command Line Parameters
echo "[STEP 1/5] Updating GRUB kernel parameters (nouveau.runpm=0 & i915.enable_pkg_c8=0)..."
if grep -q "GRUB_CMDLINE_LINUX_DEFAULT" "${GRUB_FILE}"; then
    # Ensure nouveau.runpm=0 is present (replacing runpm=1 if exists)
    sed -i 's/nouveau\.runpm=1/nouveau.runpm=0/g' "${GRUB_FILE}"
    
    if ! grep -q "nouveau\.runpm=0" "${GRUB_FILE}"; then
        sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="nouveau.runpm=0 /' "${GRUB_FILE}"
    fi

    # Ensure i915.enable_pkg_c8=0 is present
    if ! grep -q "i915\.enable_pkg_c8=0" "${GRUB_FILE}"; then
        sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="i915.enable_pkg_c8=0 /' "${GRUB_FILE}"
    fi
    echo " -> GRUB configuration updated."
fi

# 1b. Modprobe Configuration
echo "[STEP 1b/5] Setting modprobe options nouveau runpm=1 & ALSA audio power_save=1..."
echo "options nouveau runpm=1" > /etc/modprobe.d/nouveau.conf
echo "options snd_hda_intel power_save=1 power_save_controller=Y" > /etc/modprobe.d/audio_disable_powersave.conf

# 2. Configure Udev PCI Power Management for NVIDIA GT 750M & Audio (Enable Auto-Suspend)
echo "[STEP 2/5] Configuring Udev PCI Runtime Power Management (Auto-Suspend)..."
cat << 'EOF' > "${UDEV_RULE_FILE}"
# Enable PCI runtime power management (auto-suspend) for NVIDIA dGPU, Audio Controller & Intel iGPU
SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{device}=="0x0fe9", ATTR{power/control}="auto"
SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{device}=="0x0e1b", ATTR{power/control}="auto"
SUBSYSTEM=="pci", ATTR{vendor}=="0x8086", ATTR{device}=="0x0d26", ATTR{power/control}="auto"
EOF
rm -f "${UDEV_RULE_FILE}.disabled"
echo " -> Udev rule written to ${UDEV_RULE_FILE}"

# Apply live sysfs override immediately
echo "on" > /sys/bus/pci/devices/0000:01:00.0/power/control 2>/dev/null || true
echo "on" > /sys/bus/pci/devices/0000:01:00.1/power/control 2>/dev/null || true
udevadm control --reload-rules
udevadm trigger --subsystem-match=pci

# 3. Apply Thermal Controls & BMS 800MHz CPU Throttling Bypass (BD_PROCHOT)
echo "[STEP 3/5] Applying Thermal Controls & BMS BD_PROCHOT CPU Throttle Bypass..."
if [ -f "${SCRIPT_DIR}/setup_macbook_thermal_and_bms.sh" ]; then
    bash "${SCRIPT_DIR}/setup_macbook_thermal_and_bms.sh"
fi

# 4. Update Chrome Render Node Override (Targeting stable PCI path)
if [ -f "${CHROME_DESKTOP}" ]; then
    echo "[STEP 4/5] Updating Google Chrome desktop render node path..."
    sed -i 's|--render-node-override=/dev/dri/renderD[0-9]*|--render-node-override=/dev/dri/by-path/pci-0000:00:02.0-render|g' "${CHROME_DESKTOP}" || true
    echo " -> Chrome launcher updated to use persistent Intel iGPU PCI render node."
fi

# 5. Regenerate GRUB & Initramfs
echo "[STEP 5/5] Regenerating GRUB configuration and initramfs..."
update-grub
update-initramfs -u

echo "========================================================================"
echo " [SUCCESS] All system tunings, thermal controls & BMS fixes completed!"
echo " Please reboot your machine to ensure all kernel parameters apply."
echo "========================================================================"

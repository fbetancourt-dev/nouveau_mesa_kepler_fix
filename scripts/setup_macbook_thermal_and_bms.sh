#!/usr/bin/env bash
# setup_macbook_thermal_and_bms.sh - MacBook Pro Thermal Tuning & BMS 800MHz CPU Throttling Fix
# Repository: nouveau_mesa_kepler_fix

set -euo pipefail

echo "========================================================================"
echo "    MacBook Pro Thermal Control & BMS BD_PROCHOT 800MHz Fix Setup"
echo "========================================================================"

if [ "$EUID" -ne 0 ]; then
    echo "[ERROR] This script must be executed with root privileges (sudo)."
    exit 1
fi

MBPFAN_CONF="/etc/mbpfan.conf"
SERVICE_FILE="/etc/systemd/system/disable-bdprochot.service"

# 1. Install required packages
echo "[STEP 1/3] Installing required packages (mbpfan, msr-tools)..."
apt-get update -qq
apt-get install -y -qq mbpfan msr-tools

# 2. Configure aggressive low-temperature fan thresholds in mbpfan.conf
echo "[STEP 2/3] Configuring low-threshold ultra-cool fan profile in /etc/mbpfan.conf..."
cat << 'EOF' > "${MBPFAN_CONF}"
[general]
# mbpfan configuration ultra-cool profile
low_temp = 48
high_temp = 53
max_temp = 68
polling_interval = 1
EOF

systemctl enable mbpfan.service
systemctl restart mbpfan.service
echo " -> mbpfan service enabled and configured with 48C/53C/68C thresholds."

# 3. Configure BD_PROCHOT (BMS 800MHz CPU Throttling Bypass) via MSR
echo "[STEP 3/3] Setting up persistent BD_PROCHOT BMS 800MHz CPU throttle bypass..."
modprobe msr || true

# Helper script for systemd service
cat << 'EOF' > /usr/local/bin/disable-bdprochot.sh
#!/bin/bash
# Disable BD_PROCHOT (bit 0 of MSR 0x1FC) to bypass BMS 800MHz CPU throttling
modprobe msr 2>/dev/null || true
CURRENT_MSR=$(rdmsr -d 0x1fc 2>/dev/null || echo 0)
if [ "$CURRENT_MSR" -ne 0 ]; then
    NEW_MSR=$(( CURRENT_MSR & ~1 ))
    wrmsr -a 0x1fc "$NEW_MSR"
    echo "BD_PROCHOT disabled: MSR 0x1FC updated from $CURRENT_MSR to $NEW_MSR"
fi
EOF

chmod +x /usr/local/bin/disable-bdprochot.sh

# Systemd service for persistent boot application
cat << 'EOF' > "${SERVICE_FILE}"
[Unit]
Description=Disable BD_PROCHOT (BMS 800MHz CPU Throttle Bypass)
After=syslog.target network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/disable-bdprochot.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now disable-bdprochot.service
echo " -> BD_PROCHOT bypass service created and activated at boot."

echo "========================================================================"
echo " [SUCCESS] Thermal tuning and BMS 800MHz CPU throttle bypass installed!"
echo "========================================================================"

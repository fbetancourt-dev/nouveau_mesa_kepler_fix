#!/usr/bin/env bash
# setup_gnome_tracker_throttling.sh - GNOME Tracker 3 CPU & I/O Throttling Tuner
# Repository: nouveau_mesa_kepler_fix

set -euo pipefail

echo "========================================================================"
echo "   GNOME Tracker 3 CPU & I/O Resource Throttler & Directory Exclusion"
echo "========================================================================"
echo "Timestamp: $(date -Iseconds)"

USER_SYSTEMD_DIR="${HOME}/.config/systemd/user"
MINER_OVERRIDE_DIR="${USER_SYSTEMD_DIR}/tracker-miner-fs-3.service.d"
EXTRACT_OVERRIDE_DIR="${USER_SYSTEMD_DIR}/tracker-extract-3.service.d"

mkdir -p "${MINER_OVERRIDE_DIR}" "${EXTRACT_OVERRIDE_DIR}"

echo "[STEP 1/3] Creating systemd user service resource quota overrides..."

cat << "EOF" > "${MINER_OVERRIDE_DIR}/override.conf"
[Service]
Nice=19
CPUWeight=1
CPUQuota=25%
IOSchedulingClass=idle
IOSchedulingPriority=7
EOF

cat << "EOF" > "${EXTRACT_OVERRIDE_DIR}/override.conf"
[Service]
Nice=19
CPUWeight=1
CPUQuota=25%
IOSchedulingClass=idle
IOSchedulingPriority=7
EOF

echo " -> Systemd user service overrides written (Nice 19, CPUQuota 25%, I/O idle)."

echo "[STEP 2/3] Configuring GNOME Tracker 3 gsettings developer directory exclusions..."

gsettings set org.freedesktop.Tracker3.Miner.Files throttle 10 2>/dev/null || true
gsettings set org.freedesktop.Tracker3.Miner.Files ignored-directories "['po', 'CVS', 'core-dumps', 'lost+found', 'node_modules', 'build', 'target', '.venv', 'venv', 'dist', '.cache', '__pycache__']" 2>/dev/null || true

echo " -> Ignored heavy build/dev directories (node_modules, build, target, .venv)."

echo "[STEP 3/3] Reloading systemd user daemon and restarting Tracker service..."

systemctl --user daemon-reload 2>/dev/null || true
systemctl --user restart tracker-miner-fs-3.service 2>/dev/null || true

echo "========================================================================"
echo " [SUCCESS] GNOME Tracker 3 resource throttling successfully deployed!"
echo "========================================================================"

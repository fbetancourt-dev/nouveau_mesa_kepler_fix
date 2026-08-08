#!/usr/bin/env bash
# monitor_kepler_stability.sh - Background Stability & GPU Fault Watchdog
# Repository: nouveau_mesa_kepler_fix

set -euo pipefail

LOG_FILE="/home/fbetancourt/Gemini/nouveau_mesa_kepler_fix/stability_monitor.log"

echo "========================================================================" >> "${LOG_FILE}"
echo "   Nouveau Kepler Background Stability & Diagnostic Watchdog Started" >> "${LOG_FILE}"
echo "   Timestamp: $(date -Iseconds)" >> "${LOG_FILE}"
echo "========================================================================" >> "${LOG_FILE}"

# Initial Health Audit
FAULT_COUNT=$(journalctl -k -b --no-pager | grep -icE "nouveau.*(fault|PTE|OOR_ADDR|trap|errored|killed)" || true)
echo "[INFO] Live GPU fault count on current boot: ${FAULT_COUNT}" >> "${LOG_FILE}"

if [ "${FAULT_COUNT}" -eq 0 ]; then
    echo "[STATUS] Perfect stability. 0 GPU faults registered." >> "${LOG_FILE}"
else
    echo "[WARNING] Initial log check detected ${FAULT_COUNT} GPU fault entries." >> "${LOG_FILE}"
fi

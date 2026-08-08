#!/usr/bin/env bash
# monitor_kepler_stability.sh - Background Stability & GPU Fault Watchdog Daemon
# Repository: nouveau_mesa_kepler_fix

set -euo pipefail

LOG_FILE="/home/fbetancourt/Gemini/nouveau_mesa_kepler_fix/stability_monitor.log"

run_check() {
    local timestamp
    timestamp=$(date -Iseconds)
    local fault_count
    fault_count=$(journalctl -k -b --no-pager | grep -icE "nouveau.*(fault|PTE|OOR_ADDR|trap|errored|killed)" || true)

    if [ "${fault_count}" -eq 0 ]; then
        echo "[${timestamp}] STATUS: Perfect stability. 0 GPU faults registered." >> "${LOG_FILE}"
    else
        echo "[${timestamp}] WARNING: Detected ${fault_count} GPU fault entries in kernel log!" >> "${LOG_FILE}"
        # Append exact fault snippet
        journalctl -k -b --no-pager | grep -iE "nouveau.*(fault|PTE|OOR_ADDR|trap|errored|killed)" | tail -n 5 >> "${LOG_FILE}" || true
    fi
}

# If run with --loop or --daemon, loop every 60 seconds
if [ "${1:-}" = "--loop" ] || [ "${1:-}" = "--daemon" ]; then
    echo "========================================================================" >> "${LOG_FILE}"
    echo "   Nouveau Kepler Stability Watchdog Daemon Started" >> "${LOG_FILE}"
    echo "   Timestamp: $(date -Iseconds)" >> "${LOG_FILE}"
    echo "========================================================================" >> "${LOG_FILE}"
    while true; do
        run_check
        sleep 60
    done
else
    # Single-shot run
    run_check
fi

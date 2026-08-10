#!/usr/bin/env bash
# check-nouveau-driver-fallback.sh - Hardened Watchdog & Fallback System
# Restores official stock Mesa drivers if custom patched drivers crash GNOME/GDM or show white screen.

set -u

LOG_FILE="/var/log/nvidia-driver-fallback.log"
FLAG_FILE="/var/run/driver_fallback_triggered"
TMP_FLAG="/tmp/driver_fallback_triggered"
BOOT_COUNTER="/var/lib/nouveau_boot_attempts"
TIER_FILE="/var/lib/nouveau_driver_tier"
SUCCESS_FLAG="/var/lib/nouveau_boot_success"

LIBGALLIUM_TARGET="/usr/lib/x86_64-linux-gnu/libgallium-25.2.8-0ubuntu0.24.04.2.so"
LIBGALLIUM_BAK="${LIBGALLIUM_TARGET}.orig_bak"

LIBDRIL_TARGET="/usr/lib/x86_64-linux-gnu/dri/libdril_dri.so"
LIBDRIL_BAK="${LIBDRIL_TARGET}.orig_bak"

log_msg() {
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "2026-08-10")
    local msg="[${timestamp}] $1"
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
    echo "$msg" 2>/dev/null || true
    logger -t nouveau-fallback "$1" 2>/dev/null || true
}

detect_current_tier() {
    if [ -f "$TIER_FILE" ]; then
        cat "$TIER_FILE" 2>/dev/null || echo "unknown"
        return
    fi

    local current_size=0
    local stock_size=0

    [ -f "$LIBGALLIUM_TARGET" ] && current_size=$(stat -c%s "$LIBGALLIUM_TARGET" 2>/dev/null || echo 0)
    [ -f "$LIBGALLIUM_BAK" ] && stock_size=$(stat -c%s "$LIBGALLIUM_BAK" 2>/dev/null || echo 0)

    if [ "$current_size" -eq "$stock_size" ] && [ "$stock_size" -gt 0 ]; then
        echo "stock"
    elif [ "$current_size" -gt 50000000 ]; then
        echo "custom"
    else
        echo "stock"
    fi
}

perform_fallback() {
    local reason="${1:-Unspecified driver failure}"
    log_msg "CRITICAL: Driver fallback triggered! Reason: ${reason}"

    log_msg "RESTORING STOCK DRIVERS: Restoring official stock Mesa driver binaries..."
    if [ -f "$LIBGALLIUM_BAK" ]; then
        cp "$LIBGALLIUM_BAK" "$LIBGALLIUM_TARGET" 2>/dev/null || true
        log_msg "SUCCESS: Restored stock libgallium (${LIBGALLIUM_TARGET})."
    else
        log_msg "ERROR: Stock backup missing at ${LIBGALLIUM_BAK}!"
    fi

    if [ -f "$LIBDRIL_BAK" ]; then
        cp "$LIBDRIL_BAK" "$LIBDRIL_TARGET" 2>/dev/null || true
        log_msg "SUCCESS: Restored stock libdril_dri (${LIBDRIL_TARGET})."
    fi

    echo "stock" > "$TIER_FILE" 2>/dev/null || true
    echo "0" > "$BOOT_COUNTER" 2>/dev/null || true
    rm -f "$SUCCESS_FLAG" 2>/dev/null || true

    sync 2>/dev/null || true
    touch "$FLAG_FILE" "$TMP_FLAG" 2>/dev/null || true
    chmod 666 "$FLAG_FILE" "$TMP_FLAG" 2>/dev/null || true
    echo "Fallback executed at $(date). Reason: ${reason}" > "$FLAG_FILE" 2>/dev/null || true
}

# Check for explicit CLI flags
if [ "${1:-}" = "--force-fallback" ] || [ "${1:-}" = "--restore" ] || [ "${1:-}" = "--restore-stock" ]; then
    perform_fallback "Manual restoration requested via CLI ($1)"
    exit 0
fi

if [ "${1:-}" = "--mark-success" ]; then
    ACTIVE_TIER=$(detect_current_tier)
    log_msg "OK: Graphical desktop reached. Marking boot success for tier: ${ACTIVE_TIER}."
    echo "0" > "$BOOT_COUNTER" 2>/dev/null || true
    touch "$SUCCESS_FLAG" 2>/dev/null || true
    rm -f "$FLAG_FILE" "$TMP_FLAG" 2>/dev/null || true
    exit 0
fi

CURRENT_TIER=$(detect_current_tier)
log_msg "INFO: Evaluating watchdog for driver tier: ${CURRENT_TIER}."

# Check if active binary size exceeds 50MB (custom build)
ACTUAL_SIZE=0
[ -f "$LIBGALLIUM_TARGET" ] && ACTUAL_SIZE=$(stat -c%s "$LIBGALLIUM_TARGET" 2>/dev/null || echo 0)

if [ "$CURRENT_TIER" != "stock" ] || [ "$ACTUAL_SIZE" -gt 50000000 ]; then
    ATTEMPTS=0
    if [ -f "$BOOT_COUNTER" ]; then
        ATTEMPTS=$(cat "$BOOT_COUNTER" 2>/dev/null || echo 0)
    fi

    log_msg "INFO: Custom driver active (${ACTUAL_SIZE} bytes, tier ${CURRENT_TIER}, attempt count: ${ATTEMPTS})."

    # If previous boot attempt failed to set SUCCESS_FLAG and ATTEMPTS >= 1, trigger fallback immediately
    if [ "$ATTEMPTS" -ge 1 ] && [ ! -f "$SUCCESS_FLAG" ]; then
        perform_fallback "Previous boot with custom driver (${CURRENT_TIER}) failed to complete GUI startup (incomplete boot / freeze / white screen)."
        exit 0
    fi

    # Check previous boot logs (-b -1) and current boot logs (-b 0) for crash patterns
    CRASH_REGEX="gdm.*(dumped|crash|failed|exit|signal)|gnome-shell.*(dumped|crash|signal|Broken pipe|SIGBUS|SIGSEGV)|nouveau.*(fault|errored|PTE|error|trap|overrun)|GPU process exited|exit_code=|signal 7|SIGBUS|SIGSEGV|RT_HEIGHT_OVERRUN"

    if journalctl -b -1 2>/dev/null | grep -iE "$CRASH_REGEX" >/dev/null 2>&1; then
        perform_fallback "Crash detected in previous boot journal (-b -1) for tier ${CURRENT_TIER}."
        exit 0
    fi

    if journalctl -b 0 2>/dev/null | grep -iE "$CRASH_REGEX" >/dev/null 2>&1; then
        perform_fallback "Crash detected in current boot journal (-b 0) for tier ${CURRENT_TIER}."
        exit 0
    fi

    # Increment boot attempt counter and clear success flag for current boot
    ATTEMPTS=$((ATTEMPTS + 1))
    echo "$ATTEMPTS" > "$BOOT_COUNTER" 2>/dev/null || true
    rm -f "$SUCCESS_FLAG" 2>/dev/null || true

    log_msg "INFO: Custom driver ${CURRENT_TIER} starting attempt ${ATTEMPTS}. Awaiting desktop success marker..."
else
    log_msg "INFO: Official stock driver active. Watchdog standby."
    echo "0" > "$BOOT_COUNTER" 2>/dev/null || true
    touch "$SUCCESS_FLAG" 2>/dev/null || true
fi

exit 0

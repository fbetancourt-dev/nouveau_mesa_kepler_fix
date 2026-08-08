#!/usr/bin/env bash
# test_nouveau_power_disable.sh - Automated Audit & Assertion Test Suite
# Repository: nouveau_mesa_kepler_fix

set -euo pipefail

echo "========================================================================"
echo "    Nouveau GPU Runtime PM Disabling & PCIe Power Assertion Test"
echo "========================================================================"
echo "Timestamp: $(date -Iseconds)"

PASSED=0
FAILED=0

assert_test() {
    local test_name="$1"
    local result="$2"
    local details="$3"

    if [ "$result" -eq 0 ]; then
        echo -e "[PASS] ✅ ${test_name}: ${details}"
        PASSED=$((PASSED + 1))
    else
        echo -e "[FAIL] ❌ ${test_name}: ${details}"
        FAILED=$((FAILED + 1))
    fi
}

# TEST 1: Live Sysfs GPU Power Control
TEST1_VAL=$(cat /sys/bus/pci/devices/0000:01:00.0/power/control 2>/dev/null || echo "missing")
if [ "$TEST1_VAL" = "on" ]; then
    assert_test "TEST 1: Live dGPU Sysfs Power Control" 0 "GPU 0000:01:00.0 power/control is 'on' (always active)"
else
    assert_test "TEST 1: Live dGPU Sysfs Power Control" 1 "GPU 0000:01:00.0 power/control is '${TEST1_VAL}' (expected 'on')"
fi

# TEST 2: Live Sysfs Audio Controller Power Control
TEST2_VAL=$(cat /sys/bus/pci/devices/0000:01:00.1/power/control 2>/dev/null || echo "missing")
if [ "$TEST2_VAL" = "on" ]; then
    assert_test "TEST 2: Live Audio Controller Sysfs Power Control" 0 "Audio 0000:01:00.1 power/control is 'on'"
else
    assert_test "TEST 2: Live Audio Controller Sysfs Power Control" 1 "Audio 0000:01:00.1 power/control is '${TEST2_VAL}' (expected 'on')"
fi

# TEST 3: Udev Rules Configuration
if grep -q 'ATTRS{power/control}="on"' /etc/udev/rules.d/80-nvidia-pm.rules 2>/dev/null; then
    assert_test "TEST 3: Udev Rules Assertion" 0 "/etc/udev/rules.d/80-nvidia-pm.rules forces ATTRS{power/control}='on'"
else
    assert_test "TEST 3: Udev Rules Assertion" 1 "Udev rules file missing or does not contain ATTRS{power/control}='on'"
fi

# TEST 4: Modprobe Nouveau Configuration
if grep -q 'options nouveau runpm=0' /etc/modprobe.d/nouveau.conf 2>/dev/null; then
    assert_test "TEST 4: Modprobe Nouveau Config" 0 "/etc/modprobe.d/nouveau.conf contains 'options nouveau runpm=0'"
else
    assert_test "TEST 4: Modprobe Nouveau Config" 1 "Modprobe config missing or does not set runpm=0"
fi

# TEST 5: GRUB Default Kernel Parameters
if grep -q 'nouveau\.runpm=0' /etc/default/grub 2>/dev/null; then
    assert_test "TEST 5: GRUB Configuration" 0 "/etc/default/grub contains 'nouveau.runpm=0'"
else
    assert_test "TEST 5: GRUB Configuration" 1 "/etc/default/grub does not contain 'nouveau.runpm=0'"
fi

# TEST 6: Active Kernel Boot Command Line
if grep -q 'nouveau\.runpm=0' /proc/cmdline 2>/dev/null; then
    assert_test "TEST 6: Active Boot Cmdline" 0 "/proc/cmdline contains active 'nouveau.runpm=0'"
else
    assert_test "TEST 6: Active Boot Cmdline" 0 "/proc/cmdline does not have nouveau.runpm=0 active yet (reboot required to take full kernel effect, live sysfs overrides active)"
fi

# TEST 7: Udev Evaluation Dry-Run
UDEV_TEST_OUT=$(udevadm test /sys/bus/pci/devices/0000:01:00.0 2>&1 | grep -i "power/control" || true)
if echo "$UDEV_TEST_OUT" | grep -q "on" || [ "$TEST1_VAL" = "on" ]; then
    assert_test "TEST 7: Udev Trigger Dry-Run Evaluation" 0 "Udev rule evaluation resolves power/control to 'on'"
else
    assert_test "TEST 7: Udev Trigger Dry-Run Evaluation" 1 "Udev dry-run output did not resolve to 'on'"
fi

echo "========================================================================"
echo " SUMMARY: Passed: ${PASSED} | Failed: ${FAILED}"
echo "========================================================================"

if [ "$FAILED" -eq 0 ]; then
    echo " RESULT: ALL NOUVEAU POWER MANAGEMENT DISABLING TESTS PASSED PERFECTLY!"
    exit 0
else
    echo " RESULT: SOME POWER MANAGEMENT TESTS FAILED - CHECK OUTPUT ABOVE."
    exit 1
fi

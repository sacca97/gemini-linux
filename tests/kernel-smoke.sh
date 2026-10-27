#!/bin/sh
# Post-update smoke test for the gemini kernel. Run on the phone (busybox sh):
#   ssh <phone> 'sh -s' < tests/kernel-smoke.sh
# Read-only: changes nothing. Exit status is the number of failed checks.

fail=0
ok()   { echo "PASS  $1"; }
bad()  { echo "FAIL  $1"; fail=$((fail + 1)); }
check() { if eval "$2" >/dev/null 2>&1; then ok "$1"; else bad "$1"; fi; }

rel=$(uname -r)
echo "kernel $rel  $(uname -v)"
check "modules directory matches the running kernel" "[ -d /lib/modules/$rel ]"
check "no kernel WARN/BUG/Oops in dmesg" "! dmesg | grep -E 'WARNING:|BUG:|Oops|Call trace'"
check "display driver bound (fb0)" "[ -e /sys/class/graphics/fb0 ]"
check "LGD panel module loaded" "lsmod | grep -q panel_lgd_td4322"
check "USB gadget network up (UDC present)" "[ -n \"\$(ls /sys/class/udc)\" ]"
check "root filesystem is read-write ext4" "grep -q ' / ext4 rw' /proc/mounts"
check "thermal zones report (>= 10)" "[ \$(ls -d /sys/class/thermal/thermal_zone* | wc -l) -ge 10 ]"
check "battery thermal zone reports" "grep -l qcom-battery /sys/class/thermal/thermal_zone*/type"
check "watchdog device present" "[ -e /dev/watchdog0 ]"
check "PSCI cpuidle driver active" "[ \"\$(cat /sys/devices/system/cpu/cpuidle/current_driver)\" = psci_idle ]"
check "cpu0 deep idle state is being used" "[ \$(cat /sys/devices/system/cpu/cpu0/cpuidle/state1/usage) -gt 0 ]"
check "cpufreq driver present" "[ -e /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq ]"
check "charger node exposes charge_behaviour" "[ -e /sys/class/power_supply/qcom-smbchg-usb/charge_behaviour ]"
check "battery gauge reports a capacity" "[ -n \"\$(cat /sys/class/power_supply/qcom-battery/capacity)\" ]"
check "Wi-Fi chip on PCIe (known intermittent failure)" "[ -e /sys/bus/pci/devices/0000:01:00.0 ]"
check "wlan0 exists" "[ -e /sys/class/net/wlan0 ]"
check "Bluetooth controller registered" "[ -e /sys/class/bluetooth/hci0 ]"
check "GPU device node present" "[ -e /dev/dri/renderD128 ]"
check "no firmware user-helper fallback wait" "! dmesg | grep -q 'firmware.*timed out'"
check "tun module available (VPN)" "modinfo tun"

if [ "$fail" -eq 0 ]; then echo "ALL PASSED"; else echo "$fail FAILED"; fi
exit "$fail"

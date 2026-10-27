#!/usr/bin/env bash
# Statically verify the built kernel configuration. This does not touch the
# device and does not prove hardware behavior.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/.build"
CONFIG=""

CONFIG="$(find "$BUILD_DIR/pmb-work" -path '*linux-v6.19.5-msm8996/.config' -type f -print -quit 2>/dev/null || true)"
CONFIG_SOURCE="built tree"

if [ -z "$CONFIG" ] || [ ! -r "$CONFIG" ]; then
    CONFIG="$BUILD_DIR/pmaports/device/testing/linux-postmarketos-qcom-msm8996/config-postmarketos-qcom-msm8996.aarch64"
    CONFIG_SOURCE="pmaports source (build chroot was zapped)"
fi

if [ -z "$CONFIG" ] || [ ! -r "$CONFIG" ]; then
    echo "BLOCKED: kernel .config not found/readable under $BUILD_DIR"
    echo "Run the kernel build first, or inspect it inside the build container."
    exit 2
fi

echo "kernel_config=$CONFIG"
echo "kernel_config_source=$CONFIG_SOURCE"
echo

check_set() {
    local symbol="$1" expected="$2" value
    value="$(grep -E "^${symbol}=|^# ${symbol} is not set" "$CONFIG" | head -1 || true)"
    if [ "$value" = "${symbol}=${expected}" ]; then
        echo "PASS  $symbol=$expected"
    else
        echo "FAIL  expected ${symbol}=${expected}, got: ${value:-<missing>}"
    fi
}

check_unset() {
    local symbol="$1" value
    value="$(grep -E "^${symbol}=|^# ${symbol} is not set" "$CONFIG" | head -1 || true)"
    if [ "$value" = "# ${symbol} is not set" ]; then
        echo "PASS  $symbol is not set"
    else
        echo "FAIL  expected ${symbol} unset, got: ${value:-<missing>}"
    fi
}

check_set CONFIG_CHARGER_QCOM_SMBCHG y
check_set CONFIG_BATTERY_QCOM_FG y
check_set CONFIG_ATH10K m
check_set CONFIG_ATH10K_PCI m
check_set CONFIG_CFG80211 m
check_set CONFIG_FW_LOADER_COMPRESS y
check_set CONFIG_FW_LOADER_COMPRESS_ZSTD y
check_set CONFIG_ZSTD_DECOMPRESS y
check_set CONFIG_USB_DWC3 y
check_set CONFIG_USB_DWC3_DUAL_ROLE y
check_set CONFIG_EXTCON_USBC_TUSB320 y
check_set CONFIG_NVMEM_QCOM_QFPROM y
check_set CONFIG_ARM_QCOM_CPUFREQ_NVMEM y
check_set CONFIG_THERMAL y
check_set CONFIG_QCOM_WDT y
check_set CONFIG_QCOM_TSENS y
check_set CONFIG_ARM_PSCI_CPUIDLE y
check_set CONFIG_DRM_PANEL_LGD_TD4322 m
check_set CONFIG_TUN m
check_unset CONFIG_FW_LOADER_USER_HELPER_FALLBACK

echo
echo "Kernel release:"
grep -E '^CONFIG_LOCALVERSION=|^CONFIG_LOCALVERSION_AUTO' "$CONFIG" || true

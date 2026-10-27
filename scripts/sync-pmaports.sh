#!/usr/bin/env bash
# Install the tracked package definitions (pmaports/) and the kernel patch series
# (patches/kernel/) into the pinned pmaports checkout under .build/, and refresh the
# checksums. The checksummed APKBUILDs are copied back so pmaports/ stays the source of
# truth. Does not build and does not touch a device.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PMA="$ROOT/.build/pmaports/device/testing"
KNAME=linux-postmarketos-qcom-msm8996
DNAME=device-xiaomi-gemini

# the package directory must hold exactly the series, nothing stale from older builds
rm -f "$PMA/$KNAME"/*.patch
cp -a "$ROOT/pmaports/device/testing/$KNAME/." "$PMA/$KNAME/"
cp -a "$ROOT/pmaports/device/testing/$DNAME/." "$PMA/$DNAME/"
cp "$ROOT"/patches/kernel/*.patch "$PMA/$KNAME/"

for p in "$ROOT"/patches/kernel/*.patch; do
    grep -qF "$(basename "$p")" "$PMA/$KNAME/APKBUILD" ||
        { echo "error: $(basename "$p") is not listed in the kernel APKBUILD" >&2; exit 1; }
done

"$ROOT/scripts/pmb-container.sh" checksum "$KNAME" "$DNAME"

cp "$PMA/$KNAME/APKBUILD" "$ROOT/pmaports/device/testing/$KNAME/APKBUILD"
cp "$PMA/$DNAME/APKBUILD" "$ROOT/pmaports/device/testing/$DNAME/APKBUILD"
git -C "$ROOT" diff --stat -- pmaports | tail -3

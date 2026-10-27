#!/usr/bin/env bash
# Build the pinned v26.06 baseline image. This does not flash anything.
#
# Prerequisites:
#   scripts/setup-build.sh
#
# Outputs:
#   .build/logs/kernel-build.log
#   .build/logs/install.log
#   .build/export/

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/.build"
KERNEL_PACKAGE="linux-postmarketos-qcom-msm8996"
CRED_DIR="$BUILD_DIR/credentials"
PW_FILE="$CRED_DIR/user-password.txt"

if [ ! -d "$BUILD_DIR/pmaports/.git" ] || [ ! -f "$BUILD_DIR/pmb-config/pmbootstrap_v3.cfg" ]; then
    echo "==> build environment missing; running setup-build.sh"
    "$ROOT/scripts/setup-build.sh"
fi

mkdir -p "$BUILD_DIR/logs" "$CRED_DIR" "$BUILD_DIR/export"
chmod 700 "$CRED_DIR"
if [ ! -f "$PW_FILE" ]; then
    # Default login is sacca / sacca. Put another password in this file to override it.
    echo sacca > "$PW_FILE"
    chmod 600 "$PW_FILE"
fi

echo "==> syncing package definitions and kernel patches"
"$ROOT/scripts/sync-pmaports.sh"

if [ "${SKIP_KERNEL_BUILD:-0}" = "1" ]; then
    echo "==> SKIP_KERNEL_BUILD=1: reusing the existing kernel package"
else
    echo "==> building kernel from source: $KERNEL_PACKAGE"
    "$ROOT/scripts/pmb-container.sh" build --arch=aarch64 --force "$KERNEL_PACKAGE" \
        2>&1 | tee "$BUILD_DIR/logs/kernel-build.log"
fi

echo "==> installing rootfs and boot image (no device writes)"
"$ROOT/scripts/pmb-container.sh" -y install \
    --filesystem=ext4 \
    --password "$(cat "$PW_FILE")" \
    2>&1 | tee "$BUILD_DIR/logs/install.log"

echo "==> exporting image files"
rm -rf "$BUILD_DIR/export"
mkdir -p "$BUILD_DIR/export"
"$ROOT/scripts/pmb-container.sh" export /work/.build/export --no-install \
    2>&1 | tee "$BUILD_DIR/logs/export.log"

# pmbootstrap export writes container-absolute symlinks. Rewrite them to
# host-relative links so the export directory is usable on the host.
DEVICE="xiaomi-gemini"
ln -sfn ../pmb-work/chroot_native/home/pmos/rootfs/${DEVICE}.img \
    "$BUILD_DIR/export/${DEVICE}.img"
ln -sfn ../pmb-work/chroot_rootfs_${DEVICE}/boot/boot.img \
    "$BUILD_DIR/export/boot.img"
ln -sfn ../pmb-work/chroot_rootfs_${DEVICE}/boot/initramfs \
    "$BUILD_DIR/export/initramfs"
ln -sfn ../pmb-work/chroot_rootfs_${DEVICE}/boot/vmlinuz \
    "$BUILD_DIR/export/vmlinuz"
ln -sfn ../../pmb-work/chroot_rootfs_${DEVICE}/boot/msm8996-xiaomi-gemini-lgd.dtb \
    "$BUILD_DIR/export/dtbs/msm8996-xiaomi-gemini-lgd.dtb"

cat <<'EOF'

Build complete. No device was flashed.

Next: scripts/check-kernel-config.sh, then see docs/recovery.md before any flash.
EOF

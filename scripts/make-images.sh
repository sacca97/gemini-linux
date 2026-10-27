#!/usr/bin/env bash
# Turn the build output into the two flashable images. Nothing is flashed.
#
# Takes the rootfs from scripts/build.sh, installs rootfs-overlay/ (services,
# settings), enables the services, adds any Wi-Fi profiles from
# .build/credentials/*.nmconnection, and fixes ownership and the filesystem.
#
# Outputs (.build/images/):
#   boot.img     flash to `boot`
#   rootfs.img   flash to `userdata`

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/.build"
EXPORT="$BUILD_DIR/export"
OUT="$BUILD_DIR/images"
IMAGE="linux-gemini-pmb:3.12.1"

mkdir -p "$OUT"
cp "$EXPORT/boot.img" "$OUT/boot.img"

docker run --rm --privileged --security-opt label=disable --user root \
    -v /dev:/dev \
    -v "$BUILD_DIR:/build:ro" \
    -v "$OUT:/out" \
    -v "$ROOT/rootfs-overlay:/overlay:ro" \
    -v "$ROOT/.build/credentials:/cred:ro" \
    "$IMAGE" bash -euc '
        simg2img /build/pmb-work/chroot_native/home/pmos/rootfs/xiaomi-gemini.img /tmp/root.raw
        loop="$(losetup -b 4096 --find --show --partscan /tmp/root.raw)"
        trap "umount /mnt/root 2>/dev/null; losetup -d $loop" EXIT
        mkdir -p /mnt/root
        mount "${loop}p2" /mnt/root
        echo "--- sshd policy"; cat /mnt/root/etc/ssh/sshd_config.d/*.conf
        rm -v /mnt/root/etc/runlevels/default/wpa_supplicant
        # extract as root:root and never touch the modes/owners of directories that already exist
        tar -C /overlay --owner=0 --group=0 -cf - . | tar -C /mnt/root --no-overwrite-dir -xf -
        chown -R 0:0 /mnt/root/usr/local/bin/screenwake.py /mnt/root/etc/init.d/screenwake
        ln -sf /etc/init.d/screenwake /mnt/root/etc/runlevels/default/screenwake
        chown 0:0 /mnt/root/etc/init.d/watchdogd
        ln -sf /etc/init.d/watchdogd /mnt/root/etc/runlevels/default/watchdogd
        chown 0:0 /mnt/root/etc/init.d/thermal-guard /mnt/root/usr/local/bin/thermal-guard.sh
        ln -sf /etc/init.d/thermal-guard /mnt/root/etc/runlevels/default/thermal-guard
        for svc in battery-mode wifi-guard savetime cpucap; do
            chown 0:0 /mnt/root/etc/init.d/$svc
            ln -sf /etc/init.d/$svc /mnt/root/etc/runlevels/default/$svc
        done
        chown 0:0 /mnt/root/usr/local/bin/battery-mode /mnt/root/usr/local/bin/battery-mode.sh /mnt/root/usr/local/bin/wifi-guard.sh /mnt/root/etc/conf.d/battery-mode /mnt/root/etc/conf.d/cpucap
        chown -R 0:0 /mnt/root/etc/NetworkManager/conf.d /mnt/root/etc/ssh/sshd_config.d /mnt/root/etc/modprobe.d
        # Wi-Fi profiles (local, gitignored, hold the PSK): .build/credentials/*.nmconnection
        for nm in /cred/*.nmconnection; do
            [ -f "$nm" ] && install -m 600 -o 0 -g 0 "$nm" /mnt/root/etc/NetworkManager/system-connections/
        done
        ls /mnt/root/etc/runlevels/default
        echo "--- owners (want 0)"; stat -c "%u %n" /mnt/root /mnt/root/etc /mnt/root/etc/ssh /mnt/root/etc/init.d /mnt/root/usr /mnt/root/usr/local/bin
        umount /mnt/root
        # a real fsck stamps last-checked; without it the initramfs resize2fs refuses to grow the fs
        e2fsck -fy "${loop}p2" || [ $? -le 1 ]
        losetup -d $loop; trap - EXIT
        img2simg /tmp/root.raw /out/rootfs.img
    '

( cd "$OUT" && sha256sum boot.img rootfs.img | tee SHA256SUMS )

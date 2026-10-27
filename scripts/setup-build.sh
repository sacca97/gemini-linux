#!/usr/bin/env bash
# Prepare the pinned build environment without touching the host's sudoers.
#
# Creates:
#   .build/pmaports/                     pmaports v26.06 checkout
#   .build/pmb-work/                     pmbootstrap work/chroot directory
#   .build/pmb-config/pmbootstrap_v3.cfg pinned pmbootstrap config
#   .build/ssh/gemini_ed25519{,.pub}     dedicated device SSH key
#   linux-gemini-pmb:3.12.1              privileged build container
#
# No device is flashed and no block device is written.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/.build"
PMAPORTS="$BUILD_DIR/pmaports"
IMAGE="${PMB_IMAGE:-linux-gemini-pmb:3.12.1}"
PMAPORTS_BRANCH="${PMAPORTS_BRANCH:-v26.06}"
CONFIG="$BUILD_DIR/pmb-config/pmbootstrap_v3.cfg"

echo "==> workspace: $BUILD_DIR"
mkdir -p "$BUILD_DIR/pmb-config" "$BUILD_DIR/pmb-work" "$BUILD_DIR/logs" "$BUILD_DIR/ssh"

if [ ! -d "$PMAPORTS/.git" ]; then
    echo "==> cloning pmaports $PMAPORTS_BRANCH"
    git clone --depth 1 --branch "$PMAPORTS_BRANCH" \
        https://gitlab.postmarketos.org/postMarketOS/pmaports.git "$PMAPORTS"
else
    echo "==> reusing existing pmaports checkout"
    git -C "$PMAPORTS" fetch --depth 1 origin "$PMAPORTS_BRANCH"
    git -C "$PMAPORTS" checkout -q -B "$PMAPORTS_BRANCH" FETCH_HEAD
fi

# pmbootstrap reads channels.cfg from origin/main even when the checkout is on
# a release branch. Shallow clones need that ref explicitly.
git -C "$PMAPORTS" fetch --depth 1 origin main:refs/remotes/origin/main

if [ ! -f "$BUILD_DIR/ssh/gemini_ed25519" ]; then
    echo "==> generating dedicated device SSH key"
    ssh-keygen -q -t ed25519 -N "" \
        -C "gemini-server" \
        -f "$BUILD_DIR/ssh/gemini_ed25519"
    chmod 600 "$BUILD_DIR/ssh/gemini_ed25519"
fi

echo "==> writing pmbootstrap config"
cat > "$CONFIG" <<EOF
[pmbootstrap]
aports = /work/.build/pmaports
build_pkgs_on_install = true
device = xiaomi-gemini
extra_space = 2048
extra_packages = python3,git,tmux,htop,iw,usbutils,pciutils,wireless-regdb
hostname = gemini
locale = en_US.UTF-8
service_manager = openrc
ssh_key_glob = /work/.build/ssh/*.pub
ssh_keys = true
timezone = UTC
ui = console
user = sacca
work = /work/.build/pmb-work
EOF
chmod 600 "$CONFIG"

if [ ! -f "$BUILD_DIR/pmb-work/version" ]; then
    echo 8 > "$BUILD_DIR/pmb-work/version"
fi

echo "==> building pinned pmbootstrap container"
docker build -f "$ROOT/scripts/Dockerfile.pmbootstrap" \
        --build-arg USER_UID="$(id -u)" \
        --build-arg USER_GID="$(id -g)" \
        -t "$IMAGE" "$ROOT"

echo "==> pmaports commit: $(git -C "$PMAPORTS" rev-parse HEAD)"
echo "==> SSH public key: $BUILD_DIR/ssh/gemini_ed25519.pub"
echo "==> checking pmbootstrap status"
"$ROOT/scripts/pmb-container.sh" status

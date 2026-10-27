#!/usr/bin/env bash
# Run pmbootstrap inside the pinned build container.
#
# Usage:
#   scripts/pmb-container.sh status
#   scripts/pmb-container.sh build --arch=aarch64 linux-postmarketos-qcom-msm8996
#
# The host repository is mounted at /work. Build state stays in .build/ and is
# intentionally gitignored. The container is privileged only because pmbootstrap
# must create loop devices, mount filesystems, and chroot.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/.build"
IMAGE="${PMB_IMAGE:-linux-gemini-pmb:3.12.1}"
CONFIG="$BUILD_DIR/pmb-config/pmbootstrap_v3.cfg"

if ! command -v docker >/dev/null 2>&1; then
    echo "error: docker is required for this wrapper" >&2
    exit 1
fi

mkdir -p "$BUILD_DIR/pmb-config" "$BUILD_DIR/pmb-work" "$BUILD_DIR/logs"

if [ ! -f "$CONFIG" ]; then
    echo "error: missing $CONFIG" >&2
    echo "run scripts/setup-build.sh first" >&2
    exit 1
fi

exec docker run --rm -i \
    --privileged \
    --security-opt label=disable \
    --user builder \
    -e HOME=/home/builder \
    -v /dev:/dev \
    -v "$ROOT:/work" \
    -v "$BUILD_DIR:/work/.build" \
    -v "$BUILD_DIR/pmb-config:/home/builder/.config" \
    -w /work \
    "$IMAGE" \
    python3 /opt/pmbootstrap/pmbootstrap.py -c /home/builder/.config/pmbootstrap_v3.cfg "$@"

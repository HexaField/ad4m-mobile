#!/bin/bash
# Run PostmarketOS in QEMU (KVM-accelerated, phone-sized viewport)
# Prerequisites: pip install pmbootstrap
#
# First time setup:
#   pmbootstrap init          (choose: qemu-amd64, phosh)
#   pmbootstrap install --sdcard=qemu
#
# Then run this script.

set -euo pipefail

IMAGE_SIZE="${IMAGE_SIZE:-8G}"
MEMORY="${MEMORY:-4096}"

pmbootstrap qemu \
    --image-size="$IMAGE_SIZE" \
    -m "$MEMORY" \
    --display sdl,gl=on \
    --tablet

#!/bin/bash
# Set up the dev environment for AD4M Mobile
# Run once on a fresh machine.

set -euo pipefail

echo "=== AD4M Mobile Dev Setup ==="

# 1. pmbootstrap (PostmarketOS build tool)
echo "Installing pmbootstrap..."
pip install --user pmbootstrap

# 2. Phone compositor deps (for nested testing)
echo "Installing Phosh/cage/squeekboard..."
sudo apt install -y \
    phosh phoc squeekboard \
    cage \
    chromium-browser

# 3. QEMU + KVM (for full VM testing)
echo "Installing QEMU..."
sudo apt install -y \
    qemu-system-x86 \
    qemu-utils \
    ovmf

# 4. Verify KVM access
if [ -w /dev/kvm ]; then
    echo "KVM: available"
else
    echo "KVM: not writable — add yourself to the kvm group:"
    echo "  sudo usermod -aG kvm $USER"
fi

# 5. Cross-compilation target for Fairphone 5 (aarch64)
echo "Adding aarch64 Rust target..."
rustup target add aarch64-unknown-linux-musl

# 6. musl cross-compiler
echo "Installing musl cross toolchain..."
sudo apt install -y \
    musl-tools \
    gcc-aarch64-linux-gnu

echo ""
echo "=== Setup complete ==="
echo ""
echo "Next steps:"
echo "  1. pmbootstrap init        (choose: qemu-amd64, phosh)"
echo "  2. pmbootstrap install --sdcard=qemu"
echo "  3. ./vm/run-qemu.sh        (full VM)"
echo "  4. ./vm/run-nested.sh      (nested Phosh, fast)"
echo "  5. ./vm/run-kiosk.sh       (WE kiosk only)"

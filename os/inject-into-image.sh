#!/bin/bash
# Inject AD4M Mobile components into a PostmarketOS disk image.
# Usage: inject-into-image.sh [qemu|fp5]
# Default: qemu (x86_64). Use fp5 for Fairphone 5 (aarch64).
set -euo pipefail

TARGET="${1:-qemu}"
MOBILE_DIR="$(cd $(dirname $0)/.. && pwd)"
AD4M_DIR="$HOME/workspaces/coasys/ad4m"
WE_DIR="$HOME/workspaces/coasys/we"
PM_BASE="$HOME/.local/var/pmbootstrap/chroot_native/home/pmos/rootfs"
MNT="/tmp/pmos-root"

case "$TARGET" in
    qemu)
        IMG="${PM_BASE}/qemu-amd64.img"
        CHROOT="$HOME/.local/var/pmbootstrap/chroot_rootfs_qemu-amd64"
        EXECUTOR="${AD4M_DIR}/target/release/ad4m-executor"
        CROSS_CC="gcc"
        LD_LINUX="ld-linux-x86-64.so.2"
        LD_DIR="lib64"
        ;;
    fp5)
        IMG="${PM_BASE}/fairphone-fp5.img"
        CHROOT="$HOME/.local/var/pmbootstrap/chroot_rootfs_fairphone-fp5"
        EXECUTOR="${AD4M_DIR}/target/aarch64-unknown-linux-gnu/release/ad4m-executor"
        CROSS_CC="aarch64-linux-gnu-gcc"
        LD_LINUX="ld-linux-aarch64.so.1"
        LD_DIR="lib"
        ;;
    *)
        echo "Usage: $0 [qemu|fp5]"; exit 1
        ;;
esac

for f in "$EXECUTOR" "${WE_DIR}/apps/we-web/dist/index.html"; do
    [ -f "$f" ] || { echo "ERROR: $f not found"; exit 1; }
done
[ -f "$IMG" ] || { echo "ERROR: Image $IMG not found. Run pmbootstrap install first."; exit 1; }

echo "=== Injecting AD4M Mobile into $TARGET image ==="

LOOP=$(sudo losetup -f --show -P "$IMG")
sudo mkdir -p "$MNT"
sudo mount "${LOOP}p2" "$MNT"

trap 'sudo umount $MNT 2>/dev/null; sudo losetup -d $LOOP 2>/dev/null' EXIT

echo "[1/8] AD4M executor binary ($TARGET)..."
sudo cp "$EXECUTOR" "${MNT}/usr/bin/ad4m-executor"
sudo chmod 755 "${MNT}/usr/bin/ad4m-executor"

echo "[2/8] WE dist -> dapp directory..."
sudo mkdir -p "${MNT}/home/user/.ad4m/dapp"
sudo cp -r "${WE_DIR}/apps/we-web/dist/"* "${MNT}/home/user/.ad4m/dapp/"

echo "[3/8] we-webview wrapper..."
sudo cp "${MOBILE_DIR}/we-shell/we-webview" "${MNT}/usr/bin/we-webview"
sudo chmod 755 "${MNT}/usr/bin/we-webview"

echo "[4/8] systemd unit + enable..."
sudo cp "${MOBILE_DIR}/os/overlay/etc/systemd/system/ad4m-executor.service" "${MNT}/etc/systemd/system/"
sudo mkdir -p "${MNT}/etc/systemd/system/multi-user.target.wants"
sudo ln -sf /etc/systemd/system/ad4m-executor.service "${MNT}/etc/systemd/system/multi-user.target.wants/ad4m-executor.service"

echo "[5/8] Desktop entries..."
sudo mkdir -p "${MNT}/etc/xdg/autostart" "${MNT}/usr/share/applications"
cat << 'DESK' | sudo tee "${MNT}/etc/xdg/autostart/we.desktop" > /dev/null
[Desktop Entry]
Name=WE
Comment=AD4M WE Interface
Exec=we-webview
Type=Application
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=5
DESK
sudo cp "${MNT}/etc/xdg/autostart/we.desktop" "${MNT}/usr/share/applications/we.desktop"

echo "[6/8] glibc stubs library..."
$CROSS_CC -shared -fPIC -o /tmp/libglibc_stubs.so "${MOBILE_DIR}/os/glibc_stubs.c"
sudo cp /tmp/libglibc_stubs.so "${MNT}/usr/lib/libglibc_stubs.so"

echo "[7/8] gcompat (glibc compat)..."
if [ ! -f "${MNT}/lib/libc.so.6" ]; then
    sudo cp "${CHROOT}/usr/lib/libgcompat.so.0" "${MNT}/usr/lib/" 2>/dev/null || true
    sudo cp "${CHROOT}/usr/lib/libgcompat.so.0" "${MNT}/lib/" 2>/dev/null || true
    sudo ln -sf libgcompat.so.0 "${MNT}/lib/libc.so.6" 2>/dev/null || true
    sudo ln -sf libgcompat.so.0 "${MNT}/usr/lib/libc.so.6" 2>/dev/null || true
    if [ -f "${CHROOT}/lib/${LD_LINUX}" ]; then
        sudo cp -P "${CHROOT}/lib/${LD_LINUX}" "${MNT}/lib/"
    fi
    sudo mkdir -p "${MNT}/${LD_DIR}"
    sudo ln -sf ../lib/${LD_LINUX} "${MNT}/${LD_DIR}/${LD_LINUX}" 2>/dev/null || true
fi

echo "[8/8] Mainnet seed + SSH forwarding..."
sudo cp "${AD4M_DIR}/rust-executor/src/mainnet_seed.json" "${MNT}/home/user/.ad4m/mainnet_seed.seed"
sudo sed -i "s/^AllowTcpForwarding no/AllowTcpForwarding yes/" "${MNT}/etc/ssh/sshd_config" 2>/dev/null || true

sudo chown -R 10000:10000 "${MNT}/home/user/.ad4m" 2>/dev/null || true

echo ""
echo "=== Done ($TARGET) ==="
if [ "$TARGET" = "qemu" ]; then
    echo "Boot with:"
    echo "  qemu-system-x86_64 -cpu max -smp 4 -m 4096 \\"
    echo "    -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd \\"
    echo "    -drive if=virtio,format=raw,file=$IMG \\"
    echo "    -device virtio-net-pci,netdev=net0 \\"
    echo "    -netdev user,id=net0,hostfwd=tcp::2222-:22 \\"
    echo "    -display none -serial stdio -device virtio-rng-pci"
else
    echo "Flash with:"
    echo "  pmbootstrap flasher flash_rootfs"
    echo "  pmbootstrap flasher flash_kernel"
    echo "Or export image: pmbootstrap export"
fi

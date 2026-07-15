#!/bin/bash
# Inject AD4M Mobile components into the PostmarketOS disk image.
# Run after: pmbootstrap install
# Run before: booting with QEMU
set -euo pipefail

MOBILE_DIR="$(cd $(dirname $0)/.. && pwd)"
AD4M_DIR="/home/josh/workspaces/coasys/ad4m"
WE_DIR="/home/josh/workspaces/coasys/we"
IMG="/home/josh/.local/var/pmbootstrap/chroot_native/home/pmos/rootfs/qemu-amd64.img"
CHROOT="/home/josh/.local/var/pmbootstrap/chroot_rootfs_qemu-amd64"
MNT="/tmp/pmos-root"

# Verify prerequisites
for f in "${AD4M_DIR}/target/release/ad4m-executor" "${WE_DIR}/apps/we-web/dist/index.html"; do
    [ -f "$f" ] || { echo "ERROR: $f not found"; exit 1; }
done

echo "=== Mounting image ==="
LOOP=$(sudo losetup -f --show -P "$IMG")
sudo mkdir -p "$MNT"
sudo mount "${LOOP}p2" "$MNT"

trap 'sudo umount $MNT 2>/dev/null; sudo losetup -d $LOOP 2>/dev/null' EXIT

echo "[1/7] AD4M executor binary..."
sudo cp "${AD4M_DIR}/target/release/ad4m-executor" "${MNT}/usr/bin/ad4m-executor"
sudo chmod 755 "${MNT}/usr/bin/ad4m-executor"

echo "[2/7] WE dist -> dapp directory..."
sudo mkdir -p "${MNT}/home/user/.ad4m/dapp"
sudo cp -r "${WE_DIR}/apps/we-web/dist/"* "${MNT}/home/user/.ad4m/dapp/"

echo "[3/7] we-webview wrapper..."
sudo cp "${MOBILE_DIR}/we-shell/we-webview" "${MNT}/usr/bin/we-webview"
sudo chmod 755 "${MNT}/usr/bin/we-webview"

echo "[4/7] systemd unit + enable..."
sudo cp "${MOBILE_DIR}/os/overlay/etc/systemd/system/ad4m-executor.service" "${MNT}/etc/systemd/system/"
sudo mkdir -p "${MNT}/etc/systemd/system/multi-user.target.wants"
sudo ln -sf /etc/systemd/system/ad4m-executor.service "${MNT}/etc/systemd/system/multi-user.target.wants/ad4m-executor.service"

echo "[5/7] Desktop entries..."
sudo mkdir -p "${MNT}/etc/xdg/autostart" "${MNT}/usr/share/applications"
cat << 'DESK' | sudo tee "${MNT}/etc/xdg/autostart/we.desktop" > /dev/null
[Desktop Entry]
Name=WE
Comment=AD4M WE Interface
Exec=we-webview http://localhost:8080
Type=Application
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=5
DESK
sudo cp "${MNT}/etc/xdg/autostart/we.desktop" "${MNT}/usr/share/applications/we.desktop"

echo "[6/7] glibc stubs library..."
gcc -shared -fPIC -o /tmp/libglibc_stubs.so "${MOBILE_DIR}/os/glibc_stubs.c"
sudo cp /tmp/libglibc_stubs.so "${MNT}/usr/lib/libglibc_stubs.so"

echo "[7/8] gcompat (glibc compat)..."
if [ ! -f "${MNT}/lib/libc.so.6" ]; then
    sudo cp "${CHROOT}/usr/lib/libgcompat.so.0" "${MNT}/usr/lib/"
    sudo cp "${CHROOT}/usr/lib/libgcompat.so.0" "${MNT}/lib/"
    sudo ln -sf libgcompat.so.0 "${MNT}/lib/libc.so.6"
    sudo ln -sf libgcompat.so.0 "${MNT}/usr/lib/libc.so.6"
    sudo cp -P "${CHROOT}/lib/ld-linux-x86-64.so.2" "${MNT}/lib/"
    sudo mkdir -p "${MNT}/lib64"
    sudo ln -sf ../lib/ld-linux-x86-64.so.2 "${MNT}/lib64/ld-linux-x86-64.so.2"
fi

echo "[8/8] Mainnet seed + SSH forwarding fix..."
sudo cp "${AD4M_DIR}/rust-executor/src/mainnet_seed.json" "${MNT}/home/user/.ad4m/mainnet_seed.seed"
# Enable SSH TCP forwarding for debugging tunnels
sudo sed -i "s/^AllowTcpForwarding no/AllowTcpForwarding yes/" "${MNT}/etc/ssh/sshd_config" 2>/dev/null || true

sudo chown -R 10000:10000 "${MNT}/home/user/.ad4m" 2>/dev/null || true

echo ""
echo "=== Done — boot with: ==="
echo "qemu-system-x86_64 -cpu max -smp 4 -m 4096 \\"
echo "  -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd \\"
echo "  -drive if=virtio,format=raw,file=$IMG \\"
echo "  -device virtio-net-pci,netdev=net0 \\"
echo "  -netdev user,id=net0,hostfwd=tcp::2222-:22 \\"
echo "  -display none -serial stdio -device virtio-rng-pci"

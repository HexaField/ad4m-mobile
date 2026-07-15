#!/bin/bash
# Inject AD4M Mobile components into a PostmarketOS disk image.
# Usage: inject-into-image.sh [qemu|fp5]
# Default: qemu (x86_64). Use fp5 for Fairphone 5 (aarch64).
#
# For QEMU: modifies the raw disk image in-place via losetup.
# For FP5: injects into pmbootstrap chroot, then builds a new
#           GPT disk image and converts to Android sparse format.
set -euo pipefail

TARGET="${1:-qemu}"
REAL_HOME="${SUDO_USER:+$(eval echo ~$SUDO_USER)}"
REAL_HOME="${REAL_HOME:-$HOME}"
MOBILE_DIR="$(cd $(dirname $0)/.. && pwd)"
AD4M_DIR="$REAL_HOME/workspaces/coasys/ad4m"
WE_DIR="$REAL_HOME/workspaces/coasys/we"
PM_BASE="$REAL_HOME/.local/var/pmbootstrap"

case "$TARGET" in
    qemu)
        IMG="${PM_BASE}/chroot_native/home/pmos/rootfs/qemu-amd64.img"
        CHROOT="${PM_BASE}/chroot_rootfs_qemu-amd64"
        EXECUTOR="${AD4M_DIR}/target/release/ad4m-executor"
        CROSS_CC="gcc"
        LD_LINUX="ld-linux-x86-64.so.2"
        LD_DIR="lib64"
        ;;
    fp5)
        IMG="${PM_BASE}/chroot_native/home/pmos/rootfs/fairphone-fp5.img"
        CHROOT="${PM_BASE}/chroot_rootfs_fairphone-fp5"
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
[ -d "$CHROOT" ] || { echo "ERROR: Chroot $CHROOT not found. Run pmbootstrap install first."; exit 1; }

echo "=== Injecting AD4M Mobile into $TARGET ==="

# Inject into chroot directory
echo "[1/8] AD4M executor binary ($TARGET)..."
sudo cp "$EXECUTOR" "${CHROOT}/usr/bin/ad4m-executor"
sudo chmod 755 "${CHROOT}/usr/bin/ad4m-executor"

echo "[2/8] WE dist -> dapp directory..."
sudo mkdir -p "${CHROOT}/home/user/.ad4m/dapp"
sudo cp -r "${WE_DIR}/apps/we-web/dist/"* "${CHROOT}/home/user/.ad4m/dapp/"

echo "[3/8] we-webview wrapper..."
sudo cp "${MOBILE_DIR}/we-shell/we-webview" "${CHROOT}/usr/bin/we-webview"
sudo chmod 755 "${CHROOT}/usr/bin/we-webview"

echo "[4/8] systemd unit + enable..."
sudo cp "${MOBILE_DIR}/os/overlay/etc/systemd/system/ad4m-executor.service" "${CHROOT}/etc/systemd/system/"
sudo mkdir -p "${CHROOT}/etc/systemd/system/multi-user.target.wants"
sudo ln -sf /etc/systemd/system/ad4m-executor.service "${CHROOT}/etc/systemd/system/multi-user.target.wants/ad4m-executor.service"

echo "[5/8] Desktop entries..."
sudo mkdir -p "${CHROOT}/etc/xdg/autostart" "${CHROOT}/usr/share/applications"
cat << DESK | sudo tee "${CHROOT}/etc/xdg/autostart/we.desktop" > /dev/null
[Desktop Entry]
Name=WE
Comment=AD4M WE Interface
Exec=we-webview
Type=Application
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=5
DESK
sudo cp "${CHROOT}/etc/xdg/autostart/we.desktop" "${CHROOT}/usr/share/applications/we.desktop"

echo "[6/8] glibc stubs library..."
STUB_OUT="/tmp/libglibc_stubs_${TARGET}.so"
$CROSS_CC -shared -fPIC -o "$STUB_OUT" "${MOBILE_DIR}/os/glibc_stubs.c"
sudo cp "$STUB_OUT" "${CHROOT}/usr/lib/libglibc_stubs.so"

echo "[7/8] gcompat (glibc compat layer)..."
if [ ! -f "${CHROOT}/usr/lib/libgcompat.so.0" ]; then
    echo "  gcompat not installed — run: pmbootstrap chroot --suffix rootfs_<device> -- apk add gcompat"
    exit 1
fi

echo "[8/8] Mainnet seed + SSH forwarding..."
sudo cp "${AD4M_DIR}/rust-executor/src/mainnet_seed.json" "${CHROOT}/home/user/.ad4m/mainnet_seed.seed"
sudo sed -i "s/^AllowTcpForwarding no/AllowTcpForwarding yes/" "${CHROOT}/etc/ssh/sshd_config" 2>/dev/null || true
sudo chown -R 10000:10000 "${CHROOT}/home/user/.ad4m" 2>/dev/null || true

echo "=== Chroot injection complete ==="

# Build disk image from chroot
echo ""
echo "=== Building disk image from chroot ==="

# Shutdown pmbootstrap chroots to ensure clean state
"$REAL_HOME/.local/bin/pmbootstrap" shutdown 2>/dev/null || true

ROOT_SIZE=$(sudo du -sm "$CHROOT" --exclude="$CHROOT/boot" | cut -f1)
BOOT_SIZE=$(sudo du -sm "$CHROOT/boot" | cut -f1)
BOOT_PART=$((BOOT_SIZE + 100))
TOTAL_MB=$((ROOT_SIZE + BOOT_PART + 300))

RAW_IMG="/tmp/fp5-build.img"
MNT_ROOT="/tmp/pmos-root"
MNT_BOOT="/tmp/pmos-boot"

echo "Root: ${ROOT_SIZE}MB, Boot: ${BOOT_SIZE}MB, Image: ${TOTAL_MB}MB"

truncate -s ${TOTAL_MB}M "$RAW_IMG"

sudo sgdisk -Z "$RAW_IMG" 2>/dev/null || true
sudo sgdisk -n 1:0:+${BOOT_PART}M -t 1:EF00 -c 1:pmOS_boot "$RAW_IMG" >/dev/null
sudo sgdisk -n 2:0:0 -t 2:8300 -c 2:pmOS_root "$RAW_IMG" >/dev/null

LOOP=$(sudo losetup -f --show -P "$RAW_IMG")

sudo mkfs.fat -F 32 -n pmOS_boot "${LOOP}p1" >/dev/null
sudo mkfs.ext4 -F -q -L pmOS_root -i 8192 "${LOOP}p2"

sudo mkdir -p "$MNT_ROOT" "$MNT_BOOT"
sudo mount "${LOOP}p2" "$MNT_ROOT"
sudo mount "${LOOP}p1" "$MNT_BOOT"

echo "Copying rootfs..."
sudo rsync -aHX --exclude=/boot/* "$CHROOT/" "$MNT_ROOT/"
echo "Copying boot..."
sudo rsync -aHX "$CHROOT/boot/" "$MNT_BOOT/"

echo "Verifying..."
ls "$MNT_ROOT/usr/bin/ad4m-executor" >/dev/null
ls "$MNT_ROOT/home/user/.ad4m/dapp/index.html" >/dev/null
ls "$MNT_ROOT/usr/lib/libgcompat.so.0" >/dev/null
df -h "$MNT_ROOT" "$MNT_BOOT"

sudo umount "$MNT_BOOT"
sudo umount "$MNT_ROOT"
sudo losetup -d "$LOOP"

echo "Converting to sparse..."
img2simg "$RAW_IMG" "${IMG}"
rm -f "$RAW_IMG"
ls -lh "$IMG"

echo ""
echo "=== Done ($TARGET) ==="
if [ "$TARGET" = "qemu" ]; then
    echo "Boot: qemu-system-x86_64 ... -drive if=virtio,format=raw,file=$IMG ..."
else
    echo "Flash to Fairphone 5:"
    echo "  pmbootstrap flasher flash_rootfs"
    echo "  pmbootstrap flasher flash_kernel"
    echo "Or export: pmbootstrap export"
fi

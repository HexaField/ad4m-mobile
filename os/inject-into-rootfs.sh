#!/bin/bash
# Inject AD4M Mobile components into PostmarketOS rootfs chroot
# Run after: pmbootstrap install
# Run before: pmbootstrap qemu
set -euo pipefail

CHROOT="${CHROOT:-/home/josh/.local/var/pmbootstrap/chroot_rootfs_qemu-amd64}"
MOBILE_DIR="$(cd $(dirname $0)/.. && pwd)"
AD4M_DIR="/home/josh/workspaces/coasys/ad4m"
WE_DIR="/home/josh/workspaces/coasys/we"

echo '=== Injecting AD4M Mobile components into rootfs ==='

# 1. AD4M executor binary
BINARY="${AD4M_DIR}/target/release/ad4m"
if [ ! -f "$BINARY" ]; then
    echo "ERROR: Executor binary not found at $BINARY"
    exit 1
fi
echo "[1/7] Copying AD4M executor binary..."
sudo cp "$BINARY" "${CHROOT}/usr/bin/ad4m"
sudo chmod 755 "${CHROOT}/usr/bin/ad4m"

# 2. Pre-populate the dapp directory with WE dist
# The executor extracts its built-in dapp to ~/.ad4m/dapp/ on first run.
# We replace that with WE so the dapp server (port 8080) serves WE.
WE_DIST="${WE_DIR}/apps/we-web/dist"
if [ ! -d "$WE_DIST" ]; then
    echo "ERROR: WE dist not found at $WE_DIST"
    exit 1
fi
echo "[2/7] Pre-populating dapp directory with WE dist..."
sudo mkdir -p "${CHROOT}/home/user/.ad4m/dapp"
sudo cp -r "${WE_DIST}/"* "${CHROOT}/home/user/.ad4m/dapp/"

# 3. WE WebView wrapper
echo "[3/7] Installing we-webview..."
sudo cp "${MOBILE_DIR}/we-shell/we-webview" "${CHROOT}/usr/bin/we-webview"
sudo chmod 755 "${CHROOT}/usr/bin/we-webview"

# 4. Systemd unit for executor
echo "[4/7] Installing systemd unit..."
sudo cp "${MOBILE_DIR}/os/overlay/etc/systemd/system/ad4m-executor.service" \
    "${CHROOT}/etc/systemd/system/ad4m-executor.service"
sudo mkdir -p "${CHROOT}/etc/systemd/system/multi-user.target.wants"
sudo ln -sf /etc/systemd/system/ad4m-executor.service \
    "${CHROOT}/etc/systemd/system/multi-user.target.wants/ad4m-executor.service"

# 5. Autostart desktop entry for WE (launches in Phosh session)
echo "[5/7] Installing WE autostart..."
sudo mkdir -p "${CHROOT}/etc/xdg/autostart"
# Update URL to point at dapp server port
cat << 'DESKTOP' | sudo tee "${CHROOT}/etc/xdg/autostart/we.desktop" > /dev/null
[Desktop Entry]
Name=WE
Comment=AD4M WE Interface
Exec=we-webview http://localhost:8080
Type=Application
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=5
DESKTOP

# 6. Also add a .desktop entry in applications for manual launch
echo "[6/7] Installing WE application entry..."
sudo mkdir -p "${CHROOT}/usr/share/applications"
cat << 'DESKTOP' | sudo tee "${CHROOT}/usr/share/applications/we.desktop" > /dev/null
[Desktop Entry]
Name=WE
Comment=AD4M WE Interface
Exec=we-webview http://localhost:8080
Type=Application
Categories=Network;
Icon=web-browser
DESKTOP

# 7. Fix ownership
echo "[7/7] Setting ownership..."
sudo chown -R 1000:1000 "${CHROOT}/home/user/.ad4m" 2>/dev/null || true

echo ''
echo '=== All components injected ==='
echo "Rootfs: $CHROOT"
echo ''
echo 'Next: pmbootstrap qemu --image-size 8G -m 4096'

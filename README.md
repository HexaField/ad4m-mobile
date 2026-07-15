# AD4M Mobile

A Linux phone OS that runs [AD4M](https://ad4m.dev) as a persistent system service with [WE](https://github.com/coasys/we) as the full-screen UI shell. No Android. No cloud. Your agent, your phone, your data.

Built on [PostmarketOS](https://postmarketos.org/) (Alpine Linux + systemd + Phosh), targeting phones with mainline kernel support.

## Architecture

```
PostmarketOS (Alpine, systemd, Phosh)
│
├── Phosh (mobile shell: lock screen, notifications, settings)
│   └── we-webview (GTK4 + WebKitGTK 6.0)
│       └── WE (SolidJS UI) ── ad4m-connect ──> WebSocket :12000
│
└── ad4m-executor.service (systemd, auto-start)
    ├── Rocket dapp server ── :8080 (serves WE dist)
    ├── GraphQL / WebSocket API ── :12000
    └── Deno V8 · Oxigraph · SQLite
```

The executor runs headless as a systemd service. WE renders in a fullscreen WebKitGTK webview managed by Phosh. On first boot the agent auto-initialises; on subsequent boots it auto-unlocks. No login flow, no cloud auth — localhost only.

## Supported Devices

Any aarch64 phone with PostmarketOS community-tier support and 4GB+ RAM.

| Device | SoC | RAM | pmOS Tier | Notes |
|--------|-----|-----|-----------|-------|
| **OnePlus 6 / 6T** | Snapdragon 845 | 6–8 GB | Community | Best value. ~$100–150 AUD used. |
| **Xiaomi Poco F1** | Snapdragon 845 | 6–8 GB | Community | MicroSD slot. WiFi can be flaky. |
| **Fairphone 4** | Snapdragon 750G | 6–8 GB | Community | Modular, repairable. EU market. |
| **Fairphone 5** | QCM6490 | 8 GB | Testing | Expensive, hard to source in AU. |
| Pixel 3a / 3a XL | Snapdragon 670 | 4 GB | Community | Tight on RAM for this workload. |
| PinePhone Pro | RK3399S | 4 GB | Community | Poor battery life. Discontinued. |

The executor binary is ~136 MB with embedded V8, so 4 GB RAM is the practical minimum. 6–8 GB recommended.

## Build

### Prerequisites

```bash
pip install --user pmbootstrap
sudo apt install gcc-aarch64-linux-gnu g++-aarch64-linux-gnu android-sdk-libsparse-utils
```

### 1. Build the executor (aarch64 cross-compile)

```bash
cd ~/workspaces/coasys/ad4m    # branch: strip-holochain-prolog-cloud

export CC_aarch64_unknown_linux_gnu=aarch64-linux-gnu-gcc
export CXX_aarch64_unknown_linux_gnu=aarch64-linux-gnu-g++
export AR_aarch64_unknown_linux_gnu=aarch64-linux-gnu-ar
export BINDGEN_EXTRA_CLANG_ARGS_aarch64_unknown_linux_gnu='--sysroot=/usr/aarch64-linux-gnu -I/usr/aarch64-linux-gnu/include'

cargo build --release --target aarch64-unknown-linux-gnu -p ad4m
```

### 2. Build the OS image

```bash
pmbootstrap init          # select your device (e.g. oneplus-enchilada)
pmbootstrap install
pmbootstrap chroot --suffix rootfs_<device> -- apk add gcompat

cd ~/workspaces/coasys/ad4m-mobile
sudo bash os/inject-into-image.sh <target>   # qemu or fp5
```

The inject script:
1. Copies the executor binary, WE dist, webview wrapper, systemd unit, and glibc compatibility layer into the pmbootstrap chroot
2. Builds a GPT disk image (FAT32 boot + ext4 root) from the chroot
3. Converts to Android sparse format for fastboot

### 3. Flash

```bash
# Phone in fastboot mode (Vol Down + Power)
pmbootstrap flasher flash_rootfs
pmbootstrap flasher flash_kernel
```

### QEMU (x86_64 testing)

```bash
cargo build --release -p ad4m
pmbootstrap init    # qemu-amd64
pmbootstrap install
pmbootstrap chroot --suffix rootfs_qemu-amd64 -- apk add gcompat
sudo bash os/inject-into-image.sh qemu

# Boot the VM
bash vm/run-qemu.sh
```

## Repo Layout

```
os/
  inject-into-image.sh       inject components + build flashable image
  glibc_stubs.c              gcompat shims (glibc symbols missing from musl)
  overlay/                   systemd units, desktop entries
we-shell/
  we-webview                 GTK4 + WebKitGTK wrapper with auto-connect
languages/
  local-store/               single-user key-value link language
vm/
  run-qemu.sh                QEMU launch script for x86_64 testing
plan/                        design notes
```

## How It Works

**glibc on musl:** The executor is compiled on Ubuntu (glibc) but PostmarketOS uses musl. [gcompat](https://git.adelielinux.org/nicoroeser/gcompat) bridges the gap, with `libglibc_stubs.so` (LD_PRELOAD) providing a handful of missing symbols.

**Auto-init:** The executor starts with `--auto-init-passphrase ad4m`. First boot creates agent keys and unlocks. Subsequent boots load and auto-unlock. No interactive setup needed.

**WE auto-connect:** The webview wrapper loads `http://localhost:8080` (Rocket dapp server) and injects JavaScript to call `connectLocalNode()` on the ad4m-connect element. Since `admin_credential` is unset, an empty token gets full access — safe for a localhost-only single-user phone.

**V8 snapshots:** The Deno V8 snapshot generated during x86_64 compilation is portable to aarch64 (same pointer width, no compression). No need to regenerate on the target arch.

## AD4M Fork

This uses a stripped fork of AD4M ([branch `strip-holochain-prolog-cloud`](https://github.com/coasys/ad4m)) with Holochain, scryer-prolog, kalosm AI, billing, and email modules removed. The result is a local-only agent runtime — no cloud dependencies, no heavy optional subsystems.

## License

To be determined. The AD4M executor fork inherits upstream licensing. PostmarketOS components are Alpine-packaged under their respective licenses. Code in this repository is original work.

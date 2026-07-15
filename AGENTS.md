# AD4M Mobile — PostmarketOS Phone Build

## Overview

A mobile Linux phone OS that runs AD4M as a persistent system service with WE as the full-screen UI shell. Target hardware: Fairphone 5 (QCM6490, aarch64, 8GB RAM). Base OS: PostmarketOS (Alpine/musl, systemd).

Key decisions:
- **AD4M fork** (branch `strip-holochain-prolog-cloud` in `coasys/ad4m`) strips Holochain, scryer-prolog, kalosm AI, billing, email — local-only agent runtime
- **WE** (SolidJS + Lit) runs as the phone UI via WebKitGTK 6.0 WebView in Phosh
- **PostmarketOS** provides real Linux (systemd, Phosh shell, no Android)
- **gcompat + libglibc_stubs.so** bridges glibc binaries on musl

## Architecture

```
┌──────────────────────────────────────────────────┐
│                 PostmarketOS                     │
│           (Alpine, systemd, Phosh)               │
│                                                  │
│  ┌────────────────────────────────────────────┐  │
│  │         Phosh (phone shell)                │  │
│  │   lock screen · notifications · settings   │  │
│  │  ┌──────────────────────────────────────┐  │  │
│  │  │  we-webview (Python GTK4+WebKitGTK)  │  │  │
│  │  │  ┌────────────────────────────────┐  │  │  │
│  │  │  │         WE (SolidJS)           │  │  │  │
│  │  │  │   ad4m-connect → WS :12000     │  │  │  │
│  │  │  └────────────────────────────────┘  │  │  │
│  │  └──────────────────────────────────────┘  │  │
│  └────────────────────────────────────────────┘  │
│                                                  │
│  ┌────────────────────────────────────────────┐  │
│  │     ad4m-executor.service (systemd)        │  │
│  │     Rocket dapp server → :8080 (WE dist)   │  │
│  │     GraphQL/WS API → :12000                │  │
│  │  Deno V8 · Oxigraph · SQLite              │  │
│  └────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────┘
```

## Repo Layout

```
ad4m-mobile/
├── AGENTS.md
├── os/
│   ├── overlay/etc/systemd/system/ad4m-executor.service
│   ├── inject-into-image.sh    # mount image, inject components (qemu|fp5)
│   └── glibc_stubs.c           # gcompat shims for glibc→musl
├── we-shell/
│   └── we-webview              # Python GTK4+WebKitGTK wrapper
└── vm/
    ├── run-qemu.sh
    └── setup.sh
```

## Build

### x86_64 (QEMU testing)
```bash
cd ~/workspaces/coasys/ad4m && cargo build --release
cd ~/workspaces/coasys/ad4m-mobile && sudo bash os/inject-into-image.sh qemu
```

### aarch64 (Fairphone 5)
```bash
cd ~/workspaces/coasys/ad4m
export CC_aarch64_unknown_linux_gnu=aarch64-linux-gnu-gcc
export CXX_aarch64_unknown_linux_gnu=aarch64-linux-gnu-g++
export AR_aarch64_unknown_linux_gnu=aarch64-linux-gnu-ar
export BINDGEN_EXTRA_CLANG_ARGS_aarch64_unknown_linux_gnu='--sysroot=/usr/aarch64-linux-gnu -I/usr/aarch64-linux-gnu/include'
cargo build --release --target aarch64-unknown-linux-gnu -p ad4m
# Binary: target/aarch64-unknown-linux-gnu/release/ad4m-executor (136MB stripped)

cd ~/workspaces/coasys/ad4m-mobile && sudo bash os/inject-into-image.sh fp5
```

### Flash Fairphone 5
```bash
pmbootstrap flasher flash_rootfs
pmbootstrap flasher flash_kernel
```

## Gotchas

- **Binary is `ad4m-executor`, not `ad4m`.** The `ad4m` binary is the CLI client.
- **glibc/musl mismatch.** gcompat + libglibc_stubs.so (LD_PRELOAD) handles the gap.
- **pmOS user UID is 10000**, not 1000. The inject script handles ownership.
- **admin_credential is unset.** Empty tokens get ALL_CAPABILITY. Safe for localhost-only phone.
- **Auto-init passphrase.** `--auto-init-passphrase ad4m` in the service unit. First boot creates agent; subsequent boots auto-unlock.
- **ad4m-connect auto-connect.** we-webview injects JS to call `connectLocalNode()` after page loads. Works because admin_credential=None → empty token → ALL_CAPABILITY.
- **V8 snapshot portability.** The x86_64-generated Deno snapshot works on aarch64 (both 64-bit, no pointer compression). No need to regenerate.
- **Cross-compile OpenSSL.** Uses vendored feature (openssl = { features = ["vendored"] }) to avoid cross-compiled system libssl.
- **Mainnet seed.** Must be copied to ~/.ad4m/mainnet_seed.seed for RuntimeService. The inject script handles this from the embedded source.

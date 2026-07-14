# AD4M Mobile — PostmarketOS Phone Build

## Overview

A mobile Linux phone OS that runs AD4M as a persistent system service with WE as the full-screen UI shell. Target hardware: Fairphone 5 (QCM6490, aarch64, 8GB RAM). Base OS: PostmarketOS (Alpine/musl, systemd).

Key decisions:
- **AD4M fork** (branch `strip-holochain-prolog-cloud` in `~/workspaces/coasys/ad4m`) strips Holochain, scryer-prolog, kalosm AI, billing, email — local-only agent runtime
- **WE** (SolidJS + Lit) runs as the phone UI via WebKitGTK 6.0 WebView in Phosh
- **PostmarketOS** provides real Linux (systemd, Phosh shell, no Android)
- **gcompat + libglibc_stubs.so** bridges glibc binaries on musl — works for x86_64 QEMU testing

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
│  │                                            │  │
│  │  Deno V8 (language runtime)                │  │
│  │  Oxigraph (RDF/SPARQL)                     │  │
│  │  SQLite                                    │  │
│  │  (local only — no P2P transport)           │  │
│  └────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────┘
```

## Repo Layout

```
ad4m-mobile/
├── AGENTS.md                   # this file
├── plan/PLAN.md                # implementation plan
├── os/
│   ├── overlay/etc/systemd/system/ad4m-executor.service
│   ├── overlay/etc/xdg/autostart/we.desktop
│   ├── inject-into-image.sh    # mount image, inject all components
│   ├── inject-into-rootfs.sh   # legacy chroot injection (don't use)
│   └── glibc_stubs.c           # gcompat shims for glibc→musl
├── languages/local-store/      # local-only stub link language
│   ├── index.ts                # defineLanguage() entry point
│   ├── src/store.ts            # KV-backed link store
│   └── tests/store.test.ts     # 9 passing tests
├── we-shell/
│   ├── we-webview              # Python GTK4+WebKitGTK wrapper
│   └── we-webview.desktop
└── vm/
    ├── run-qemu.sh             # pmbootstrap QEMU launcher
    └── setup.sh
```

## Build & Test (x86_64 QEMU)

```bash
# Prerequisites (on josh machine)
# pmbootstrap (from git), Rust toolchain 1.92, Node 22, gcc

# 1. Build executor (branch strip-holochain-prolog-cloud)
cd ~/workspaces/coasys/ad4m
cargo build --release
# Binary: target/release/ad4m-executor (141MB stripped)

# 2. Build WE
cd ~/workspaces/coasys/we
npm run build
# Dist: apps/we-web/dist/ (11MB)

# 3. Build pmOS image
pmbootstrap init  # edge channel, qemu-amd64, phosh
pmbootstrap install

# 4. Inject into image
cd ~/workspaces/coasys/ad4m-mobile
sudo bash os/inject-into-image.sh

# 5. Boot QEMU (headless, SSH on 2222)
qemu-system-x86_64 -cpu max -smp 4 -m 4096 \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd \
  -drive if=virtio,format=raw,file=<image-path> \
  -device virtio-net-pci,netdev=net0 \
  -netdev user,id=net0,hostfwd=tcp::2222-:22 \
  -display none -serial stdio -device virtio-rng-pci

# 6. SSH in
sshpass -p ad4m ssh -p 2222 user@localhost
```

## Gotchas

- **Binary is `ad4m-executor`, not `ad4m`.** The `ad4m` binary is the CLI client (no `run` subcommand). Use `ad4m-executor run ...`.
- **glibc/musl mismatch.** The executor is compiled on Ubuntu (glibc) but pmOS uses musl. `gcompat` + `libglibc_stubs.so` (LD_PRELOAD) handles the gap. Missing symbols: `__res_init`, `__isoc23_sscanf/strtol*`, `fcntl64`.
- **No KVM on josh machine.** User `josh` isn't in the `kvm` group. QEMU runs in software emulation (slower but works).
- **File ownership.** Injected files end up as root; must `chown -R user:user /home/user/.ad4m` before executor can start.
- **Image vs chroot.** `pmbootstrap install` creates both a rootfs chroot and a disk image. They're separate — inject into the **image** (use `inject-into-image.sh`), not the chroot.
- **Dapp server.** The executor extracts its built-in dapp to `~/.ad4m/dapp/`. We pre-populate this with WE dist so the Rocket server on :8080 serves WE.

## Current Status

- [x] Executor compiles (0 errors, surgery complete)
- [x] WE built to dist (11MB SPA)
- [x] Local-store link language (9/9 tests passing)
- [x] WebView wrapper (Python GTK4 + WebKitGTK 6.0)
- [x] PostmarketOS QEMU image boots with Phosh
- [x] Executor runs as systemd service, API on :12000, dapp on :8080
- [ ] WE actually connects to executor (needs init/agent setup)
- [ ] aarch64 cross-compile for Fairphone 5
- [ ] Local-store language bundled and loaded by executor

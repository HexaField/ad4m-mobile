# AD4M Mobile — PostmarketOS Phone Build

## Overview

A mobile Linux phone OS that runs AD4M as a persistent system service with WE as the full-screen UI shell. Target hardware: Fairphone 5 (QCM6490, aarch64, 8GB RAM). Base OS: PostmarketOS.

Key decisions:
- **AD4M fork** strips Holochain, scryer-prolog, and all networked languages — local-only agent runtime, networking added later
- **WE** (SolidJS + Lit web components) runs as the phone UI via a kiosk-mode Wayland compositor
- **PostmarketOS** provides real Linux (systemd, full networking, no Android process-killing)

## Architecture

```
┌──────────────────────────────────────────────────┐
│                 PostmarketOS                     │
│              (Alpine, systemd)                   │
│                                                  │
│  ┌────────────────────────────────────────────┐  │
│  │         cage (kiosk compositor)            │  │
│  │  ┌──────────────────────────────────────┐  │  │
│  │  │   Chromium (kiosk, --app=localhost)  │  │  │
│  │  │  ┌────────────────────────────────┐  │  │  │
│  │  │  │         WE (SolidJS)           │  │  │  │
│  │  │  │   ad4m-connect → WS :12000     │  │  │  │
│  │  │  └────────────────────────────────┘  │  │  │
│  │  └──────────────────────────────────────┘  │  │
│  └────────────────────────────────────────────┘  │
│                                                  │
│  ┌────────────────────────────────────────────┐  │
│  │     ad4m-executor.service (systemd)        │  │
│  │                                            │  │
│  │  ┌──────────┐  ┌────────────┐              │  │
│  │  │ Language  │  │  Language   │  (on demand)│  │
│  │  │ (Deno V8) │  │  (Deno V8)  │             │  │
│  │  └──────────┘  └────────────┘              │  │
│  │                                            │  │
│  │  ┌──────────────────────────┐              │  │
│  │  │  Oxigraph (RDF/SPARQL)  │              │  │
│  │  └──────────────────────────┘              │  │
│  │                                            │  │
│  │  SQLite · WebSocket RPC :12000             │  │
│  │  (local only — no P2P transport)           │  │
│  └────────────────────────────────────────────┘  │
│                                                  │
│  squeekboard (on-screen keyboard)                │
│  NetworkManager · avahi (mDNS)                   │
└──────────────────────────────────────────────────┘
```

## Repo Layout

```
ad4m-mobile/
├── AGENTS.md               # this file
├── plan/
│   └── PLAN.md             # implementation plan
├── os/                     # PostmarketOS image config
│   ├── overlay/            # rootfs overlay (systemd units, configs)
│   └── pmbootstrap.cfg     # device config
├── executor/               # AD4M fork patches / build scripts
│   └── patches/            # quilt-style patches against upstream ad4m
├── we-shell/               # WE build config for kiosk mode
│   └── cage-session.sh     # compositor launch script
└── vm/                     # local dev VM scripts
    └── run-qemu.sh         # pmbootstrap QEMU launcher
```

## Build Commands

```bash
# VM dev environment (x86_64, KVM-accelerated)
./vm/run-qemu.sh

# Nested Phosh on desktop (fastest UI iteration)
./vm/run-nested.sh

# Build AD4M executor (from upstream fork)
cd executor && cargo build --release --target aarch64-unknown-linux-musl

# Build WE for kiosk
cd we-shell && pnpm build
```

## Dev Setup

Requires:
- `pmbootstrap` (pip install pmbootstrap)
- Rust toolchain with `aarch64-unknown-linux-musl` target
- Node 20+ / pnpm for WE builds
- QEMU with KVM for local testing

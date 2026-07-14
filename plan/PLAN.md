# AD4M Mobile — Implementation Plan

## Goal

Build a phone OS image (PostmarketOS) that boots into AD4M + WE as a persistent P2P agent node. The phone is a first-class AD4M node — always on, always connected, always participating in neighbourhoods.

## Non-goals

- Android support (that's the Volla/Holochain path)
- iOS support
- General-purpose phone OS (this is a purpose-built AD4M device)
- Shipping to end users (local iteration, proof of concept)

## Constraints

- Fairphone 5: QCM6490 (aarch64), 8GB RAM, ~128GB storage
- Battery: AD4M must be resource-conscious — lazy language loading, configurable P2P participation
- Offline-first: must work without internet, syncing when connectivity returns

---

## Phase 1: Dev Environment

Set up local virtualised PostmarketOS to iterate without hardware.

### 1.1 pmbootstrap QEMU (full OS)

PostmarketOS has first-class qemu-amd64 support. This gives us a real pmOS image running under KVM.

```bash
pip install pmbootstrap
pmbootstrap init              # device: qemu-amd64, UI: phosh
pmbootstrap install --sdcard=qemu
pmbootstrap qemu --image-size=8G -m 4096 --display sdl,gl=on --tablet
```

This runs Phosh (GNOME-based phone shell) in a QEMU VM. Near-native performance via KVM. Use this for full integration testing — systemd services, networking, the whole stack.

### 1.2 Nested Phosh (fast UI iteration)

Run Phosh directly on the desktop as a nested Wayland compositor. No VM overhead.

```bash
# Install
sudo apt install phosh phoc squeekboard

# Run nested
export WLR_BACKENDS=wayland
export GSETTINGS_BACKEND=memory
phoc -C /usr/share/phosh/phoc.ini &
WAYLAND_DISPLAY=wayland-1 dbus-run-session /usr/libexec/phosh
```

Use this for rapid UI iteration — testing WE in a phone-sized viewport at native speed.

### 1.3 Cage kiosk (WE-only testing)

Test just the WE kiosk shell without the full phone UI:

```bash
sudo apt install cage chromium-browser
cage -- chromium-browser --kiosk --app=http://localhost:3000 --window-size=390,844
```

---

## Phase 2: AD4M Executor Fork

Fork `ad4m/rust-executor` and remove Holochain + Prolog. The executor should build and run as a standalone P2P agent runtime.

### 2.1 Remove Holochain

Holochain is embedded in the executor at these touch points:

| Location | What | Action |
|---|---|---|
| `Cargo.toml` | `holochain`, `holochain_cli_bundle`, `holochain_types`, `lair_keystore_api`, `kitsune_p2p_types`, `holochain_cli_run_local_services` | Remove deps |
| `src/holochain_service/` | Conductor init, DHT ops, signal routing | Remove module |
| `src/init.rs` | Conductor startup in executor init | Remove HC init path |
| `src/lib.rs` | Module declarations | Remove `mod holochain_service` |
| `src/languages/` | Language loading references HC for Holochain-backed languages | Make HC language support a no-op / stub trait |
| `src/neighbourhoods.rs` | Neighbourhood sync via Holochain | Replace with pluggable sync trait |

The goal is not to rewrite neighbourhood sync yet — just make the executor compile and run without Holochain. Neighbourhoods that require Holochain simply won't load. Languages are already isolated Deno workers; non-HC languages keep working.

### 2.2 Remove scryer-prolog

| Location | What | Action |
|---|---|---|
| `Cargo.toml` | `scryer-prolog` | Remove dep |
| `src/prolog.rs` | Prolog engine wrapper | Remove |
| `src/prolog_service/` | Prolog query service | Remove module |
| `src/lib.rs` | Module declarations | Remove `mod prolog`, `mod prolog_service` |
| Any SPARQL/reasoning paths | Prolog-backed inference | Gracefully degrade (Oxigraph SPARQL still works) |

### 2.3 Remove / feature-gate heavy optional deps

| Dep | Purpose | Action |
|---|---|---|
| `kalosm` | Local AI inference (LLM + voice) | Feature-gate behind `ai` feature, off by default |
| `voice_activity_detector`, `rodio`, `candle-core` | Audio/voice | Feature-gate with `ai` |
| `chat-gpt-lib-rs` | OpenAI API | Feature-gate behind `cloud-ai` |
| `lettre` | Email sending | Remove (not needed on phone) |
| `webbrowser` | Open browser | Remove (we ARE the browser) |
| `billing.rs`, `email_service.rs`, `user_management.rs` | Cloud/SaaS features | Remove |

### 2.4 Add lightweight P2P default

Replace Holochain's Kitsune2 as the default neighbourhood transport:

- **libp2p** with QUIC transport for peer connections
- **gossipsub** for neighbourhood message propagation
- **mDNS** for local peer discovery (avahi on pmOS)
- **Rendezvous** or relay for NAT traversal

This is a trait — `NeighbourhoodTransport` — so Holochain can be re-added as a language-provided transport later. The default libp2p transport handles the common case.

### 2.5 Lazy language loading

Current behaviour: all installed languages load at startup.
Phone behaviour: languages load on first access, unload after idle timeout.

Add lifecycle to `LanguageController`:
- `load(address)` — spin up Deno worker thread
- `suspend(address)` — pause worker, keep state
- `unload(address)` — tear down worker, free memory
- Configurable idle timeout (default: 5 min)

---

## Phase 3: WE as Phone Shell

WE is a SolidJS SPA with Lit web components. It connects to AD4M via `@coasys/ad4m-connect` over WebSocket. To make it the phone UI:

### 3.1 Kiosk compositor

Use **cage** (minimal Wayland kiosk compositor from wlroots) to run a single full-screen application. No window management, no taskbar — just WE.

```
cage -- chromium --kiosk --app=http://localhost:5173
```

cage handles:
- Full-screen display
- Touch input routing
- On-screen keyboard integration (via squeekboard, spawned separately or via input-method protocol)

### 3.2 WE mobile adaptations

WE's design system (7-layer: tokens → themes → elements → components → widgets → pages → templates) is framework-agnostic via Lit web components. The SolidJS app needs mobile adaptations:

- **Viewport**: lock to device dimensions, no scroll-zoom
- **Touch**: all interactions must be touch-friendly (48px min tap targets)
- **Navigation**: bottom nav bar pattern (tab-based, not sidebar)
- **On-screen keyboard**: layout must reflow when squeekboard appears
- **Status bar**: battery, signal, time — either via a WE component reading system APIs, or a thin native status bar overlay

### 3.3 System integration

WE needs to surface phone-level functions:
- **Notifications**: AD4M signals → system notifications (via libnotify / D-Bus)
- **Connectivity status**: NetworkManager D-Bus → WE indicator
- **Battery**: UPower D-Bus → WE indicator
- **Settings**: WiFi, Bluetooth, volume — either via WE pages calling system D-Bus, or Phosh's quick-settings panel as a separate layer

### 3.4 Alternative: Phosh + WE app

Instead of replacing the phone shell entirely, run Phosh as the compositor and auto-launch WE as a maximised GTK WebView app. This gives you:
- Lock screen, notifications, quick settings for free (Phosh provides these)
- WE runs as a "launcher" app — always visible, always maximised
- Other apps (terminal, settings) accessible via Phosh's app drawer

Trade-off: less "bespoke" feel, more polish out of the box. Recommend starting here and graduating to cage-only once WE handles all system functions.

---

## Phase 4: OS Image

### 4.1 PostmarketOS package

Package the AD4M executor as an Alpine APK:

```
APKBUILD:
  pkgname=ad4m-executor
  pkgver=0.13.0
  build() { cargo build --release --target aarch64-unknown-linux-musl }
  package() { install -Dm755 target/release/ad4m-executor "$pkgdir/usr/bin/ad4m-executor" }
```

### 4.2 systemd unit

```ini
[Unit]
Description=AD4M Executor
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/ad4m-executor --config /etc/ad4m/config.toml
Restart=always
RestartSec=5
MemoryMax=3G
User=ad4m

[Install]
WantedBy=multi-user.target
```

### 4.3 WE kiosk session

```ini
# /usr/share/wayland-sessions/we-kiosk.desktop
[Desktop Entry]
Name=WE
Exec=/usr/libexec/we-session.sh
Type=Application
```

```bash
#!/bin/sh
# /usr/libexec/we-session.sh
squeekboard &
exec cage -- chromium --kiosk --app=http://localhost:12000/we
```

### 4.4 Custom image build

```bash
pmbootstrap init                    # device: fairphone-fp5, UI: none (custom session)
pmbootstrap install --add ad4m-executor,we-shell,cage,chromium,squeekboard
pmbootstrap export                  # → .img file for flashing
```

---

## Phase 5: Hardware Bring-up (when Fairphone 5 arrives)

1. Flash PostmarketOS via `pmbootstrap flasher flash_rootfs`
2. Verify boot, touch, WiFi, cellular, Bluetooth
3. Install AD4M executor package, verify it runs as systemd service
4. Install WE kiosk session, verify it launches and connects to executor
5. Test neighbourhood creation, language loading, P2P sync over WiFi
6. Battery profiling — measure idle drain with AD4M running

---

## Open Questions

1. **Chromium vs WebView**: Chromium in kiosk mode works but is heavy. A purpose-built WebView (servo? wry/tauri-without-tauri?) could be lighter. Investigate once baseline works.
2. **Cellular data**: does libp2p QUIC work over cellular NAT? Need relay/TURN.
3. **Push wakeup**: when the phone sleeps, how does the AD4M node wake for incoming messages? systemd inhibit locks? Wakelocks via kernel interface?
4. **Phone calls / SMS**: out of scope for v1, but eventually — ofono integration? ModemManager?
5. **Camera / sensors**: WE could access via Web APIs (getUserMedia etc.) through the browser — but Chromium on pmOS may need V4L2 integration.

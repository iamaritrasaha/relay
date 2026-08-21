# Relay

**One desktop for all the devices around you.**

Relay is a Linux-first cross-device continuity application with a GNOME/Yaru-oriented Flutter interface and independent KDE Connect-compatible device interoperability. It unifies phones, computers, and nearby devices through a coherent, restrained interface regardless of which supported protocol connects them.

```
                    Relay Desktop
                          │
                 Unified Device Layer
                          │
         ┌────────────────┼────────────────┐
         │                │                │
    KDE Connect       LocalSend        Relay-native
    compatible        compatible       continuity
```

The user interacts with nearby and paired devices and their live capabilities; the underlying transport protocols are clean implementation details.

---

## Key Features

### 🖥️ GNOME & Yaru Desktop Experience
- **GNOME/Yaru Interface:** Built for modern Linux desktop environments with a native Yaru theme, Ubuntu typography, handy_window rounded GTK3 window integration, and GNOME navigation patterns.
- **Ambient Motion & Liveliness:** Subtle multicolor device perimeter motion and breath animation on focal cards, paired with smooth edge sweeps on connection, selection, and transfers (fully respecting `prefers-reduced-motion` and Spatial Animations settings).
- **GNOME Shell Extension:** Integrated top-bar pill showing connected phone status, battery percentage, notification indicator, and cellular network signal with configurable presentation options.

### 📱 KDE Connect Compatibility
Relay embeds an independent Rust implementation of KDE Connect LAN protocols (v8) without requiring `kdeconnectd`, KDE Plasma, Kirigami, or KDE Frameworks:
- **LAN Discovery & Secure Pairing:** Mutual TLS handshake, persistent trust, and automatic reconnection.
- **Battery & Power State:** Real-time battery percentage, charging state, full charge indicators, and stale state detection.
- **Find Phone & Ping:** Audible ringing trigger (even when silent) and connection latency testing.
- **Clipboard Sync:** Bidirectional clipboard text synchronization.
- **Notification Mirroring:** Real-time phone notification streaming with action dismissing.
- **Messages & SMS:** Desktop split-view conversation viewer with thread history, unread counters, date grouping, and a multiline composer that sends with `Ctrl+Enter`.
- **Telephony & Call State:** Awareness of incoming ringing, active calls and missed calls, plus remote ringer muting, on phones that advertise telephony. Relay reports call state and silences the ringer; it does not place, answer or end calls from the desktop.

### ⚡ LocalSend Transfer Protocol
- Retains compatibility with the fast LocalSend local-network transfer protocol.
- High-speed peer-to-peer file, folder, and text transfers over encrypted local HTTPS with SHA-256 integrity verification.

### 🔒 Relay-Native Continuity
- Next-generation authenticated peer-to-peer identity, secure LAN routing, and extensible continuity capabilities.

---

## Architecture

```
app/ (Flutter / Libadwaita UI)
  │
  └── packages/relay_isolates/ (Dart Isolate Runtime + flutter_rust_bridge)
        │
        └── packages/core/ (Rust Protocol Implementation: KDE Connect, LocalSend, Crypto, WebRTC)
```

- **UI & State:** Flutter (`3.41.9`) using Refena Redux state management.
- **Protocol Engine:** Rust (`1.97.1`) in `packages/core` with asynchronous Tokio networking.
- **FFI Bridge:** `flutter_rust_bridge` (FRB v2) ensuring zero network or cryptography overhead on the UI thread.
- **Desktop Shell Integration:** GNOME Shell extension in `app/linux/gnome-shell/` communicating via D-Bus.

---

## Building from Source

### Prerequisites
- [FVM](https://fvm.app/) (Flutter Version Management)
- Rust toolchain (managed via `rust-toolchain.toml`)
- Linux build dependencies:

```bash
sudo apt install clang cmake ninja-build libgtk-3-dev libayatana-appindicator3-dev libsecret-1-dev
```

### Development & Testing

```bash
# Run tests
cargo test --features full            # in packages/core
fvm flutter test                     # in app/

# Analyze and format
fvm flutter analyze                  # in app/
fvm dart format --set-exit-if-changed lib test

# Launch debug app
cd app
fvm flutter run -d linux
```

### Local Build & Installation

Relay includes a dedicated Linux packaging script for direct compilation and user-space installation (`~/.local/bin/relay`):

```bash
./linux/install-relay-local.sh
```

To install the accompanying GNOME Shell top-bar pill:

```bash
cd app/linux/gnome-shell
./install-relay-extension.sh
```

---

## Ecosystem & Acknowledgements

- **[LocalSend](https://github.com/localsend/localsend):** Relay originated from the LocalSend codebase and retains portions of its cross-platform transfer infrastructure. Applicable upstream notices remain preserved. LocalSend is an independent project and does not endorse Relay.
- **[KDE Connect](https://kdeconnect.kde.org/):** Relay implements protocol-level compatibility to communicate seamlessly with existing KDE Connect Android devices. KDE Connect is an independent KDE project. Relay is not affiliated with or endorsed by KDE. Relay's KDE Connect integration runs independently without KDE desktop dependencies.

---

## License

Relay is licensed under the [Apache License 2.0](LICENSE).

© 2026 Aritra Saha

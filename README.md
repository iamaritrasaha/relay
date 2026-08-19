# Relay

**One desktop for all the devices around you.**

Relay is an open-source cross-device continuity application being developed desktop-first. Its goal is to present phones, computers, and nearby devices through one coherent desktop interface regardless of which supported protocol connects them.

```
                    Relay Desktop
                          │
                 Unified Device Layer
                          │
         ┌────────────────┼────────────────┐
         │                │                │
    KDE Connect       LocalSend        Relay-native
    compatible        compatible       mechanisms
```

The user sees devices and their capabilities; the underlying protocols are implementation details.

---

## Platform Focus

Relay is being developed with a clear platform priority:

1. **Linux** (active primary target)
2. **Windows** (second priority)
3. **Android** (later)

Linux is the active product target. Android Relay development is not currently a priority. During Linux development, phone integration is accomplished by connecting directly with mature, existing Android companion applications such as KDE Connect.

---

## Ecosystem Compatibility

### KDE Connect Compatibility

Relay implements direct KDE Connect protocol compatibility inside its own lightweight core.

Relay's KDE Connect compatibility layer does not depend on the KDE Connect desktop stack. It runs independently on any desktop environment (such as GNOME or standard window managers) without requiring:

- `kdeconnectd`
- KDE Plasma or KDE Frameworks
- KIO or Kirigami
- The KDE Connect desktop application's D-Bus API

#### Currently Verified Status

The physically verified foundation has been tested with real Android devices running KDE Connect and includes:

- KDE Connect protocol version 8 compatibility foundation
- LAN device discovery
- Secure TCP/TLS connection establishment
- Protocol-v8 secure identity exchange
- Pairing initiated from either side (desktop or mobile)
- Accept / reject pairing requests
- Persistent paired trust across sessions
- Automatic reconnection after Relay restart
- Unpair / remove device

#### Planned Capabilities

Capabilities planned for incremental implementation and physical validation include:

- Battery status and charging indicators
- Clipboard continuity
- Notifications sync
- Messages and SMS
- File and URL sharing
- Media playback controls
- Telephony status
- Contacts integration
- Remote commands

---

### LocalSend Compatibility

Relay originated from the LocalSend codebase and retains mature components of its cross-platform transfer and application infrastructure. Relay is not a simple rebrand: LocalSend compatibility is intended to serve as a dedicated transfer backend within Relay's unified device experience.

---

### Relay-Native Mechanisms

Relay includes foundational work toward its own authenticated device identity and transport layer. These mechanisms are designed for future Relay-to-Relay workflows and advanced capabilities where third-party compatibility protocols are insufficient.

---

## Architecture & Security

```
KDE Connect ─┐
LocalSend   ─┼──→ Unified Relay device/capability model ──→ Relay Desktop UI
Relay       ─┘
```

While Relay unifies device presence and capabilities in a single interface, each protocol's security domain remains isolated internally:

- **Discovery does not imply trust:** Nearby devices are visible only according to their discovery rules; pairing and capabilities require explicit authorization.
- **IP address is not identity:** Cryptographic certificates and persistent key exchanges define device identity, remaining stable across network changes.
- **No silent credential replacement:** Certificate or identity changes require explicit user re-verification.
- **Isolated trust domains:** KDE Connect, LocalSend, and Relay-native pairing and trust boundaries remain strictly separated.

---

## Design Direction

Relay aims to provide a calm, device-centric desktop hub:

- **Device-centric overview:** Nearby and paired devices visible in a single space.
- **Contextual capability surfaces:** Quick access to device health, battery levels, notifications, clipboard sharing, and transfer queues.
- **Polished desktop integration:** Native desktop conventions, system tray support, and responsive layouts.

---

## Project Status

**Status: Active Development**

Relay is actively evolving and is not yet a general-consumer stable release. Development proceeds in the following order:

1. Complete KDE Connect functionality on Linux
2. Improve and refine the Relay Linux UX and visual identity
3. Expand LocalSend integration
4. Expand Relay-native functionality
5. Windows platform support
6. Android application later

---

## Technology Stack

- **UI & State:** [Flutter](https://flutter.dev/) (pinned: `3.41.9`)
- **Core Engine & Networking:** [Rust](https://www.rust-lang.org/) (pinned: `1.97.1`)
- **FFI Bridge:** [flutter_rust_bridge](https://github.com/fzyzcjy/flutter_rust_bridge)

---

## Building from Source

### Prerequisites

- [FVM](https://fvm.app/) (Flutter Version Management)
- Rust toolchain (managed via `rust-toolchain.toml`)
- Linux development libraries for secure credential storage:

```bash
sudo apt install libsecret-1-dev
```

### Build & Run

```bash
# Clone the repository
git clone https://github.com/iamaritrasaha/relay.git
cd relay/app

# Install dependencies and run on Linux
fvm flutter pub get
fvm flutter run -d linux

# Build release executable
fvm flutter build linux --release
```

---

## Acknowledgements

- **[LocalSend](https://github.com/localsend/localsend):** Relay originated from the LocalSend codebase and retains portions of its cross-platform infrastructure. Applicable upstream notices remain preserved. LocalSend is an independent project and does not endorse Relay.
- **[KDE Connect](https://kdeconnect.kde.org/):** Relay implements compatible protocol behavior to communicate with existing KDE Connect devices. KDE Connect is an independent KDE project. Relay is not affiliated with or endorsed by KDE. Relay's KDE Connect integration does not vendor or require the KDE Connect desktop application.

---

## License

Relay is licensed under the [Apache License 2.0](LICENSE).

© 2026 Aritra Saha

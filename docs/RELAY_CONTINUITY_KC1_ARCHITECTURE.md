# Relay continuity with KDE Connect — KC1 architecture spike

Status: architecture and protocol research only

Research snapshot: 2026-08-18

Relay baseline: `relay/continuity-kde` at `56dffd8854e912a3fea86f622fefb22b46f1bb64`

This document does not authorize production implementation. It deliberately leaves Relay discovery, transfer, TLS, authenticated-peer trust, UI, and existing device state unchanged.

## 1. Executive recommendation

Adopt an **asymmetric, staged hybrid**, behind a provider-neutral continuity boundary:

- On Linux, prefer a **best-effort bridge to an installed `kdeconnectd` over the session D-Bus**. Let the official daemon own KDE discovery, protocol framing, TLS certificates, pairing, plugin negotiation, reconnects, and KDE peer state.
- Do **not** add a direct KDE Connect endpoint on Linux as a fallback. It would duplicate the daemon, contend for KDE Connect LAN ports, create another KDE identity/pairing database, and substantially increase security and lifecycle risk.
- Treat GSConnect as a separate possible future backend, not as an alias for `kdeconnectd`. Its wire protocol is compatible, but its local service and APIs are not.
- If Relay Android must eventually interoperate as a KDE Connect endpoint without the official KDE Connect Android app, add a **small-in-capability but not small-in-transport** direct Android backend later. It must own a separate KDE certificate, pairing state, LAN lifecycle, and only the explicitly implemented continuity packet types. It must never reuse or promote Relay trust.
- Keep Relay-native continuity as a possible independent backend. Relay file transfer remains Relay-native in every case; KDE `share` file payloads and SFTP are out of scope.

This is “hybrid” by platform/provider, not by running two competing KDE endpoints on one Linux host. The first production-capable Linux provider should be the daemon bridge. A direct Linux provider is deferred indefinitely.

The **smallest honest KC2** is a development-only Linux D-Bus clipboard bridge exercised against the current official KDE Connect Android app. On Android 10 and newer, Android-to-Linux push is explicitly manual; Linux-to-Android placement may be automatic while the KDE connection is alive. This validates the daemon API and the real clipboard UX without pretending that a Relay Android KDE endpoint is a clipboard-only task. If KC2 is required to put the endpoint inside Relay Android, KC2 must instead be renamed and scoped as a protocol-v8 LAN/TLS/pairing foundation spike with clipboard as its only advertised plugin.

## 2. Current KDE Connect architecture facts

### 2.1 Status of the protocol material

The official `kdeconnect-meta` protocol reference is generated from the project's JSON schemas. It says that maintainers try to keep it accurate and current, but that it may be incomplete and is not a formal specification. It is nevertheless the best current interoperability contract and is corroborated below with the current desktop and Android implementations.

Therefore:

- Packet names and documented required fields are stable enough to build conformance tests around.
- Transport, certificate, pairing, and lifecycle behavior must be verified against current implementations for every supported version.
- Undocumented extensions, internal object layouts, implementation-specific timeouts, and unversioned local IPC must be feature-detected rather than assumed.

The inspected desktop and Android sources both report protocol version `8`.

### 2.2 Discovery and connection lifecycle

Current LAN behavior is:

1. A device listens for TCP connections in the range `1716..1764` and listens for UDP discovery on port `1716`.
2. It announces a `kdeconnect.identity` packet by UDP broadcast. The packet contains at least `deviceId`, `protocolVersion`, and `tcpPort`.
3. Current implementations also advertise/discover `_kdeconnect._udp` over mDNS. For compatibility, an mDNS discovery may still trigger the UDP exchange rather than directly opening TCP.
4. The connecting side opens TCP and sends a pre-TLS identity packet containing its ID/version plus `targetDeviceId` and `targetProtocolVersion`.
5. Both sides upgrade that socket to mutually authenticated TLS roles selected by which side opened TCP. They exchange a full identity again inside TLS and reject a device ID or protocol version that changes across the handshake.
6. The secure identity includes `deviceName`, `deviceType`, `incomingCapabilities`, and `outgoingCapabilities`.
7. For an unpaired device, the peer certificate can initially be queried/accepted so that pairing can occur. After pairing, the peer certificate is stored and pinned; current desktop code switches to peer verification against that stored certificate.
8. A paired/reachable device loads plugins whose declared packet directions intersect the remote capabilities. Unpaired peers may exchange pairing packets but ordinary plugin packets are discarded.

Android runs the link providers from a connected-device foreground service when persistent operation is enabled, listens for network changes, and returns `START_STICKY`. That lifecycle is part of a reliable Android endpoint; a Dart socket living only while a Flutter screen is open is not equivalent.

Recent Android source also declares `ACCESS_LOCAL_NETWORK`. This is an additional moving platform dependency for direct LAN compatibility and must be rechecked against Relay's target/compile SDK at implementation time.

### 2.3 Packet framing

A normal packet is one JSON object with:

```json
{
  "id": 0,
  "type": "kdeconnect.clipboard",
  "body": { "content": "example" }
}
```

Packets on the stream are serialized sequentially and terminated by `\n`. Current code still writes `id`, but the protocol reference marks it deprecated and says receivers should not depend on it. Binary payloads add `payloadSize` and `payloadTransferInfo`; those are not needed for the proposed text-only KC2.

Implementations must bound identity and packet reads, validate types and sizes before allocation/use, and ignore unknown packet types. These defensive details are not completely specified by the high-level reference and are security-sensitive implementation work.

### 2.4 Pairing and certificates

KDE Connect pairing is a KDE-domain trust ceremony, independent of Relay:

- The initiator sends `kdeconnect.pair` with `pair: true` and, for protocol 8, a seconds-since-epoch `timestamp`.
- The receiver rejects an initiation timestamp more than 30 minutes from its clock and prompts the user.
- Acceptance returns `pair: true`; rejection/unpair uses `pair: false`.
- Current implementations can display an eight-character uppercase verification value derived from SHA-256 over the two TLS public keys in deterministic order plus the pairing timestamp.
- Successful pairing stores the peer TLS certificate. Later TLS connections pin it; a regenerated local certificate invalidates the corresponding KDE pairings.

The KDE device ID is also placed in the certificate common name by current implementations. It is not a Relay ID and must never be used as one.

### 2.5 Capabilities and plugin negotiation

`incomingCapabilities` is the set of packet types a peer says it can consume; `outgoingCapabilities` is the set it says it can emit. This is an indication, not a guarantee that a plugin is enabled or an operation will succeed. Current desktop code intersects those sets with local plugin metadata and only loads plugins for paired, reachable peers.

Relay must expose semantic capabilities, not raw KDE packet names, and must update them when reachability, pairing, plugin enablement, daemon ownership, or permissions change.

### 2.6 Continuity packet types relevant to Relay

| Feature | Current packet types | Stable-enough body facts | Cautions |
|---|---|---|---|
| Clipboard text | `kdeconnect.clipboard`, `kdeconnect.clipboard.connect` | `content` is text; connect form also has an epoch-ms `timestamp`, and stale/zero connect content is ignored | Current desktop additionally advertises `kdeconnect.clipboard.file`; current Android clipboard plugin does not. Treat it as a non-portable extension and exclude it. |
| Share text/link | `kdeconnect.share.request` | A request can contain `text` or `url` | The same type also carries KDE file transfers. Relay must reject/ignore the file/payload branch rather than route it into Relay transfer. |
| Battery | `kdeconnect.battery` | `currentCharge` (`-1..100`), `isCharging`, optional `thresholdEvent` | `kdeconnect.battery.request` is deprecated in the protocol reference. Prefer event state, not polling assumptions. |
| Notifications | `kdeconnect.notification`, `.notification.request`, `.notification.reply`, `.notification.action` | Notification IDs, app/title/text/ticker, cancellation, actions, reply IDs, conversation data, optional icon payload | Requires Android notification-listener access for exporting phone notifications; Android 13+ notification permission is separately relevant when showing received notifications. Fields and action semantics are richer and more fragile than clipboard. Defer. |

The `share` packet family is useful later for text/URL handoff, but KDE file transfer is an explicit non-goal even though it shares the same packet type.

### 2.7 What is public/stable versus private/fragile

**Documented and stable enough for guarded interoperability**

- Protocol version 8 identity shape and capability directions.
- UDP 1716 discovery, TCP range 1716–1764, and `_kdeconnect._udp` mDNS behavior.
- Newline-delimited JSON packet envelope.
- TLS upgrade, paired-certificate pinning, and protocol-8 pairing timestamp/verification ceremony.
- The documented text clipboard, share text/URL, battery, and notification packet families.

**Publicly exposed but not a versioned compatibility contract**

- `kdeconnectd` session D-Bus service, object paths, properties, signals, and plugin methods. KDE's README describes D-Bus as the UI/core boundary, the in-tree UI and CLI consume it, and it is useful in practice. No inspected source declares an API version or backwards-compatibility policy.
- `kdeconnect-cli`. It is a supported user tool but its localized text output is not a machine API. Use D-Bus for events/state; CLI may only be a manual diagnostic fallback.

**Implementation details or likely fragile**

- Concrete C++/Kotlin class layout, timeouts, packet size limits, reconnect heuristics, file paths, and certificate key-generation details.
- Undocumented packet extensions such as desktop clipboard file/image transfer.
- Plugin object existence at a fixed path without introspection; a plugin object is only exported when supported, enabled, paired, and reachable.
- GSConnect's GAction names/object paths as a cross-project contract.
- Assuming every distribution ships identical KDE plugin sets or D-Bus signatures.

### 2.8 `kdeconnectd` D-Bus finding

The daemon surface is sufficient for a Linux continuity bridge and should be preferred over Linux wire-protocol reimplementation.

Current desktop source registers:

- Session service `org.kde.kdeconnect`.
- Root object `/modules/kdeconnect`, interface `org.kde.kdeconnect.daemon`.
- Device objects `/modules/kdeconnect/devices/<id>`, interface `org.kde.kdeconnect.device`.
- Plugin objects below the device, including `/clipboard`, `/share`, `/battery`, and `/notifications`.

Useful current operations/state include:

- Daemon: enumerate devices/device names, obtain self ID, observe device add/remove/visibility, and inspect link providers.
- Device: name/type, reachable addresses, reachable/paired/pair-request state, supported/loaded plugins, pairing request/accept/cancel/unpair, and plugin enablement.
- Clipboard: `sendClipboard()` (current Linux clipboard) and an overload accepting content; automatic receive is performed by the daemon plugin.
- Share: `shareText`, `shareUrl`, and receive signal.
- Battery: charge, charging, has-battery properties and refresh signal.
- Notifications: active IDs, posted/updated/removed signals, reply/action methods, and per-notification objects.

Bridge rules:

1. Opt in before activating or depending on the daemon. A passive probe should first check whether the session-bus name has an owner; Relay should not silently start a stopped daemon merely by constructing a proxy.
2. Introspect the root, device, and plugin object before each capability is exposed. Treat missing interfaces/methods as unsupported, not fatal.
3. Require `isPaired && isReachable` and the relevant loaded plugin before dispatch.
4. Subscribe to name-owner, device-list, reachability, pairing, and plugin-change signals; invalidate stale objects when the owner changes.
5. Use bounded D-Bus timeouts and typed failure results.
6. Do not parse `kdeconnect-cli` display output or link Relay against KDE's GPL D-Bus wrapper library.

Important limitation: this bridge controls the daemon's KDE identity and KDE peers. It does not make a Relay-native Android app a KDE endpoint. Without a direct KDE backend in Relay Android, the Android counterpart is the official KDE Connect app (or another KDE-compatible implementation).

## 3. Direct vs daemon bridge vs hybrid

| Dimension | A. Direct protocol on Android + Linux | B. Linux daemon bridge; no Relay Android KDE endpoint | C. Staged asymmetric hybrid |
|---|---|---|---|
| Architecture complexity | Highest: two platform endpoints plus shared framing, discovery, TLS, pairing, plugin routing, persistence, and lifecycle | Low on Linux; Android compatibility is supplied by another installed app | Medium long-term: daemon bridge on Linux, optional direct Android endpoint later; no direct Linux endpoint |
| Interoperability | Potentially broad, but entirely Relay's responsibility across implementation drift | High with peers already owned/paired by `kdeconnectd` | High on daemon-supported Linux; eventual Relay Android can interoperate directly after full transport conformance |
| KDE installation | None | `kdeconnectd` and relevant plugins required on Linux; a KDE-compatible Android app required | Daemon optional on Linux; eventual direct Android backend does not require the official Android app |
| GNOME / GSConnect | A direct Linux endpoint can work on GNOME but conflicts with GSConnect/kdeconnectd ownership and ports | `kdeconnectd` works outside Plasma, but GSConnect-only users are not covered | Detect GSConnect; add a separate adapter only after its API is deliberately supported. Never run a competing Linux endpoint automatically |
| Pairing | Relay must implement and store KDE pairing on both platforms | Owned by `kdeconnectd` and the Android KDE implementation | Linux pairing owned by daemon; Android direct pairing owned by a separate Relay KDE store |
| Discovery | Relay owns UDP/mDNS/TCP behavior on both platforms | Daemon owns Linux discovery | Daemon owns Linux; direct Android backend owns Android discovery only |
| Certificates/security | Relay implements KDE key/cert generation, TOFU-to-pinning transition, verification code, downgrade defense, secure storage, and rotation | Official implementations own it | Same daemon benefit on Linux; Android security work remains substantial and isolated from Relay identity |
| Background lifecycle | Desktop daemon plus Android connected-device foreground service equivalents must be built | Daemon/official Android app own it | Daemon owns Linux; Relay Android must add native lifecycle before its direct backend can be reliable |
| Android implications | Largest: foreground service, boot/network recovery, LAN permissions, clipboard focus rules, secure KDE key storage | No Relay Android changes, but users need the official Android companion | KC2 can use official Android app; later direct Android support is a separate, explicit phase |
| Packaging | No KDE runtime dependency, but much more Relay code and native surface | Optional runtime dependency only; use generic D-Bus, no KDE library link | Optional Linux dependency; Android capability can later be bundled without Linux KDE libraries |
| Testing | Full protocol matrix against desktop, Android, GSConnect, versions, networks, suspend, key rotation, malicious packets | D-Bus contract/daemon lifecycle tests plus interoperability with official Android | Bridge tests first; later add the Android protocol/security matrix without duplicating Linux protocol tests |
| Maintenance | Highest and continuous | Lowest, but subject to unversioned D-Bus drift and distro packaging | Moderate and capability-driven; avoids direct Linux maintenance |
| User experience | No companion install, but new pairing/lifecycle UI on both platforms and possible collision with existing KDE tools | Extra install/pairing; can feel duplicated beside Relay; unavailable to GSConnect-only users | Honest optional capability; best future path, but must clearly show which provider owns each peer/pairing |
| Licensing | Clean-room interoperability is possible, but source-copying risk is highest | Separate-process IPC has the cleanest boundary | Clean D-Bus boundary on Linux; direct Android code must be independently authored |

### A. Direct protocol

**Rejected for KC2 and deferred for Linux.** It provides installation independence but recreates the most security-sensitive and failure-prone parts of KDE Connect. A “clipboard plugin” is only a small layer after discovery, secure connection, pairing, persistence, capability routing, and background lifecycle exist. On Linux it also creates a poor coexistence story with `kdeconnectd` and GSConnect.

If a later Relay Android endpoint is approved, direct implementation is reasonable only on Android, behind the continuity boundary, with clipboard as the sole advertised plugin initially.

### B. Linux daemon bridge

**Selected as the first proof and first Linux provider, but insufficient as the complete product architecture.** D-Bus is useful enough for peer state, pairing, clipboard, share, battery, and notifications. It sharply reduces protocol/security risk and does not require Plasma. Its limitations are the optional KDE installation, lack of GSConnect coverage, unversioned IPC, and the fact that it cannot turn Relay Android into a KDE endpoint.

### C. Hybrid

**Recommended long-term, with strict platform ownership.** “Hybrid” means daemon bridge on Linux plus, only if justified, a direct Android compatibility backend. It does not mean opportunistically starting a direct Linux listener when the daemon disappears. Provider selection must be deterministic, and each provider retains its own identity/trust domain.

## 4. Recommended approach

1. Introduce a provider-neutral continuity domain that is not imported by Relay transfer/home discovery state.
2. Validate a Linux `kdeconnectd` backend with clipboard only and runtime D-Bus introspection.
3. Keep the backend disabled/unavailable without the daemon and fully independent of Relay network bootstrap.
4. Test against the official KDE Connect Android app, including Android 10+ manual push and Linux-to-Android automatic receive.
5. Decide from that evidence whether the extra companion app is acceptable. If not, separately approve a direct Android KDE transport/pairing foundation.
6. Consider a GSConnect backend only as its own compatibility project; do not disguise it as daemon-bridge compatibility.
7. Add text/URL, battery, then notifications in later phases only after capability and permission models are proven.

## 5. Trust and identity separation

Relay and KDE Connect have separate identities, credentials, pairing ceremonies, persistence, and revocation:

| Domain | Authority | What it authorizes |
|---|---|---|
| Relay | Relay secure private-key storage and Relay authenticated-peer state | Relay-native operations, including Relay file/folder transfer |
| KDE Connect | `kdeconnectd`, GSConnect, or a future direct backend's own KDE certificate and pairing store | Only capabilities sent through that KDE provider |

Hard rules:

- `kdePaired` never implies `relayTrusted`; `relayTrusted` never implies `kdePaired`.
- KDE device ID, certificate fingerprint, device name, IP, and D-Bus object path must not be written into Relay's trusted-peer database as proof of Relay identity.
- A continuity backend receives no Relay private key and cannot authorize Relay transfers.
- Pair, unpair, certificate rotation, reset, and error states are surfaced with the owning provider named.
- Unpairing/resetting one domain does not silently mutate the other.
- Logs and analytics must not contain clipboard content, notification bodies, private keys, or unredacted D-Bus payloads.

### Explicit linking model for a later phase

Linking is presentation metadata, not trust promotion. A safe cryptographic link would require all of the following:

1. An already authenticated Relay session with the Relay peer.
2. The peer sends its KDE device ID and KDE certificate public-key fingerprint over that authenticated Relay session, bound to a fresh local nonce.
3. The local continuity backend independently observes the same KDE ID and pinned certificate fingerprint through its already-paired provider.
4. The user sees both identities/providers and explicitly confirms the link.
5. Relay stores a revocable mapping of `(relayId, providerId, providerPeerId, kdeCertificateFingerprint)`.

If a backend cannot expose trustworthy structured certificate evidence, Relay may offer a manual visual grouping marked **unverified**, but it must not use that grouping for authorization. Hostname, display name, model, IP address, MAC address, or temporal co-occurrence are never sufficient.

## 6. Clipboard platform reality

### 6.1 Android → Linux

Android 10 and newer limit clipboard reads to the default input method or the app that currently has focus. There is no ordinary runtime permission that restores background clipboard reads.

Current official KDE Connect Android behavior confirms the practical choices:

- Before Android 10, it can observe/read clipboard changes automatically while its service is alive.
- On Android 10+, its normal UI exposes manual send.
- Its Quick Settings tile launches a short activity, reads while focused, sends to reachable paired devices, and closes.
- Its persistent notification offers a manual “send clipboard” action when automatic sync is unavailable.
- It contains a `READ_LOGS` plus floating/overlay workaround for automatic detection. `READ_LOGS` is protected and must be granted by ADB; overlay is a special capability. Relay must not make this hack a supported product path.

Honest Relay behavior for Android 10+:

- **Foreground:** a visible Relay screen may offer “Send clipboard” and read only after the user invokes it.
- **Quick Settings:** a user-added Relay tile may launch a transient activity through a `PendingIntent`, read the clipboard while focused, send, show minimal confirmation, and finish. The current Android 14 tile API requires the `PendingIntent` form.
- **Notification action:** available only when Relay's connected-device foreground service/persistent notification is active and the notification can be shown. Android 13+ notification permission can make this surface unavailable.
- **Background automatic:** unsupported by default. Do not advertise instant Android-to-Linux sync.

For KC2, Android-to-Linux is manual. Automatic behavior on Android 9 and older is not required and should not define product wording.

### 6.2 Linux → Android

Current KDE Connect Android code handles incoming `kdeconnect.clipboard` by setting the Android system clipboard directly, even from its background connection service. This direction can therefore be automatic while the app process/service and paired connection are alive.

It is still not guaranteed or silent:

- Android may stop the service/process or the network may disconnect.
- Android 13+ shows system clipboard UI when content is placed on the clipboard.
- Received text overwrites the user's current clipboard.
- Clipboard content can include credentials, one-time codes, personal data, or hostile text/URLs.

Relay should default this direction to **explicitly enabled per provider/device**, show that it will replace the Android clipboard, impose a conservative text-size limit, suppress loops/duplicates, and never persist/history-log content. A future “receive but require tap to copy” mode is safer for sensitive environments.

### 6.3 Sensitive content policy

Android exposes `ClipDescription.EXTRA_IS_SENSITIVE`; current KDE source can detect it and optionally skip automatic forwarding. Relay should:

- Skip sensitive clips by default.
- Require an explicit confirmation to send a clip marked sensitive.
- Never place received remote content on Android with a claim that it is safe; if Relay knows content is sensitive, apply the Android sensitive flag before setting it.
- Support plain text only in the first phases. No images, URIs, intents, files, or clipboard history.

### 6.4 Proposed clipboard wording

- Android → Linux: **“Send current clipboard”**; “Tap in Relay, Quick Settings, or the Relay connection notification on Android 10+.”
- Linux → Android: **“Allow this paired KDE device to replace Android clipboard automatically”**; off until explicitly enabled in a production phase.
- Never use “instant two-way sync” as an unconditional capability claim.

## 7. GSConnect analysis

GSConnect is a complete, independent implementation of the KDE Connect wire protocol for GNOME. It is not a front end for `kdeconnectd`; current metadata explicitly says it does not rely on the KDE Connect desktop application and will not work with it installed.

Its local API is different:

- Service: `org.gnome.Shell.Extensions.GSConnect`.
- It exports a D-Bus ObjectManager with device objects under `/org/gnome/Shell/Extensions/GSConnect/Device/<id>`.
- Device state is exposed through `org.gnome.Shell.Extensions.GSConnect.Device` properties such as `Connected`, `Paired`, `Id`, and `Name`.
- Operations are primarily exported as generic `org.gtk.Actions`/GActions on each device. The clipboard plugin currently registers `clipboardPush` and `clipboardPull` actions.

This is not compatible with KDE's `org.kde.kdeconnect` object model. It is technically callable, but the inspected GSConnect source does not present those plugin GActions as a stable cross-application API, and the project currently describes itself as community-maintained without dedicated developers.

Consequences:

- A `kdeconnectd`-only bridge excludes users who only run GSConnect.
- Relay should care about GSConnect for detection, conflict avoidance, and honest availability messaging.
- KC2 should detect the GSConnect bus owner and report “GSConnect detected; this bridge currently supports kdeconnectd only.” It must not start a competing direct Linux endpoint.
- A later `GsConnectContinuityBackend` needs its own contract tests and upstream discussion. It should not be implemented by translating KDE D-Bus paths mechanically.

## 8. Licensing considerations

Relay's repository is Apache-2.0. Current KDE Connect desktop and Android repositories describe the applications as GPL v2/GPL v3, and the inspected implementation files commonly carry `GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL`. Their repositories also contain files under other licenses, so every copied file would require file-level SPDX analysis. GSConnect's inspected code is GPL-2.0-or-later. The official meta protocol repository also states GPL v2/GPL v3.

This document is not legal advice. Recommended engineering boundary:

- **Protocol interoperability:** independently authored code that implements functional wire behavior does not, merely by interoperating, copy or link KDE Connect code. Still obtain legal review before distribution because the implementation team has studied GPL sources and the protocol documentation itself is GPL-licensed.
- **Invoking `kdeconnectd`:** generic session-D-Bus calls to a separately installed process provide the clearest separation. Do not bundle the daemon, claim it is part of Relay, or imply that IPC alone changes either program's license.
- **Studying/reimplementing behavior:** use this factual architecture record, the official protocol reference, independently written test vectors, and black-box interoperability tests. Do not translate C++/Kotlin/JavaScript control flow, comments, tests, schemas, or data structures into Relay.
- **Copying/linking:** do not copy KDE/GSConnect source, generated D-Bus wrappers, XML interface files, JSON schemas, plugin metadata, icons, or test fixtures into Relay; do not link KDE Connect's GPL libraries into Relay. If any such reuse becomes desirable, stop for explicit legal and product review and comply with the applicable file-level licenses.
- **D-Bus declarations:** issue the minimal required generic calls and discover signatures by runtime introspection. Keep independently authored constants and adapter tests. Have counsel review any plan to vendor upstream interface definitions.
- **Attribution/trademarks:** accurately describe compatibility and provider ownership. Review KDE trademark/branding guidance before shipping public naming or icons.

The daemon bridge is the lowest-risk licensing direction because it avoids copying and linking upstream implementation code. A clean direct Android implementation remains possible in principle but has a higher provenance/review burden.

## 9. Proposed Relay continuity abstraction

Relay uses Refena “providers” for app state, so call the protocol-facing units **backends** to avoid overloading that term. Names below are conceptual.

```dart
abstract interface class ContinuityBackend {
  ContinuityBackendId get id;
  Stream<ContinuityBackendHealth> watchHealth();
  Stream<List<ContinuityPeer>> watchPeers();
  Future<Set<ContinuityCapability>> capabilities(ContinuityPeerId peer);

  Future<ContinuityResult> sendClipboardText(
    ContinuityPeerId peer,
    String text,
  );

  Stream<ClipboardOffer> clipboardOffers();
  Stream<BatterySnapshot> batteryEvents();
  Stream<ContinuityNotificationEvent> notificationEvents();
}
```

Capabilities should be directional and semantic, for example:

```text
clipboard.sendText
clipboard.receiveText
clipboard.receiveTextAutomatically
handoff.sendText
handoff.sendUrl
battery.read
notifications.read
notifications.dismiss
notifications.act
notifications.reply
```

Model requirements:

- `ContinuityPeerId` is `(backendId, opaquePeerId)`, never a hostname/IP/name.
- `ContinuityPeer` contains provider-scoped identity, display metadata, reachability, pairing state, and optional explicit Relay link; it is not `localsend_isolates.Device`.
- `ContinuityResult` distinguishes `ok`, `backendUnavailable`, `peerUnreachable`, `peerUnpaired`, `capabilityDisabled`, `userActionRequired`, `permissionRequired`, `unsupported`, `timedOut`, and redacted `failed`.
- Health distinguishes not installed, stopped, incompatible API, permission missing, degraded, and ready.
- Clipboard data is ephemeral: no replay queue across restarts and no persistence in Refena state.
- Backend events are bounded/redacted before entering app state.

Likely backend set:

- `RelayNativeContinuityBackend` — future continuity over Relay-authenticated channels; never uses KDE pairing.
- `KdeConnectDaemonBackend` — Linux session-D-Bus adapter selected first.
- `KdeConnectDirectAndroidBackend` — later, only after a protocol/security phase.
- `GsConnectContinuityBackend` — possible later adapter with its own local API contract.

A Refena `continuityProvider` can aggregate snapshots and dispatch actions, but `RelayHome`, `NearbyDevicesState`, `ParentIsolateState`, the Rust HTTP server, multicast discovery, and send/receive controllers must not depend on KDE-specific types. Continuity startup occurs after core Relay bootstrap and its failure is swallowed into backend health rather than failing `preInit` or `NetworkBootstrap`.

## 10. Device-model strategy

Use two layers:

1. **Raw provider endpoints:** Relay transfer devices and continuity peers remain separate authoritative records.
2. **Optional presentation association:** an explicit link may group endpoints visually without merging identity or trust.

Initial behavior:

- Keep the current nearby Relay transfer list unchanged.
- Show unlinked KDE continuity peers in a separate continuity context in a later UI phase.
- A Relay device gets a continuity badge/actions only after an explicit link record exists and the linked continuity backend currently reports the capability.
- If the same phone is visible through Relay and KDE without a link, duplicates are intentional and labeled by provider.
- A hidden automatic bridge is rejected because it obscures which pairing/trust domain authorizes an action.

Never merge on display name, hostname, model, IP, network interface, timing, or user account. IPs are routing data and may be shared/reassigned; names are user-controlled; KDE device IDs are provider identities, not Relay proof.

Deleting a presentation link removes only the mapping. It does not unpair KDE or revoke Relay trust unless the user separately requests those provider-owned operations.

## 11. Failure and optional-dependency model

Continuity is an optional subsystem with no effect on Relay transfer readiness.

| Condition | Continuity behavior | Relay transfer behavior |
|---|---|---|
| KDE Connect not installed | Daemon backend reports `notInstalled`; no retries that spam logs | Unchanged |
| `kdeconnectd` installed but stopped | Report `stopped`; start only after explicit opt-in/action | Unchanged |
| Daemon exits/restarts | Drop D-Bus proxies, mark peers unavailable, reacquire owner and rebuild by introspection | Unchanged |
| GSConnect only | Report detected-but-unsupported in KC2; do not launch a direct Linux endpoint | Unchanged |
| Peer unpaired | Show provider-scoped unpaired state; no clipboard dispatch | Unchanged; never treat KDE pairing as Relay trust |
| Plugin disabled/missing | Remove semantic capability dynamically | Unchanged |
| Android clipboard read unavailable | Return `userActionRequired`; offer foreground/tile/notification path if available | Unchanged |
| Notification permission denied | Notification action surface unavailable; foreground/tile may remain | Unchanged |
| D-Bus API drift | Capability fails closed after introspection/signature mismatch | Unchanged |
| Compatibility backend error | Bounded retry/backoff, redacted diagnostic, no content persistence | Unchanged |

Additional rules:

- Do not add a KDE package as a hard dependency of Relay's Linux package.
- Do not reserve KDE LAN ports from Relay unless a later direct backend is explicitly enabled.
- Never queue clipboard content while a peer/provider is unavailable; a later reconnect must not send stale secrets.
- Do not let a backend exception escape into Relay file-transfer isolates or server startup.
- Feature flags/config are provider-scoped. Disabling compatibility closes its streams/proxies and leaves Relay running.

## 12. KC2 implementation scope

### Recommended KC2: daemon-bridge clipboard proof

**Linux path**

- Development-only `KdeConnectDaemonBackend` using generic session D-Bus.
- Passive detection of `org.kde.kdeconnect`; explicit activation only from the KC2 harness.
- Enumerate device IDs and expose name, reachable, paired, and clipboard-plugin availability after introspection.
- One operation: invoke the paired/reachable device clipboard plugin's no-argument `sendClipboard()` to push the current Linux clipboard.
- Observe daemon owner and peer/plugin state changes; no file/share/battery/notification calls.
- No linked KDE library, vendored XML, production settings, or home-page redesign.

**Android path**

- Counterpart is the current official KDE Connect Android app, paired to that daemon. This is deliberate: KC2 validates Relay's Linux bridge, not a new Android transport stack.
- Android 10+: Android → Linux uses the app's explicit foreground button, Quick Settings tile, or persistent-notification action. It is manual.
- Linux → Android uses the KC2 Linux operation and may place text automatically while the official Android service/connection is alive.
- Text only; sensitive clipboard cases are included in the test notes and never logged.

**KC2 acceptance checks**

- Official Android app ↔ current `kdeconnectd`, both directions, with observed manual/automatic wording.
- KDE not installed, daemon stopped/restarted, peer unpaired, peer unreachable, clipboard plugin disabled, and method/object absent.
- GSConnect-only session is detected and left untouched.
- Relay discovery, authenticated peer state, transfers, and startup work normally in every failure case.
- D-Bus payload/content is absent from logs.

### KC2 validation status

- Automated D-Bus bridge tests: **PASS**.
- Real `kdeconnectd` ↔ official KDE Connect Android interoperability: **DEFERRED**.
- Physical validation will be performed on an isolated VM or dedicated test host so the KDE dependency stack is not installed on the primary GNOME development machine.
- KDE compatibility remains experimental, optional, and disabled from the production Relay UI.

### If Relay Android must be the KC2 endpoint

Do not label that work “clipboard proof-of-concept only.” Approve a separate **KC2A protocol foundation spike** containing only:

- Android native connected-device foreground service and network recovery.
- Protocol-8 UDP/mDNS discovery and bounded newline JSON framing.
- Separate KDE device ID, certificate/private-key secure storage, TLS upgrade, certificate pinning, pairing prompt/verification, and unpair/reset.
- Capabilities limited to `kdeconnect.clipboard` and `kdeconnect.clipboard.connect`.
- Manual Android 10+ send and automatic receive only after explicit enablement.

That is the minimum safe direct endpoint. It should be reviewed before any clipboard product surface is considered.

## 13. Explicit non-goals

- No production code or UI in KC1.
- No modification/replacement of Relay discovery, HTTP/TLS, multicast, WebRTC, transfer controllers, or file/folder transfer.
- No KDE file transfer, SFTP, clipboard file/image extension, or payload channel.
- No Relay/KDE identity merge or implicit trust promotion.
- No GSConnect adapter in KC2.
- No direct Linux KDE endpoint or automatic fallback when `kdeconnectd` stops.
- No notifications, replies/actions, battery, URL/text handoff, SMS, media control, or remote input in KC2.
- No protected `READ_LOGS`, overlay hack, root requirement, Accessibility misuse, or claim of automatic Android 10+ clipboard reads.
- No KDE/GSConnect source, generated bindings, interface XML, schemas, assets, or tests copied into Relay.
- No commit or push in KC1.

## 14. Risks and open questions

1. **D-Bus compatibility policy:** the surface is real and in-tree clients use it, but no API version/stability guarantee was found. Which distro/version floor should Relay support, and will KDE upstream endorse third-party use of these interfaces?
2. **Daemon activation:** should an opted-in backend start `org.kde.kdeconnect`, or require users to start/configure it separately? KC2 should measure user-visible behavior before deciding.
3. **Companion-app UX:** is installing the official KDE Connect Android app acceptable, or is a Relay-owned Android endpoint a product requirement? This changes the next phase from small IPC work to security-sensitive protocol work.
4. **Flutter Linux D-Bus dependency:** select a maintained generic D-Bus client without linking KDE Connect libraries; validate packaging on Ubuntu/GNOME and other target distributions.
5. **Wayland clipboard behavior:** current daemon abstracts desktop clipboard access, but compositor/portal/distribution differences must be runtime-tested.
6. **GSConnect demand:** how many target users are GSConnect-only, and is its unversioned ObjectManager/GAction API supportable with upstream cooperation?
7. **Concurrent implementations:** GSConnect states it will not work with the KDE desktop app installed. Relay must detect and avoid creating a third KDE endpoint or prompting users into an unsupported combination.
8. **Android lifecycle and permissions:** direct Android support must re-evaluate foreground-service, notification, local-network, background activity, and clipboard rules against the then-current Relay target SDK.
9. **Clipboard privacy:** decide default receive policy, size limit, sensitive-flag behavior, and whether remote replacement is per-device or global.
10. **Link proof availability:** `kdeconnectd` exposes human-readable encryption info but a structured peer certificate/fingerprint API was not found in the inspected public surface. Upstream support may be needed for cryptographic cross-linking.
11. **Capability freshness:** D-Bus `supportedPlugins`, `loadedPlugins`, enabled state, and object introspection may change asynchronously. The adapter must define one authoritative readiness calculation.
12. **Licensing review:** counsel should review the independently authored D-Bus adapter and any later wire implementation before release.

## 15. Exact upstream sources examined

All KDE Invent links below are pinned to the exact revisions read, not moving `master` links.

### Official protocol and documentation

- `kdeconnect-meta` `e41a145f31f1aeab36af71d466f616a308be1021` (2026-08-02): [`protocol.md`](https://invent.kde.org/network/kdeconnect-meta/-/blob/e41a145f31f1aeab36af71d466f616a308be1021/protocol.md), [`README.md`](https://invent.kde.org/network/kdeconnect-meta/-/blob/e41a145f31f1aeab36af71d466f616a308be1021/README.md).
- KDE UserBase: [KDE Connect](https://userbase.kde.org/KDEConnect/en), specifically the clipboard/Android 10+ material.
- Android Developers: [Android 10 limited clipboard access](https://developer.android.com/about/versions/10/privacy/changes#clipboard-data), [copy and paste](https://developer.android.com/develop/ui/views/touch-and-input/copy-paste), and [Android 14 tile launch API change](https://developer.android.com/about/versions/14/behavior-changes-14#tiles-launch-api).

### Official KDE Connect desktop source

Revision: `9f25b09476feedd17a37a980ce87f720f32d59d0` (2026-08-17).

- Repository/license overview: [`README.md`](https://invent.kde.org/network/kdeconnect-kde/-/blob/9f25b09476feedd17a37a980ce87f720f32d59d0/README.md), [`REUSE.toml`](https://invent.kde.org/network/kdeconnect-kde/-/blob/9f25b09476feedd17a37a980ce87f720f32d59d0/REUSE.toml), `LICENSES/` file list.
- Core/API: [`core/daemon.h`](https://invent.kde.org/network/kdeconnect-kde/-/blob/9f25b09476feedd17a37a980ce87f720f32d59d0/core/daemon.h), [`core/daemon.cpp`](https://invent.kde.org/network/kdeconnect-kde/-/blob/9f25b09476feedd17a37a980ce87f720f32d59d0/core/daemon.cpp), [`core/device.h`](https://invent.kde.org/network/kdeconnect-kde/-/blob/9f25b09476feedd17a37a980ce87f720f32d59d0/core/device.h), [`core/device.cpp`](https://invent.kde.org/network/kdeconnect-kde/-/blob/9f25b09476feedd17a37a980ce87f720f32d59d0/core/device.cpp), [`core/kdeconnectplugin.h`](https://invent.kde.org/network/kdeconnect-kde/-/blob/9f25b09476feedd17a37a980ce87f720f32d59d0/core/kdeconnectplugin.h), [`core/pluginloader.cpp`](https://invent.kde.org/network/kdeconnect-kde/-/blob/9f25b09476feedd17a37a980ce87f720f32d59d0/core/pluginloader.cpp).
- Packet framing: [`core/networkpacket.h`](https://invent.kde.org/network/kdeconnect-kde/-/blob/9f25b09476feedd17a37a980ce87f720f32d59d0/core/networkpacket.h), [`core/networkpacket.cpp`](https://invent.kde.org/network/kdeconnect-kde/-/blob/9f25b09476feedd17a37a980ce87f720f32d59d0/core/networkpacket.cpp), [`core/networkpackettypes.h`](https://invent.kde.org/network/kdeconnect-kde/-/blob/9f25b09476feedd17a37a980ce87f720f32d59d0/core/networkpackettypes.h).
- LAN/security/pairing: [`core/backends/lan/lanlinkprovider.h`](https://invent.kde.org/network/kdeconnect-kde/-/blob/9f25b09476feedd17a37a980ce87f720f32d59d0/core/backends/lan/lanlinkprovider.h), [`lanlinkprovider.cpp`](https://invent.kde.org/network/kdeconnect-kde/-/blob/9f25b09476feedd17a37a980ce87f720f32d59d0/core/backends/lan/lanlinkprovider.cpp), [`server.h`](https://invent.kde.org/network/kdeconnect-kde/-/blob/9f25b09476feedd17a37a980ce87f720f32d59d0/core/backends/lan/server.h), [`server.cpp`](https://invent.kde.org/network/kdeconnect-kde/-/blob/9f25b09476feedd17a37a980ce87f720f32d59d0/core/backends/lan/server.cpp), [`landevicelink.cpp`](https://invent.kde.org/network/kdeconnect-kde/-/blob/9f25b09476feedd17a37a980ce87f720f32d59d0/core/backends/lan/landevicelink.cpp), [`core/backends/pairinghandler.cpp`](https://invent.kde.org/network/kdeconnect-kde/-/blob/9f25b09476feedd17a37a980ce87f720f32d59d0/core/backends/pairinghandler.cpp), [`core/kdeconnectconfig.cpp`](https://invent.kde.org/network/kdeconnect-kde/-/blob/9f25b09476feedd17a37a980ce87f720f32d59d0/core/kdeconnectconfig.cpp), [`core/sslhelper.cpp`](https://invent.kde.org/network/kdeconnect-kde/-/blob/9f25b09476feedd17a37a980ce87f720f32d59d0/core/sslhelper.cpp).
- D-Bus/CLI/daemon: [`dbusinterfaces/dbusinterfaces.h`](https://invent.kde.org/network/kdeconnect-kde/-/blob/9f25b09476feedd17a37a980ce87f720f32d59d0/dbusinterfaces/dbusinterfaces.h), [`dbusinterfaces.cpp`](https://invent.kde.org/network/kdeconnect-kde/-/blob/9f25b09476feedd17a37a980ce87f720f32d59d0/dbusinterfaces/dbusinterfaces.cpp), [`cli/kdeconnect-cli.cpp`](https://invent.kde.org/network/kdeconnect-kde/-/blob/9f25b09476feedd17a37a980ce87f720f32d59d0/cli/kdeconnect-cli.cpp), [`daemon/kdeconnectd.cpp`](https://invent.kde.org/network/kdeconnect-kde/-/blob/9f25b09476feedd17a37a980ce87f720f32d59d0/daemon/kdeconnectd.cpp), [`daemon/org.kde.kdeconnect.service.in`](https://invent.kde.org/network/kdeconnect-kde/-/blob/9f25b09476feedd17a37a980ce87f720f32d59d0/daemon/org.kde.kdeconnect.service.in).
- Clipboard: [`plugins/clipboard/clipboardplugin.h`](https://invent.kde.org/network/kdeconnect-kde/-/blob/9f25b09476feedd17a37a980ce87f720f32d59d0/plugins/clipboard/clipboardplugin.h), [`clipboardplugin.cpp`](https://invent.kde.org/network/kdeconnect-kde/-/blob/9f25b09476feedd17a37a980ce87f720f32d59d0/plugins/clipboard/clipboardplugin.cpp), [`kdeconnect_clipboard.json`](https://invent.kde.org/network/kdeconnect-kde/-/blob/9f25b09476feedd17a37a980ce87f720f32d59d0/plugins/clipboard/kdeconnect_clipboard.json), [`clipboardlistener.h`](https://invent.kde.org/network/kdeconnect-kde/-/blob/9f25b09476feedd17a37a980ce87f720f32d59d0/plugins/clipboard/clipboardlistener.h), [`clipboardlistener.cpp`](https://invent.kde.org/network/kdeconnect-kde/-/blob/9f25b09476feedd17a37a980ce87f720f32d59d0/plugins/clipboard/clipboardlistener.cpp).
- Later-feature API/metadata: [`plugins/share/shareplugin.h`](https://invent.kde.org/network/kdeconnect-kde/-/blob/9f25b09476feedd17a37a980ce87f720f32d59d0/plugins/share/shareplugin.h), [`shareplugin.cpp`](https://invent.kde.org/network/kdeconnect-kde/-/blob/9f25b09476feedd17a37a980ce87f720f32d59d0/plugins/share/shareplugin.cpp), [`kdeconnect_share.json`](https://invent.kde.org/network/kdeconnect-kde/-/blob/9f25b09476feedd17a37a980ce87f720f32d59d0/plugins/share/kdeconnect_share.json), [`plugins/battery/batteryplugin.h`](https://invent.kde.org/network/kdeconnect-kde/-/blob/9f25b09476feedd17a37a980ce87f720f32d59d0/plugins/battery/batteryplugin.h), [`batteryplugin.cpp`](https://invent.kde.org/network/kdeconnect-kde/-/blob/9f25b09476feedd17a37a980ce87f720f32d59d0/plugins/battery/batteryplugin.cpp), [`kdeconnect_battery.json`](https://invent.kde.org/network/kdeconnect-kde/-/blob/9f25b09476feedd17a37a980ce87f720f32d59d0/plugins/battery/kdeconnect_battery.json), [`plugins/notifications/notificationsplugin.h`](https://invent.kde.org/network/kdeconnect-kde/-/blob/9f25b09476feedd17a37a980ce87f720f32d59d0/plugins/notifications/notificationsplugin.h), [`notificationsplugin.cpp`](https://invent.kde.org/network/kdeconnect-kde/-/blob/9f25b09476feedd17a37a980ce87f720f32d59d0/plugins/notifications/notificationsplugin.cpp), [`kdeconnect_notifications.json`](https://invent.kde.org/network/kdeconnect-kde/-/blob/9f25b09476feedd17a37a980ce87f720f32d59d0/plugins/notifications/kdeconnect_notifications.json).

### Official KDE Connect Android source

Revision: `5c5768667b1afc181a9420797b43ed93e9264db4` (2026-08-17).

- Repository/license and platform declarations: [`README.md`](https://invent.kde.org/network/kdeconnect-android/-/blob/5c5768667b1afc181a9420797b43ed93e9264db4/README.md), [`src/main/AndroidManifest.xml`](https://invent.kde.org/network/kdeconnect-android/-/blob/5c5768667b1afc181a9420797b43ed93e9264db4/src/main/AndroidManifest.xml), `LICENSES/` file list.
- Core/lifecycle: [`NetworkPacket.kt`](https://invent.kde.org/network/kdeconnect-android/-/blob/5c5768667b1afc181a9420797b43ed93e9264db4/src/main/java/org/kde/kdeconnect/NetworkPacket.kt), [`DeviceInfo.kt`](https://invent.kde.org/network/kdeconnect-android/-/blob/5c5768667b1afc181a9420797b43ed93e9264db4/src/main/java/org/kde/kdeconnect/DeviceInfo.kt), [`Device.kt`](https://invent.kde.org/network/kdeconnect-android/-/blob/5c5768667b1afc181a9420797b43ed93e9264db4/src/main/java/org/kde/kdeconnect/Device.kt), [`PairingHandler.kt`](https://invent.kde.org/network/kdeconnect-android/-/blob/5c5768667b1afc181a9420797b43ed93e9264db4/src/main/java/org/kde/kdeconnect/PairingHandler.kt), [`BackgroundService.kt`](https://invent.kde.org/network/kdeconnect-android/-/blob/5c5768667b1afc181a9420797b43ed93e9264db4/src/main/java/org/kde/kdeconnect/BackgroundService.kt), [`helpers/DeviceHelper.kt`](https://invent.kde.org/network/kdeconnect-android/-/blob/5c5768667b1afc181a9420797b43ed93e9264db4/src/main/java/org/kde/kdeconnect/helpers/DeviceHelper.kt).
- LAN: [`backends/lan/LanLinkProvider.java`](https://invent.kde.org/network/kdeconnect-android/-/blob/5c5768667b1afc181a9420797b43ed93e9264db4/src/main/java/org/kde/kdeconnect/backends/lan/LanLinkProvider.java), [`LanLink.java`](https://invent.kde.org/network/kdeconnect-android/-/blob/5c5768667b1afc181a9420797b43ed93e9264db4/src/main/java/org/kde/kdeconnect/backends/lan/LanLink.java).
- Clipboard: [`ClipboardPlugin.kt`](https://invent.kde.org/network/kdeconnect-android/-/blob/5c5768667b1afc181a9420797b43ed93e9264db4/src/main/java/org/kde/kdeconnect/plugins/clipboard/ClipboardPlugin.kt), [`ClipboardListener.kt`](https://invent.kde.org/network/kdeconnect-android/-/blob/5c5768667b1afc181a9420797b43ed93e9264db4/src/main/java/org/kde/kdeconnect/plugins/clipboard/ClipboardListener.kt), [`ClipboardTileService.kt`](https://invent.kde.org/network/kdeconnect-android/-/blob/5c5768667b1afc181a9420797b43ed93e9264db4/src/main/java/org/kde/kdeconnect/plugins/clipboard/ClipboardTileService.kt), [`ClipboardFloatingActivity.java`](https://invent.kde.org/network/kdeconnect-android/-/blob/5c5768667b1afc181a9420797b43ed93e9264db4/src/main/java/org/kde/kdeconnect/plugins/clipboard/ClipboardFloatingActivity.java).
- Later-feature implementations: [`plugins/share/SharePlugin.kt`](https://invent.kde.org/network/kdeconnect-android/-/blob/5c5768667b1afc181a9420797b43ed93e9264db4/src/main/java/org/kde/kdeconnect/plugins/share/SharePlugin.kt), [`plugins/battery/BatteryPlugin.kt`](https://invent.kde.org/network/kdeconnect-android/-/blob/5c5768667b1afc181a9420797b43ed93e9264db4/src/main/java/org/kde/kdeconnect/plugins/battery/BatteryPlugin.kt), [`plugins/notifications/NotificationsPlugin.kt`](https://invent.kde.org/network/kdeconnect-android/-/blob/5c5768667b1afc181a9420797b43ed93e9264db4/src/main/java/org/kde/kdeconnect/plugins/notifications/NotificationsPlugin.kt), [`plugins/notifications/NotificationReceiver.java`](https://invent.kde.org/network/kdeconnect-android/-/blob/5c5768667b1afc181a9420797b43ed93e9264db4/src/main/java/org/kde/kdeconnect/plugins/notifications/NotificationReceiver.java), [`plugins/receivenotifications/ReceiveNotificationsPlugin.kt`](https://invent.kde.org/network/kdeconnect-android/-/blob/5c5768667b1afc181a9420797b43ed93e9264db4/src/main/java/org/kde/kdeconnect/plugins/receivenotifications/ReceiveNotificationsPlugin.kt).

### GSConnect primary source

Revision: `0be3a14d8a6db8bbd287d694e3397ce9f9888f0f` (2026-08-10).

- Project status/compatibility: [`README.md`](https://github.com/GSConnect/gnome-shell-extension-gsconnect/blob/0be3a14d8a6db8bbd287d694e3397ce9f9888f0f/README.md), [`data/metadata.json.in`](https://github.com/GSConnect/gnome-shell-extension-gsconnect/blob/0be3a14d8a6db8bbd287d694e3397ce9f9888f0f/data/metadata.json.in).
- Local service/API: [`data/org.gnome.Shell.Extensions.GSConnect.service.in`](https://github.com/GSConnect/gnome-shell-extension-gsconnect/blob/0be3a14d8a6db8bbd287d694e3397ce9f9888f0f/data/org.gnome.Shell.Extensions.GSConnect.service.in), [`data/org.gnome.Shell.Extensions.GSConnect.xml`](https://github.com/GSConnect/gnome-shell-extension-gsconnect/blob/0be3a14d8a6db8bbd287d694e3397ce9f9888f0f/data/org.gnome.Shell.Extensions.GSConnect.xml), [`src/service/daemon.js`](https://github.com/GSConnect/gnome-shell-extension-gsconnect/blob/0be3a14d8a6db8bbd287d694e3397ce9f9888f0f/src/service/daemon.js), [`manager.js`](https://github.com/GSConnect/gnome-shell-extension-gsconnect/blob/0be3a14d8a6db8bbd287d694e3397ce9f9888f0f/src/service/manager.js), [`device.js`](https://github.com/GSConnect/gnome-shell-extension-gsconnect/blob/0be3a14d8a6db8bbd287d694e3397ce9f9888f0f/src/service/device.js), [`core.js`](https://github.com/GSConnect/gnome-shell-extension-gsconnect/blob/0be3a14d8a6db8bbd287d694e3397ce9f9888f0f/src/service/core.js), [`utils/dbus.js`](https://github.com/GSConnect/gnome-shell-extension-gsconnect/blob/0be3a14d8a6db8bbd287d694e3397ce9f9888f0f/src/service/utils/dbus.js).
- Protocol/plugins: [`src/service/backends/lan.js`](https://github.com/GSConnect/gnome-shell-extension-gsconnect/blob/0be3a14d8a6db8bbd287d694e3397ce9f9888f0f/src/service/backends/lan.js), [`plugins/clipboard.js`](https://github.com/GSConnect/gnome-shell-extension-gsconnect/blob/0be3a14d8a6db8bbd287d694e3397ce9f9888f0f/src/service/plugins/clipboard.js), [`plugins/share.js`](https://github.com/GSConnect/gnome-shell-extension-gsconnect/blob/0be3a14d8a6db8bbd287d694e3397ce9f9888f0f/src/service/plugins/share.js), [`plugins/battery.js`](https://github.com/GSConnect/gnome-shell-extension-gsconnect/blob/0be3a14d8a6db8bbd287d694e3397ce9f9888f0f/src/service/plugins/battery.js), [`plugins/notification.js`](https://github.com/GSConnect/gnome-shell-extension-gsconnect/blob/0be3a14d8a6db8bbd287d694e3397ce9f9888f0f/src/service/plugins/notification.js).

## KC1 decision

Proceed to review with the staged asymmetric hybrid recommendation. Do not start production implementation until the KC2 companion-app decision and licensing review are explicitly approved.

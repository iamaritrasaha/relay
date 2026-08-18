# Relay Anywhere RA2B

Development-only Android/Linux physical proof harness for the approved Relay Anywhere RA1 architecture.

This crate reuses the RA2A protocol layering (Iroh QUIC path, production-shaped inner TLS, mutual `RelayIdentityProofV1`, bounded 1 MiB SHA-256 test) but does **not** copy RA2A's permissive proof-only TLS verifiers.

## Dual-app development harness

The same Flutter entrypoint hosts **and** joins:

```bash
cd app
/home/hrik/fvm/bin/fvm flutter run -t lib/main_ra2b.dart
/home/hrik/fvm/bin/fvm flutter build linux -t lib/main_ra2b.dart
JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 \
/home/hrik/fvm/bin/fvm flutter build apk --release --flavor ra2b -t lib/main_ra2b.dart
```

Host creates one `Ra2bInviteV1` string (copy / QR). Join pastes or scans that invite. There is no separate RelayId or EndpointAddr field.

**RA2B invite = test convenience / addressing package. It is not production trust architecture.**

## Physical Android ↔ Linux result

**PASS** (verified on real devices after the completion-teardown and scanner lifecycle fixes).

Observed:

- release Android RA2B APK (`app-ra2b-release.apk`, flavor `ra2b`) ↔ Linux RA2B app
- QR / invite workflow physically usable
- completed run selected the **Iroh relay** path
- inner TLS authenticated
- mutual `RelayIdentityProofV1` authenticated
- 1,048,576 bytes transferred
- SHA-256 PASS
- remote completion acknowledgement PASS (`0xAC` / `0x5C`)
- both endpoints COMPLETE
- physical wrong-identity check REJECTED with no payload accepted

A previous physical **Auto** run observed Iroh selecting a **direct IP** path and successfully reached TLS, mutual Relay authentication, 1 MiB, and SHA-256. That run happened **before** the completion-teardown fix, so it is **not** a post-fix full DIRECT COMPLETE result.

## Optional CLI (not required)

```bash
cargo run -p relay-anywhere-ra2b --features linux-harness -- responder
cargo run -p relay-anywhere-ra2b --features linux-harness -- initiator --invite '<RA2B1...>'
```

## Relay infrastructure notes

- Flutter **Auto** uses pinned Iroh `RelayMode::Default` (n0 public relays) plus direct attempts.
- Flutter **Force Relay** (Linux and Android) clears IP transports and uses those public relays. The optional CLI `ForceRelay` path still uses a local stock `iroh-relay` 1.0.3 test server.
- RA2B currently proves end-to-end Relay identity/content security over the relay path. It does **not** yet prove deployment-time relay-server TLS verification.

Relay infrastructure is routing-only; authoritative identity remains inner TLS + `RelayIdentityProofV1`.

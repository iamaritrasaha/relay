# Relay

Relay is a cross-device continuity and local transfer application. It connects your devices for fast, direct local file transfer, with broader cross-device continuity planned.

## Status

Relay is in early development. Its current verified foundation includes Linux and Android builds, local-network transfer infrastructure inherited from LocalSend, background receiver lifecycle support, and Android local-network permission handling.

## Current Scope

- Linux
- Android
- Nearby/local-network transfer
- Files and folders
- Background receiver foundation

## Planned

- Relay device identity and pairing
- Trusted devices
- Resumable transfers
- Clipboard continuity
- Internet-assisted continuity

These features are planned and are not implemented yet.

## Development

Relay currently uses:

- Flutter 3.41.9, selected with [FVM](https://fvm.app/)
- Rust 1.97.1

Linux builds additionally need the libsecret development headers (used for Relay's secure identity storage via the desktop Secret Service):

```bash
sudo apt install libsecret-1-dev
```

From `app/`, use the pinned Flutter toolchain:

```bash
fvm flutter pub get
fvm flutter test
fvm flutter build linux
fvm flutter build apk --debug
```

## Upstream / Attribution

Relay is built on the open-source [LocalSend](https://github.com/localsend/localsend) project and retains portions of its transfer, discovery, and cross-platform infrastructure. LocalSend is licensed under Apache-2.0; Relay preserves applicable license and copyright notices. Relay is an independent fork and is not affiliated with or endorsed by LocalSend.

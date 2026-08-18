# RA4B physical validation

## Passed evidence

- RA4A transferred a normal real file physically over the Android-to-Linux
  Anywhere path.
- Automated bounded Hyper/v2 streaming completed at 256 KiB, 1 MiB, and
  16 MiB.
- An automated 16 MiB transfer completed over authenticated Iroh, inner TLS,
  HTTP v2, and the existing save path.
- Android emulator DocumentsUI/SAF selected and prepared a real 16 MiB file
  through the release RA2B harness.

## Open physical blocker

**PHYSICAL ANDROID LARGE-FILE VALIDATION PENDING.**

A previous physical Android large-file transfer stalled near 134 KB. The
condition has not been reproduced by the focused tests or emulator SAF
preparation. No speculative fix has been applied.

If the stall recurs, capture bounded byte counters at the source/SAF reader,
`FileContent` producer, Hyper request body, server body, save writer, and
progress boundary before changing code.

## Required future physical retest

1. Use an Android physical device and one real 20–100 MiB file.
2. Send Android to Linux through the RA2B release harness.
3. Observe progress through completion.
4. Verify the saved file size and SHA-256.
5. Repeat once if practical.

## Release harness commands

Run from `app/` only when a rebuild is required:

```sh
JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 \
/home/hrik/fvm/bin/fvm flutter build apk \
  --release \
  --flavor ra2b \
  -t lib/main_ra2b.dart

/home/hrik/fvm/bin/fvm flutter build linux \
  --release \
  -t lib/main_ra2b.dart
```

Expected artifacts:

- `app/build/app/outputs/flutter-apk/app-ra2b-release.apk`
- `app/build/linux/x64/release/bundle/localsend_app`

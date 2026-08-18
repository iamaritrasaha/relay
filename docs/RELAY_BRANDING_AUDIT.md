# Relay branding audit

## Scope and rule

This audit covers tracked product sources containing `LocalSend`, `localsend`,
`org.localsend`, or `localsend_app`, with generated Dart output treated as a
derivative of its source i18n/configuration. The product rule for RA4C is:
user-visible language becomes **Relay**, except where a statement genuinely
means LocalSend interoperability or legal attribution.

No identifier is renamed by this audit. Category D changes need a dedicated
migration plan and compatibility review before implementation.

## A. User-facing: change to Relay in RA4C

| Area | Important tracked locations | RA4C action |
| --- | --- | --- |
| App name, About, support, quit, permissions, web-share copy | `app/assets/i18n/*.json` (all locale sources; notably `appName`, `about`, `settings`, `webShare`, context-menu, notifications, and close/quit strings) | Update source translations and regenerate Slang output. Localized statements that literally describe LocalSend-peer compatibility move to C instead. |
| Desktop/package presentation | `app/linux/packaging/{deb,rpm}/make_config.yaml`, `app/windows/runner/Runner.rc`, `app/macos/Runner/Info.plist`, `app/macos/Runner/Base.lproj/MainMenu.xib`, `app/macos/Runner/Configs/AppInfo.xcconfig` | Change display names, descriptions, launcher/menu text, and user-visible bundle labels while retaining app identity until migration is approved. |
| Android label/share-facing text | `app/android/app/src/main/AndroidManifest.xml`, Android resources referenced by it, share extension presentation files | Change launcher/application/share-facing labels to Relay; keep the application ID unchanged in RA4C unless a separate migration is approved. |
| In-app visible diagnostics and documents | user-facing LocalSend wording in `app/lib/**`, `README.md`, and current-release documentation | Replace product wording with Relay; preserve actual LocalSend compatibility wording under C and attribution under B. |

Generated files under `app/lib/gen/` are Category A derivatives, not manual
edit targets. The i18n JSON sources are authoritative.

## B. Legal / attribution: keep LocalSend

| Location | Why it stays |
| --- | --- |
| `README.md` attribution and Apache-2.0 acknowledgement | Identifies the upstream project and license relationship. |
| `LICENSE`, `NOTICE`, copyright headers, dependency licenses, and vendored-source notices | Legal provenance must remain accurate. |
| Historical entries in `app/assets/CHANGELOG.md` | Release history must not be rewritten as if the upstream product had a different name. |
| `CONTRIBUTING.md` upstream links and historical release/distribution references | Retain until the contributing/release process itself is deliberately migrated. |

## C. Interoperability: keep LocalSend name

| Location/pattern | Why it stays |
| --- | --- |
| `/api/localsend/...` routes, v2/v3 DTO/client/server comments and tests in `packages/core/src/http/**` | Wire-compatible LocalSend protocol path; changing it breaks LAN/manual interoperability. |
| `LocalSendPeer`, `LegacyLanInboundSession`, LocalSend protocol/discovery comments in `packages/core/src/relay/**`, `packages/core/src/multicast/**`, and `packages/core/src/discovery/**` | Explicitly distinguishes unauthenticated LocalSend-compatible LAN peers from Relay-authenticated peers. |
| LocalSend certificate/fingerprint compatibility wording in `packages/core/src/crypto/**` and `packages/core/src/http/client/**` | Documents protocol behavior, not Relay product presentation. |
| Browser/share wording that specifically means a LocalSend peer or protocol endpoint | Keep only where the meaning is interoperability; otherwise change the visible product wording under A. |

## D. Internal identifier / migration-sensitive: do not rename automatically

| Item | Representative locations | Migration impact |
| --- | --- | --- |
| Android application/package ID `org.localsend.localsend_app` | `app/android/app/build.gradle`, manifests, Kotlin package directory, method-channel constants | Changing it breaks Android upgrade continuity and installed-app identity; it also changes deep links, permissions, signing/update lineage, and channel lookup. |
| Android secure-storage alias and method channel | `RelayIdentitySecretStore.kt`, `MainActivity.kt`, Dart Android channel helpers | Changing without dual-read/migration can orphan the Relay identity secret and break persisted platform-channel communication. |
| Flutter Dart package `localsend_app` | `app/pubspec.yaml` and all `package:localsend_app/...` imports | Broad build/import migration; does not itself change protocol compatibility but requires a coordinated package rename. |
| Dart isolate package `localsend_isolates` and Rust plugin/crate `rust_lib_localsend_app` | `packages/localsend_isolates/**`, cargokit/build files, generated FRB bindings | Build/package/import migration with high generated-code and platform-artifact risk; no automatic rename. |
| Core crate/module names and Cargo lock entries | `packages/core`, workspace `Cargo.toml`, Cargo manifests/lock | Build/import migration; protocol route compatibility must remain separately preserved. |
| Linux desktop/app identity and binary identifiers | `app/linux/CMakeLists.txt`, generated runner/plugin files, packaging configuration | Changing affects desktop launchers, MIME associations, autostart/tray integration, and installed desktop identity. |
| macOS bundle IDs, app-group/keychain identifiers, share extension identifiers | `app/macos/Runner/**`, `app/macos/ShareExtension/**`, Xcode project settings | Changing affects upgrade continuity, installed identity, keychain/app-group data, and extension linkage. |
| Windows executable/MSIX/package identifiers and registry/context-menu keys | `app/windows/**`, `support/scripts/**` | Changing affects installed identity, upgrades, context-menu registration, and packaging/build tooling. |
| Preference/database/storage namespaces containing `localsend` | persistence helpers, platform paths, secure-store identifiers, and any serialized namespace discovered during RA4C planning | Can strand persisted preferences/history/database data unless old namespaces are read and migrated. |

## RA4C execution order

1. Update Category A source strings/metadata and regenerate derived files.
2. Keep B and C intact unless an individual occurrence is reclassified with
   evidence.
3. For every proposed D rename, document upgrade, storage, package, and
   interoperability migration behavior before editing it.

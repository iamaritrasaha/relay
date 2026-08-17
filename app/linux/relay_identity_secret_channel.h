#ifndef FLUTTER_RELAY_IDENTITY_SECRET_CHANNEL_H_
#define FLUTTER_RELAY_IDENTITY_SECRET_CHANNEL_H_

#include <flutter_linux/flutter_linux.h>

G_BEGIN_DECLS

// Registers the Relay identity secret MethodChannel on `messenger`.
//
// Backs `relayIdentitySecretLoad` / `relayIdentitySecretSave` /
// `relayIdentitySecretDelete` with the desktop Secret Service
// (org.freedesktop.secrets) via libsecret. Stores only the opaque PKCS#8
// private-key bytes for the single local Relay device identity; it does not
// generate keys, derive RelayId, or make trust decisions.
//
// Never unlocks or prompts the keyring: a locked default collection is
// reported back to Dart as `locked` rather than triggering the desktop's
// unlock UI.
void relay_identity_secret_channel_register(FlBinaryMessenger* messenger);

G_END_DECLS

#endif  // FLUTTER_RELAY_IDENTITY_SECRET_CHANNEL_H_

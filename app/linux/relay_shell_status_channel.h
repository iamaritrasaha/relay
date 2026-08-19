#ifndef FLUTTER_RELAY_SHELL_STATUS_CHANNEL_H_
#define FLUTTER_RELAY_SHELL_STATUS_CHANNEL_H_

#include <flutter_linux/flutter_linux.h>

G_BEGIN_DECLS

// Registers Relay's desktop shell status service on `messenger`.
//
// Relay publishes one sanitized snapshot of the user's primary phone on the
// session bus (com.foresight.app.relay.Shell) so shell surfaces such as the
// GNOME Shell panel extension can present it without speaking any device
// protocol themselves.
//
// The snapshot is filtered against a fixed field whitelist here, so the bus
// can only ever carry the presentation fields Relay intends: no message or
// notification bodies, no clipboard contents, no phone numbers or contacts,
// and no keys, certificates or other trust material.
void relay_shell_status_channel_register(FlBinaryMessenger* messenger);

G_END_DECLS

#endif  // FLUTTER_RELAY_SHELL_STATUS_CHANNEL_H_

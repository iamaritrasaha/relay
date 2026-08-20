#ifndef FLUTTER_RELAY_DESKTOP_NOTIFICATION_CHANNEL_H_
#define FLUTTER_RELAY_DESKTOP_NOTIFICATION_CHANNEL_H_

#include <flutter_linux/flutter_linux.h>

G_BEGIN_DECLS

// Registers Relay's desktop notification service on `messenger`.
void relay_desktop_notification_channel_register(FlBinaryMessenger* messenger);

G_END_DECLS

#endif  // FLUTTER_RELAY_DESKTOP_NOTIFICATION_CHANNEL_H_

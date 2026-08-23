#ifndef RELAY_CLIPBOARD_CHANNEL_H_
#define RELAY_CLIPBOARD_CHANNEL_H_

#include <flutter_linux/flutter_linux.h>

// Registers the Relay clipboard channel, which reports local clipboard changes
// to Dart and applies remote ones.
void relay_clipboard_channel_register(FlBinaryMessenger* messenger);

#endif  // RELAY_CLIPBOARD_CHANNEL_H_

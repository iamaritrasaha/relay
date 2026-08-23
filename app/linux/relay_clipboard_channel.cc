#include "relay_clipboard_channel.h"

#include <gtk/gtk.h>
#include <cstring>

namespace {

constexpr char kChannelName[] = "com.foresight.app.relay/clipboard";

constexpr char kMethodSetText[] = "setText";
constexpr char kMethodGetText[] = "getText";
constexpr char kMethodStartWatching[] = "startWatching";
constexpr char kMethodStopWatching[] = "stopWatching";
constexpr char kMethodClipboardChanged[] = "clipboardChanged";

// Mirrors relay_core's MAX_CLIPBOARD_BYTES. Enforced here as well so an
// enormous local selection is dropped before it is ever copied into Dart.
constexpr gsize kMaxClipboardBytes = 64 * 1024;

struct RelayClipboardService {
  FlMethodChannel* channel;
  GtkClipboard* clipboard;
  gulong owner_change_handler;
};

RelayClipboardService* g_service = nullptr;

// Reads the clipboard after an owner change and hands the text to Dart.
//
// GTK delivers clipboard text asynchronously, so the read cannot happen inside
// the signal handler itself. Note that this also fires for clipboard writes
// Relay made: distinguishing those is deliberately not attempted here, because
// the authoritative loop suppression lives in relay_core where it can also see
// what arrived from remote devices.
void relay_clipboard_text_received(GtkClipboard* clipboard, const gchar* text, gpointer user_data) {
  auto* service = static_cast<RelayClipboardService*>(user_data);
  if (text == nullptr || service == nullptr || service->channel == nullptr) {
    return;
  }
  gsize length = strlen(text);
  if (length == 0 || length > kMaxClipboardBytes) {
    // Length only: clipboard contents are never logged.
    g_debug("Relay clipboard: ignoring a local change of %" G_GSIZE_FORMAT " bytes", length);
    return;
  }
  g_autoptr(FlValue) args = fl_value_new_map();
  fl_value_set_string_take(args, "text", fl_value_new_string(text));
  fl_method_channel_invoke_method(service->channel, kMethodClipboardChanged, args, nullptr, nullptr,
                                  nullptr);
}

void relay_clipboard_owner_changed(GtkClipboard* clipboard, GdkEvent* event, gpointer user_data) {
  auto* service = static_cast<RelayClipboardService*>(user_data);
  if (service == nullptr) {
    return;
  }
  gtk_clipboard_request_text(clipboard, relay_clipboard_text_received, service);
}

// GTK's clipboard abstraction is backed by the Wayland data-device protocol on
// a Wayland session and by X11 selections under Xwayland/X11, so this one path
// covers both without the app needing to know which it is running on.
GtkClipboard* relay_clipboard_get() {
  return gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
}

void relay_clipboard_start_watching(RelayClipboardService* service) {
  if (service->owner_change_handler != 0) {
    return;
  }
  service->clipboard = relay_clipboard_get();
  if (service->clipboard == nullptr) {
    return;
  }
  service->owner_change_handler = g_signal_connect(
      service->clipboard, "owner-change", G_CALLBACK(relay_clipboard_owner_changed), service);
}

void relay_clipboard_stop_watching(RelayClipboardService* service) {
  if (service->owner_change_handler == 0 || service->clipboard == nullptr) {
    return;
  }
  g_signal_handler_disconnect(service->clipboard, service->owner_change_handler);
  service->owner_change_handler = 0;
}

void relay_clipboard_method_call_handler(FlMethodChannel* channel, FlMethodCall* method_call,
                                         gpointer user_data) {
  auto* service = static_cast<RelayClipboardService*>(user_data);
  const gchar* name = fl_method_call_get_name(method_call);
  g_autoptr(GError) error = nullptr;

  if (strcmp(name, kMethodStartWatching) == 0) {
    relay_clipboard_start_watching(service);
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    fl_method_call_respond(method_call, response, &error);
    return;
  }

  if (strcmp(name, kMethodStopWatching) == 0) {
    relay_clipboard_stop_watching(service);
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    fl_method_call_respond(method_call, response, &error);
    return;
  }

  if (strcmp(name, kMethodSetText) == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    FlValue* text_value =
        fl_value_get_type(args) == FL_VALUE_TYPE_MAP ? fl_value_lookup_string(args, "text") : nullptr;
    if (text_value == nullptr || fl_value_get_type(text_value) != FL_VALUE_TYPE_STRING) {
      fl_method_call_respond_error(method_call, "INVALID_ARGUMENT", "Missing text", nullptr, &error);
      return;
    }
    const char* text = fl_value_get_string(text_value);
    gsize length = strlen(text);
    if (length == 0 || length > kMaxClipboardBytes) {
      fl_method_call_respond_error(method_call, "OUT_OF_RANGE", "Clipboard text out of range",
                                   nullptr, &error);
      return;
    }
    gtk_clipboard_set_text(relay_clipboard_get(), text, static_cast<gint>(length));
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    fl_method_call_respond(method_call, response, &error);
    return;
  }

  if (strcmp(name, kMethodGetText) == 0) {
    g_autofree gchar* text = gtk_clipboard_wait_for_text(relay_clipboard_get());
    g_autoptr(FlValue) result =
        text == nullptr ? fl_value_new_null() : fl_value_new_string(text);
    g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
    fl_method_call_respond(method_call, response, &error);
    return;
  }

  fl_method_call_respond_not_implemented(method_call, &error);
}

}  // namespace

void relay_clipboard_channel_register(FlBinaryMessenger* messenger) {
  if (g_service != nullptr) {
    return;
  }
  auto* service = g_new0(RelayClipboardService, 1);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  service->channel = fl_method_channel_new(messenger, kChannelName, FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(service->channel, relay_clipboard_method_call_handler,
                                            service, nullptr);
  g_service = service;
}

#include "relay_shell_status_channel.h"

#include <gio/gio.h>

#include <cstring>

namespace {

constexpr char kChannelName[] = "com.foresight.app.relay/relay_shell_status";

constexpr char kMethodPublish[] = "relayShellStatusPublish";
constexpr char kMethodActivate[] = "relayShellActivate";
constexpr char kMethodQuit[] = "relayShellQuit";
constexpr char kMethodFindPhone[] = "relayShellFindPhone";
constexpr char kMethodSurfaceChanged[] = "relayShellSurfaceChanged";
constexpr char kMethodSurfaceQuery[] = "relayShellSurfaceQuery";

constexpr char kBusName[] = "com.foresight.app.relay.Shell";

// Held by a desktop shell surface (the GNOME Shell panel extension) for as long
// as it is presenting Relay. Relay watches it so it can stay out of the
// notification area while the shell already shows it.
constexpr char kSurfaceBusName[] = "com.foresight.app.relay.ShellSurface";
constexpr char kObjectPath[] = "/com/foresight/app/relay/Shell";
constexpr char kInterfaceName[] = "com.foresight.app.relay.Shell1";

// Bumped only when the meaning of an existing field changes. Adding a new
// optional field does not break a consumer that ignores unknown keys, so it
// does not bump this.
constexpr guint32 kProtocolVersion = 1;

constexpr char kIntrospectionXml[] =
    "<node>"
    "  <interface name='com.foresight.app.relay.Shell1'>"
    "    <method name='GetPhoneStatus'>"
    "      <arg type='a{sv}' name='status' direction='out'/>"
    "    </method>"
    "    <method name='Activate'/>"
    "    <method name='Quit'/>"
    "    <method name='FindPhone'>"
    "      <arg type='s' name='device_id' direction='in'/>"
    "    </method>"
    "    <signal name='PhoneStatusChanged'>"
    "      <arg type='a{sv}' name='status'/>"
    "    </signal>"
    "    <property name='ProtocolVersion' type='u' access='read'/>"
    "  </interface>"
    "</node>";

// The complete set of fields Relay is willing to put on the bus.
//
// This is the privacy boundary: a key that is not listed here never leaves the
// process, whatever Dart sends. Optional fields are simply absent when Relay
// does not know them, which is deliberately distinct from a zero value.
enum class FieldType { kString, kBool, kInt32, kInt64 };

struct FieldSpec {
  const char* key;
  FieldType type;
};

constexpr FieldSpec kAllowedFields[] = {
    {"deviceId", FieldType::kString},
    {"displayName", FieldType::kString},
    {"deviceType", FieldType::kString},
    {"connected", FieldType::kBool},
    {"paired", FieldType::kBool},
    {"batteryPercentage", FieldType::kInt32},
    {"batteryIsCharging", FieldType::kBool},
    {"batteryIsFull", FieldType::kBool},
    {"batteryIsStale", FieldType::kBool},
    {"networkKind", FieldType::kString},
    {"networkLabel", FieldType::kString},
    {"signalLevel", FieldType::kInt32},
    {"unreadMessageCount", FieldType::kInt32},
    {"notificationCount", FieldType::kInt32},
    {"supportsFindDevice", FieldType::kBool},
    {"supportsClipboard", FieldType::kBool},
    {"supportsMessages", FieldType::kBool},
    {"supportsNotifications", FieldType::kBool},
    {"phoneCount", FieldType::kInt32},
    {"lastUpdated", FieldType::kInt64},
};

struct RelayShellStatusService {
  FlMethodChannel* channel;  // owned
  GDBusConnection* connection;  // owned while the name is held
  guint owner_id;
  guint surface_watch_id;
  guint registration_id;
  // Whether a shell surface is presenting Relay right now. Kept here as well as
  // pushed, because the watch can fire before Dart is listening.
  bool surface_attached;
  // The snapshot last published by Dart, always a floating-free "a{sv}".
  // An empty dictionary means Relay currently has no phone to present.
  GVariant* status;
};

RelayShellStatusService* g_service = nullptr;

const FieldSpec* relay_lookup_field(const gchar* key) {
  for (const FieldSpec& spec : kAllowedFields) {
    if (strcmp(spec.key, key) == 0) {
      return &spec;
    }
  }
  return nullptr;
}

// Converts one whitelisted entry, or returns nullptr when the value does not
// have the type the field is declared with. A mistyped value is dropped rather
// than coerced, so a consumer never sees an invented number.
GVariant* relay_field_to_variant(const FieldSpec& spec, FlValue* value) {
  FlValueType type = fl_value_get_type(value);
  switch (spec.type) {
    case FieldType::kString:
      return type == FL_VALUE_TYPE_STRING ? g_variant_new_string(fl_value_get_string(value)) : nullptr;
    case FieldType::kBool:
      return type == FL_VALUE_TYPE_BOOL ? g_variant_new_boolean(fl_value_get_bool(value)) : nullptr;
    case FieldType::kInt32: {
      if (type != FL_VALUE_TYPE_INT) {
        return nullptr;
      }
      int64_t raw = fl_value_get_int(value);
      if (raw < G_MININT32 || raw > G_MAXINT32) {
        return nullptr;
      }
      return g_variant_new_int32(static_cast<gint32>(raw));
    }
    case FieldType::kInt64:
      return type == FL_VALUE_TYPE_INT ? g_variant_new_int64(fl_value_get_int(value)) : nullptr;
  }
  return nullptr;
}

// Builds the "a{sv}" snapshot from what Dart published.
//
// `args` is either a map or null; anything else, and every unknown or mistyped
// entry inside a map, is ignored. The result is always a valid dictionary, so a
// malformed publish degrades to "no phone" instead of breaking the bus.
GVariant* relay_status_from_fl_value(FlValue* args) {
  g_auto(GVariantBuilder) builder;
  g_variant_builder_init(&builder, G_VARIANT_TYPE("a{sv}"));

  if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
    size_t length = fl_value_get_length(args);
    for (size_t i = 0; i < length; i++) {
      FlValue* key = fl_value_get_map_key(args, i);
      if (fl_value_get_type(key) != FL_VALUE_TYPE_STRING) {
        continue;
      }
      const FieldSpec* spec = relay_lookup_field(fl_value_get_string(key));
      if (spec == nullptr) {
        continue;
      }
      GVariant* entry = relay_field_to_variant(*spec, fl_value_get_map_value(args, i));
      if (entry != nullptr) {
        g_variant_builder_add(&builder, "{sv}", spec->key, entry);
      }
    }
  }

  return g_variant_ref_sink(g_variant_builder_end(&builder));
}

void relay_handle_method_call(GDBusConnection* /*connection*/,
                              const gchar* /*sender*/,
                              const gchar* /*object_path*/,
                              const gchar* /*interface_name*/,
                              const gchar* method_name,
                              GVariant* parameters,
                              GDBusMethodInvocation* invocation,
                              gpointer user_data) {
  auto* service = static_cast<RelayShellStatusService*>(user_data);

  if (strcmp(method_name, "GetPhoneStatus") == 0) {
    g_dbus_method_invocation_return_value(invocation, g_variant_new_tuple(&service->status, 1));
    return;
  }

  if (strcmp(method_name, "Activate") == 0) {
    fl_method_channel_invoke_method(service->channel, kMethodActivate, nullptr, nullptr, nullptr, nullptr);
    g_dbus_method_invocation_return_value(invocation, nullptr);
    return;
  }

  if (strcmp(method_name, "Quit") == 0) {
    // Answered before Relay acts on it, so the caller is not left waiting on a
    // process that is on its way out.
    g_dbus_method_invocation_return_value(invocation, nullptr);
    fl_method_channel_invoke_method(service->channel, kMethodQuit, nullptr, nullptr, nullptr, nullptr);
    return;
  }

  if (strcmp(method_name, "FindPhone") == 0) {
    const gchar* device_id = nullptr;
    g_variant_get(parameters, "(&s)", &device_id);
    g_autoptr(FlValue) argument = fl_value_new_string(device_id == nullptr ? "" : device_id);
    fl_method_channel_invoke_method(service->channel, kMethodFindPhone, argument, nullptr, nullptr, nullptr);
    g_dbus_method_invocation_return_value(invocation, nullptr);
    return;
  }

  g_dbus_method_invocation_return_error(invocation, G_DBUS_ERROR, G_DBUS_ERROR_UNKNOWN_METHOD, "Unknown method %s", method_name);
}

GVariant* relay_handle_get_property(GDBusConnection* /*connection*/,
                                    const gchar* /*sender*/,
                                    const gchar* /*object_path*/,
                                    const gchar* /*interface_name*/,
                                    const gchar* property_name,
                                    GError** error,
                                    gpointer /*user_data*/) {
  if (strcmp(property_name, "ProtocolVersion") == 0) {
    return g_variant_new_uint32(kProtocolVersion);
  }
  g_set_error(error, G_DBUS_ERROR, G_DBUS_ERROR_UNKNOWN_PROPERTY, "Unknown property %s", property_name);
  return nullptr;
}

const GDBusInterfaceVTable kInterfaceVTable = {
    relay_handle_method_call,
    relay_handle_get_property,
    nullptr,
    {nullptr, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr},
};

void relay_on_bus_acquired(GDBusConnection* connection, const gchar* /*name*/, gpointer user_data) {
  auto* service = static_cast<RelayShellStatusService*>(user_data);

  g_autoptr(GError) error = nullptr;
  g_autoptr(GDBusNodeInfo) node = g_dbus_node_info_new_for_xml(kIntrospectionXml, &error);
  if (node == nullptr) {
    g_warning("Relay shell status introspection is invalid: %s", error->message);
    return;
  }

  guint registration_id = g_dbus_connection_register_object(connection, kObjectPath, node->interfaces[0], &kInterfaceVTable, service, nullptr, &error);
  if (registration_id == 0) {
    g_warning("Failed to publish the Relay shell status object: %s", error->message);
    return;
  }

  service->connection = G_DBUS_CONNECTION(g_object_ref(connection));
  service->registration_id = registration_id;
}

void relay_on_name_lost(GDBusConnection* /*connection*/, const gchar* name, gpointer user_data) {
  auto* service = static_cast<RelayShellStatusService*>(user_data);

  // Another Relay instance took the name, or there is no session bus at all.
  // Neither is fatal: Relay keeps running and shell surfaces simply see the
  // service as absent.
  if (service->registration_id != 0 && service->connection != nullptr) {
    g_dbus_connection_unregister_object(service->connection, service->registration_id);
    service->registration_id = 0;
  }
  g_clear_object(&service->connection);
  g_debug("Relay no longer owns %s", name);
}

// Publishes a snapshot and tells subscribers about it.
//
// Dart already drops updates that describe the same phone state, so every call
// that reaches here is a real change and is worth one signal.
void relay_publish_status(RelayShellStatusService* service, FlValue* args) {
  GVariant* status = relay_status_from_fl_value(args);
  g_clear_pointer(&service->status, g_variant_unref);
  service->status = status;

  if (service->connection == nullptr) {
    return;
  }

  g_autoptr(GError) error = nullptr;
  if (!g_dbus_connection_emit_signal(service->connection, nullptr, kObjectPath, kInterfaceName, "PhoneStatusChanged",
                                     g_variant_new_tuple(&service->status, 1), &error)) {
    g_debug("Emitting the Relay phone status signal failed: %s", error->message);
  }
}

// Tells Dart whether a desktop shell surface is presenting Relay right now.
void relay_notify_surface(RelayShellStatusService* service, bool attached) {
  service->surface_attached = attached;
  g_autoptr(FlValue) argument = fl_value_new_bool(attached);
  fl_method_channel_invoke_method(service->channel, kMethodSurfaceChanged, argument, nullptr, nullptr, nullptr);
}

void relay_on_surface_appeared(GDBusConnection* /*connection*/, const gchar* /*name*/, const gchar* /*owner*/, gpointer user_data) {
  relay_notify_surface(static_cast<RelayShellStatusService*>(user_data), true);
}

void relay_on_surface_vanished(GDBusConnection* /*connection*/, const gchar* /*name*/, gpointer user_data) {
  relay_notify_surface(static_cast<RelayShellStatusService*>(user_data), false);
}

void relay_shell_status_method_call_handler(FlMethodChannel* /*channel*/, FlMethodCall* method_call, gpointer user_data) {
  auto* service = static_cast<RelayShellStatusService*>(user_data);
  g_autoptr(GError) error = nullptr;

  const gchar* name = fl_method_call_get_name(method_call);

  // The name watch can fire before Dart has a handler installed, so the state
  // is asked for once rather than relying on having caught the notification.
  if (strcmp(name, kMethodSurfaceQuery) == 0) {
    g_autoptr(FlValue) attached = fl_value_new_bool(service->surface_attached);
    g_autoptr(FlMethodResponse) surface_response = FL_METHOD_RESPONSE(fl_method_success_response_new(attached));
    fl_method_call_respond(method_call, surface_response, &error);
    return;
  }

  if (strcmp(name, kMethodPublish) != 0) {
    fl_method_call_respond_not_implemented(method_call, &error);
    return;
  }

  relay_publish_status(service, fl_method_call_get_args(method_call));

  g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  fl_method_call_respond(method_call, response, &error);
}

}  // namespace

void relay_shell_status_channel_register(FlBinaryMessenger* messenger) {
  if (g_service != nullptr) {
    return;
  }

  auto* service = g_new0(RelayShellStatusService, 1);

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  service->channel = fl_method_channel_new(messenger, kChannelName, FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(service->channel, relay_shell_status_method_call_handler, service, nullptr);
  service->status = relay_status_from_fl_value(nullptr);

  service->owner_id = g_bus_own_name(G_BUS_TYPE_SESSION, kBusName,
                                     static_cast<GBusNameOwnerFlags>(G_BUS_NAME_OWNER_FLAGS_REPLACE | G_BUS_NAME_OWNER_FLAGS_ALLOW_REPLACEMENT),
                                     relay_on_bus_acquired, nullptr, relay_on_name_lost, service, nullptr);

  service->surface_watch_id = g_bus_watch_name(G_BUS_TYPE_SESSION, kSurfaceBusName, G_BUS_NAME_WATCHER_FLAGS_NONE,
                                               relay_on_surface_appeared, relay_on_surface_vanished, service, nullptr);

  g_service = service;
}

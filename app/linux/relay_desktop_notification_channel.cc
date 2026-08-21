#include "relay_desktop_notification_channel.h"

#include <gio/gio.h>
#include <cstring>

namespace {

constexpr char kChannelName[] = "com.foresight.app.relay/desktop_notifications";

constexpr char kMethodShowNotification[] = "showNotification";
constexpr char kMethodWithdrawNotification[] = "withdrawNotification";
constexpr char kMethodNotificationActivated[] = "notificationActivated";

constexpr char kNotificationsBusName[] = "org.freedesktop.Notifications";
constexpr char kNotificationsObjectPath[] = "/org/freedesktop/Notifications";
constexpr char kNotificationsInterface[] = "org.freedesktop.Notifications";

struct RelayDesktopNotificationService {
  FlMethodChannel* channel;
  GDBusConnection* connection;
  GHashTable* id_map; // maps string dart id to uint32 freedesktop id
  GHashTable* reverse_id_map; // maps uint32 freedesktop id to string dart id
  guint signal_action_invoked_id;
  guint signal_notification_closed_id;
};

RelayDesktopNotificationService* g_service = nullptr;

// The icon the notification server should draw beside "Relay".
//
// The freedesktop specification lets app_icon be either a themed icon name or
// a file URI. The themed name only resolves once the package has installed the
// icon under the application id, so prefer the copy that ships inside the
// Flutter bundle: that one is present for an uninstalled build too, and the
// banner otherwise falls back to a generic placeholder.
const char* relay_notification_icon() {
  static gchar* icon = nullptr;
  static gboolean resolved = FALSE;
  if (!resolved) {
    resolved = TRUE;
    g_autofree gchar* exe_path = g_file_read_link("/proc/self/exe", nullptr);
    if (exe_path != nullptr) {
      g_autofree gchar* exe_dir = g_path_get_dirname(exe_path);
      g_autofree gchar* icon_path = g_build_filename(
          exe_dir, "data", "flutter_assets", "assets", "img",
          "relay-icon-linux-512.png", nullptr);
      if (g_file_test(icon_path, G_FILE_TEST_EXISTS)) {
        icon = g_filename_to_uri(icon_path, nullptr, nullptr);
      }
    }
    if (icon == nullptr) {
      icon = g_strdup("com.foresight.app.relay");
    }
  }
  return icon;
}

void relay_notify_action_invoked(GDBusConnection* connection,
                                 const gchar* sender_name,
                                 const gchar* object_path,
                                 const gchar* interface_name,
                                 const gchar* signal_name,
                                 GVariant* parameters,
                                 gpointer user_data) {
  auto* service = static_cast<RelayDesktopNotificationService*>(user_data);
  guint32 id;
  const gchar* action_key;
  g_variant_get(parameters, "(us)", &id, &action_key);

  g_debug("Notification activated: %u", id);

  gpointer dart_id_ptr = g_hash_table_lookup(service->reverse_id_map, GUINT_TO_POINTER(id));
  if (dart_id_ptr != nullptr) {
    const char* dart_id = static_cast<const char*>(dart_id_ptr);
    g_autoptr(FlValue) args = fl_value_new_map();
    fl_value_set_string_take(args, "id", fl_value_new_string(dart_id));
    fl_method_channel_invoke_method(service->channel, kMethodNotificationActivated, args, nullptr, nullptr, nullptr);
  }
}

void relay_notify_notification_closed(GDBusConnection* connection,
                                      const gchar* sender_name,
                                      const gchar* object_path,
                                      const gchar* interface_name,
                                      const gchar* signal_name,
                                      GVariant* parameters,
                                      gpointer user_data) {
  auto* service = static_cast<RelayDesktopNotificationService*>(user_data);
  guint32 id;
  guint32 reason;
  g_variant_get(parameters, "(uu)", &id, &reason);

  g_debug("Notification closed: %u", id);

  gpointer dart_id_ptr = g_hash_table_lookup(service->reverse_id_map, GUINT_TO_POINTER(id));
  if (dart_id_ptr != nullptr) {
    g_hash_table_remove(service->id_map, dart_id_ptr);
    g_hash_table_remove(service->reverse_id_map, GUINT_TO_POINTER(id));
  }
}

void relay_show_notification(RelayDesktopNotificationService* service, FlMethodCall* method_call, FlValue* args) {
  g_autoptr(GError) error = nullptr;

  if (fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    fl_method_call_respond_error(method_call, "INVALID_ARGUMENT", "Expected a map", nullptr, &error);
    return;
  }

  FlValue* id_val = fl_value_lookup_string(args, "id");
  FlValue* app_name_val = fl_value_lookup_string(args, "appName");
  FlValue* title_val = fl_value_lookup_string(args, "title");
  FlValue* body_val = fl_value_lookup_string(args, "body");
  FlValue* device_name_val = fl_value_lookup_string(args, "deviceName");

  if (id_val == nullptr || fl_value_get_type(id_val) != FL_VALUE_TYPE_STRING) {
    fl_method_call_respond_error(method_call, "INVALID_ARGUMENT", "Missing or invalid id", nullptr, &error);
    return;
  }

  const char* dart_id = fl_value_get_string(id_val);
  const char* raw_app_name = (app_name_val && fl_value_get_type(app_name_val) == FL_VALUE_TYPE_STRING) ? fl_value_get_string(app_name_val) : "";
  const char* title = (title_val && fl_value_get_type(title_val) == FL_VALUE_TYPE_STRING) ? fl_value_get_string(title_val) : "";
  const char* body = (body_val && fl_value_get_type(body_val) == FL_VALUE_TYPE_STRING) ? fl_value_get_string(body_val) : "";
  const char* device_name = (device_name_val && fl_value_get_type(device_name_val) == FL_VALUE_TYPE_STRING) ? fl_value_get_string(device_name_val) : "";

  g_autofree gchar* app_name = nullptr;
  if (strlen(device_name) > 0) {
    app_name = g_strdup_printf("Relay · %s", device_name);
  } else if (strlen(raw_app_name) > 0) {
    app_name = g_strdup_printf("Relay · %s", raw_app_name);
  } else {
    app_name = g_strdup("Relay");
  }

  guint32 replaces_id = 0;
  gpointer existing_id_ptr = g_hash_table_lookup(service->id_map, dart_id);
  if (existing_id_ptr != nullptr) {
    replaces_id = GPOINTER_TO_UINT(existing_id_ptr);
  }

  g_debug("Showing notification for dart id: %s, replacing: %u", dart_id, replaces_id);

  g_auto(GVariantBuilder) hints_builder;
  g_variant_builder_init(&hints_builder, G_VARIANT_TYPE("a{sv}"));
  g_variant_builder_add(&hints_builder, "{sv}", "desktop-entry", g_variant_new_string("com.foresight.app.relay"));

  g_auto(GVariantBuilder) actions_builder;
  g_variant_builder_init(&actions_builder, G_VARIANT_TYPE("as"));
  g_variant_builder_add(&actions_builder, "s", "default");
  g_variant_builder_add(&actions_builder, "s", "Open");

  if (service->connection == nullptr) {
    service->connection = g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, &error);
    if (service->connection == nullptr) {
      fl_method_call_respond_error(method_call, "DBUS_ERROR", "Failed to connect to session bus", nullptr, &error);
      return;
    }

    service->signal_action_invoked_id = g_dbus_connection_signal_subscribe(
        service->connection, kNotificationsBusName, kNotificationsInterface, "ActionInvoked",
        kNotificationsObjectPath, nullptr, G_DBUS_SIGNAL_FLAGS_NONE, relay_notify_action_invoked, service, nullptr);

    service->signal_notification_closed_id = g_dbus_connection_signal_subscribe(
        service->connection, kNotificationsBusName, kNotificationsInterface, "NotificationClosed",
        kNotificationsObjectPath, nullptr, G_DBUS_SIGNAL_FLAGS_NONE, relay_notify_notification_closed, service, nullptr);
  }

  GVariant* parameters = g_variant_new("(susssasa{sv}i)",
                                       app_name,
                                       replaces_id,
                                       relay_notification_icon(),
                                       title,
                                       body,
                                       &actions_builder,
                                       &hints_builder,
                                       -1); // expire_timeout

  g_autoptr(GVariant) result = g_dbus_connection_call_sync(
      service->connection, kNotificationsBusName, kNotificationsObjectPath, kNotificationsInterface,
      "Notify", parameters, G_VARIANT_TYPE("(u)"), G_DBUS_CALL_FLAGS_NONE, -1, nullptr, &error);

  if (result == nullptr) {
    g_debug("Failed to call Notify: %s", error->message);
    fl_method_call_respond_error(method_call, "DBUS_ERROR", error->message, nullptr, nullptr); // Do not double-free error
    return;
  }

  guint32 new_id;
  g_variant_get(result, "(u)", &new_id);

  g_hash_table_insert(service->id_map, g_strdup(dart_id), GUINT_TO_POINTER(new_id));
  g_hash_table_insert(service->reverse_id_map, GUINT_TO_POINTER(new_id), g_strdup(dart_id));

  g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  fl_method_call_respond(method_call, response, &error);
}

void relay_withdraw_notification(RelayDesktopNotificationService* service, FlMethodCall* method_call, FlValue* args) {
  g_autoptr(GError) error = nullptr;

  if (fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    fl_method_call_respond_error(method_call, "INVALID_ARGUMENT", "Expected a map", nullptr, &error);
    return;
  }

  FlValue* id_val = fl_value_lookup_string(args, "id");
  if (id_val == nullptr || fl_value_get_type(id_val) != FL_VALUE_TYPE_STRING) {
    fl_method_call_respond_error(method_call, "INVALID_ARGUMENT", "Missing or invalid id", nullptr, &error);
    return;
  }

  const char* dart_id = fl_value_get_string(id_val);

  gpointer existing_id_ptr = g_hash_table_lookup(service->id_map, dart_id);
  if (existing_id_ptr == nullptr) {
    g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    fl_method_call_respond(method_call, response, &error);
    return;
  }

  guint32 fd_id = GPOINTER_TO_UINT(existing_id_ptr);
  g_debug("Withdrawing notification for dart id: %s, freedesktop id: %u", dart_id, fd_id);

  if (service->connection != nullptr) {
    g_dbus_connection_call(service->connection, kNotificationsBusName, kNotificationsObjectPath, kNotificationsInterface,
                           "CloseNotification", g_variant_new("(u)", fd_id), nullptr, G_DBUS_CALL_FLAGS_NONE, -1, nullptr, nullptr, nullptr);
  }

  g_hash_table_remove(service->id_map, dart_id);
  g_hash_table_remove(service->reverse_id_map, GUINT_TO_POINTER(fd_id));

  g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  fl_method_call_respond(method_call, response, &error);
}

void relay_desktop_notification_method_call_handler(FlMethodChannel* channel, FlMethodCall* method_call, gpointer user_data) {
  auto* service = static_cast<RelayDesktopNotificationService*>(user_data);
  const gchar* name = fl_method_call_get_name(method_call);

  if (strcmp(name, kMethodShowNotification) == 0) {
    relay_show_notification(service, method_call, fl_method_call_get_args(method_call));
  } else if (strcmp(name, kMethodWithdrawNotification) == 0) {
    relay_withdraw_notification(service, method_call, fl_method_call_get_args(method_call));
  } else {
    g_autoptr(GError) error = nullptr;
    fl_method_call_respond_not_implemented(method_call, &error);
  }
}

}  // namespace

void relay_desktop_notification_channel_register(FlBinaryMessenger* messenger) {
  if (g_service != nullptr) {
    return;
  }

  auto* service = g_new0(RelayDesktopNotificationService, 1);
  service->id_map = g_hash_table_new_full(g_str_hash, g_str_equal, g_free, nullptr);
  service->reverse_id_map = g_hash_table_new_full(g_direct_hash, g_direct_equal, nullptr, g_free);

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  service->channel = fl_method_channel_new(messenger, kChannelName, FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(service->channel, relay_desktop_notification_method_call_handler, service, nullptr);

  g_service = service;
}

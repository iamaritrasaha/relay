#include "relay_identity_secret_channel.h"

#include <libsecret/secret.h>

#include <cstring>

namespace {

constexpr char kChannelName[] = "org.localsend.localsend_app/relay_identity_secret";

constexpr char kMethodLoad[] = "relayIdentitySecretLoad";
constexpr char kMethodSave[] = "relayIdentitySecretSave";
constexpr char kMethodDelete[] = "relayIdentitySecretDelete";

// Private SecretService subtype for Relay's background identity store. Its
// prompt vfuncs fail closed so libsecret cannot automatically execute a
// SecretPrompt returned by CreateItem, Delete, or another backend operation.
typedef struct _RelayNoPromptSecretService RelayNoPromptSecretService;
typedef struct _RelayNoPromptSecretServiceClass RelayNoPromptSecretServiceClass;

struct _RelayNoPromptSecretService {
  SecretService parent_instance;
};

struct _RelayNoPromptSecretServiceClass {
  SecretServiceClass parent_class;
};

#define RELAY_TYPE_NO_PROMPT_SECRET_SERVICE (relay_no_prompt_secret_service_get_type())

G_DEFINE_TYPE(RelayNoPromptSecretService, relay_no_prompt_secret_service, SECRET_TYPE_SERVICE)

GVariant* relay_no_prompt_secret_service_prompt_sync(SecretService* /*service*/,
                                                      SecretPrompt* /*prompt*/,
                                                      GCancellable* /*cancellable*/,
                                                      const GVariantType* /*return_type*/,
                                                      GError** error) {
  g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_FAILED, "Relay secret storage refuses interactive Secret Service prompts");
  return nullptr;
}

void relay_no_prompt_secret_service_prompt_async(SecretService* service,
                                                 SecretPrompt* /*prompt*/,
                                                 const GVariantType* /*return_type*/,
                                                 GCancellable* cancellable,
                                                 GAsyncReadyCallback callback,
                                                 gpointer user_data) {
  g_autoptr(GTask) task = g_task_new(service, cancellable, callback, user_data);
  g_task_return_new_error(task, G_IO_ERROR, G_IO_ERROR_FAILED, "Relay secret storage refuses interactive Secret Service prompts");
}

GVariant* relay_no_prompt_secret_service_prompt_finish(SecretService* /*service*/, GAsyncResult* result, GError** error) {
  return static_cast<GVariant*>(g_task_propagate_pointer(G_TASK(result), error));
}

void relay_no_prompt_secret_service_class_init(RelayNoPromptSecretServiceClass* klass) {
  SecretServiceClass* service_class = SECRET_SERVICE_CLASS(klass);
  service_class->prompt_sync = relay_no_prompt_secret_service_prompt_sync;
  service_class->prompt_async = relay_no_prompt_secret_service_prompt_async;
  service_class->prompt_finish = relay_no_prompt_secret_service_prompt_finish;
}

void relay_no_prompt_secret_service_init(RelayNoPromptSecretService* /*service*/) {}

// Fixed schema for the single local Relay device identity secret. Lookup is
// always by this fixed attribute set only, never by alias/IP/RelayId.
const SecretSchema kRelayIdentitySchema = {
    "org.localsend.relay.identity",
    SECRET_SCHEMA_NONE,
    {
        {"application", SECRET_SCHEMA_ATTRIBUTE_STRING},
        {"purpose", SECRET_SCHEMA_ATTRIBUTE_STRING},
        {"version", SECRET_SCHEMA_ATTRIBUTE_STRING},
        {nullptr, SECRET_SCHEMA_ATTRIBUTE_STRING},
    },
};

enum class RelayOp { kLoad, kSave, kDelete };

struct RelayTaskData {
  RelayOp op;
  FlMethodCall* method_call;  // owned (reffed on creation)
  guint8* secret;             // owned, only populated for kSave
  gsize secret_len;
};

struct RelayTaskResult {
  gchar* state;      // owned, always set
  guint8* secret;     // owned, only set for a successful load
  gsize secret_len;
};

void relay_task_data_free(gpointer data) {
  RelayTaskData* task_data = reinterpret_cast<RelayTaskData*>(data);
  if (task_data->method_call != nullptr) {
    g_object_unref(task_data->method_call);
  }
  if (task_data->secret != nullptr) {
    // Best-effort clear of the secret bytes we copied for the async hop.
    memset(task_data->secret, 0, task_data->secret_len);
    g_free(task_data->secret);
  }
  g_free(task_data);
}

void relay_task_result_free(gpointer data) {
  RelayTaskResult* result = reinterpret_cast<RelayTaskResult*>(data);
  g_free(result->state);
  if (result->secret != nullptr) {
    memset(result->secret, 0, result->secret_len);
    g_free(result->secret);
  }
  g_free(result);
}

// Maps a GError from a Secret Service D-Bus call to one of the load/save
// result states shared with the Dart RelayIdentitySecretStore contract.
// `unmapped_fallback` is returned for errors that don't match a known cause.
const gchar* relay_map_service_error(GError* error, const gchar* unmapped_fallback) {
  if (error == nullptr) {
    return unmapped_fallback;
  }

  g_autofree gchar* dbus_name = g_dbus_error_get_remote_error(error);
  if (dbus_name != nullptr) {
    if (g_str_has_suffix(dbus_name, "IsLocked")) {
      return "locked";
    }
    if (g_str_has_suffix(dbus_name, "NoSuchObject")) {
      return "notFound";
    }
    if (g_str_has_suffix(dbus_name, "AccessDenied") || g_str_has_suffix(dbus_name, "NotAuthorized")) {
      return "permissionDenied";
    }
    if (g_str_has_suffix(dbus_name, "ServiceUnknown") || g_str_has_suffix(dbus_name, "NameHasNoOwner")) {
      return "notAvailable";
    }
    return "failed";
  }

  if (g_error_matches(error, G_DBUS_ERROR, G_DBUS_ERROR_SERVICE_UNKNOWN) ||
      g_error_matches(error, G_DBUS_ERROR, G_DBUS_ERROR_NAME_HAS_NO_OWNER) ||
      g_error_matches(error, G_DBUS_ERROR, G_DBUS_ERROR_NO_REPLY) ||
      g_error_matches(error, G_IO_ERROR, G_IO_ERROR_DBUS_ERROR)) {
    return "notAvailable";
  }

  return unmapped_fallback;
}

// Finds the single item matching the fixed Relay identity schema/attributes,
// without loading its secret or unlocking anything. Returns nullptr (with
// *out_error unset) if none exists.
SecretItem* relay_find_item(SecretService* service, GHashTable* attributes, GCancellable* cancellable, GError** out_error) {
  GList* items = secret_service_search_sync(service, &kRelayIdentitySchema, attributes, SECRET_SEARCH_NONE, cancellable, out_error);
  if (items == nullptr) {
    return nullptr;
  }
  SecretItem* item = SECRET_ITEM(g_object_ref(items->data));
  g_list_free_full(items, g_object_unref);
  return item;
}

void relay_perform_load(SecretService* service, GHashTable* attributes, GCancellable* cancellable, RelayTaskResult* result) {
  GError* error = nullptr;
  g_autoptr(SecretItem) item = relay_find_item(service, attributes, cancellable, &error);
  if (error != nullptr) {
    result->state = g_strdup(relay_map_service_error(error, "failed"));
    g_clear_error(&error);
    return;
  }
  if (item == nullptr) {
    result->state = g_strdup("notFound");
    return;
  }

  // Per-item lock state; this is a plain property read, not a D-Bus round
  // trip that could prompt.
  if (secret_item_get_locked(item)) {
    result->state = g_strdup("locked");
    return;
  }

  // Item.GetSecret has no Prompt out-parameter in the Secret Service D-Bus
  // spec, so this cannot trigger an implicit unlock/prompt.
  if (!secret_item_load_secret_sync(item, cancellable, &error)) {
    result->state = g_strdup(relay_map_service_error(error, "failed"));
    g_clear_error(&error);
    return;
  }

  g_autoptr(SecretValue) value = secret_item_get_secret(item);
  if (value == nullptr) {
    result->state = g_strdup("corrupt");
    return;
  }

  gsize length = 0;
  const gchar* bytes = secret_value_get(value, &length);
  if (bytes == nullptr || length == 0) {
    result->state = g_strdup("corrupt");
    return;
  }

  result->state = g_strdup("found");
  result->secret = static_cast<guint8*>(g_memdup2(bytes, length));
  result->secret_len = length;
}

void relay_perform_save(SecretService* service,
                        SecretCollection* collection,
                        GHashTable* attributes,
                        const guint8* secret,
                        gsize secret_len,
                        GCancellable* cancellable,
                        RelayTaskResult* result) {
  if (secret == nullptr || secret_len == 0) {
    result->state = g_strdup("failed");
    return;
  }

  GError* error = nullptr;
  g_autoptr(SecretItem) existing = relay_find_item(service, attributes, cancellable, &error);
  if (error != nullptr) {
    result->state = g_strdup(relay_map_service_error(error, "failed"));
    g_clear_error(&error);
    return;
  }

  g_autoptr(SecretValue) value =
      secret_value_new(reinterpret_cast<const gchar*>(secret), static_cast<gssize>(secret_len), "application/octet-stream");

  if (existing != nullptr) {
    if (secret_item_get_locked(existing)) {
      result->state = g_strdup("locked");
      return;
    }
    // Item.SetSecret has no Prompt out-parameter, so replacing an existing
    // item's value cannot trigger an implicit unlock/prompt.
    gboolean ok = secret_item_set_secret_sync(existing, value, cancellable, &error);
    result->state = g_strdup(ok ? "success" : relay_map_service_error(error, "failed"));
    g_clear_error(&error);
    return;
  }

  // Collection.CreateItem can return a SecretPrompt. The Relay-specific
  // SecretService subtype rejects it immediately, so this operation fails
  // closed instead of showing or executing an interactive prompt.
  g_autoptr(SecretItem) created =
      secret_item_create_sync(collection, &kRelayIdentitySchema, attributes, "Relay device identity", value, SECRET_ITEM_CREATE_NONE,
                              cancellable, &error);
  result->state = g_strdup(created != nullptr ? "success" : relay_map_service_error(error, "failed"));
  g_clear_error(&error);
}

void relay_perform_delete(SecretService* service, GHashTable* attributes, GCancellable* cancellable, RelayTaskResult* result) {
  GError* error = nullptr;
  g_autoptr(SecretItem) item = relay_find_item(service, attributes, cancellable, &error);
  if (error != nullptr) {
    result->state = g_strdup(relay_map_service_error(error, "failed"));
    g_clear_error(&error);
    return;
  }
  if (item == nullptr) {
    result->state = g_strdup("success");  // idempotent: nothing to delete
    return;
  }

  if (secret_item_get_locked(item)) {
    result->state = g_strdup("locked");
    return;
  }

  // Item.Delete can return a SecretPrompt. The Relay-specific SecretService
  // subtype rejects it immediately, so this operation fails closed.
  gboolean ok = secret_item_delete_sync(item, cancellable, &error);
  result->state = g_strdup(ok ? "success" : relay_map_service_error(error, "failed"));
  g_clear_error(&error);
}

// Runs entirely on a GLib worker thread (via g_task_run_in_thread). All
// blocking libsecret calls happen here, off the GTK/UI thread.
void relay_task_worker(GTask* task, gpointer /*source_object*/, gpointer task_data, GCancellable* cancellable) {
  RelayTaskData* data = reinterpret_cast<RelayTaskData*>(task_data);
  RelayTaskResult* result = g_new0(RelayTaskResult, 1);

  GError* error = nullptr;
  // Opening a session is a session-key handshake, not an unlock. This private
  // service subtype refuses every SecretPrompt libsecret might otherwise
  // perform while completing an operation.
  g_autoptr(SecretService) service =
      secret_service_open_sync(RELAY_TYPE_NO_PROMPT_SECRET_SERVICE, nullptr, SECRET_SERVICE_OPEN_SESSION, cancellable, &error);
  if (service == nullptr) {
    result->state = g_strdup(relay_map_service_error(error, "notAvailable"));
    g_clear_error(&error);
    g_task_return_pointer(task, result, relay_task_result_free);
    return;
  }

  // Resolving the "default" alias to a collection is a read of service
  // state; it does not unlock or create anything.
  g_autoptr(SecretCollection) collection =
      secret_collection_for_alias_sync(service, SECRET_COLLECTION_DEFAULT, SECRET_COLLECTION_NONE, cancellable, &error);
  if (error != nullptr) {
    result->state = g_strdup(relay_map_service_error(error, "notAvailable"));
    g_clear_error(&error);
    g_task_return_pointer(task, result, relay_task_result_free);
    return;
  }
  if (collection == nullptr) {
    // No default collection is configured. Do not create one (that could
    // require confirmation); report it as no usable secret store.
    result->state = g_strdup("notAvailable");
    g_task_return_pointer(task, result, relay_task_result_free);
    return;
  }

  // Plain property read, loaded when the collection proxy was created above;
  // not a fresh D-Bus round trip and never unlocks anything.
  if (secret_collection_get_locked(collection)) {
    result->state = g_strdup("locked");
    g_task_return_pointer(task, result, relay_task_result_free);
    return;
  }

  g_autoptr(GHashTable) attributes = secret_attributes_build(&kRelayIdentitySchema, "application", "Relay", "purpose",
                                                              "relay-device-identity", "version", "1", nullptr);

  switch (data->op) {
    case RelayOp::kLoad:
      relay_perform_load(service, attributes, cancellable, result);
      break;
    case RelayOp::kSave:
      relay_perform_save(service, collection, attributes, data->secret, data->secret_len, cancellable, result);
      break;
    case RelayOp::kDelete:
      relay_perform_delete(service, attributes, cancellable, result);
      break;
  }

  g_task_return_pointer(task, result, relay_task_result_free);
}

// Runs on the GTK/main thread (the thread-default context captured when the
// task was created, i.e. the one the MethodChannel call arrived on).
void relay_task_complete(GObject* /*source_object*/, GAsyncResult* res, gpointer user_data) {
  RelayTaskData* data = reinterpret_cast<RelayTaskData*>(user_data);
  g_autoptr(GError) error = nullptr;
  RelayTaskResult* result = reinterpret_cast<RelayTaskResult*>(g_task_propagate_pointer(G_TASK(res), &error));

  g_autoptr(FlValue) response = fl_value_new_map();
  if (result == nullptr) {
    // The task itself failed to run (e.g. cancelled); this is not expected
    // in normal operation since we never cancel.
    fl_value_set_string_take(response, "state", fl_value_new_string("failed"));
  } else {
    fl_value_set_string_take(response, "state", fl_value_new_string(result->state));
    if (result->secret != nullptr) {
      fl_value_set_string_take(response, "secret", fl_value_new_uint8_list(result->secret, result->secret_len));
    }
  }

  g_autoptr(GError) respond_error = nullptr;
  fl_method_call_respond_success(data->method_call, response, &respond_error);

  if (result != nullptr) {
    relay_task_result_free(result);
  }
  relay_task_data_free(data);
}

void relay_start_task(RelayOp op, FlMethodCall* method_call, guint8* secret, gsize secret_len) {
  RelayTaskData* data = g_new0(RelayTaskData, 1);
  data->op = op;
  data->method_call = FL_METHOD_CALL(g_object_ref(method_call));
  data->secret = secret;
  data->secret_len = secret_len;

  // task_data is owned by relay_task_complete/relay_task_data_free, not by
  // GTask itself, since we need it in the completion callback too.
  GTask* task = g_task_new(nullptr, nullptr, relay_task_complete, data);
  g_task_run_in_thread(task, relay_task_worker);
  g_object_unref(task);
}

void relay_identity_secret_method_call_handler(FlMethodChannel* /*channel*/, FlMethodCall* method_call, gpointer /*user_data*/) {
  const gchar* method = fl_method_call_get_name(method_call);

  if (strcmp(method, kMethodLoad) == 0) {
    relay_start_task(RelayOp::kLoad, method_call, nullptr, 0);
    return;
  }

  if (strcmp(method, kMethodDelete) == 0) {
    relay_start_task(RelayOp::kDelete, method_call, nullptr, 0);
    return;
  }

  if (strcmp(method, kMethodSave) == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    FlValue* secret_value = args != nullptr ? fl_value_lookup_string(args, "secret") : nullptr;
    if (secret_value == nullptr || fl_value_get_type(secret_value) != FL_VALUE_TYPE_UINT8_LIST) {
      g_autoptr(GError) error = nullptr;
      fl_method_call_respond_error(method_call, "invalid_args", "secret must be a byte list", nullptr, &error);
      return;
    }

    gsize length = fl_value_get_length(secret_value);
    guint8* secret_copy = length > 0 ? static_cast<guint8*>(g_memdup2(fl_value_get_uint8_list(secret_value), length)) : nullptr;
    relay_start_task(RelayOp::kSave, method_call, secret_copy, length);
    return;
  }

  g_autoptr(GError) error = nullptr;
  fl_method_call_respond_not_implemented(method_call, &error);
}

}  // namespace

void relay_identity_secret_channel_register(FlBinaryMessenger* messenger) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  // Intentionally leaked for the lifetime of the process, matching how the
  // generated plugin registrant's channels are never explicitly torn down.
  FlMethodChannel* channel = fl_method_channel_new(messenger, kChannelName, FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, relay_identity_secret_method_call_handler, nullptr, nullptr);
}

#include "my_application.h"

#include <cstddef>
#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"
#include "relay_identity_secret_channel.h"

#include <stdlib.h>
#include <string.h>

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Gives every Relay window the Relay icon.
//
// Without this the window carries no _NET_WM_ICON, so X11 docks, task
// switchers and window lists fall back to a generic placeholder. The icon
// ships inside the Flutter bundle, so it resolves relative to the executable
// and therefore works for an uninstalled bundle as well as an installed one.
// If the bundle layout is not found we fall back to the hicolor theme entry
// installed under the application id by the packaging step.
static void relay_set_default_window_icon() {
  g_autofree gchar* exe_path = g_file_read_link("/proc/self/exe", nullptr);
  if (exe_path != nullptr) {
    g_autofree gchar* exe_dir = g_path_get_dirname(exe_path);
    g_autofree gchar* icon_path = g_build_filename(
        exe_dir, "data", "flutter_assets", "assets", "img",
        "relay-icon-linux-512.png", nullptr);
    if (g_file_test(icon_path, G_FILE_TEST_EXISTS)) {
      g_autoptr(GError) error = nullptr;
      if (gtk_window_set_default_icon_from_file(icon_path, &error)) {
        return;
      }
      g_warning("Failed to load the Relay window icon: %s", error->message);
    }
  }

  gtk_window_set_default_icon_name(APPLICATION_ID);
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  relay_set_default_window_icon();
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Check if --hidden is present in arguments
  bool start_hidden = false;
  if (self->dart_entrypoint_arguments != nullptr) {
    for (int i = 0; self->dart_entrypoint_arguments[i] != nullptr; i++) {
      if (strcmp(self->dart_entrypoint_arguments[i], "--hidden") == 0) {
        start_hidden = true;
        break;
      }
    }
  }

  // If have GTK_CSD in env and it is equal to 1 then add the gtk header bar
  // to always use client side decorations
  const char* GTK_CSD = getenv("GTK_CSD");
  if (GTK_CSD && strcmp(GTK_CSD, "1") == 0) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "Relay");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "Relay");
  }

  gtk_window_set_default_size(window, 400, 500);

  if (!start_hidden) {
    gtk_widget_show(GTK_WIDGET(window));
  } else {
    // Realize the window so plugins (like tray) can initialize, 
    // but don't map it to the screen.
    gtk_widget_realize(GTK_WIDGET(window));
  }

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  relay_identity_secret_channel_register(fl_engine_get_binary_messenger(fl_view_get_engine(view)));

  if (!start_hidden) {
    gtk_widget_grab_focus(GTK_WIDGET(view));
  }
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application, gchar*** arguments, int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
     g_warning("Failed to register: %s", error->message);
     *exit_status = 1;
     return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line = my_application_local_command_line;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID,
                                     "flags", G_APPLICATION_NON_UNIQUE,
                                     nullptr));
}

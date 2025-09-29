#include "tray_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <cstring>

#ifdef HAVE_AYATANA
#include <libayatana-appindicator/app-indicator.h>
#else
#include <libappindicator/app-indicator.h>
#endif

struct _PasteproTrayPlugin {
  GObject parent_instance;
  FlMethodChannel* channel;
  AppIndicator* indicator;
  GtkWidget* menu;
  GtkWidget* toggle_item;
};

G_DEFINE_TYPE(PasteproTrayPlugin, pastepro_tray_plugin, g_object_get_type())

static void send_activate_signal(PasteproTrayPlugin* self) {
  if (self->channel == nullptr) {
    return;
  }
  fl_method_channel_invoke_method(self->channel, "onActivate", nullptr,
                                  nullptr, nullptr, nullptr);
}

static void toggle_menu_item_activate(GtkWidget* widget, gpointer user_data) {
  auto* plugin = PASTEPRO_TRAY_PLUGIN(user_data);
  send_activate_signal(plugin);
}

static void ensure_menu(PasteproTrayPlugin* self) {
  if (self->menu != nullptr) {
    return;
  }
  self->menu = gtk_menu_new();
  self->toggle_item = gtk_menu_item_new_with_label("Toggle PastePro");
  g_signal_connect(self->toggle_item, "activate",
                   G_CALLBACK(toggle_menu_item_activate), self);
  gtk_menu_shell_append(GTK_MENU_SHELL(self->menu), self->toggle_item);
  gtk_widget_show(self->toggle_item);
}

static void set_icon(PasteproTrayPlugin* self, FlValue* args) {
  const gchar* icon_path =
      fl_value_get_string(fl_value_lookup_string(args, "iconPath"));
  const gchar* tooltip =
      fl_value_get_string(fl_value_lookup_string(args, "tooltip"));

  ensure_menu(self);

  if (self->indicator == nullptr) {
#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#elif defined(__GNUC__)
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
#endif
    self->indicator = app_indicator_new("pastepro", icon_path,
                                        APP_INDICATOR_CATEGORY_APPLICATION_STATUS);
#if defined(__clang__)
#pragma clang diagnostic pop
#elif defined(__GNUC__)
#pragma GCC diagnostic pop
#endif
    app_indicator_set_menu(self->indicator, GTK_MENU(self->menu));
    if (self->toggle_item != nullptr) {
#if defined(HAVE_AYATANA)
      app_indicator_set_secondary_activate_target(self->indicator,
                                                  GTK_WIDGET(self->toggle_item));
#endif
    }
  }

  app_indicator_set_status(self->indicator, APP_INDICATOR_STATUS_ACTIVE);
  app_indicator_set_icon_full(self->indicator, icon_path, tooltip);
  app_indicator_set_label(self->indicator, tooltip, "");
  gtk_widget_show_all(self->menu);
}

static void dispose_indicator(PasteproTrayPlugin* self) {
  if (self->indicator != nullptr) {
    app_indicator_set_status(self->indicator, APP_INDICATOR_STATUS_PASSIVE);
    g_clear_object(&self->indicator);
  }
  if (self->menu != nullptr) {
    gtk_widget_destroy(self->menu);
    self->menu = nullptr;
    self->toggle_item = nullptr;
  }
}

static void pastepro_tray_plugin_handle_method_call(FlMethodChannel* channel,
                                                    FlMethodCall* method_call,
                                                    gpointer user_data) {
  auto* self = PASTEPRO_TRAY_PLUGIN(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;

  if (std::strcmp(method, "setIcon") == 0) {
    set_icon(self, fl_method_call_get_args(method_call));
    response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_bool(true)));
  } else if (std::strcmp(method, "dispose") == 0) {
    dispose_indicator(self);
    response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_bool(true)));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

static void pastepro_tray_plugin_dispose(GObject* object) {
  auto* self = PASTEPRO_TRAY_PLUGIN(object);
  dispose_indicator(self);
  g_clear_object(&self->channel);
  G_OBJECT_CLASS(pastepro_tray_plugin_parent_class)->dispose(object);
}

static void pastepro_tray_plugin_class_init(PasteproTrayPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = pastepro_tray_plugin_dispose;
}

static void pastepro_tray_plugin_init(PasteproTrayPlugin* self) {}

void pastepro_tray_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  PasteproTrayPlugin* plugin =
      PASTEPRO_TRAY_PLUGIN(g_object_new(pastepro_tray_plugin_get_type(), nullptr));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar), "pastepro/tray",
      FL_METHOD_CODEC(codec));

  plugin->channel = FL_METHOD_CHANNEL(g_object_ref(channel));

  fl_method_channel_set_method_call_handler(channel,
                                            pastepro_tray_plugin_handle_method_call,
                                            g_object_ref(plugin), g_object_unref);

  g_object_unref(plugin);
}

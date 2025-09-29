#ifndef PASTEPRO_TRAY_PLUGIN_H_
#define PASTEPRO_TRAY_PLUGIN_H_

#include <flutter_linux/flutter_linux.h>

G_BEGIN_DECLS

G_DECLARE_FINAL_TYPE(PasteproTrayPlugin, pastepro_tray_plugin, PASTEPRO, TRAY_PLUGIN, GObject)

void pastepro_tray_plugin_register_with_registrar(FlPluginRegistrar* registrar);

G_END_DECLS

#endif  // PASTEPRO_TRAY_PLUGIN_H_

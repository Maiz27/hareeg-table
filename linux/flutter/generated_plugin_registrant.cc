//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <audioplayers_linux/audioplayers_linux_plugin.h>

/**
 * @brief Registers Linux plugins with the given Flutter plugin registry.
 *
 * This function registers the AudioplayersLinuxPlugin with the provided
 * FlPluginRegistry so the plugin becomes available to the Flutter engine.
 *
 * @param registry The plugin registry into which the plugin will be registered.
 */
void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) audioplayers_linux_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "AudioplayersLinuxPlugin");
  audioplayers_linux_plugin_register_with_registrar(audioplayers_linux_registrar);
}

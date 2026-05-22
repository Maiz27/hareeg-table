//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <audioplayers_windows/audioplayers_windows_plugin.h>

/**
 * @brief Registers generated platform plugins with the provided Flutter plugin registry.
 *
 * Registers platform plugin implementations so they are available to the Flutter
 * embedding on Windows (currently registers AudioplayersWindowsPlugin).
 *
 * @param registry Pointer to the Flutter plugin registry to receive plugin registrations.
 */
void RegisterPlugins(flutter::PluginRegistry* registry) {
  AudioplayersWindowsPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("AudioplayersWindowsPlugin"));
}

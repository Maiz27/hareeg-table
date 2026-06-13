import 'key_value_store.dart';
// Selects the platform-appropriate factory at compile time: the web
// implementation (localStorage) when `dart:js_interop` is available, otherwise
// the native platform-channel store.
import 'key_value_store_native.dart'
    if (dart.library.js_interop) 'key_value_store_web.dart';

/// Builds the default [KeyValueStore] for the current platform.
KeyValueStore createDefaultKeyValueStore() => createKeyValueStore();

import 'replay_file_store.dart';
// Selects the platform-appropriate factory at compile time: the web
// implementation (localStorage) when `dart:js_interop` is available, otherwise
// the native platform-channel store. Mirrors `key_value_store_factory.dart`.
import 'replay_file_store_native.dart'
    if (dart.library.js_interop) 'replay_file_store_web.dart';

/// Builds the default [ReplayFileStore] for the current platform.
ReplayFileStore createDefaultReplayFileStore() => createReplayFileStore();

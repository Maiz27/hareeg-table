import 'key_value_store.dart';

/// Native (Android/iOS/desktop) factory: the platform-channel store, which
/// itself falls back to in-memory on platforms without the channel.
KeyValueStore createKeyValueStore() => MethodChannelKeyValueStore();

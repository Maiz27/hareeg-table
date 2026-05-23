import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Minimal string key/value store used by persistence repositories.
abstract interface class KeyValueStore {
  /// Loads a stored string value.
  Future<String?> loadString(String key);

  /// Saves a string value.
  Future<void> saveString(String key, String value);

  /// Removes a stored value.
  Future<void> remove(String key);
}

/// Platform-channel key/value storage backed by Android SharedPreferences and
/// iOS UserDefaults.
///
/// Falls back to an in-process map when the platform channel is unavailable
/// (desktop/web), so the app continues to function in unsupported targets.
/// The fallback is logged loudly so support gaps are visible in the console
/// rather than silently swallowing persisted state.
class MethodChannelKeyValueStore implements KeyValueStore {
  /// Creates platform-channel storage.
  MethodChannelKeyValueStore({
    MethodChannel channel = const MethodChannel('hareeg_table/local_storage'),
  }) : _channel = channel;

  final MethodChannel _channel;
  final Map<String, String> _fallbackMemory = {};
  bool _loggedFallback = false;

  bool get _canUseInMemoryFallback {
    if (kIsWeb) {
      return true;
    }

    return switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS => false,
      TargetPlatform.linux ||
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.fuchsia => true,
    };
  }

  void _warnAboutFallback() {
    if (_loggedFallback) {
      return;
    }
    _loggedFallback = true;
    debugPrint(
      '[hareeg_table] Platform channel "hareeg_table/local_storage" is not '
      'available on this platform. Falling back to in-memory storage; saved '
      'preferences and matches will not survive app restart. '
      'Android and iOS register this channel at startup.',
    );
  }

  @override
  Future<String?> loadString(String key) async {
    try {
      return await _channel.invokeMethod<String>('getString', {'key': key});
    } on MissingPluginException {
      if (!_canUseInMemoryFallback) {
        rethrow;
      }
      _warnAboutFallback();
      return _fallbackMemory[key];
    }
  }

  @override
  Future<void> remove(String key) async {
    try {
      await _channel.invokeMethod<void>('remove', {'key': key});
    } on MissingPluginException {
      if (!_canUseInMemoryFallback) {
        rethrow;
      }
      _warnAboutFallback();
      _fallbackMemory.remove(key);
    }
  }

  @override
  Future<void> saveString(String key, String value) async {
    try {
      await _channel.invokeMethod<void>('setString', {
        'key': key,
        'value': value,
      });
    } on MissingPluginException {
      if (!_canUseInMemoryFallback) {
        rethrow;
      }
      _warnAboutFallback();
      _fallbackMemory[key] = value;
    }
  }
}

/// Coerces a dynamic JSON value into a `Map<String, Object?>` when possible.
///
/// Shared by repositories that decode persisted JSON blobs and need to defend
/// against unexpected types after schema evolution or manual edits.
Map<String, Object?>? jsonMapOrNull(Object? value) {
  if (value is Map) {
    return {
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }

  return null;
}

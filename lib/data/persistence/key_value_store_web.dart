import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'key_value_store.dart';

/// Web factory: a `localStorage`-backed store so preferences, in-progress
/// matches, and onboarding/practice progress survive a page refresh.
KeyValueStore createKeyValueStore() => WebLocalStorageKeyValueStore();

/// [KeyValueStore] backed by the browser's `window.localStorage`.
///
/// `localStorage` is synchronous and origin-scoped, which is exactly what the
/// repositories need: the same string keys that the native platform channel
/// stores now persist across reloads on web too. Access is wrapped in
/// try/catch because `localStorage` can throw when storage is disabled
/// (private browsing, blocked cookies) or the quota is exceeded — in those
/// cases we degrade to a no-op read/write rather than crashing the app.
class WebLocalStorageKeyValueStore implements KeyValueStore {
  /// Creates a `localStorage`-backed store.
  WebLocalStorageKeyValueStore();

  web.Storage get _storage => web.window.localStorage;

  @override
  Future<String?> loadString(String key) async {
    try {
      return _storage.getItem(key);
    } catch (error) {
      debugPrint('[hareeg_table] localStorage read failed for "$key": $error');
      return null;
    }
  }

  @override
  Future<void> saveString(String key, String value) async {
    try {
      _storage.setItem(key, value);
    } catch (error) {
      debugPrint('[hareeg_table] localStorage write failed for "$key": $error');
    }
  }

  @override
  Future<void> remove(String key) async {
    try {
      _storage.removeItem(key);
    } catch (error) {
      debugPrint('[hareeg_table] localStorage remove failed for "$key": $error');
    }
  }
}

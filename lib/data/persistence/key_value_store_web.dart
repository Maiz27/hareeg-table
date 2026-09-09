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
/// cases repositories must receive the error. A failed read is not absence,
/// and a failed write must never authorize deletion of recovery data.
class WebLocalStorageKeyValueStore implements KeyValueStore {
  /// Creates a `localStorage`-backed store.
  WebLocalStorageKeyValueStore({web.Storage? storage})
    : _injectedStorage = storage;
  final web.Storage? _injectedStorage;

  web.Storage get _storage => _injectedStorage ?? web.window.localStorage;

  @override
  Future<String?> loadString(String key) async {
    try {
      return _storage.getItem(key);
    } catch (error) {
      debugPrint('[hareeg_table] localStorage read failed for "$key": $error');
      rethrow;
    }
  }

  @override
  Future<void> saveString(String key, String value) async {
    try {
      _storage.setItem(key, value);
    } catch (error) {
      debugPrint('[hareeg_table] localStorage write failed for "$key": $error');
      rethrow;
    }
  }

  @override
  Future<void> remove(String key) async {
    try {
      _storage.removeItem(key);
    } catch (error) {
      debugPrint(
        '[hareeg_table] localStorage remove failed for "$key": $error',
      );
      rethrow;
    }
  }
}

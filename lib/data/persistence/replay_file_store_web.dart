import 'package:web/web.dart' as web;

import 'replay_file_store.dart';
import 'replay_file_store_browser.dart';

/// Web factory: a `localStorage`-backed replay store, since the browser build
/// has no filesystem.
ReplayFileStore createReplayFileStore() =>
    WebReplayFileStore(storage: const WindowLocalStorage());

/// [ReplayBrowserStorage] backed by `window.localStorage`.
///
/// Deliberately logic-free: it is the only part of the browser adapter that
/// needs a real browser to execute, so everything that could be wrong lives
/// above it in [WebReplayFileStore], where any runner can test it.
class WindowLocalStorage implements ReplayBrowserStorage {
  /// Creates `localStorage`-backed browser storage.
  const WindowLocalStorage();

  web.Storage get _storage => web.window.localStorage;

  @override
  String? read(String key) => _storage.getItem(key);

  @override
  void write(String key, String value) => _storage.setItem(key, value);

  @override
  void delete(String key) => _storage.removeItem(key);

  @override
  List<String> keys() {
    final storage = _storage;
    final names = <String>[];
    for (var index = 0; index < storage.length; index++) {
      final name = storage.key(index);
      if (name != null) {
        names.add(name);
      }
    }
    return names;
  }
}

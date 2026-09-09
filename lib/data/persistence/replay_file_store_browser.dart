import 'replay_file_store.dart';

/// Narrow seam over the browser storage API.
///
/// It carries no `package:web` import on purpose. Everything interesting about
/// the browser adapter — prefixing, listing, key re-validation, failure
/// propagation — lives in [WebReplayFileStore] above this seam, so all of it is
/// testable on any platform. Only [WindowLocalStorage] in
/// `replay_file_store_web.dart` needs a real browser, and it holds no logic to
/// get wrong.
abstract interface class ReplayBrowserStorage {
  /// Reads a raw entry, or `null` when it is absent.
  String? read(String key);

  /// Writes a raw entry.
  void write(String key, String value);

  /// Removes a raw entry.
  void delete(String key);

  /// Lists every raw entry name currently held.
  List<String> keys();
}

/// [ReplayFileStore] backed by browser storage.
///
/// Entries live under [entryPrefix] so replay payloads never collide with, or
/// appear alongside, the key/value entries the preferences, active-match, and
/// learning-progress repositories write to the same origin.
///
/// Unlike `WebLocalStorageKeyValueStore`, a failed write throws instead of
/// degrading to a silent no-op. A dropped preference is a small annoyance; a
/// silently dropped replay payload would let a match be published as replayable
/// with nothing behind it, which is exactly the dead link this store exists to
/// prevent.
class WebReplayFileStore implements ReplayFileStore {
  /// Creates a browser-storage replay store.
  WebReplayFileStore({required ReplayBrowserStorage storage})
    : _storage = storage;

  /// Prefix applied to every replay entry name.
  static const String entryPrefix = 'hareeg_table.replay/';

  final ReplayBrowserStorage _storage;

  String _entryName(String key) => '$entryPrefix$key';

  Never _throwIoError(Object error, String? key) {
    throw ReplayFileStoreException(
      code: ReplayFileStoreErrorCode.ioError,
      message: 'Browser storage rejected the replay operation: $error',
      key: key,
      cause: error,
    );
  }

  @override
  Future<void> writeFile(String key, String contents) async {
    validateReplayFileKey(key);
    try {
      _storage.write(_entryName(key), contents);
    } catch (error) {
      _throwIoError(error, key);
    }
  }

  @override
  Future<String?> readFile(String key) async {
    validateReplayFileKey(key);
    try {
      return _storage.read(_entryName(key));
    } catch (error) {
      _throwIoError(error, key);
    }
  }

  @override
  Future<bool> deleteFile(String key) async {
    validateReplayFileKey(key);
    final name = _entryName(key);
    try {
      final existed = _storage.read(name) != null;
      _storage.delete(name);
      return existed;
    } catch (error) {
      _throwIoError(error, key);
    }
  }

  @override
  Future<List<String>> listKeys() async {
    final List<String> names;
    try {
      names = _storage.keys();
    } catch (error) {
      _throwIoError(error, null);
    }

    final keys = <String>[];
    for (final name in names) {
      if (!name.startsWith(entryPrefix)) {
        continue;
      }
      final key = name.substring(entryPrefix.length);
      // An entry can carry the prefix and still not name a usable key — a
      // hand-edited `hareeg_table.replay/bad key` for instance. Dropping it
      // here keeps the promise that everything listed is accepted by the
      // keyed operations, matching how the native handlers skip a file whose
      // name does not map back to a valid key.
      if (isValidReplayFileKey(key)) {
        keys.add(key);
      }
    }

    return keys..sort();
  }
}

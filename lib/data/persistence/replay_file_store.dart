import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Error codes carried by [ReplayFileStoreException].
///
/// The set is deliberately tiny: callers only ever need to tell "this key was
/// never valid" from "the backend failed" from "this platform has no store".
abstract final class ReplayFileStoreErrorCode {
  /// The logical key does not satisfy [replayFileKeyPattern].
  static const String invalidKey = 'invalid_key';

  /// The backend refused or failed the operation.
  ///
  /// Every platform failure that is not an invalid key collapses here, with
  /// the original platform code preserved in the message and the underlying
  /// error preserved as [ReplayFileStoreException.cause].
  static const String ioError = 'io_error';

  /// No replay file backend exists on this platform.
  ///
  /// Raised only from the Dart side when the platform channel is missing on a
  /// target that is expected to provide it. A platform response never carries
  /// this code.
  static const String unavailable = 'unavailable';
}

/// Failure raised by every [ReplayFileStore] operation that cannot complete.
///
/// A raw `PlatformException` never escapes a store — callers see this type or
/// nothing, so error handling does not have to know which adapter is live.
class ReplayFileStoreException implements Exception {
  /// Creates a replay-file failure.
  const ReplayFileStoreException({
    required this.code,
    required this.message,
    this.key,
    this.cause,
  });

  /// One of the constants on [ReplayFileStoreErrorCode].
  final String code;

  /// Human-readable detail, including the originating platform code when the
  /// failure came from a platform channel.
  final String message;

  /// The logical key the operation targeted, when the operation had one.
  ///
  /// `null` for [ReplayFileStore.listKeys], which takes no key.
  final String? key;

  /// The underlying error, when this failure wraps one.
  final Object? cause;

  @override
  String toString() {
    final target = key == null ? '' : ' (key: "$key")';
    return 'ReplayFileStoreException[$code]$target: $message';
  }
}

/// The logical-key rule shared by every adapter and re-asserted natively.
///
/// First character alphanumeric, then alphanumerics, `_`, and `-`, to a total
/// of 120 characters. The rule exists so a caller's key can never become a
/// path: `.`, `..`, separators, drive letters, percent escapes, whitespace,
/// and control characters are all outside the character class, and the leading
/// alphanumeric requirement additionally rules out dotfiles.
const String replayFileKeyPattern = r'^[A-Za-z0-9][A-Za-z0-9_-]{0,119}$';

final RegExp _replayFileKeyExpression = RegExp(replayFileKeyPattern);

/// Whether [key] is a usable logical replay key.
bool isValidReplayFileKey(String key) => _replayFileKeyExpression.hasMatch(key);

/// Throws [ReplayFileStoreException] with [ReplayFileStoreErrorCode.invalidKey]
/// unless [key] satisfies [replayFileKeyPattern].
///
/// Adapters call this before touching their backend, so an unsafe key never
/// reaches a platform channel or browser storage in the first place. The
/// native handlers repeat the check independently — this is the first guard,
/// not the only one.
void validateReplayFileKey(String key) {
  if (isValidReplayFileKey(key)) {
    return;
  }

  throw ReplayFileStoreException(
    code: ReplayFileStoreErrorCode.invalidKey,
    message:
        'Replay file keys must match $replayFileKeyPattern. '
        'Keys are logical identifiers, never paths.',
    key: key,
  );
}

/// Storage for one heavy replay payload per completed match.
///
/// Keys are *logical* — a match id, not a path. The store owns the directory,
/// the file name, and the extension; no operation accepts, returns, or exposes
/// a filesystem path.
///
/// Absence and failure are distinct: reading a key that was never written
/// returns `null`, while a backend failure throws. Callers that self-heal a
/// missing replay depend on being able to tell those apart.
abstract interface class ReplayFileStore {
  /// Stores [contents] under [key], replacing any existing payload.
  ///
  /// Returning normally means the payload is stored. A failed replacement
  /// leaves the previously committed payload readable.
  Future<void> writeFile(String key, String contents);

  /// Reads the payload stored under [key], or `null` when nothing is stored.
  Future<String?> readFile(String key);

  /// Removes the payload stored under [key].
  ///
  /// Returns whether a payload existed. Deleting an absent key is not an
  /// error.
  Future<bool> deleteFile(String key);

  /// Lists the stored logical keys, ascending.
  ///
  /// Every returned key is accepted by the keyed operations — entries the
  /// backend cannot map back to a valid logical key are dropped rather than
  /// surfaced.
  Future<List<String>> listKeys();
}

/// In-process [ReplayFileStore].
///
/// Backs tests and the degraded desktop path of [MethodChannelReplayFileStore];
/// it is not a platform adapter of its own.
class MemoryReplayFileStore implements ReplayFileStore {
  /// Creates an empty in-process store.
  MemoryReplayFileStore();

  final Map<String, String> _files = <String, String>{};

  @override
  Future<void> writeFile(String key, String contents) async {
    validateReplayFileKey(key);
    _files[key] = contents;
  }

  @override
  Future<String?> readFile(String key) async {
    validateReplayFileKey(key);
    return _files[key];
  }

  @override
  Future<bool> deleteFile(String key) async {
    validateReplayFileKey(key);
    return _files.remove(key) != null;
  }

  @override
  Future<List<String>> listKeys() async {
    return _files.keys.toList(growable: false)..sort();
  }
}

/// Platform-channel [ReplayFileStore] over the existing
/// `hareeg_table/local_storage` channel.
///
/// The channel is shared with [MethodChannelKeyValueStore] on purpose: the app
/// stores its own data by hand rather than taking on a database or file-path
/// package, and a second channel would be a second thing to register in
/// `MainActivity.kt` and `AppDelegate.swift` for no gain.
///
/// Android stores payloads under the no-backup files directory and iOS under
/// an Application Support directory flagged as excluded from backup, so replay
/// data never travels through a cloud restore.
class MethodChannelReplayFileStore implements ReplayFileStore {
  /// Creates platform-channel replay-file storage.
  MethodChannelReplayFileStore({
    MethodChannel channel = const MethodChannel('hareeg_table/local_storage'),
  }) : _channel = channel;

  final MethodChannel _channel;
  MemoryReplayFileStore? _fallback;
  bool _loggedFallback = false;

  /// Mirrors [MethodChannelKeyValueStore]: Android and iOS register the
  /// channel, so a missing plugin there is a real defect and must surface.
  /// Desktop and web have no handler by design and degrade instead.
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

  /// Returns the degraded in-process store, or throws when this platform is
  /// supposed to have a real one.
  ///
  /// The instance is created once and reused, so a write on the degraded path
  /// is readable by the next call.
  ReplayFileStore _degradedStore(String? key) {
    if (!_canUseInMemoryFallback) {
      throw ReplayFileStoreException(
        code: ReplayFileStoreErrorCode.unavailable,
        message:
            'Platform channel "hareeg_table/local_storage" is not available, '
            'but this platform is expected to register it.',
        key: key,
      );
    }

    if (!_loggedFallback) {
      _loggedFallback = true;
      debugPrint(
        '[hareeg_table] Platform channel "hareeg_table/local_storage" is not '
        'available on this platform. Falling back to in-memory replay file '
        'storage; saved replays will not survive app restart. '
        'Android and iOS register this channel at startup.',
      );
    }

    return _fallback ??= MemoryReplayFileStore();
  }

  ReplayFileStoreException _mapPlatformException(
    PlatformException error,
    String? key,
  ) {
    if (error.code == ReplayFileStoreErrorCode.invalidKey) {
      return ReplayFileStoreException(
        code: ReplayFileStoreErrorCode.invalidKey,
        message:
            error.message ??
            'The platform rejected this key as an invalid replay key.',
        key: key,
        cause: error,
      );
    }

    // Everything else — including the channel's `invalid_arguments` and any
    // code this build has not seen — is an I/O failure to the caller. The
    // original code and message stay in the message so a platform-specific
    // failure is still diagnosable.
    final detail = error.message == null ? '' : ': ${error.message}';
    return ReplayFileStoreException(
      code: ReplayFileStoreErrorCode.ioError,
      message:
          'Replay file operation failed '
          '(platform code "${error.code}")$detail',
      key: key,
      cause: error,
    );
  }

  @override
  Future<void> writeFile(String key, String contents) async {
    validateReplayFileKey(key);
    try {
      await _channel.invokeMethod<void>('writeFile', <String, Object?>{
        'key': key,
        'value': contents,
      });
    } on MissingPluginException {
      await _degradedStore(key).writeFile(key, contents);
    } on PlatformException catch (error) {
      throw _mapPlatformException(error, key);
    }
  }

  @override
  Future<String?> readFile(String key) async {
    validateReplayFileKey(key);
    try {
      return await _channel.invokeMethod<String>('readFile', <String, Object?>{
        'key': key,
      });
    } on MissingPluginException {
      return _degradedStore(key).readFile(key);
    } on PlatformException catch (error) {
      throw _mapPlatformException(error, key);
    }
  }

  @override
  Future<bool> deleteFile(String key) async {
    validateReplayFileKey(key);
    try {
      final removed = await _channel.invokeMethod<bool>(
        'deleteFile',
        <String, Object?>{'key': key},
      );
      return removed ?? false;
    } on MissingPluginException {
      return _degradedStore(key).deleteFile(key);
    } on PlatformException catch (error) {
      throw _mapPlatformException(error, key);
    }
  }

  @override
  Future<List<String>> listKeys() async {
    try {
      final keys = await _channel.invokeListMethod<String>('listFiles');
      if (keys == null) {
        return const <String>[];
      }

      // The native handlers already drop entries they cannot map back to a
      // valid logical key. Filtering again here keeps the "listKeys output is
      // always accepted by the keyed operations" guarantee true even if a
      // handler regresses.
      return keys.where(isValidReplayFileKey).toList(growable: false)..sort();
    } on MissingPluginException {
      return _degradedStore(null).listKeys();
    } on PlatformException catch (error) {
      throw _mapPlatformException(error, null);
    }
  }
}

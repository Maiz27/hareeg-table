import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/data/persistence/replay_file_store.dart';
import 'package:hareeg_table/data/persistence/replay_file_store_browser.dart';

import 'replay_file_store_conformance.dart';

const MethodChannel _channel = MethodChannel('hareeg_table/local_storage');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  runReplayFileStoreConformanceTests(
    name: 'MemoryReplayFileStore',
    setUpStore: () async => MemoryReplayFileStore(),
  );

  late _FakeNativeReplayBackend backend;

  runReplayFileStoreConformanceTests(
    name: 'MethodChannelReplayFileStore over a fake native backend',
    setUpStore: () async {
      backend = _FakeNativeReplayBackend()..install();
      return MethodChannelReplayFileStore(channel: _channel);
    },
    tearDownStore: () async => backend.uninstall(),
    breakBackend: () => backend.broken = true,
    repairBackend: () => backend.broken = false,
  );

  late _FakeBrowserStorage browserStorage;

  runReplayFileStoreConformanceTests(
    name: 'WebReplayFileStore over a fake browser storage',
    setUpStore: () async {
      browserStorage = _FakeBrowserStorage();
      return WebReplayFileStore(storage: browserStorage);
    },
    breakBackend: () => browserStorage.broken = true,
    repairBackend: () => browserStorage.broken = false,
  );

  group('WebReplayFileStore entry naming', () {
    late _FakeBrowserStorage storage;
    late WebReplayFileStore store;

    setUp(() {
      storage = _FakeBrowserStorage();
      store = WebReplayFileStore(storage: storage);
    });

    test('writes under the replay prefix', () async {
      await store.writeFile('match-1', 'payload');

      expect(
        storage.entries,
        containsPair('${WebReplayFileStore.entryPrefix}match-1', 'payload'),
      );
      expect(storage.entries.containsKey('match-1'), isFalse);
    });

    test('listKeys ignores key/value entries sharing the origin', () async {
      storage.entries['active_match.v1'] = '{"version":1}';
      storage.entries['preferences.v1'] = '{"version":1}';
      storage.entries['learning_progress.v1'] = '{"version":1}';

      await store.writeFile('match-1', 'payload');

      expect(await store.listKeys(), <String>['match-1']);
    });

    test('listKeys drops prefixed entries whose suffix is not a valid key', () async {
      storage.entries['${WebReplayFileStore.entryPrefix}bad key'] = 'edited';
      storage.entries['${WebReplayFileStore.entryPrefix}../escape'] = 'edited';
      storage.entries['${WebReplayFileStore.entryPrefix}.hidden'] = 'edited';

      await store.writeFile('match-1', 'payload');

      expect(await store.listKeys(), <String>['match-1']);
    });

    test('delete removes the underlying entry', () async {
      await store.writeFile('match-1', 'payload');

      expect(await store.deleteFile('match-1'), isTrue);
      expect(storage.entries, isEmpty);
    });

    test('a quota failure throws instead of dropping the write silently', () async {
      storage.broken = true;

      await expectLater(
        store.writeFile('match-1', 'payload'),
        throwsA(
          isA<ReplayFileStoreException>()
              .having(
                (error) => error.code,
                'code',
                ReplayFileStoreErrorCode.ioError,
              )
              .having((error) => error.key, 'key', 'match-1')
              .having((error) => error.cause, 'cause', isNotNull),
        ),
      );
      expect(storage.entries, isEmpty);
    });
  });

  group('replay file key rule', () {
    test('accepts logical keys and rejects unsafe ones', () {
      expect(isValidReplayFileKey('match-1'), isTrue);
      expect(isValidReplayFileKey('9'), isTrue);
      expect(isValidReplayFileKey('a' * 120), isTrue);

      for (final key in <String>[
        ...invalidReplayFileKeys,
        overLongReplayFileKey,
      ]) {
        expect(
          isValidReplayFileKey(key),
          isFalse,
          reason: 'expected "$key" to be rejected',
        );
      }
    });

    test('validate throws with the offending key attached', () {
      expect(
        () => validateReplayFileKey('../escape'),
        throwsA(
          isA<ReplayFileStoreException>()
              .having(
                (error) => error.code,
                'code',
                ReplayFileStoreErrorCode.invalidKey,
              )
              .having((error) => error.key, 'key', '../escape'),
        ),
      );
    });

    test('validate accepts a legal key without throwing', () {
      expect(() => validateReplayFileKey('match-1'), returnsNormally);
    });
  });

  group('MethodChannelReplayFileStore channel shape', () {
    late _FakeNativeReplayBackend backend;
    late MethodChannelReplayFileStore store;

    setUp(() {
      backend = _FakeNativeReplayBackend()..install();
      store = MethodChannelReplayFileStore(channel: _channel);
    });

    tearDown(() => backend.uninstall());

    test('writeFile sends key and value', () async {
      await store.writeFile('match-1', 'payload');

      expect(backend.calls.single.method, 'writeFile');
      expect(backend.calls.single.arguments, <String, Object?>{
        'key': 'match-1',
        'value': 'payload',
      });
    });

    test('readFile sends only the key', () async {
      await store.readFile('match-1');

      expect(backend.calls.single.method, 'readFile');
      expect(backend.calls.single.arguments, <String, Object?>{
        'key': 'match-1',
      });
    });

    test('deleteFile sends only the key', () async {
      await store.deleteFile('match-1');

      expect(backend.calls.single.method, 'deleteFile');
      expect(backend.calls.single.arguments, <String, Object?>{
        'key': 'match-1',
      });
    });

    test('listKeys sends listFiles with no arguments', () async {
      await store.listKeys();

      expect(backend.calls.single.method, 'listFiles');
      expect(backend.calls.single.arguments, isNull);
    });

    test('an invalid key never reaches the channel', () async {
      for (final key in <String>[
        ...invalidReplayFileKeys,
        overLongReplayFileKey,
      ]) {
        await expectLater(
          store.writeFile(key, 'payload'),
          throwsA(isA<ReplayFileStoreException>()),
        );
        await expectLater(
          store.readFile(key),
          throwsA(isA<ReplayFileStoreException>()),
        );
        await expectLater(
          store.deleteFile(key),
          throwsA(isA<ReplayFileStoreException>()),
        );
      }

      expect(backend.calls, isEmpty);
    });

    test('deleteFile treats a null platform answer as "did not exist"', () async {
      backend.uninstall();
      _installRawHandler((call) async => null);

      expect(await store.deleteFile('match-1'), isFalse);
    });

    test('listKeys treats a null platform answer as empty', () async {
      backend.uninstall();
      _installRawHandler((call) async => null);

      expect(await store.listKeys(), isEmpty);
    });

    test('listKeys drops platform entries that are not valid keys', () async {
      backend.uninstall();
      _installRawHandler(
        (call) async => <String>['match-b', 'bad key', '../escape', 'match-a'],
      );

      expect(await store.listKeys(), <String>['match-a', 'match-b']);
    });
  });

  group('MethodChannelReplayFileStore listing rule', () {
    late _FakeNativeReplayBackend backend;
    late MethodChannelReplayFileStore store;

    setUp(() {
      backend = _FakeNativeReplayBackend()..install();
      store = MethodChannelReplayFileStore(channel: _channel);
    });

    tearDown(() => backend.uninstall());

    test('skips all four foreign-entry classes but keeps valid replays', () async {
      await store.writeFile('probe-alpha', 'alpha');
      await store.writeFile('probe-beta', 'beta');

      // The same four classes the on-device adb injection covers.
      backend.entries['looks-like-replay.json'] = '';
      backend.directoryEntries.add('looks-like-replay.json');
      backend.entries['probe-gamma.json.tmp'] = 'staging leftovers';
      backend.entries['notes.txt'] = 'not a replay';
      backend.entries['bad key.json'] = 'invalid logical key';

      expect(await store.listKeys(), <String>['probe-alpha', 'probe-beta']);
    });

    test('a directory occupying a valid key reads as absent', () async {
      backend.entries['match-1.json'] = '';
      backend.directoryEntries.add('match-1.json');

      expect(await store.readFile('match-1'), isNull);
    });

    test('a directory occupying a valid key is reported absent, not deleted', () async {
      backend.entries['match-1.json'] = '';
      backend.directoryEntries.add('match-1.json');

      expect(await store.deleteFile('match-1'), isFalse);
      // The directory is still there: delete must never recursively remove an
      // entry that is not a replay payload.
      expect(backend.entries.containsKey('match-1.json'), isTrue);
    });

    test('a path-inspection failure on read is io_error, not a null read', () async {
      await store.writeFile('match-1', 'payload');
      backend.statMetadataBroken = true;

      // "Cannot inspect this path" must never be reported as "nothing is
      // stored here". A caller self-healing a missing replay would otherwise
      // discard a payload that was only momentarily unreadable.
      await expectLater(
        store.readFile('match-1'),
        throwsA(
          isA<ReplayFileStoreException>()
              .having(
                (error) => error.code,
                'code',
                ReplayFileStoreErrorCode.ioError,
              )
              .having((error) => error.key, 'key', 'match-1'),
        ),
      );
    });

    test('a path-inspection failure on delete is io_error, not "did not exist"', () async {
      await store.writeFile('match-1', 'payload');
      backend.statMetadataBroken = true;

      await expectLater(
        store.deleteFile('match-1'),
        throwsA(
          isA<ReplayFileStoreException>()
              .having(
                (error) => error.code,
                'code',
                ReplayFileStoreErrorCode.ioError,
              )
              .having((error) => error.key, 'key', 'match-1'),
        ),
      );

      // The payload is untouched: a failed inspection must not have deleted it.
      backend.statMetadataBroken = false;
      expect(await store.readFile('match-1'), 'payload');
    });

    test('a per-entry metadata failure surfaces as io_error, not a short list', () async {
      await store.writeFile('match-a', 'a');
      await store.writeFile('match-b', 'b');
      backend.listingMetadataBroken = true;

      await expectLater(
        store.listKeys(),
        throwsA(
          isA<ReplayFileStoreException>()
              .having(
                (error) => error.code,
                'code',
                ReplayFileStoreErrorCode.ioError,
              )
              .having((error) => error.key, 'key', isNull),
        ),
      );
    });

    test('a path-resolution failure on a valid key is io_error, not invalid_key', () async {
      backend.uninstall();
      _installRawHandler(
        (call) async => throw PlatformException(
          code: 'io_error',
          message: 'Could not canonicalize the replay path.',
        ),
      );

      // A valid key whose path resolution fails is a retryable backend
      // problem. Reporting invalid_key would tell the caller its match id was
      // malformed and send it down a permanent-failure path.
      for (final operation in <Future<Object?> Function()>[
        () => store.readFile('match-1'),
        () => store.writeFile('match-1', 'payload'),
        () => store.deleteFile('match-1'),
      ]) {
        await expectLater(
          operation(),
          throwsA(
            isA<ReplayFileStoreException>().having(
              (error) => error.code,
              'code',
              ReplayFileStoreErrorCode.ioError,
            ),
          ),
        );
      }
    });

    test('a skipped entry never becomes a readable key', () async {
      backend.entries['bad key.json'] = 'invalid logical key';

      expect(await store.listKeys(), isEmpty);
      await expectLater(
        store.readFile('bad key'),
        throwsA(
          isA<ReplayFileStoreException>().having(
            (error) => error.code,
            'code',
            ReplayFileStoreErrorCode.invalidKey,
          ),
        ),
      );
    });
  });

  group('MethodChannelReplayFileStore platform error mapping', () {
    late MethodChannelReplayFileStore store;

    setUp(() {
      store = MethodChannelReplayFileStore(channel: _channel);
    });

    tearDown(_clearHandler);

    test('invalid_key maps to invalid_key and keeps the cause', () async {
      _installRawHandler(
        (call) async => throw PlatformException(
          code: 'invalid_key',
          message: 'rejected natively',
        ),
      );

      await expectLater(
        store.readFile('match-1'),
        throwsA(
          isA<ReplayFileStoreException>()
              .having(
                (error) => error.code,
                'code',
                ReplayFileStoreErrorCode.invalidKey,
              )
              .having((error) => error.message, 'message', 'rejected natively')
              .having((error) => error.key, 'key', 'match-1')
              .having((error) => error.cause, 'cause', isA<PlatformException>()),
        ),
      );
    });

    test('io_error maps to io_error and preserves code and message', () async {
      _installRawHandler(
        (call) async =>
            throw PlatformException(code: 'io_error', message: 'disk full'),
      );

      await expectLater(
        store.writeFile('match-1', 'payload'),
        throwsA(
          isA<ReplayFileStoreException>()
              .having(
                (error) => error.code,
                'code',
                ReplayFileStoreErrorCode.ioError,
              )
              .having((error) => error.message, 'message', contains('io_error'))
              .having((error) => error.message, 'message', contains('disk full'))
              .having((error) => error.cause, 'cause', isA<PlatformException>()),
        ),
      );
    });

    test('invalid_arguments maps to io_error, preserving the platform code', () async {
      _installRawHandler(
        (call) async => throw PlatformException(
          code: 'invalid_arguments',
          message: 'A string value is required.',
        ),
      );

      await expectLater(
        store.writeFile('match-1', 'payload'),
        throwsA(
          isA<ReplayFileStoreException>()
              .having(
                (error) => error.code,
                'code',
                ReplayFileStoreErrorCode.ioError,
              )
              .having(
                (error) => error.message,
                'message',
                contains('invalid_arguments'),
              ),
        ),
      );
    });

    test('an unrecognised platform code maps to io_error, code preserved', () async {
      _installRawHandler(
        (call) async => throw PlatformException(code: 'meteor_strike'),
      );

      await expectLater(
        store.listKeys(),
        throwsA(
          isA<ReplayFileStoreException>()
              .having(
                (error) => error.code,
                'code',
                ReplayFileStoreErrorCode.ioError,
              )
              .having(
                (error) => error.message,
                'message',
                contains('meteor_strike'),
              )
              .having((error) => error.key, 'key', isNull),
        ),
      );
    });

    test('a raw PlatformException never escapes the store', () async {
      _installRawHandler(
        (call) async => throw PlatformException(code: 'io_error'),
      );

      for (final operation in <Future<Object?> Function()>[
        () => store.writeFile('match-1', 'payload'),
        () => store.readFile('match-1'),
        () => store.deleteFile('match-1'),
        () => store.listKeys(),
      ]) {
        await expectLater(
          operation(),
          throwsA(
            allOf(
              isA<ReplayFileStoreException>(),
              isNot(isA<PlatformException>()),
            ),
          ),
        );
      }
    });
  });

  group('MethodChannelReplayFileStore missing-plugin policy', () {
    late MethodChannelReplayFileStore store;

    setUp(() {
      _clearHandler();
      store = MethodChannelReplayFileStore(channel: _channel);
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    for (final platform in <TargetPlatform>[
      TargetPlatform.android,
      TargetPlatform.iOS,
    ]) {
      test('$platform surfaces unavailable instead of degrading', () async {
        debugDefaultTargetPlatformOverride = platform;

        final unavailable = isA<ReplayFileStoreException>().having(
          (error) => error.code,
          'code',
          ReplayFileStoreErrorCode.unavailable,
        );

        await expectLater(
          store.writeFile('match-1', 'payload'),
          throwsA(unavailable),
        );
        await expectLater(store.readFile('match-1'), throwsA(unavailable));
        await expectLater(store.deleteFile('match-1'), throwsA(unavailable));
        await expectLater(store.listKeys(), throwsA(unavailable));
      });
    }

    for (final platform in <TargetPlatform>[
      TargetPlatform.linux,
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.fuchsia,
    ]) {
      test('$platform degrades to a single in-memory store', () async {
        debugDefaultTargetPlatformOverride = platform;

        await store.writeFile('match-1', 'payload');

        expect(await store.readFile('match-1'), 'payload');
        expect(await store.listKeys(), <String>['match-1']);
        expect(await store.deleteFile('match-1'), isTrue);
        expect(await store.readFile('match-1'), isNull);
      });
    }

    test('the degraded store still enforces the key rule', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;

      await expectLater(
        store.writeFile('../escape', 'payload'),
        throwsA(
          isA<ReplayFileStoreException>().having(
            (error) => error.code,
            'code',
            ReplayFileStoreErrorCode.invalidKey,
          ),
        ),
      );
    });
  });
}

void _installRawHandler(Future<Object?> Function(MethodCall call) handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, handler);
}

void _clearHandler() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, null);
}

/// Fake standing in for `MainActivity.kt` / `AppDelegate.swift`.
///
/// It reproduces the native semantics the Dart store depends on — independent
/// key re-validation, path containment, `<key>.json` naming, the listing rule
/// that skips directories/staging files/foreign extensions/invalid names,
/// `null` for a missing read, `false` for a missing delete, and an overwrite
/// that cannot destroy the committed payload when it fails.
class _FakeNativeReplayBackend {
  static const String _extension = '.json';

  /// Entry name (`match-1.json`) to payload, mirroring one directory.
  final Map<String, String> entries = <String, String>{};

  /// Entry names that stand for directories rather than regular files.
  final Set<String> directoryEntries = <String>{};

  /// Every call the store made, in order.
  final List<MethodCall> calls = <MethodCall>[];

  /// When true, every backend operation fails the way a full disk would.
  bool broken = false;

  /// When true, listing fails the way a per-entry metadata lookup would.
  ///
  /// Modelled separately from [broken] because the tempting native
  /// implementation swallows exactly this failure and returns a short list
  /// that looks complete.
  bool listingMetadataBroken = false;

  /// When true, inspecting a path fails the way a permissions or metadata
  /// error would.
  ///
  /// Modelled separately because the tempting native implementation asks a
  /// boolean "does this exist" API, which reports an uninspectable path
  /// identically to an absent one — turning a failure into a silent `null`
  /// read or a `false` delete.
  bool statMetadataBroken = false;

  void install() {
    _installRawHandler(_handle);
  }

  void uninstall() {
    _clearHandler();
  }

  Future<Object?> _handle(MethodCall call) async {
    calls.add(call);
    final arguments = call.arguments as Map<Object?, Object?>?;

    if (call.method == 'listFiles') {
      _failIfBroken();
      if (listingMetadataBroken) {
        throw PlatformException(
          code: 'io_error',
          message: 'Simulated per-entry metadata failure.',
        );
      }
      return entries.keys
          .where((name) => !directoryEntries.contains(name))
          .where((name) => name.endsWith(_extension))
          .map((name) => name.substring(0, name.length - _extension.length))
          .where(isValidReplayFileKey)
          .toList(growable: false)
        ..sort();
    }

    final key = arguments?['key'] as String?;
    if (key == null) {
      throw PlatformException(
        code: 'invalid_arguments',
        message: 'A storage key is required.',
      );
    }

    final name = _entryName(key);

    switch (call.method) {
      case 'writeFile':
        final value = arguments?['value'] as String?;
        if (value == null) {
          throw PlatformException(
            code: 'invalid_arguments',
            message: 'A string value is required.',
          );
        }
        // Staging happens before the committed payload is touched, so a
        // failure here leaves the previous payload intact — the same property
        // `renameTo` and atomic `Data.write` give on the real platforms.
        _failIfBroken();
        entries[name] = value;
        return null;
      case 'readFile':
        _failIfBroken();
        _failIfStatBroken();
        // A directory occupying the name is not a payload: absent, not an
        // error. Both native handlers check for a regular file first.
        return directoryEntries.contains(name) ? null : entries[name];
      case 'deleteFile':
        _failIfBroken();
        _failIfStatBroken();
        // Never remove a directory collision. Reporting "did not exist" and
        // leaving it alone is the only safe answer — the alternative is a
        // recursive delete of something that was never a replay.
        if (directoryEntries.contains(name)) {
          return false;
        }
        return entries.remove(name) != null;
      default:
        throw MissingPluginException('No implementation for ${call.method}');
    }
  }

  String _entryName(String key) {
    if (!isValidReplayFileKey(key)) {
      throw PlatformException(
        code: 'invalid_key',
        message: 'Rejected "$key" as an invalid replay key.',
      );
    }

    final name = '$key$_extension';
    if (name.contains('/') || name.contains(r'\') || name.contains('..')) {
      throw PlatformException(
        code: 'invalid_key',
        message: 'Rejected "$key" as escaping the replay directory.',
      );
    }

    return name;
  }

  void _failIfBroken() {
    if (broken) {
      throw PlatformException(
        code: 'io_error',
        message: 'Simulated backend failure.',
      );
    }
  }

  void _failIfStatBroken() {
    if (statMetadataBroken) {
      throw PlatformException(
        code: 'io_error',
        message: 'Simulated path-inspection failure.',
      );
    }
  }
}

/// [ReplayBrowserStorage] that can be made to fail the way a browser does when
/// storage is disabled or the quota is exhausted.
///
/// It throws *before* mutating, matching a real `setItem` quota rejection, so
/// "a failed overwrite leaves the committed payload readable" is tested against
/// realistic behaviour rather than a convenient one.
class _FakeBrowserStorage implements ReplayBrowserStorage {
  final Map<String, String> entries = <String, String>{};

  bool broken = false;

  void _failIfBroken() {
    if (broken) {
      throw StateError('QuotaExceededError');
    }
  }

  @override
  String? read(String key) {
    _failIfBroken();
    return entries[key];
  }

  @override
  void write(String key, String value) {
    _failIfBroken();
    entries[key] = value;
  }

  @override
  void delete(String key) {
    _failIfBroken();
    entries.remove(key);
  }

  @override
  List<String> keys() {
    _failIfBroken();
    return entries.keys.toList(growable: false);
  }
}

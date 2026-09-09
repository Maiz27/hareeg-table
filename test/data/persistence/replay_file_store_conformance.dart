import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/data/persistence/replay_file_store.dart';

/// Keys every adapter must reject from every keyed operation.
///
/// The list is the path-safety argument in one place: traversal, separators of
/// both flavours, absolute and drive-qualified paths, percent-escaped dots,
/// whitespace, control characters, dotfiles, leading punctuation, non-ASCII,
/// and an over-length key.
const List<String> invalidReplayFileKeys = <String>[
  '',
  '.',
  '..',
  '../escape',
  'a/b',
  r'a\b',
  '/abs',
  r'C:\x',
  'a:b',
  'a%2e%2e',
  'a b',
  'a\u0000b',
  '.hidden',
  '-lead',
  '_lead',
  'ملف',
];

/// A key one character past the 120-character limit.
final String overLongReplayFileKey = 'a' * 121;

/// Payloads a round trip must preserve byte for byte.
const Map<String, String> replayFilePayloads = <String, String>{
  'empty': '',
  'single character': 'x',
  'unix newlines': 'line one\nline two\nline three',
  'windows newlines': 'line one\r\nline two\r\n',
  'json punctuation': r'{"a":"b\\c","d":"\"quoted\""}',
  'arabic': 'حريقة على الطاولة — جولة أولى',
  'emoji': 'winner 🏆 fifty 🔥 joker 🃏',
};

/// Runs the behaviour every [ReplayFileStore] must exhibit, whatever backs it.
///
/// [setUpStore] must return a store that starts empty. [breakBackend] and
/// [repairBackend] are supplied only by bindings that own a failure seam —
/// when they are absent the failure-propagation group is skipped rather than
/// faked, because a binding with no seam cannot honestly assert it.
void runReplayFileStoreConformanceTests({
  required String name,
  required Future<ReplayFileStore> Function() setUpStore,
  Future<void> Function()? tearDownStore,
  void Function()? breakBackend,
  void Function()? repairBackend,
}) {
  group('$name conformance', () {
    late ReplayFileStore store;

    setUp(() async {
      store = await setUpStore();
    });

    tearDown(() async {
      repairBackend?.call();
      await tearDownStore?.call();
    });

    group('round trip', () {
      for (final entry in replayFilePayloads.entries) {
        test('preserves a ${entry.key} payload exactly', () async {
          await store.writeFile('match-1', entry.value);

          expect(await store.readFile('match-1'), entry.value);
        });
      }

      test('preserves a 200 KB payload exactly', () async {
        final payload = '0123456789' * 20000;

        await store.writeFile('match-1', payload);

        final restored = await store.readFile('match-1');
        expect(restored, hasLength(200000));
        expect(restored, payload);
      });
    });

    test('reading a never-written key returns null', () async {
      expect(await store.readFile('match-absent'), isNull);
    });

    test('reading a deleted key returns null', () async {
      await store.writeFile('match-1', 'payload');
      await store.deleteFile('match-1');

      expect(await store.readFile('match-1'), isNull);
    });

    test('overwriting replaces the payload with no stale tail', () async {
      await store.writeFile('match-1', 'a very long original payload');
      await store.writeFile('match-1', 'short');

      expect(await store.readFile('match-1'), 'short');
    });

    test('delete reports whether the payload existed', () async {
      await store.writeFile('match-1', 'payload');

      expect(await store.deleteFile('match-1'), isTrue);
      expect(await store.deleteFile('match-1'), isFalse);
      expect(await store.deleteFile('match-never-written'), isFalse);
    });

    test('listKeys is empty for a fresh store', () async {
      expect(await store.listKeys(), isEmpty);
    });

    test('listKeys returns written keys ascending, without duplicates', () async {
      await store.writeFile('match-c', 'c');
      await store.writeFile('match-a', 'a');
      await store.writeFile('match-b', 'b');
      await store.writeFile('match-a', 'a again');

      expect(await store.listKeys(), <String>['match-a', 'match-b', 'match-c']);
    });

    test('listKeys drops deleted keys', () async {
      await store.writeFile('match-a', 'a');
      await store.writeFile('match-b', 'b');
      await store.deleteFile('match-a');

      expect(await store.listKeys(), <String>['match-b']);
    });

    test('listKeys returns bare logical keys, not paths or file names', () async {
      await store.writeFile('match-1', 'payload');

      final keys = await store.listKeys();
      expect(keys, <String>['match-1']);
      expect(keys.single, isNot(contains('/')));
      expect(keys.single, isNot(contains(r'\')));
      expect(keys.single, isNot(endsWith('.json')));
    });

    test('every listed key is accepted by the keyed operations', () async {
      await store.writeFile('match-a', 'a');
      await store.writeFile('match-b', 'b');

      for (final key in await store.listKeys()) {
        expect(await store.readFile(key), isNotNull);
      }
    });

    test('keys are independent', () async {
      await store.writeFile('match-a', 'a');
      await store.writeFile('match-b', 'b');

      await store.deleteFile('match-a');

      expect(await store.readFile('match-b'), 'b');
      expect(await store.listKeys(), <String>['match-b']);
    });

    group('key validation', () {
      for (final key in <String>[
        ...invalidReplayFileKeys,
        overLongReplayFileKey,
      ]) {
        test('rejects ${_describeKey(key)} from every keyed operation', () async {
          await expectLater(
            store.writeFile(key, 'payload'),
            throwsA(_invalidKey(key)),
          );
          await expectLater(store.readFile(key), throwsA(_invalidKey(key)));
          await expectLater(store.deleteFile(key), throwsA(_invalidKey(key)));
        });
      }

      test('accepts the boundary-legal keys', () async {
        final maxLengthKey = 'a' * 120;

        await store.writeFile('9', 'digit start');
        await store.writeFile('a-b_c', 'punctuation inside');
        await store.writeFile(maxLengthKey, 'max length');

        expect(await store.readFile('9'), 'digit start');
        expect(await store.readFile('a-b_c'), 'punctuation inside');
        expect(await store.readFile(maxLengthKey), 'max length');
      });
    });

    if (breakBackend != null && repairBackend != null) {
      group('failure propagation', () {
        test('write failures throw io_error and carry the key', () async {
          breakBackend();

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
        });

        test('read failures throw rather than collapsing to null', () async {
          await store.writeFile('match-1', 'payload');
          breakBackend();

          await expectLater(store.readFile('match-1'), throwsA(_ioError()));
        });

        test('delete failures throw io_error', () async {
          await store.writeFile('match-1', 'payload');
          breakBackend();

          await expectLater(store.deleteFile('match-1'), throwsA(_ioError()));
        });

        test('listKeys failures throw instead of returning a partial list', () async {
          await store.writeFile('match-1', 'payload');
          breakBackend();

          await expectLater(store.listKeys(), throwsA(_ioError()));
        });

        test('a failed overwrite leaves the committed payload readable', () async {
          await store.writeFile('match-1', 'committed payload');
          breakBackend();

          await expectLater(
            store.writeFile('match-1', 'replacement payload'),
            throwsA(_ioError()),
          );

          repairBackend();
          expect(await store.readFile('match-1'), 'committed payload');
          expect(await store.listKeys(), <String>['match-1']);
        });
      });
    }
  });
}

Matcher _invalidKey(String key) {
  return isA<ReplayFileStoreException>()
      .having(
        (error) => error.code,
        'code',
        ReplayFileStoreErrorCode.invalidKey,
      )
      .having((error) => error.key, 'key', key);
}

Matcher _ioError() {
  return isA<ReplayFileStoreException>().having(
    (error) => error.code,
    'code',
    ReplayFileStoreErrorCode.ioError,
  );
}

String _describeKey(String key) {
  if (key.isEmpty) {
    return 'an empty key';
  }
  if (key.length > 120) {
    return 'a ${key.length}-character key';
  }
  return '"${key.replaceAll('\u0000', r'\u0000')}"';
}

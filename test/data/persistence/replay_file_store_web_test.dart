@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/data/persistence/replay_file_store.dart';
import 'package:hareeg_table/data/persistence/replay_file_store_browser.dart';
import 'package:hareeg_table/data/persistence/replay_file_store_web.dart';

import 'replay_file_store_conformance.dart';

/// The one binding that cannot run anywhere but a browser: [WebReplayFileStore]
/// over the real `window.localStorage`.
///
/// Everything above the [ReplayBrowserStorage] seam — prefixing, listing, key
/// re-validation, failure propagation — is covered on the VM in
/// `replay_file_store_test.dart` against a fake storage. What is left here is
/// the proof that [WindowLocalStorage] actually talks to the browser, and that
/// a payload survives in a real origin.
void main() {
  runReplayFileStoreConformanceTests(
    name: 'WebReplayFileStore over real localStorage',
    setUpStore: () async {
      _clearReplayEntries();
      return WebReplayFileStore(storage: const WindowLocalStorage());
    },
    tearDownStore: () async => _clearReplayEntries(),
  );

  group('WindowLocalStorage against the real browser', () {
    const storage = WindowLocalStorage();
    late ReplayFileStore store;

    setUp(() {
      _clearReplayEntries();
      store = WebReplayFileStore(storage: storage);
    });

    tearDown(_clearReplayEntries);

    test('a written payload lands in localStorage under the prefix', () async {
      await store.writeFile('match-1', 'payload');

      expect(storage.read('${WebReplayFileStore.entryPrefix}match-1'), 'payload');
      expect(storage.read('match-1'), isNull);
    });

    test('listKeys ignores real key/value entries in the same origin', () async {
      storage.write('active_match.v1', '{"version":1}');
      storage.write('preferences.v1', '{"version":1}');
      storage.write('learning_progress.v1', '{"version":1}');
      addTearDown(() {
        storage.delete('active_match.v1');
        storage.delete('preferences.v1');
        storage.delete('learning_progress.v1');
      });

      await store.writeFile('match-1', 'payload');

      expect(await store.listKeys(), <String>['match-1']);
    });

    test('listKeys drops a hand-edited entry with an invalid suffix', () async {
      storage.write('${WebReplayFileStore.entryPrefix}bad key', 'edited');
      addTearDown(
        () => storage.delete('${WebReplayFileStore.entryPrefix}bad key'),
      );

      await store.writeFile('match-1', 'payload');

      expect(await store.listKeys(), <String>['match-1']);
    });

    test('a payload survives a fresh store over the same origin', () async {
      await store.writeFile('match-1', 'payload');

      final reopened = WebReplayFileStore(storage: const WindowLocalStorage());
      expect(await reopened.readFile('match-1'), 'payload');
    });

    test('delete removes the real entry', () async {
      await store.writeFile('match-1', 'payload');

      expect(await store.deleteFile('match-1'), isTrue);
      expect(storage.read('${WebReplayFileStore.entryPrefix}match-1'), isNull);
    });
  });
}

void _clearReplayEntries() {
  const storage = WindowLocalStorage();
  for (final name in storage.keys()) {
    if (name.startsWith(WebReplayFileStore.entryPrefix)) {
      storage.delete(name);
    }
  }
}

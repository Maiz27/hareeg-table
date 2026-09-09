@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;
import 'package:hareeg_table/data/persistence/key_value_store_web.dart';

void main() {
  test('browser adapter propagates read, quota and remove errors', () async {
    final storage = JSObject();
    JSString? read(JSString key) => throw StateError('blocked read');
    void write(JSString key, JSString value) =>
        throw StateError('quota exceeded');
    void remove(JSString key) => throw StateError('blocked remove');
    storage.setProperty('getItem'.toJS, read.toJS);
    storage.setProperty('setItem'.toJS, write.toJS);
    storage.setProperty('removeItem'.toJS, remove.toJS);
    final adapter = WebLocalStorageKeyValueStore(
      storage: storage as web.Storage,
    );
    await expectLater(adapter.loadString('active_match.v1'), throwsA(anything));
    await expectLater(
      adapter.saveString('match_history_index.v1', '{}'),
      throwsA(anything),
    );
    await expectLater(
      adapter.remove('match_archive_pending.v1'),
      throwsA(anything),
    );
  });

  test(
    'successful operations still distinguish an absent key from a stored value',
    () async {
      final storage = JSObject();
      final values = <String, String>{};
      JSString? read(JSString key) => values[key.toDart]?.toJS;
      void write(JSString key, JSString value) {
        values[key.toDart] = value.toDart;
      }

      void remove(JSString key) {
        values.remove(key.toDart);
      }

      storage.setProperty('getItem'.toJS, read.toJS);
      storage.setProperty('setItem'.toJS, write.toJS);
      storage.setProperty('removeItem'.toJS, remove.toJS);
      final adapter = WebLocalStorageKeyValueStore(
        storage: storage as web.Storage,
      );
      expect(await adapter.loadString('key'), isNull);
      await adapter.saveString('key', 'saved');
      expect(await adapter.loadString('key'), 'saved');
      await adapter.remove('key');
      expect(await adapter.loadString('key'), isNull);
    },
  );
}

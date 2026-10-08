import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/data/persistence/preferences_repository.dart';

import '../../support/test_fixtures.dart';

/// Crash/bug report consent (HT-56): opt-out, default on, but never acted on
/// before the first-run disclosure has been seen.
void main() {
  group('diagnostics consent preferences', () {
    test('default on, disclosure not yet seen, so not yet consented', () {
      final defaults = GamePreferences.defaults();

      expect(defaults.diagnosticsEnabled, isTrue);
      expect(defaults.diagnosticsNoticeSeen, isFalse);
      expect(defaults.diagnosticsConsented, isFalse);
    });

    test('consent needs both the disclosure and no opt-out', () {
      final seen = GamePreferences.defaults().copyWith(
        diagnosticsNoticeSeen: true,
      );

      expect(seen.diagnosticsConsented, isTrue);
      expect(
        seen.copyWith(diagnosticsEnabled: false).diagnosticsConsented,
        isFalse,
      );
    });

    test('an opt-out survives a save and reload', () async {
      final store = MemoryKeyValueStore();
      final repository = LocalPreferencesRepository(store: store);

      await repository.savePreferences(
        GamePreferences.defaults().copyWith(
          diagnosticsEnabled: false,
          diagnosticsNoticeSeen: true,
        ),
      );
      final restored = await repository.loadPreferences();

      expect(restored.diagnosticsEnabled, isFalse);
      expect(restored.diagnosticsNoticeSeen, isTrue);
      expect(restored.diagnosticsConsented, isFalse);
    });

    test('preferences saved before HT-56 load with the defaults', () async {
      final store = MemoryKeyValueStore();
      final legacy = GamePreferences.defaults().toJson()
        ..remove('diagnosticsEnabled')
        ..remove('diagnosticsNoticeSeen');
      await store.saveString('preferences.v1', jsonEncode(legacy));

      final restored = await LocalPreferencesRepository(
        store: store,
      ).loadPreferences();

      expect(restored.diagnosticsEnabled, isTrue);
      expect(restored.diagnosticsNoticeSeen, isFalse);
    });
  });
}

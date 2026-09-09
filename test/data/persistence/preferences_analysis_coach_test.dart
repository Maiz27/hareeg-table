import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/data/persistence/preferences_repository.dart';

import '../../support/test_fixtures.dart';

void main() {
  late MemoryKeyValueStore store;
  late LocalPreferencesRepository repository;

  setUp(() {
    store = MemoryKeyValueStore();
    repository = LocalPreferencesRepository(store: store);
  });

  test('a first run gets key moments with dead-card warnings on', () {
    final defaults = GamePreferences.defaults().analysisCoach;
    expect(defaults.verbosity, AnalysisVerbosity.keyMoments);
    expect(defaults.cardDeathWarnings, isTrue);
  });

  test('every combination survives a save and load', () async {
    for (final verbosity in AnalysisVerbosity.values) {
      for (final warnings in [true, false]) {
        final settings = AnalysisCoachSettings(
          verbosity: verbosity,
          cardDeathWarnings: warnings,
        );
        await repository.savePreferences(
          GamePreferences.defaults().copyWith(analysisCoach: settings),
        );

        final loaded = await repository.loadPreferences();
        expect(
          loaded.analysisCoach,
          settings,
          reason: '${verbosity.name}/$warnings',
        );
      }
    }
  });

  test('preferences saved before this feature existed still load', () async {
    // An older build's file simply has no analysisCoach key. Refusing to load
    // it would lose every other setting the player had chosen.
    final legacy = GamePreferences.defaults().toJson()
      ..remove('analysisCoach');
    await store.saveString('preferences.v1', jsonEncode(legacy));

    final loaded = await repository.loadPreferences();
    expect(loaded.analysisCoach, AnalysisCoachSettings.defaults());
  });

  test('a verbosity this build does not know falls back rather than throwing', () async {
    final json = GamePreferences.defaults().toJson();
    json['analysisCoach'] = {
      'verbosity': 'narrateEverythingTwice',
      'cardDeathWarnings': false,
    };
    await store.saveString('preferences.v1', jsonEncode(json));

    final loaded = await repository.loadPreferences();
    expect(loaded.analysisCoach.verbosity, AnalysisVerbosity.keyMoments);
    // The half it *could* read is still honoured.
    expect(loaded.analysisCoach.cardDeathWarnings, isFalse);
  });

  test('the settings live in the existing preferences record', () async {
    await repository.savePreferences(GamePreferences.defaults());

    // One key, not a second store to keep in sync with the first.
    final raw = await store.loadString('preferences.v1');
    expect(raw, isNotNull);
    expect(
      (jsonDecode(raw!) as Map<String, Object?>)['analysisCoach'],
      isA<Map<String, Object?>>(),
    );
  });

  test('changing the coach settings leaves every other preference alone', () {
    final before = GamePreferences.defaults();
    final after = before.copyWith(
      analysisCoach: before.analysisCoach.copyWith(
        verbosity: AnalysisVerbosity.clearMistakes,
      ),
    );

    expect(after.analysisCoach.verbosity, AnalysisVerbosity.clearMistakes);
    expect(after.language, before.language);
    expect(after.cardThemeId, before.cardThemeId);
    expect(after.coachingTipsEnabled, before.coachingTipsEnabled);
    expect(after.setup.tableStrictness, before.setup.tableStrictness);
  });
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/data/persistence/preferences_repository.dart';
import 'package:hareeg_table/ui/core/cards/card_theme_registry.dart';
import 'package:hareeg_table/ui/features/settings/models/settings_section.dart';
import 'package:hareeg_table/ui/features/settings/views/settings_screen.dart';
import 'package:hareeg_table/l10n/app_strings.dart';

void main() {
  late GamePreferences preferences;
  late List<GamePreferences> saves;

  setUp(() {
    preferences = GamePreferences.defaults();
    saves = [];
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => SettingsScreen(
            preferences: preferences,
            onUpdate: (value) {
              saves.add(value);
              setState(() => preferences = value);
            },
            cardThemes: CardThemeRegistry.all(),
            isMatchActive: false,
            initialSection: SettingsSection.review,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the review section is reachable and shows the current level', (
    tester,
  ) async {
    await pumpSettings(tester);
    final strings = AppStrings.english;

    expect(find.text(strings.settingsReviewTitle), findsOneWidget);
    expect(find.text(strings.replayCardDeathWarnings), findsWidgets);
    // Deep-linked open, like every other section.
    expect(find.text(strings.replayVerbosityKeyMoments), findsWidgets);
  });

  testWidgets('choosing a level saves exactly that change', (tester) async {
    await pumpSettings(tester);
    final strings = AppStrings.english;

    await tester.tap(find.text(strings.replayVerbosityClearMistakes).last);
    await tester.pumpAndSettle();

    expect(saves, hasLength(1));
    expect(saves.single.analysisCoach.verbosity, AnalysisVerbosity.clearMistakes);
    // Nothing else moved.
    expect(saves.single.analysisCoach.cardDeathWarnings, isTrue);
    expect(saves.single.coachingTipsEnabled, preferences.coachingTipsEnabled);
  });

  testWidgets('silencing dead-card warnings saves exactly that change', (
    tester,
  ) async {
    await pumpSettings(tester);

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    expect(saves, hasLength(1));
    expect(saves.single.analysisCoach.cardDeathWarnings, isFalse);
    expect(
      saves.single.analysisCoach.verbosity,
      AnalysisVerbosity.keyMoments,
      reason: 'the level must not move when the toggle does',
    );
  });

  test('the replay viewer has no way to write preferences at all', () {
    // The override is session-only, and that is structural rather than a rule
    // the screen has to remember: nothing in the replay feature can reach a
    // preferences repository, so there is no save to accidentally perform.
    final directory = Directory('lib/ui/features/replay');
    final files = directory
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList();
    expect(files, isNotEmpty);

    for (final file in files) {
      final source = file.readAsStringSync();
      for (final forbidden in const [
        'savePreferences',
        'PreferencesRepository',
        'MatchRepository',
        'archiveCompletedMatch',
        'saveActiveMatch',
        'MatchRecorder',
        'ReplayFileStore',
        'KeyValueStore',
      ]) {
        expect(
          source,
          isNot(contains(forbidden)),
          reason: '${file.path} must not reach $forbidden',
        );
      }
    }
  });

  test('the same level names are used in settings and in the viewer', () {
    // Two surfaces calling the same level different things would be a small
    // thing that makes the feature feel unfinished.
    final panel = File(
      'lib/ui/features/replay/widgets/analysis_coach_panel.dart',
    ).readAsStringSync();
    final settings = File(
      'lib/ui/features/settings/views/settings_screen.dart',
    ).readAsStringSync();

    expect(panel, contains('String verbosityLabel('));
    expect(settings, contains('verbosityLabel('));
  });
}

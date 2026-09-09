import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/app/app_routes.dart';
import 'package:hareeg_table/data/persistence/preferences_repository.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/l10n/app_strings.dart';
import 'package:hareeg_table/ui/features/game_setup/views/new_game_setup_screen.dart';

import '../../../support/test_fixtures.dart';

class _Preferences extends MemoryPreferencesRepository {
  bool fail = false;
  int writes = 0;
  Completer<void>? pending;

  @override
  Future<void> savePreferences(GamePreferences value) async {
    writes++;
    if (pending case final pending?) await pending.future;
    if (fail) throw StateError('Storage unavailable');
    await super.savePreferences(value);
  }
}

Future<void> _pump(
  WidgetTester tester,
  _Preferences repository,
  AppStrings strings, {
  ValueChanged<ClassicHareegSetup>? onStart,
}) async {
  tester.view.physicalSize = const Size(800, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    AppStringsScope(
      strings: strings,
      child: MaterialApp(
        builder: (context, child) =>
            Directionality(textDirection: strings.textDirection, child: child!),
        home: NewGameSetupScreen(preferencesRepository: repository),
        onGenerateRoute: (settings) {
          if (settings.name != AppRoutes.table) return null;
          onStart?.call(settings.arguments! as ClassicHareegSetup);
          return MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('table')),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final strings in [AppStrings.english, AppStrings.arabic]) {
    testWidgets(
      'unsaved selection is passed to the table ${strings.languageCode}',
      (tester) async {
        final repository = _Preferences()..fail = true;
        ClassicHareegSetup? started;
        await _pump(
          tester,
          repository,
          strings,
          onStart: (setup) => started = setup,
        );
        await tester.tap(find.text(strings.beginner));
        await tester.pumpAndSettle();
        expect(find.byType(SnackBar), findsOneWidget);
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text(strings.startTable));
        await tester.pumpAndSettle();
        await tester.tap(find.text(strings.startTable));
        await tester.pumpAndSettle();
        expect(started?.cpuDifficulty, CpuDifficulty.beginner);
        expect(
          repository.preferences.setup.cpuDifficulty,
          CpuDifficulty.casual,
        );
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      'setup reports failed save and remains usable ${strings.languageCode}',
      (tester) async {
        final repository = _Preferences()..fail = true;
        await _pump(tester, repository, strings);
        await tester.tap(find.text(strings.beginner));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(repository.writes, 1);
        final picker = tester.widget<SegmentedButton<CpuDifficulty>>(
          find.byType(SegmentedButton<CpuDifficulty>),
        );
        expect(picker.selected, {CpuDifficulty.beginner});
        expect(
          repository.preferences.setup.cpuDifficulty,
          CpuDifficulty.casual,
        );
        expect(find.byType(SnackBar), findsOneWidget);
        final warning = strings.languageCode == 'ar'
            ? 'تعذر حفظ إعدادات اللعبة. لا يزال بإمكانك بدء اللعب بالإعدادات المحددة.'
            : 'Could not save game setup. You can still start with your selected settings.';
        expect(find.text(warning), findsOneWidget);

        repository.fail = false;
        await tester.tap(find.text(strings.skilled));
        await tester.pumpAndSettle();
        expect(repository.writes, 2);
        expect(
          repository.preferences.setup.cpuDifficulty,
          CpuDifficulty.skilled,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('successful setup save has no failure warning', (tester) async {
    final repository = _Preferences();
    await _pump(tester, repository, AppStrings.english);
    await tester.tap(find.text(AppStrings.english.beginner));
    await tester.pumpAndSettle();
    expect(repository.preferences.setup.cpuDifficulty, CpuDifficulty.beginner);
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late setup failure is handled after disposal', (tester) async {
    final repository = _Preferences()..pending = Completer<void>();
    await _pump(tester, repository, AppStrings.english);
    await tester.tap(find.text(AppStrings.english.beginner));
    await tester.pumpWidget(const SizedBox.shrink());
    repository.pending!.completeError(StateError('Storage unavailable'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

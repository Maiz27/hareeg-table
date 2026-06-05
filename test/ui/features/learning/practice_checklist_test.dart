import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/app/app_routes.dart';
import 'package:hareeg_table/app/hareeg_table_app.dart';
import 'package:hareeg_table/data/persistence/learning_progress_repository.dart';
import 'package:hareeg_table/l10n/app_strings.dart';
import 'package:hareeg_table/ui/core/cards/showcase_card_fan.dart';
import 'package:hareeg_table/ui/features/learning/models/practice_catalog.dart';
import 'package:hareeg_table/ui/features/learning/views/onboarding_screen.dart';

import '../../../support/test_fixtures.dart';

void main() {
  ShowcaseCardFan.disableLoopingMotionForTesting = true;

  testWidgets('checklist lists every planned lesson grouped by pack', (
    tester,
  ) async {
    await tester.pumpWidget(_practiceApp(MemoryLearningProgressRepository()));
    await tester.pumpAndSettle();

    expect(PracticeCatalog.lessons, hasLength(15));
    expect(find.text('0 of 15 completed'), findsOneWidget);
    // The checklist builds lazily; walk it top to bottom, checking each pack
    // header followed by its lessons.
    for (final pack in PracticePackId.values) {
      final header = find.text(pack.title(AppStrings.english));
      await tester.scrollUntilVisible(header, 150);
      expect(header, findsOneWidget);
      for (final lesson in PracticeCatalog.lessonsIn(pack)) {
        final title = find.text(lesson.title(AppStrings.english));
        await tester.scrollUntilVisible(title, 150);
        expect(
          title,
          findsOneWidget,
          reason: 'missing checklist entry for ${lesson.id}',
        );
      }
    }
  });

  testWidgets('seeded progress states render and count', (tester) async {
    final learning = MemoryLearningProgressRepository(
      progress: LearningProgress.defaults()
          .withLessonStatus('turn-rhythm', PracticeLessonStatus.completed)
          .withLessonStatus('pending-discard', PracticeLessonStatus.skipped),
    );
    await tester.pumpWidget(_practiceApp(learning));
    await tester.pumpAndSettle();

    expect(find.text('1 of 15 completed'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Skipped'), findsOneWidget);
    // Completed lessons offer replay instead of start.
    expect(find.text('Replay'), findsOneWidget);
    expect(find.text('Unskip'), findsOneWidget);
  });

  testWidgets('skipping and unskipping a lesson persists', (tester) async {
    final learning = MemoryLearningProgressRepository();
    await tester.pumpWidget(_practiceApp(learning));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Skip').first);
    await tester.pumpAndSettle();

    expect(
      learning.progress.statusFor('turn-rhythm'),
      PracticeLessonStatus.skipped,
    );
    expect(find.text('Skipped'), findsOneWidget);

    await tester.tap(find.text('Unskip'));
    await tester.pumpAndSettle();

    expect(
      learning.progress.statusFor('turn-rhythm'),
      PracticeLessonStatus.notStarted,
    );
    expect(find.text('Skipped'), findsNothing);
  });

  testWidgets('starting a lesson whose pack has not shipped shows the notice', (
    tester,
  ) async {
    // Tall surface so the unscripted tile is on-screen without scrolling.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_practiceApp(MemoryLearningProgressRepository()));
    await tester.pumpAndSettle();

    // Benchmark-pressure has no script until HT-47.
    await tester.tap(
      find.descendant(
        of: find.byKey(
          const ValueKey('practice-lesson-tile-benchmark-pressure'),
        ),
        matching: find.text('Start'),
      ),
    );
    await tester.pump();

    expect(
      find.text('This practice hand arrives in an upcoming update.'),
      findsOneWidget,
    );
  });

  testWidgets('replay intro from the hub opens onboarding and pops back', (
    tester,
  ) async {
    final learning = MemoryLearningProgressRepository(
      progress: LearningProgress.defaults().copyWith(
        onboardingCompleted: true,
      ),
    );
    await tester.pumpWidget(_practiceApp(learning));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Replay intro'));
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingScreen), findsOneWidget);

    await tester.tap(find.text('Skip intro'));
    await tester.pumpAndSettle();

    expect(find.text('0 of 15 completed'), findsOneWidget);
  });
}

Widget _practiceApp(MemoryLearningProgressRepository learning) {
  return HareegTableApp(
    preferencesRepository: MemoryPreferencesRepository(),
    matchRepository: MemoryMatchRepository(),
    learningProgressRepository: learning,
    initialRouteOverride: AppRoutes.practice,
  );
}

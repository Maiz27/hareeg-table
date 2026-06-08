import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/data/persistence/learning_progress_repository.dart';
import 'package:hareeg_table/l10n/app_strings.dart';
import 'package:hareeg_table/ui/core/cards/card_view.dart';
import 'package:hareeg_table/ui/core/cards/showcase_card_fan.dart';
import 'package:hareeg_table/ui/features/learning/models/practice_catalog.dart';
import 'package:hareeg_table/ui/features/learning/views/onboarding_screen.dart';

import '../../../support/practice_widget_harness.dart';
import '../../../support/test_fixtures.dart';

void main() {
  ShowcaseCardFan.disableLoopingMotionForTesting = true;

  testWidgets('checklist lists every planned lesson grouped by pack', (
    tester,
  ) async {
    await tester.pumpWidget(
      practiceApp(learning: MemoryLearningProgressRepository()),
    );
    await tester.pumpAndSettle();

    expect(PracticeCatalog.lessons, hasLength(24));
    expect(find.text('0 of 24 completed'), findsOneWidget);
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
          .withLessonStatus('card-values', PracticeLessonStatus.completed)
          .withLessonStatus('meld-shapes', PracticeLessonStatus.skipped),
    );
    await tester.pumpWidget(practiceApp(learning: learning));
    await tester.pumpAndSettle();

    expect(find.text('1 of 24 completed'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Skipped'), findsOneWidget);
    // Completed lessons offer replay instead of start.
    expect(find.text('Replay'), findsOneWidget);
    expect(find.text('Unskip'), findsOneWidget);
  });

  testWidgets('skipping and unskipping a lesson persists', (tester) async {
    final learning = MemoryLearningProgressRepository();
    await tester.pumpWidget(practiceApp(learning: learning));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Skip').first);
    await tester.pumpAndSettle();

    expect(
      learning.progress.statusFor('card-values'),
      PracticeLessonStatus.skipped,
    );
    expect(find.text('Skipped'), findsOneWidget);

    await tester.tap(find.text('Unskip'));
    await tester.pumpAndSettle();

    expect(
      learning.progress.statusFor('card-values'),
      PracticeLessonStatus.notStarted,
    );
    expect(find.text('Skipped'), findsNothing);
  });

  // The coming-soon notice path became defensive-only once HT-48 shipped the
  // final pack: every catalog lesson now has a script (or the explainer
  // route), which the scripts-registry test asserts catalog-wide.

  testWidgets('replay intro from the hub opens onboarding and pops back', (
    tester,
  ) async {
    final learning = MemoryLearningProgressRepository(
      progress: LearningProgress.defaults().copyWith(onboardingCompleted: true),
    );
    await tester.pumpWidget(practiceApp(learning: learning));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Replay intro'));
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingScreen), findsOneWidget);

    await tester.tap(find.text('Skip intro'));
    await tester.pumpAndSettle();

    expect(find.text('0 of 24 completed'), findsOneWidget);
  });

  testWidgets(
    'a Fundamentals reading panel shows its content and completes on Got it',
    (tester) async {
      final learning = MemoryLearningProgressRepository();
      await tester.pumpWidget(practiceApp(learning: learning));
      await tester.pumpAndSettle();

      await openLesson(tester, 'card-values');

      // The generic reading panel renders the panel title and a known line.
      expect(find.text('What your cards are worth'), findsWidgets);
      expect(
        find.text('Worth the number on the card. A 7 is 7 points.'),
        findsOneWidget,
      );

      // The card-values panel teaches with real card faces: the three number
      // demo cards plus the four face/ace cards all worth 10.
      expect(find.byType(HareegCardView), findsNWidgets(7));
      expect(find.text('= 5'), findsOneWidget);
      expect(find.text('Each = 10'), findsOneWidget);

      // The panel scrolls; bring "Got it" fully into view before tapping.
      await tester.scrollUntilVisible(find.text('Got it'), 150);
      await tester.ensureVisible(find.text('Got it'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();

      // Back on the checklist, the lesson is persisted as completed.
      expect(
        learning.progress.statusFor('card-values'),
        PracticeLessonStatus.completed,
      );
      expect(find.text('Completed'), findsOneWidget);
    },
  );
}

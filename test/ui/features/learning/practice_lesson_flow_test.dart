import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/app/app_routes.dart';
import 'package:hareeg_table/app/hareeg_table_app.dart';
import 'package:hareeg_table/data/persistence/learning_progress_repository.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/ui/core/cards/card_view.dart';
import 'package:hareeg_table/ui/core/cards/showcase_card_fan.dart';
import 'package:hareeg_table/ui/features/learning/views/practice_lesson_screen.dart';

import '../../../support/test_fixtures.dart';

void main() {
  ShowcaseCardFan.disableLoopingMotionForTesting = true;

  testWidgets('checklist launches the turn-rhythm lesson deterministically', (
    tester,
  ) async {
    final learning = MemoryLearningProgressRepository();
    await tester.pumpWidget(_practiceApp(learning: learning));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start').first);
    await tester.pumpAndSettle();

    expect(find.byType(PracticeLessonScreen), findsOneWidget);
    expect(find.text('Step 1 of 2'), findsOneWidget);
    expect(
      find.text('Your turn starts with a card: draw one from the stock.'),
      findsOneWidget,
    );
    expect(find.text('Draw Stock'), findsOneWidget);
  });

  testWidgets('completing the lesson updates and persists checklist progress', (
    tester,
  ) async {
    final learning = MemoryLearningProgressRepository();
    await tester.pumpWidget(_practiceApp(learning: learning));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Draw Stock'));
    await tester.pumpAndSettle();
    expect(find.text('Step 2 of 2'), findsOneWidget);
    expect(find.text('Card drawn — it joined your hand.'), findsOneWidget);

    // Select a hand card; the exact legal discard action becomes a button.
    // (The table strip also labels its pile "Discard", so target the button.)
    expect(find.widgetWithText(FilledButton, 'Discard'), findsNothing);
    await tester.tap(find.byType(HareegCardView).last);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Discard'));
    await tester.pumpAndSettle();

    expect(find.text('Lesson complete!'), findsOneWidget);
    expect(
      learning.progress.statusFor('turn-rhythm'),
      PracticeLessonStatus.completed,
    );

    await tester.tap(find.text('Back to practice'));
    await tester.pumpAndSettle();

    expect(find.text('1 of 15 completed'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Replay'), findsOneWidget);
  });

  testWidgets('replaying a completed lesson restarts the same board', (
    tester,
  ) async {
    final learning = MemoryLearningProgressRepository(
      progress: LearningProgress.defaults().withLessonStatus(
        'turn-rhythm',
        PracticeLessonStatus.completed,
      ),
    );
    await tester.pumpWidget(_practiceApp(learning: learning));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Replay').first);
    await tester.pumpAndSettle();

    expect(find.text('Step 1 of 2'), findsOneWidget);
    expect(find.text('Draw Stock'), findsOneWidget);
  });

  testWidgets('exiting practice never touches the saved match', (
    tester,
  ) async {
    final savedMatch = snapshotWithSouthHand(const []);
    final matches = MemoryMatchRepository(saved: savedMatch);
    final learning = MemoryLearningProgressRepository();
    await tester.pumpWidget(
      _practiceApp(learning: learning, matches: matches),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Draw Stock'));
    await tester.pumpAndSettle();

    // Leave mid-lesson.
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(matches.saved, same(savedMatch));
    expect(
      learning.progress.statusFor('turn-rhythm'),
      PracticeLessonStatus.notStarted,
    );
  });

  testWidgets('selection hint shows until the selection matches an action', (
    tester,
  ) async {
    // The surface only offers exact legal engine actions, so a mismatched
    // selection has no button; the hint guides the player instead. (Real
    // engine rejections are covered at the session layer.)
    final learning = MemoryLearningProgressRepository();
    await tester.pumpWidget(_practiceApp(learning: learning));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Draw Stock'));
    await tester.pumpAndSettle();

    expect(
      find.text('Tap cards in your hand to select them.'),
      findsOneWidget,
    );
  });

  testWidgets('pending-discard lesson walks take, meld, and discard on the '
      'surface', (tester) async {
    final learning = MemoryLearningProgressRepository();
    await tester.pumpWidget(_practiceApp(learning: learning));
    await tester.pumpAndSettle();

    // Second lesson: Taking the discard.
    await tester.tap(find.text('Start').at(1));
    await tester.pumpAndSettle();

    expect(find.text('Step 1 of 3'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Take Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Step 2 of 3'), findsOneWidget);

    // Select the three eights; the pending eight renders in both the table
    // strip and the hand, so tap the hand copy.
    for (final suit in [CardSuit.clubs, CardSuit.hearts, CardSuit.diamonds]) {
      final id = HareegCard.standard(
        rank: CardRank.eight,
        suit: suit,
        deckIndex: 0,
      ).id;
      await tester.tap(
        find
            .byWidgetPredicate(
              (w) => w is HareegCardView && w.card.id == id,
            )
            .last,
      );
      await tester.pump();
    }
    await tester.tap(find.widgetWithText(FilledButton, 'Play meld'));
    await tester.pumpAndSettle();
    expect(find.text('Step 3 of 3'), findsOneWidget);

    await tester.tap(find.byType(HareegCardView).last);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Discard'));
    await tester.pumpAndSettle();

    expect(find.text('Lesson complete!'), findsOneWidget);
    expect(
      learning.progress.statusFor('pending-discard'),
      PracticeLessonStatus.completed,
    );
  });

  testWidgets('lesson surface fits a compact portrait phone', (tester) async {
    tester.view.physicalSize = const Size(1080, 2070);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final learning = MemoryLearningProgressRepository();
    await tester.pumpWidget(_practiceApp(learning: learning));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Start').first, 120);
    await tester.tap(find.text('Start').first);
    await tester.pumpAndSettle();

    // Walk the whole lesson at 360x690 logical; overflows would throw.
    await tester.tap(find.text('Draw Stock'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byType(HareegCardView).last, 120);
    await tester.tap(find.byType(HareegCardView).last);
    await tester.pump();
    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, 'Discard'),
      120,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Discard'));
    await tester.pumpAndSettle();

    expect(find.text('Lesson complete!'), findsOneWidget);
  });
}

Widget _practiceApp({
  required MemoryLearningProgressRepository learning,
  MemoryMatchRepository? matches,
}) {
  return HareegTableApp(
    preferencesRepository: MemoryPreferencesRepository(),
    matchRepository: matches ?? MemoryMatchRepository(),
    learningProgressRepository: learning,
    initialRouteOverride: AppRoutes.practice,
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/app/app_routes.dart';
import 'package:hareeg_table/app/hareeg_table_app.dart';
import 'package:hareeg_table/data/persistence/learning_progress_repository.dart';
import 'package:hareeg_table/ui/core/cards/showcase_card_fan.dart';
import 'package:hareeg_table/ui/features/game_table/views/game_table_screen.dart';

import '../../../support/test_fixtures.dart';

void main() {
  ShowcaseCardFan.disableLoopingMotionForTesting = true;

  Future<void> openLesson(WidgetTester tester) async {
    await tester.tap(find.text('Start').first);
    await tester.pumpAndSettle();
  }

  Future<void> dragToDiscard(WidgetTester tester, String semanticsLabel) async {
    final card = find.bySemanticsLabel(semanticsLabel).first;
    final target = find.byKey(const ValueKey('discard-pile-drop-target'));
    await tester.dragFrom(
      tester.getCenter(card),
      tester.getCenter(target) - tester.getCenter(card),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('checklist launches the turn-rhythm lesson on the real table', (
    tester,
  ) async {
    final learning = MemoryLearningProgressRepository();
    await tester.pumpWidget(_practiceApp(learning: learning));
    await tester.pumpAndSettle();

    await openLesson(tester);

    // The lesson is the real table surface in practice mode.
    expect(find.byType(GameTableScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('practice-step-banner')), findsOneWidget);
    expect(
      find.text('Your turn starts with a card: draw one from the stock.'),
      findsOneWidget,
    );
    // Match chrome is hidden; the exit shortcut takes the score slot.
    expect(find.byTooltip('Scores'), findsNothing);
    expect(find.byKey(const ValueKey('practice-exit')), findsOneWidget);
  });

  testWidgets('completing the lesson with real gestures persists progress', (
    tester,
  ) async {
    final learning = MemoryLearningProgressRepository();
    await tester.pumpWidget(_practiceApp(learning: learning));
    await tester.pumpAndSettle();
    await openLesson(tester);

    // Step 1: draw by tapping the stock pile, exactly like a real match.
    await tester.tap(find.byTooltip('Draw Stock'));
    await tester.pumpAndSettle();

    expect(find.text('Card drawn — it joined your hand.'), findsOneWidget);
    expect(
      find.text(
        'Now end your turn: pick a card you do not need and discard it.',
      ),
      findsOneWidget,
    );

    // Step 2: drag a hand card onto the discard pile.
    await dragToDiscard(tester, 'Three of Clubs');

    expect(find.text('Lesson complete!'), findsOneWidget);
    expect(
      learning.progress.statusFor('turn-rhythm'),
      PracticeLessonStatus.completed,
    );

    await tester.tap(find.text('Back to practice'));
    await tester.pumpAndSettle();

    expect(find.text('1 of 15 completed'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
  });

  testWidgets('replay restarts the lesson in place on a fresh board', (
    tester,
  ) async {
    final learning = MemoryLearningProgressRepository();
    await tester.pumpWidget(_practiceApp(learning: learning));
    await tester.pumpAndSettle();
    await openLesson(tester);

    await tester.tap(find.byTooltip('Draw Stock'));
    await tester.pumpAndSettle();
    await dragToDiscard(tester, 'Three of Clubs');
    expect(find.text('Lesson complete!'), findsOneWidget);

    // The pack's next lesson is unscripted in this slice, so the overlay
    // must not offer a continuation — only replay and the way back.
    expect(find.text('Next lesson'), findsNothing);

    await tester.tap(find.text('Replay lesson'));
    await tester.pumpAndSettle();

    // In-place restart: the same table route, fresh board, step 1 again.
    expect(find.byType(GameTableScreen), findsOneWidget);
    expect(
      find.text('Your turn starts with a card: draw one from the stock.'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Three of Clubs'), findsWidgets);
  });

  testWidgets('off-script affordances stay dark during a step', (tester) async {
    final learning = MemoryLearningProgressRepository();
    await tester.pumpWidget(_practiceApp(learning: learning));
    await tester.pumpAndSettle();
    await openLesson(tester);

    // Step 1 allows only the stock draw. Discarding a hand card is a legal
    // engine action, but the step gate must keep the drop target dark.
    await dragToDiscard(tester, 'Three of Clubs');

    expect(
      find.text('Your turn starts with a card: draw one from the stock.'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Three of Clubs'), findsWidgets);
    expect(
      learning.progress.statusFor('turn-rhythm'),
      PracticeLessonStatus.notStarted,
    );
  });

  testWidgets('exiting practice never touches the saved match', (tester) async {
    final savedMatch = snapshotWithSouthHand(const []);
    final matches = MemoryMatchRepository(saved: savedMatch);
    final learning = MemoryLearningProgressRepository();
    await tester.pumpWidget(_practiceApp(learning: learning, matches: matches));
    await tester.pumpAndSettle();
    await openLesson(tester);

    await tester.tap(find.byTooltip('Draw Stock'));
    await tester.pumpAndSettle();

    // Leave mid-lesson through the practice exit shortcut.
    await tester.tap(find.byKey(const ValueKey('practice-exit')));
    await tester.pumpAndSettle();

    expect(find.text('0 of 15 completed'), findsOneWidget);
    expect(matches.saved, same(savedMatch));
    expect(
      learning.progress.statusFor('turn-rhythm'),
      PracticeLessonStatus.notStarted,
    );
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

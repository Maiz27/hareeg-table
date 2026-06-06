import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/app/app_routes.dart';
import 'package:hareeg_table/app/hareeg_table_app.dart';
import 'package:hareeg_table/data/persistence/learning_progress_repository.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/ui/core/cards/showcase_card_fan.dart';
import 'package:hareeg_table/ui/features/game_table/views/game_table_screen.dart';

import '../../../support/test_fixtures.dart';

void main() {
  ShowcaseCardFan.disableLoopingMotionForTesting = true;

  // The checklist is a lazy ListView, so a lower lesson tile may not be built
  // until the list scrolls; target tiles by key, then tap their start button.
  Future<void> openLesson(WidgetTester tester, String lessonId) async {
    final tile = find.byKey(ValueKey('practice-lesson-tile-$lessonId'));
    if (tile.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        tile,
        160,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: tile, matching: find.byType(OutlinedButton)),
    );
    await tester.pumpAndSettle();
  }

  // Scrolls the checklist back to its header (the completed-count line) after
  // a lesson opened from a scrolled position pops back to the list.
  Future<void> scrollChecklistToTop(WidgetTester tester) async {
    await tester.drag(find.byType(ListView), const Offset(0, 600));
    await tester.pumpAndSettle();
  }

  Future<void> dragToDiscard(WidgetTester tester, String semanticsLabel) async {
    // Lesson boards hold each named card exactly once (the deterministic
    // seeded deal guarantees it); `.first` only guards against transient
    // duplicate semantics nodes mid-animation, mirroring the established
    // pattern in the game-table widget tests.
    final card = find.bySemanticsLabel(semanticsLabel).first;
    final target = find.byKey(const ValueKey('discard-pile-drop-target'));
    await tester.dragFrom(
      tester.getCenter(card),
      tester.getCenter(target) - tester.getCenter(card),
    );
    await tester.pumpAndSettle();
  }

  /// Toggles a south-hand card's selection via the hand fan's drag key, so a
  /// card that also renders elsewhere (a pending discard shows on the pile
  /// too) cannot be hit by mistake. Taps just inside the card's left edge:
  /// fanned cards overlap to the right, so the left sliver is the only region
  /// guaranteed to belong to this card.
  Future<void> toggleHandCard(
    WidgetTester tester,
    CardRank rank,
    CardSuit suit,
  ) async {
    final id = HareegCard.standard(rank: rank, suit: suit, deckIndex: 0).id;
    final rect = tester.getRect(find.byKey(ValueKey('south-hand-drag-$id')));
    await tester.tapAt(Offset(rect.left + 6, rect.center.dy));
    await tester.pump();
  }

  Future<void> playSelectedMeld(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Play selected meld'));
    await tester.pumpAndSettle();
  }

  Future<void> tapDiscardPile(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('discard-pile-drop-target')));
    await tester.pumpAndSettle();
  }

  testWidgets('checklist launches the turn-rhythm lesson on the real table', (
    tester,
  ) async {
    final learning = MemoryLearningProgressRepository();
    await tester.pumpWidget(_practiceApp(learning: learning));
    await tester.pumpAndSettle();

    await openLesson(tester, 'turn-rhythm');

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
    await openLesson(tester, 'turn-rhythm');

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
    await scrollChecklistToTop(tester);

    expect(find.text('1 of 15 completed'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
  });

  testWidgets('replay restarts the lesson in place on a fresh board', (
    tester,
  ) async {
    final learning = MemoryLearningProgressRepository();
    await tester.pumpWidget(_practiceApp(learning: learning));
    await tester.pumpAndSettle();
    await openLesson(tester, 'turn-rhythm');

    await tester.tap(find.byTooltip('Draw Stock'));
    await tester.pumpAndSettle();
    await dragToDiscard(tester, 'Three of Clubs');
    expect(find.text('Lesson complete!'), findsOneWidget);

    await tester.tap(find.text('Replay lesson'));
    await tester.pumpAndSettle();

    // In-place restart: the same table route, fresh board, step 1 again.
    expect(find.byType(GameTableScreen), findsOneWidget);
    expect(
      find.text('Your turn starts with a card: draw one from the stock.'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Three of Clubs'), findsOneWidget);
  });

  testWidgets('completion overlay chains into the next lesson in the pack', (
    tester,
  ) async {
    final learning = MemoryLearningProgressRepository();
    await tester.pumpWidget(_practiceApp(learning: learning));
    await tester.pumpAndSettle();
    await openLesson(tester, 'turn-rhythm');

    await tester.tap(find.byTooltip('Draw Stock'));
    await tester.pumpAndSettle();
    await dragToDiscard(tester, 'Three of Clubs');
    expect(find.text('Lesson complete!'), findsOneWidget);

    // Pending-discard is the next scripted lesson in the core turn pack.
    await tester.tap(find.text('Next lesson'));
    await tester.pumpAndSettle();

    // In-place swap: same table route, the next lesson's board and step 1.
    expect(find.byType(GameTableScreen), findsOneWidget);
    expect(
      find.text(
        'The last discard is the 8 of diamonds — and you hold two more '
        'eights. Tap the pile to take it instead of drawing.',
      ),
      findsOneWidget,
    );
    expect(
      learning.progress.statusFor('turn-rhythm'),
      PracticeLessonStatus.completed,
    );
    expect(
      learning.progress.statusFor('pending-discard'),
      PracticeLessonStatus.notStarted,
    );
  });

  testWidgets('off-script affordances stay dark during a step', (tester) async {
    final learning = MemoryLearningProgressRepository();
    await tester.pumpWidget(_practiceApp(learning: learning));
    await tester.pumpAndSettle();
    await openLesson(tester, 'turn-rhythm');

    // Step 1 allows only the stock draw. Discarding a hand card is a legal
    // engine action, but the step gate must keep the drop target dark.
    await dragToDiscard(tester, 'Three of Clubs');

    expect(
      find.text('Your turn starts with a card: draw one from the stock.'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Three of Clubs'), findsOneWidget);
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
    await openLesson(tester, 'turn-rhythm');

    await tester.tap(find.byTooltip('Draw Stock'));
    await tester.pumpAndSettle();

    // Leave mid-lesson through the practice exit shortcut.
    await tester.tap(find.byKey(const ValueKey('practice-exit')));
    await tester.pumpAndSettle();
    await scrollChecklistToTop(tester);

    expect(find.text('0 of 15 completed'), findsOneWidget);
    expect(matches.saved, same(savedMatch));
    expect(
      learning.progress.statusFor('turn-rhythm'),
      PracticeLessonStatus.notStarted,
    );
  });

  testWidgets('pending-discard lesson: take the discard and meld it', (
    tester,
  ) async {
    final learning = MemoryLearningProgressRepository();
    await tester.pumpWidget(_practiceApp(learning: learning));
    await tester.pumpAndSettle();
    await openLesson(tester, 'pending-discard');

    // Step 1: take the discard by tapping the pile, like a real match.
    await tapDiscardPile(tester);
    expect(
      find.text(
        'A taken discard must earn its place. Play it in a meld now — or '
        'return it and draw from stock instead.',
      ),
      findsOneWidget,
    );

    // Step 2: meld the three eights. The pending eight renders on the pile
    // and in the hand; the hand-key helper always hits the hand copy.
    await toggleHandCard(tester, CardRank.eight, CardSuit.clubs);
    await toggleHandCard(tester, CardRank.eight, CardSuit.hearts);
    await toggleHandCard(tester, CardRank.eight, CardSuit.diamonds);
    await playSelectedMeld(tester);
    expect(
      find.text(
        'End your turn with a discard. (If you returned the eight, draw '
        'from stock first.)',
      ),
      findsOneWidget,
    );

    // Step 3: end the turn with a discard.
    await dragToDiscard(tester, 'King of Spades');

    expect(find.text('Lesson complete!'), findsOneWidget);
    expect(
      learning.progress.statusFor('pending-discard'),
      PracticeLessonStatus.completed,
    );

    await tester.tap(find.text('Back to practice'));
    await tester.pumpAndSettle();
    await scrollChecklistToTop(tester);
    expect(find.text('1 of 15 completed'), findsOneWidget);
  });

  testWidgets('pending-discard lesson: return the discard and draw instead', (
    tester,
  ) async {
    final learning = MemoryLearningProgressRepository();
    await tester.pumpWidget(_practiceApp(learning: learning));
    await tester.pumpAndSettle();
    await openLesson(tester, 'pending-discard');

    // Take the discard, then change course: tapping the pile again returns
    // the pending card (the same gesture a real match uses).
    await tapDiscardPile(tester);
    await tapDiscardPile(tester);

    // The return path lands back in the draw phase; the final step accepts
    // the stock draw it needs before the closing discard.
    expect(
      find.text(
        'End your turn with a discard. (If you returned the eight, draw '
        'from stock first.)',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Draw Stock'));
    await tester.pumpAndSettle();
    await dragToDiscard(tester, 'King of Spades');

    expect(find.text('Lesson complete!'), findsOneWidget);
    expect(
      learning.progress.statusFor('pending-discard'),
      PracticeLessonStatus.completed,
    );
  });

  testWidgets('meld-picker lesson: exact selection plays, extras stay dark', (
    tester,
  ) async {
    final learning = MemoryLearningProgressRepository();
    await tester.pumpWidget(_practiceApp(learning: learning));
    await tester.pumpAndSettle();
    await openLesson(tester, 'meld-picker');

    // Off-script gate: the lesson opens in the action phase, so a discard is
    // engine-legal, but step 1 only teaches the meld.
    await dragToDiscard(tester, 'Nine of Diamonds');
    expect(find.bySemanticsLabel('Nine of Diamonds'), findsOneWidget);

    // A selection with an extra card is not an exact meld: no play offer.
    await toggleHandCard(tester, CardRank.five, CardSuit.spades);
    await toggleHandCard(tester, CardRank.six, CardSuit.spades);
    await toggleHandCard(tester, CardRank.seven, CardSuit.spades);
    await toggleHandCard(tester, CardRank.nine, CardSuit.diamonds);
    expect(find.byTooltip('Play selected meld'), findsNothing);

    // Dropping the extra restores the exact run and the offer lights up.
    await toggleHandCard(tester, CardRank.nine, CardSuit.diamonds);
    await playSelectedMeld(tester);
    expect(
      find.text('Finish the turn: discard a card you do not need.'),
      findsOneWidget,
    );

    await dragToDiscard(tester, 'Nine of Diamonds');

    expect(find.text('Lesson complete!'), findsOneWidget);
    expect(
      learning.progress.statusFor('meld-picker'),
      PracticeLessonStatus.completed,
    );
  });

  testWidgets('opening-51 lesson: stage kings, open with jacks, then discard', (
    tester,
  ) async {
    final learning = MemoryLearningProgressRepository();
    await tester.pumpWidget(_practiceApp(learning: learning));
    await tester.pumpAndSettle();
    await openLesson(tester, 'opening-51');

    // Step 1: the kings stage at 30 — below the 51 benchmark.
    await toggleHandCard(tester, CardRank.king, CardSuit.spades);
    await toggleHandCard(tester, CardRank.king, CardSuit.diamonds);
    await toggleHandCard(tester, CardRank.king, CardSuit.hearts);
    await playSelectedMeld(tester);
    expect(
      find.text('Add the jacks to push the total past 51.'),
      findsOneWidget,
    );

    // Step 2: the jacks push the staged total to 60 and complete the opening.
    await toggleHandCard(tester, CardRank.jack, CardSuit.clubs);
    await toggleHandCard(tester, CardRank.jack, CardSuit.diamonds);
    await toggleHandCard(tester, CardRank.jack, CardSuit.hearts);
    await playSelectedMeld(tester);
    expect(
      find.text('Seal the opening: end your turn with a discard.'),
      findsOneWidget,
    );

    // Step 3: the closing discard.
    await dragToDiscard(tester, 'Three of Clubs');

    expect(find.text('Lesson complete!'), findsOneWidget);
    expect(
      learning.progress.statusFor('opening-51'),
      PracticeLessonStatus.completed,
    );

    // Opening-51 ends the core turn pack: finishing a pack is a deliberate
    // stopping point, so the overlay offers no continuation.
    expect(find.text('Next lesson'), findsNothing);
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

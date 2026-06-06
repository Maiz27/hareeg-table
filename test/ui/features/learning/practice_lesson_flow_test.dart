import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/app/app_routes.dart';
import 'package:hareeg_table/app/hareeg_table_app.dart';
import 'package:hareeg_table/data/persistence/learning_progress_repository.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/ui/core/cards/card_state.dart';
import 'package:hareeg_table/ui/core/cards/card_view.dart';
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

  Rect handCardRect(WidgetTester tester, CardRank rank, CardSuit suit) {
    final id = HareegCard.standard(rank: rank, suit: suit, deckIndex: 0).id;
    return tester.getRect(find.byKey(ValueKey('south-hand-drag-$id')));
  }

  /// Drags a south-hand card onto the discard pile, gripping the card just
  /// inside its left edge: fanned cards overlap to the right, so the left
  /// sliver is the only region guaranteed to belong to this card on the
  /// full 14-card opening hands.
  Future<void> dragToDiscard(
    WidgetTester tester,
    CardRank rank,
    CardSuit suit,
  ) async {
    final rect = handCardRect(tester, rank, suit);
    final grip = Offset(rect.left + 6, rect.center.dy);
    final target = tester.getCenter(
      find.byKey(const ValueKey('discard-pile-drop-target')),
    );
    await tester.dragFrom(grip, target - grip);
    await tester.pumpAndSettle();
  }

  /// Toggles a south-hand card's selection via the hand fan's drag key, so a
  /// card that also renders elsewhere (a pending discard shows on the pile
  /// too) cannot be hit by mistake.
  Future<void> toggleHandCard(
    WidgetTester tester,
    CardRank rank,
    CardSuit suit,
  ) async {
    final rect = handCardRect(tester, rank, suit);
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

  /// Pumps through a lesson's scripted intro — the lead-in pause plus the
  /// other seat's animated turn — until the step banner hands control to
  /// the player.
  Future<void> pumpThroughIntro(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 400));
      if (find
          .byKey(const ValueKey('practice-step-banner'))
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('practice-step-banner')),
      findsOneWidget,
      reason: 'the scripted intro must hand the turn to the player',
    );
  }

  /// A card rendered with the coach-highlight ring — the same visual the
  /// live coaching tier uses, reused by practice steps to point at the
  /// specific cards being taught.
  Finder ringedCard(CardRank rank, CardSuit suit) {
    final id = HareegCard.standard(rank: rank, suit: suit, deckIndex: 0).id;
    return find.byWidgetPredicate(
      (widget) =>
          widget is HareegCardView &&
          widget.card.id == id &&
          widget.visualState == CardVisualState.coachHighlight,
    );
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
    await dragToDiscard(tester, CardRank.three, CardSuit.clubs);

    expect(find.text('Lesson complete!'), findsOneWidget);
    expect(
      learning.progress.statusFor('turn-rhythm'),
      PracticeLessonStatus.completed,
    );

    await tester.tap(find.text('Back to practice'));
    await tester.pumpAndSettle();
    await scrollChecklistToTop(tester);

    expect(find.text('1 of 17 completed'), findsOneWidget);
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
    await dragToDiscard(tester, CardRank.three, CardSuit.clubs);
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
    await dragToDiscard(tester, CardRank.three, CardSuit.clubs);
    expect(find.text('Lesson complete!'), findsOneWidget);

    // First-meld is the next scripted lesson in the core turn pack.
    await tester.tap(find.text('Next lesson'));
    await tester.pumpAndSettle();

    // In-place swap: same table route, the next lesson's board and step 1.
    expect(find.byType(GameTableScreen), findsOneWidget);
    expect(
      find.text('Your turn starts with a card: draw one from the stock.'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Ace of Hearts'), findsOneWidget);
    expect(
      learning.progress.statusFor('turn-rhythm'),
      PracticeLessonStatus.completed,
    );
    expect(
      learning.progress.statusFor('first-meld'),
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
    await dragToDiscard(tester, CardRank.three, CardSuit.clubs);

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

    expect(find.text('0 of 17 completed'), findsOneWidget);
    expect(matches.saved, same(savedMatch));
    expect(
      learning.progress.statusFor('turn-rhythm'),
      PracticeLessonStatus.notStarted,
    );
  });

  testWidgets('first-meld lesson: draw, open with the heart run, discard', (
    tester,
  ) async {
    final learning = MemoryLearningProgressRepository();
    await tester.pumpWidget(_practiceApp(learning: learning));
    await tester.pumpAndSettle();
    await openLesson(tester, 'first-meld');

    await tester.tap(find.byTooltip('Draw Stock'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('9 through ace is one run worth 59'),
      findsOneWidget,
    );

    // The step rings exactly the run it teaches, in the coach's visual
    // language; fillers stay unringed.
    expect(ringedCard(CardRank.nine, CardSuit.hearts), findsOneWidget);
    expect(ringedCard(CardRank.ace, CardSuit.hearts), findsOneWidget);
    expect(ringedCard(CardRank.two, CardSuit.clubs), findsNothing);

    // Wrong split: K-Q-J alone is a legal run, so it stages — and the undo
    // pill (always offered in practice) takes it back instead of stranding
    // the lesson.
    final kingInHand = find.byKey(
      ValueKey(
        'south-hand-drag-'
        '${HareegCard.standard(rank: CardRank.king, suit: CardSuit.hearts, deckIndex: 0).id}',
      ),
    );
    await toggleHandCard(tester, CardRank.king, CardSuit.hearts);
    await toggleHandCard(tester, CardRank.queen, CardSuit.hearts);
    await toggleHandCard(tester, CardRank.jack, CardSuit.hearts);
    await playSelectedMeld(tester);
    expect(kingInHand, findsNothing, reason: 'the partial run is staged');
    // The banner reacts to the stall instead of repeating the prompt, and
    // the reaction persists until the situation changes.
    final reaction = find.text(
      'Staged — but only the full six-heart run reaches 51. The undo pill '
      'takes it back; then play all six.',
    );
    expect(reaction, findsOneWidget);
    await tester.tap(find.byTooltip('Take Back Melds'));
    await tester.pumpAndSettle();
    expect(kingInHand, findsOneWidget, reason: 'the undo restores the hand');
    expect(reaction, findsNothing, reason: 'the take-back resolves it');

    // A selection with an extra card is not an exact meld: no play offer.
    await toggleHandCard(tester, CardRank.nine, CardSuit.hearts);
    await toggleHandCard(tester, CardRank.ten, CardSuit.hearts);
    await toggleHandCard(tester, CardRank.jack, CardSuit.hearts);
    await toggleHandCard(tester, CardRank.queen, CardSuit.hearts);
    await toggleHandCard(tester, CardRank.king, CardSuit.hearts);
    await toggleHandCard(tester, CardRank.ace, CardSuit.hearts);
    await toggleHandCard(tester, CardRank.two, CardSuit.clubs);
    expect(find.byTooltip('Play selected meld'), findsNothing);

    // Dropping the extra restores the exact run and the offer lights up.
    await toggleHandCard(tester, CardRank.two, CardSuit.clubs);
    await playSelectedMeld(tester);
    expect(find.text('Finish the turn: discard a card you do not need.'),
        findsOneWidget);

    await dragToDiscard(tester, CardRank.two, CardSuit.clubs);

    expect(find.text('Lesson complete!'), findsOneWidget);
    expect(
      learning.progress.statusFor('first-meld'),
      PracticeLessonStatus.completed,
    );

    await tester.tap(find.text('Back to practice'));
    await tester.pumpAndSettle();
    await scrollChecklistToTop(tester);
    expect(find.text('1 of 17 completed'), findsOneWidget);
  });

  testWidgets('discard-opening lesson: take the eight, open with both sets', (
    tester,
  ) async {
    final learning = MemoryLearningProgressRepository();
    await tester.pumpWidget(_practiceApp(learning: learning));
    await tester.pumpAndSettle();
    await openLesson(tester, 'discard-opening');

    // The board opens on west's turn with an empty pile; the step banner
    // waits while west visibly draws and throws the eight.
    expect(find.byKey(const ValueKey('practice-step-banner')), findsNothing);
    await pumpThroughIntro(tester);
    expect(find.bySemanticsLabel('Eight of Diamonds'), findsOneWidget);

    // Stepwise rings: the pile's eight and the pair it completes — the
    // queens stay dark until their own step.
    expect(ringedCard(CardRank.eight, CardSuit.diamonds), findsOneWidget);
    expect(ringedCard(CardRank.eight, CardSuit.clubs), findsOneWidget);
    expect(ringedCard(CardRank.queen, CardSuit.spades), findsNothing);

    // Step 1: take the eight by tapping the pile, like a real match.
    await tapDiscardPile(tester);
    expect(
      find.text(
        'The taken eight must hit the table first: meld the three eights.',
      ),
      findsOneWidget,
    );

    // Step 2: the eights stage at 24. The pending eight renders on the pile
    // and in the hand; the hand-key helper always hits the hand copy.
    await toggleHandCard(tester, CardRank.eight, CardSuit.clubs);
    await toggleHandCard(tester, CardRank.eight, CardSuit.hearts);
    await toggleHandCard(tester, CardRank.eight, CardSuit.diamonds);
    await playSelectedMeld(tester);

    // Step 3: now the queens ring and push the total to 54.
    expect(
      find.text('Now the queens: 24 + 30 makes 54 and the opening seals.'),
      findsOneWidget,
    );
    expect(ringedCard(CardRank.queen, CardSuit.spades), findsOneWidget);
    await toggleHandCard(tester, CardRank.queen, CardSuit.spades);
    await toggleHandCard(tester, CardRank.queen, CardSuit.diamonds);
    await toggleHandCard(tester, CardRank.queen, CardSuit.hearts);
    await playSelectedMeld(tester);
    expect(find.text('End your turn with a discard.'), findsOneWidget);

    // Step 3: end the turn with a discard.
    await dragToDiscard(tester, CardRank.two, CardSuit.hearts);

    expect(find.text('Lesson complete!'), findsOneWidget);
    expect(
      learning.progress.statusFor('discard-opening'),
      PracticeLessonStatus.completed,
    );
  });

  testWidgets('bait-discard lesson: the pile stays dark, draw and discard', (
    tester,
  ) async {
    final learning = MemoryLearningProgressRepository();
    await tester.pumpWidget(_practiceApp(learning: learning));
    await tester.pumpAndSettle();
    await openLesson(tester, 'bait-discard');

    // West opens on screen: the lesson starts on west's turn and the melds
    // arrive through the real table flights before the player acts.
    expect(find.byKey(const ValueKey('practice-step-banner')), findsNothing);
    await pumpThroughIntro(tester);

    // West's opening is visible on the table.
    expect(find.bySemanticsLabel('King of Hearts'), findsOneWidget);
    expect(find.bySemanticsLabel('Six of Diamonds'), findsOneWidget);

    // The bait must not ring: the lesson points away from the pile.
    expect(ringedCard(CardRank.seven, CardSuit.hearts), findsNothing);

    // The bait: tapping the pile must do nothing — taking is off-script.
    await tapDiscardPile(tester);
    expect(
      find.textContaining('Leave it and draw from the stock.'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Seven of Spades'), findsOneWidget);

    await tester.tap(find.byTooltip('Draw Stock'));
    await tester.pumpAndSettle();
    expect(
      find.text('Bank the patience: end your turn with a discard.'),
      findsOneWidget,
    );

    await dragToDiscard(tester, CardRank.queen, CardSuit.spades);

    expect(find.text('Lesson complete!'), findsOneWidget);
    expect(
      learning.progress.statusFor('bait-discard'),
      PracticeLessonStatus.completed,
    );
  });

  testWidgets('opening-51 lesson: draw, stage kings, open with jacks, discard',
      (tester) async {
    final learning = MemoryLearningProgressRepository();
    await tester.pumpWidget(_practiceApp(learning: learning));
    await tester.pumpAndSettle();
    await openLesson(tester, 'opening-51');

    await tester.tap(find.byTooltip('Draw Stock'));
    await tester.pumpAndSettle();

    // Step 2: the kings stage at 30 — below the 51 benchmark.
    await toggleHandCard(tester, CardRank.king, CardSuit.spades);
    await toggleHandCard(tester, CardRank.king, CardSuit.diamonds);
    await toggleHandCard(tester, CardRank.king, CardSuit.hearts);
    await playSelectedMeld(tester);
    expect(
      find.text('Add the jacks to push the total past 51.'),
      findsOneWidget,
    );

    // Step 3: the jacks push the staged total to 60 and complete the opening.
    await toggleHandCard(tester, CardRank.jack, CardSuit.clubs);
    await toggleHandCard(tester, CardRank.jack, CardSuit.diamonds);
    await toggleHandCard(tester, CardRank.jack, CardSuit.hearts);
    await playSelectedMeld(tester);
    expect(
      find.text('Seal the opening: end your turn with a discard.'),
      findsOneWidget,
    );

    // Step 4: the closing discard.
    await dragToDiscard(tester, CardRank.three, CardSuit.clubs);

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

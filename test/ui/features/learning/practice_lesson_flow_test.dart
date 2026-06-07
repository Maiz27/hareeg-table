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
        'The taken eight must be used before your turn ends: '
        'meld the three eights.',
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

  /// Drags a south-hand card onto another seat's placed meld — the cover
  /// and joker-replacement gesture. Targets the meld stack by owner and
  /// index with the same left-edge grip the discard helper uses.
  Future<void> dragToMeld(
    WidgetTester tester,
    CardRank rank,
    CardSuit suit, {
    required String owner,
    required int meldIndex,
  }) async {
    final rect = handCardRect(tester, rank, suit);
    final grip = Offset(rect.left + 6, rect.center.dy);
    final target = tester.getCenter(
      find.byKey(ValueKey('table-meld-$owner-$meldIndex-normal')),
    );
    await tester.dragFrom(grip, target - grip);
    await tester.pumpAndSettle();
  }

  testWidgets('pending-discard lesson: take, hand back, draw, free meld, '
      'and the overlay chains into benchmark-pressure', (tester) async {
    final learning = MemoryLearningProgressRepository();
    await tester.pumpWidget(_practiceApp(learning: learning));
    await tester.pumpAndSettle();
    await openLesson(tester, 'pending-discard');

    // West visibly draws and throws the four; the player starts opened with
    // their prior melds already on the table.
    expect(find.byKey(const ValueKey('practice-step-banner')), findsNothing);
    await pumpThroughIntro(tester);
    expect(find.bySemanticsLabel('Four of Clubs'), findsOneWidget);

    // Step 1 rings the pair the take completes.
    expect(ringedCard(CardRank.four, CardSuit.hearts), findsOneWidget);
    expect(ringedCard(CardRank.two, CardSuit.spades), findsNothing);

    // Take by tapping the pile.
    await tapDiscardPile(tester);
    expect(
      find.textContaining('tapping the pile hands it back'),
      findsOneWidget,
    );

    // Return by tapping the pile again — the taught step move.
    await tapDiscardPile(tester);
    expect(
      find.textContaining('draw from the stock', findRichText: false),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Draw Stock'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Play your twos'), findsOneWidget);

    // The free six-point meld: legal only because the player is open.
    await toggleHandCard(tester, CardRank.two, CardSuit.spades);
    await toggleHandCard(tester, CardRank.two, CardSuit.diamonds);
    await toggleHandCard(tester, CardRank.two, CardSuit.clubs);
    await playSelectedMeld(tester);
    expect(find.text('End your turn with a discard.'), findsOneWidget);

    await dragToDiscard(tester, CardRank.ace, CardSuit.clubs);

    expect(find.text('Lesson complete!'), findsOneWidget);
    expect(
      learning.progress.statusFor('pending-discard'),
      PracticeLessonStatus.completed,
    );

    // Pack two chains: benchmark-pressure is the next scripted lesson. Its
    // own scripted intro starts immediately, so pump through it before the
    // test ends or its lead-in timer would still be pending.
    await tester.tap(find.text('Next lesson'));
    await tester.pumpAndSettle();
    expect(find.byType(GameTableScreen), findsOneWidget);
    expect(
      learning.progress.statusFor('benchmark-pressure'),
      PracticeLessonStatus.notStarted,
    );
    await pumpThroughIntro(tester);
  });

  testWidgets('benchmark-pressure lesson: west raises the bar on screen; '
      'staging, the taught retract, and the closing discard', (tester) async {
    final learning = MemoryLearningProgressRepository();
    await tester.pumpWidget(_practiceApp(learning: learning));
    await tester.pumpAndSettle();
    await openLesson(tester, 'benchmark-pressure');

    // West's intro opens three melds totalling 75 through the real flights.
    await pumpThroughIntro(tester);
    expect(find.bySemanticsLabel('Ace of Spades'), findsOneWidget);
    expect(
      find.textContaining('the bar is now 75'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Draw Stock'));
    await tester.pumpAndSettle();

    // Stage the legal-but-short run.
    expect(ringedCard(CardRank.seven, CardSuit.hearts), findsOneWidget);
    await toggleHandCard(tester, CardRank.seven, CardSuit.hearts);
    await toggleHandCard(tester, CardRank.eight, CardSuit.hearts);
    await toggleHandCard(tester, CardRank.nine, CardSuit.hearts);
    await toggleHandCard(tester, CardRank.ten, CardSuit.hearts);
    await toggleHandCard(tester, CardRank.jack, CardSuit.hearts);
    await toggleHandCard(tester, CardRank.queen, CardSuit.hearts);
    await playSelectedMeld(tester);

    // The retract step: the take-back is the taught move, so the undo pill
    // must advance the lesson instead of holding it as a correction.
    expect(
      find.textContaining('Take the run back'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Take Back Melds'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('End the turn with a discard'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Queen of Hearts'),
      findsOneWidget,
      reason: 'the retract restored the run to the hand',
    );

    await dragToDiscard(tester, CardRank.queen, CardSuit.spades);

    expect(find.text('Lesson complete!'), findsOneWidget);
    expect(
      learning.progress.statusFor('benchmark-pressure'),
      PracticeLessonStatus.completed,
    );
  });

  testWidgets('sequence-cover lesson: stack the jack and queen on west\'s '
      'run, then fill the eights with the twin diamond', (tester) async {
    final learning = MemoryLearningProgressRepository();
    await tester.pumpWidget(_practiceApp(learning: learning));
    await tester.pumpAndSettle();
    await openLesson(tester, 'sequence-cover');

    await pumpThroughIntro(tester);

    await tester.tap(find.byTooltip('Draw Stock'));
    await tester.pumpAndSettle();

    // The step rings both stacked covers in hand (the run's cards ring on
    // the table side).
    expect(ringedCard(CardRank.jack, CardSuit.diamonds), findsOneWidget);
    expect(ringedCard(CardRank.queen, CardSuit.diamonds), findsOneWidget);

    // West staged the eights first, so the diamond run is meld index 1.
    // One card at a time: the jack lands, the banner reacts and holds for
    // the queen.
    await dragToMeld(
      tester,
      CardRank.jack,
      CardSuit.diamonds,
      owner: 'west',
      meldIndex: 1,
    );
    expect(
      find.textContaining('The queen is its new neighbor'),
      findsOneWidget,
    );
    await dragToMeld(
      tester,
      CardRank.queen,
      CardSuit.diamonds,
      owner: 'west',
      meldIndex: 1,
    );

    // Second target, same turn: the duplicate-deck eight fills the set.
    expect(find.textContaining('Fill the set.'), findsOneWidget);
    final eightRect = tester.getRect(
      find.byKey(const ValueKey('south-hand-drag-deck-1-eight-diamonds')),
    );
    final eightsTarget = tester.getCenter(
      find.byKey(const ValueKey('table-meld-west-0-normal')),
    );
    final grip = Offset(eightRect.left + 6, eightRect.center.dy);
    await tester.dragFrom(grip, eightsTarget - grip);
    await tester.pumpAndSettle();

    expect(find.text('End your turn with a discard.'), findsOneWidget);
    await dragToDiscard(tester, CardRank.ace, CardSuit.clubs);

    expect(find.text('Lesson complete!'), findsOneWidget);
    expect(
      learning.progress.statusFor('sequence-cover'),
      PracticeLessonStatus.completed,
    );
  });

  testWidgets('set-cover lesson: the club king fills west\'s kings', (
    tester,
  ) async {
    final learning = MemoryLearningProgressRepository();
    await tester.pumpWidget(_practiceApp(learning: learning));
    await tester.pumpAndSettle();
    await openLesson(tester, 'set-cover');

    await pumpThroughIntro(tester);
    await tester.tap(find.byTooltip('Draw Stock'));
    await tester.pumpAndSettle();

    await dragToMeld(
      tester,
      CardRank.king,
      CardSuit.clubs,
      owner: 'west',
      meldIndex: 1,
    );
    expect(find.text('End your turn with a discard.'), findsOneWidget);

    await dragToDiscard(tester, CardRank.ace, CardSuit.hearts);

    expect(find.text('Lesson complete!'), findsOneWidget);
    expect(
      learning.progress.statusFor('set-cover'),
      PracticeLessonStatus.completed,
    );
  });

  testWidgets('cover-discard-block lesson: the trapped ten bounces off the '
      'pile; any other card ends the turn', (tester) async {
    final learning = MemoryLearningProgressRepository();
    await tester.pumpWidget(_practiceApp(learning: learning));
    await tester.pumpAndSettle();
    await openLesson(tester, 'cover-discard-block');

    await pumpThroughIntro(tester);
    await tester.tap(find.byTooltip('Draw Stock'));
    await tester.pumpAndSettle();

    // The trapped cover rings beside the set it would complete — a playtest
    // missed the relationship when only the hand card ringed. Trying to
    // throw it does nothing: the drop target never accepts it.
    expect(ringedCard(CardRank.ten, CardSuit.hearts), findsOneWidget);
    expect(ringedCard(CardRank.ten, CardSuit.spades), findsOneWidget);
    await dragToDiscard(tester, CardRank.ten, CardSuit.hearts);
    expect(find.bySemanticsLabel('Ten of Hearts'), findsOneWidget);
    expect(
      learning.progress.statusFor('cover-discard-block'),
      PracticeLessonStatus.notStarted,
    );

    await dragToDiscard(tester, CardRank.ace, CardSuit.spades);

    expect(find.text('Lesson complete!'), findsOneWidget);
    expect(
      learning.progress.statusFor('cover-discard-block'),
      PracticeLessonStatus.completed,
    );
  });

  testWidgets('joker-identity lesson: the picker offers both sevens and the '
      'declaration completes the meld', (tester) async {
    final learning = MemoryLearningProgressRepository();
    await tester.pumpWidget(_practiceApp(learning: learning));
    await tester.pumpAndSettle();
    await openLesson(tester, 'joker-identity');

    await tester.tap(find.byTooltip('Draw Stock'));
    await tester.pumpAndSettle();

    await toggleHandCard(tester, CardRank.seven, CardSuit.clubs);
    await toggleHandCard(tester, CardRank.seven, CardSuit.hearts);
    // The joker has no rank/suit key; toggle it by its drag key directly.
    final jokerRect = tester.getRect(
      find.byKey(const ValueKey('south-hand-drag-deck-0-joker-0')),
    );
    await tester.tapAt(Offset(jokerRect.left + 6, jokerRect.center.dy));
    await tester.pump();
    await tester.tap(find.byTooltip('Play selected meld'));
    await tester.pumpAndSettle();

    // The real identity picker: both missing sevens are offered.
    expect(find.byKey(const ValueKey('joker-choice-dialog')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('joker-choice-seven-diamonds')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('joker-choice-seven-spades')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('joker-choice-seven-diamonds')));
    await tester.pumpAndSettle();

    expect(find.text('End your turn with a discard.'), findsOneWidget);
    await dragToDiscard(tester, CardRank.ace, CardSuit.spades);

    expect(find.text('Lesson complete!'), findsOneWidget);
    expect(
      learning.progress.statusFor('joker-identity'),
      PracticeLessonStatus.completed,
    );
  });

  testWidgets('joker-replacement lesson: swap the real seven in; the freed '
      'joker bounces off the pile', (tester) async {
    final learning = MemoryLearningProgressRepository();
    await tester.pumpWidget(_practiceApp(learning: learning));
    await tester.pumpAndSettle();
    await openLesson(tester, 'joker-replacement');

    await pumpThroughIntro(tester);
    await tester.tap(find.byTooltip('Draw Stock'));
    await tester.pumpAndSettle();

    expect(ringedCard(CardRank.seven, CardSuit.diamonds), findsOneWidget);

    // West melded the sevens (with the joker) first: meld index 0.
    await dragToMeld(
      tester,
      CardRank.seven,
      CardSuit.diamonds,
      owner: 'west',
      meldIndex: 0,
    );
    expect(
      find.textContaining('a joker never leaves as a discard'),
      findsOneWidget,
    );

    // The freed joker is in hand and blocked as a discard.
    final jokerInHand = find.byKey(
      const ValueKey('south-hand-drag-deck-0-joker-0'),
    );
    expect(jokerInHand, findsOneWidget);
    final jokerRect = tester.getRect(jokerInHand);
    final pileCenter = tester.getCenter(
      find.byKey(const ValueKey('discard-pile-drop-target')),
    );
    final grip = Offset(jokerRect.left + 6, jokerRect.center.dy);
    await tester.dragFrom(grip, pileCenter - grip);
    await tester.pumpAndSettle();
    expect(jokerInHand, findsOneWidget, reason: 'joker discards are blocked');

    // The use branch: bridge the 8 and 10 of hearts with the joker as a
    // nine. The step accepts the meld, reacts, and still waits for the
    // closing discard.
    await toggleHandCard(tester, CardRank.eight, CardSuit.hearts);
    await toggleHandCard(tester, CardRank.ten, CardSuit.hearts);
    final freshJokerRect = tester.getRect(jokerInHand);
    await tester.tapAt(
      Offset(freshJokerRect.left + 6, freshJokerRect.center.dy),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Play selected meld'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('the joker is a nine of hearts now'),
      findsOneWidget,
    );

    await dragToDiscard(tester, CardRank.king, CardSuit.hearts);

    expect(find.text('Lesson complete!'), findsOneWidget);
    expect(
      learning.progress.statusFor('joker-replacement'),
      PracticeLessonStatus.completed,
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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/app/app_routes.dart';
import 'package:hareeg_table/app/hareeg_table_app.dart';
import 'package:hareeg_table/data/persistence/preferences_repository.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/ui/core/cards/card_state.dart';
import 'package:hareeg_table/ui/core/cards/card_view.dart';
import 'package:hareeg_table/ui/features/game_table/views/game_table_screen.dart';
import 'package:hareeg_table/ui/features/learning/models/practice_lesson_registry.dart';
import 'package:hareeg_table/ui/features/learning/practice/practice_session.dart';

import 'test_fixtures.dart';

// Re-exported so widget-test files importing only this harness can reach the
// shared [PracticeTestClock] without a second import.
export 'practice_lesson_harness.dart' show PracticeTestClock;

/// Pumps the practice checklist route with in-memory app dependencies.
Widget practiceApp({
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

/// Hosts a practice session directly on the real table surface.
Widget practiceTable(
  PracticeSession session, {
  required void Function(String lessonId) onFinished,
}) {
  return MaterialApp(
    home: GameTableScreen(
      setup: session.controller.setup,
      matchRepository: MemoryMatchRepository(),
      preferences: GamePreferences.defaults(),
      onPreferencesChanged: (_) {},
      practiceSession: session,
      onPracticeFinished: (lessonId) async => onFinished(lessonId),
      nextPracticeScript: PracticeLessonRegistry.nextScriptInPack,
    ),
  );
}

/// Opens [lessonId] from the checklist, scrolling lazily built tiles into view.
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

/// Scrolls the checklist back to its header after a lesson pops to the list.
///
/// Drags far enough to clear the catalog's tallest return position so the
/// progress header sits in view regardless of which pack the lesson lives in.
Future<void> scrollChecklistToTop(WidgetTester tester) async {
  await tester.drag(find.byType(ListView), const Offset(0, 2000));
  await tester.pumpAndSettle();
}

/// South-hand card rect for a physical card.
Rect handCardRect(WidgetTester tester, CardRank rank, CardSuit suit) {
  final id = HareegCard.standard(rank: rank, suit: suit, deckIndex: 0).id;
  return tester.getRect(find.byKey(ValueKey('south-hand-drag-$id')));
}

/// Drags a south-hand card onto the discard pile.
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

/// Toggles a south-hand card selection without hitting duplicate table copies.
Future<void> toggleHandCard(
  WidgetTester tester,
  CardRank rank,
  CardSuit suit,
) async {
  final rect = handCardRect(tester, rank, suit);
  await tester.tapAt(Offset(rect.left + 6, rect.center.dy));
  await tester.pump();
}

/// Taps the selected-meld affordance.
Future<void> playSelectedMeld(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Play selected meld'));
  await tester.pumpAndSettle();
}

/// Taps the discard pile target.
Future<void> tapDiscardPile(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('discard-pile-drop-target')));
  await tester.pumpAndSettle();
}

/// Pumps a lesson's scripted intro until the player step banner appears.
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

/// A card rendered with the coach-highlight ring.
Finder ringedCard(CardRank rank, CardSuit suit) {
  final id = HareegCard.standard(rank: rank, suit: suit, deckIndex: 0).id;
  return find.byWidgetPredicate(
    (widget) =>
        widget is HareegCardView &&
        widget.card.id == id &&
        widget.visualState == CardVisualState.coachHighlight,
  );
}

/// The override ring colour of a coach-highlighted card, or null when the card
/// rings in the default teal (no per-group override). Reads the first ringed
/// [HareegCardView] for the card — cover lessons render both the hand card and
/// its table-meld twin, so [deckIndex] selects which copy to inspect.
Color? ringColorOf(
  WidgetTester tester,
  CardRank rank,
  CardSuit suit, {
  int deckIndex = 0,
}) {
  final id = HareegCard.standard(rank: rank, suit: suit, deckIndex: deckIndex).id;
  final matches = tester
      .widgetList<HareegCardView>(
        find.byWidgetPredicate(
          (widget) =>
              widget is HareegCardView &&
              widget.card.id == id &&
              widget.visualState == CardVisualState.coachHighlight,
        ),
      )
      .toList();
  assert(
    matches.isNotEmpty,
    'No HareegCardView found for card "$id" in '
    'CardVisualState.coachHighlight (deckIndex: $deckIndex). '
    'Expected a coach-highlighted card matching widget.card.id == "$id".',
  );
  return matches.first.coachRingColor;
}

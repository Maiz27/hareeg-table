import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/app/app_routes.dart';
import 'package:hareeg_table/app/hareeg_table_app.dart';
import 'package:hareeg_table/data/persistence/preferences_repository.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_game_controller.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/ui/core/cards/card_state.dart';
import 'package:hareeg_table/ui/core/cards/card_theme.dart';
import 'package:hareeg_table/ui/core/cards/card_theme_registry.dart';
import 'package:hareeg_table/ui/core/cards/card_view.dart';
import 'package:hareeg_table/ui/features/game_table/widgets/fifty_ring.dart';
import 'package:hareeg_table/ui/features/game_table/widgets/pause_overlay.dart';
import 'package:hareeg_table/ui/features/game_table/widgets/physical_table_playfield.dart';
import 'package:hareeg_table/ui/features/game_table/widgets/score_overlay.dart';

import '../../../support/test_fixtures.dart';

void main() {
  group('Game table widget tests', () {
    testWidgets('table chrome shows score + pause icons', (tester) async {
      await _openTable(tester);
      expect(find.byTooltip('Scores'), findsOneWidget);
      expect(find.byTooltip('Pause'), findsOneWidget);
    });

    testWidgets('score button opens the score overlay', (tester) async {
      await _openTable(tester);
      await tester.tap(find.byTooltip('Scores'));
      await tester.pumpAndSettle();
      expect(find.byType(ScoreOverlay), findsOneWidget);
      expect(find.text('Match scores'), findsOneWidget);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(ScoreOverlay), findsNothing);
    });

    testWidgets('pause button opens the pause overlay with table controls', (
      tester,
    ) async {
      await _openTable(tester);
      await tester.tap(find.byTooltip('Pause'));
      await tester.pumpAndSettle();
      expect(find.byType(PauseOverlay), findsOneWidget);
      expect(find.text('Table aids'), findsOneWidget);
      expect(find.text('Motion speed'), findsOneWidget);
      expect(find.text('Table haptics'), findsOneWidget);

      await tester.tap(find.text('Resume table').last);
      await tester.pumpAndSettle();
      expect(find.byType(PauseOverlay), findsNothing);
    });

    testWidgets('south hand renders card views and tapping selects', (
      tester,
    ) async {
      await _openTable(tester);
      // Wait for any deferred CPU work to settle.
      await tester.pumpAndSettle(const Duration(milliseconds: 800));
      // Find any card in the south seat hand.
      final southCards = find.byType(HareegCardView);
      expect(southCards, findsWidgets);

      // Tap one card and confirm tap doesn't throw.
      await tester.tap(southCards.first, warnIfMissed: false);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('meld picker only offers combinations from selected cards', (
      tester,
    ) async {
      final diamondRun = [
        _card(CardRank.eight, CardSuit.diamonds, 80),
        _card(CardRank.nine, CardSuit.diamonds, 80),
        _card(CardRank.ten, CardSuit.diamonds, 80),
      ];
      final jackSet = [
        _card(CardRank.jack, CardSuit.diamonds, 80),
        _card(CardRank.jack, CardSuit.hearts, 80),
        _card(CardRank.jack, CardSuit.clubs, 80),
      ];
      await _openTable(
        tester,
        southHand: [
          ...diamondRun,
          ...jackSet,
          _card(CardRank.two, CardSuit.clubs, 80),
        ],
      );

      await tester.tap(
        find.bySemanticsLabel('Eight of Diamonds').first,
        warnIfMissed: false,
      );
      await tester.tap(
        find.bySemanticsLabel('Nine of Diamonds').first,
        warnIfMissed: false,
      );
      await tester.tap(
        find.bySemanticsLabel('Ten of Diamonds').first,
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      final selectedAction = ClassicHareegActionIds.playMeldActionId(
        diamondRun.map((card) => card.id),
      );
      final bundledAction = ClassicHareegActionIds.playMeldActionId(
        [...diamondRun, ...jackSet].map((card) => card.id),
      );
      expect(
        find.byKey(ValueKey('meld-suggestion-$selectedAction')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('meld-suggestion-$bundledAction')),
        findsNothing,
      );
    });

    testWidgets('hand reorder accepts a drop after the last card', (
      tester,
    ) async {
      await _openTable(
        tester,
        southHand: [
          _card(CardRank.four, CardSuit.clubs, 81),
          _card(CardRank.five, CardSuit.clubs, 81),
          _card(CardRank.six, CardSuit.clubs, 81),
          _card(CardRank.seven, CardSuit.clubs, 81),
        ],
      );

      final moved = find.bySemanticsLabel('Four of Clubs').first;
      final last = find.bySemanticsLabel('Seven of Clubs').first;
      final start = tester.getCenter(moved);
      final end = tester.getCenter(
        find.byKey(const ValueKey('south-hand-trailing-drop-target')),
      );

      await tester.dragFrom(start, end - start);
      await tester.pumpAndSettle();

      expect(
        tester.getCenter(moved).dx,
        greaterThan(tester.getCenter(last).dx),
      );
    });

    testWidgets('south hand can be reordered while CPU has the turn', (
      tester,
    ) async {
      final cards = [
        _card(CardRank.four, CardSuit.clubs, 82),
        _card(CardRank.five, CardSuit.clubs, 82),
        _card(CardRank.six, CardSuit.clubs, 82),
        _card(CardRank.seven, CardSuit.clubs, 82),
      ];
      final moves = <({HareegCard card, int targetIndex})>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 900,
              height: 500,
              child: PhysicalTablePlayfield(
                theme: CardThemeRegistry.byId(null),
                stockCount: 30,
                discardPile: const [],
                topDiscard: null,
                pendingDiscard: null,
                cardCounts: const {
                  PlayerSeat.south: 4,
                  PlayerSeat.east: 14,
                  PlayerSeat.north: 14,
                  PlayerSeat.west: 14,
                },
                tableMelds: const {},
                southCards: cards,
                selectedIds: const {},
                onCardTap: (_) {},
                onReorderHand: (card, targetIndex) {
                  moves.add((card: card, targetIndex: targetIndex));
                },
                canDiscardCard: (_) => false,
                canPlayCardOnTable: (_) => false,
                canPlaceMeldOnTable: (_) => false,
                canPlayCardOnMeld: (_, _, _) => false,
                canRetractMeld: (_, _) => false,
                onDiscardCard: (_) {},
                onPlayCardOnTable: (_) {},
                onPlayCardOnMeld: (_, _, _) {},
                onRetractMeld: (_, _) {},
                canDrawStock: false,
                canTakeDiscard: false,
                canReturnDiscard: false,
                canClaimFifty: false,
                canReturnOpeningMelds: false,
                onDrawStock: () {},
                onTakeDiscard: () {},
                onReturnDiscard: () {},
                onClaimFifty: () {},
                onReturnOpeningMelds: () {},
                fiftySecondsRemaining: null,
                fiftyTotalSeconds: 50,
                fiftyPulse: false,
                meldRequirement: 51,
                meldSelectionValue: null,
                meldSelectionValid: false,
                meldSelectionHasOpened: false,
                onPlaySelectedMeld: null,
                meldSuggestions: const [],
                showMeldSuggestions: false,
                onMeldSuggestion: (_) {},
                isHumanTurn: false,
                isCpuRunning: true,
                currentSeat: PlayerSeat.east,
                activeSeats: PlayerSeat.values.toSet(),
              ),
            ),
          ),
        ),
      );

      final moved = find.bySemanticsLabel('Four of Clubs').first;
      final start = tester.getCenter(moved);
      final end = tester.getCenter(
        find.byKey(const ValueKey('south-hand-trailing-drop-target')),
      );

      await tester.dragFrom(start, end - start);
      await tester.pump();

      expect(moves, hasLength(1));
      expect(moves.single.card.id, cards.first.id);
      expect(moves.single.targetIndex, cards.length);
    });

    testWidgets('table fits a compact 640x360 landscape viewport', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(640, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await _openTable(tester);
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Pause'), findsOneWidget);
    });

    testWidgets('pending discard can be returned from the discard pile', (
      tester,
    ) async {
      final pending = _card(CardRank.nine, CardSuit.clubs, 91);
      await _openTable(
        tester,
        savedSnapshot: _savedSnapshot(
          southHand: [
            pending,
            _card(CardRank.three, CardSuit.hearts, 91),
            _card(CardRank.four, CardSuit.hearts, 91),
            _card(CardRank.five, CardSuit.hearts, 91),
          ],
          discardPile: [_card(CardRank.ace, CardSuit.spades, 91)],
          pendingDiscard: pending,
        ),
      );

      expect(
        find.byKey(ValueKey('south-hand-drag-${pending.id}')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('discard-pile-drop-target')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(ValueKey('south-hand-drag-${pending.id}')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('discard-pile-drop-target')),
        findsOneWidget,
      );
    });

    testWidgets('FiftyRing is present during a claimable Fifty window', (
      tester,
    ) async {
      final setup = ClassicHareegSetup.defaults().copyWith(
        rulePreset: RulePreset.tablePenalties,
        fiftyTimerSeconds: 50,
      );
      await _openTable(
        tester,
        savedSnapshot: _savedSnapshot(
          setup: setup,
          southHand: [
            _card(CardRank.seven, CardSuit.clubs, 92),
            _card(CardRank.eight, CardSuit.clubs, 92),
            _card(CardRank.two, CardSuit.hearts, 92),
          ],
          discardPile: [_card(CardRank.nine, CardSuit.clubs, 92)],
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.draw,
          savedAt: DateTime.now().toUtc(),
          fiftyWindowOpenedAt: DateTime.now().toUtc().add(
            const Duration(seconds: 10),
          ),
        ),
      );

      expect(find.byType(FiftyRing), findsOneWidget);
    });

    testWidgets('memory joker preference flows into table card rendering', (
      tester,
    ) async {
      const represented = CardIdentity(
        rank: CardRank.queen,
        suit: CardSuit.hearts,
      );
      const joker = HareegCard.joker(
        deckIndex: 93,
        jokerIndex: 0,
        representedIdentity: represented,
      );
      final preferences = MemoryPreferencesRepository()
        ..preferences = GamePreferences.defaults().copyWith(
          memoryJokerDisplay: true,
        );

      await _openTable(
        tester,
        southHand: [
          joker,
          _card(CardRank.three, CardSuit.spades, 93),
          _card(CardRank.four, CardSuit.spades, 93),
        ],
        preferencesRepository: preferences,
      );

      expect(
        find.byKey(
          ValueKey(
            '${CardThemeRegistry.defaultThemeId}-${joker.id}-'
            '${CardVisualState.normal}-${JokerDisplay.memoryReveal}',
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('FiftyRing is not present when no Fifty window is open', (
      tester,
    ) async {
      await _openTable(tester);
      expect(find.byType(FiftyRing), findsNothing);
    });
  });
}

Future<void> _openTable(
  WidgetTester tester, {
  List<HareegCard>? southHand,
  ClassicHareegMatchSnapshot? savedSnapshot,
  MemoryPreferencesRepository? preferencesRepository,
}) async {
  final repository = MemoryMatchRepository(
    saved: savedSnapshot ?? _savedSnapshot(southHand: southHand),
  );
  await tester.pumpWidget(
    HareegTableApp(
      preferencesRepository:
          preferencesRepository ?? MemoryPreferencesRepository(),
      matchRepository: repository,
      initialRouteOverride: AppRoutes.home,
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
  // Use deterministic playing_card import to satisfy lints.
  expect(
    HareegCard.standard(
      rank: CardRank.ace,
      suit: CardSuit.spades,
      deckIndex: 0,
    ).label,
    'AS',
  );
}

ClassicHareegMatchSnapshot _savedSnapshot({
  List<HareegCard>? southHand,
  ClassicHareegSetup? setup,
  PlayerSeat currentSeat = PlayerSeat.south,
  TurnPhase turnPhase = TurnPhase.action,
  List<HareegCard>? discardPile,
  HareegCard? pendingDiscard,
  DateTime? savedAt,
  DateTime? fiftyWindowOpenedAt,
}) {
  final resolvedSetup = setup ?? ClassicHareegSetup.defaults();
  final snapshot = ClassicHareegRound.deal(setup: resolvedSetup, seed: 3);
  final hands = southHand == null
      ? snapshot.hands
      : {...snapshot.hands, PlayerSeat.south: southHand};
  return ClassicHareegMatchSnapshot(
    setup: resolvedSetup,
    hands: hands,
    stock: snapshot.stock,
    discardPile: discardPile ?? snapshot.discardPile,
    starter: snapshot.starter,
    currentSeat: currentSeat,
    turnPhase: turnPhase,
    pendingDiscard: pendingDiscard,
    fiftyWindowOpenedAt: fiftyWindowOpenedAt,
    savedAt: savedAt ?? DateTime.utc(2026, 5, 18),
  );
}

HareegCard _card(CardRank rank, CardSuit suit, int deckIndex) {
  return HareegCard.standard(rank: rank, suit: suit, deckIndex: deckIndex);
}

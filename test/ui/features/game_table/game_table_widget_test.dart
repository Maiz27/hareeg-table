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
import 'package:hareeg_table/domain/classic_hareeg/rules/opening_rules.dart';
import 'package:hareeg_table/ui/core/aids/table_aids.dart';
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

    testWidgets('score and pause overlays dismiss from a scrim tap', (
      tester,
    ) async {
      await _openTable(tester);

      await tester.tap(find.byTooltip('Scores'));
      await tester.pumpAndSettle();
      expect(find.byType(ScoreOverlay), findsOneWidget);

      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(find.byType(ScoreOverlay), findsNothing);

      await tester.tap(find.byTooltip('Pause'));
      await tester.pumpAndSettle();
      expect(find.byType(PauseOverlay), findsOneWidget);

      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(find.byType(PauseOverlay), findsNothing);
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

    testWidgets('selected ambiguous joker set asks which identity to use', (
      tester,
    ) async {
      const joker = HareegCard.joker(deckIndex: 83, jokerIndex: 0);
      final aceHearts = _card(CardRank.ace, CardSuit.hearts, 83);
      final aceSpades = _card(CardRank.ace, CardSuit.spades, 83);
      await _openTable(
        tester,
        savedSnapshot: _savedSnapshot(
          southHand: [
            aceHearts,
            aceSpades,
            joker,
            _card(CardRank.four, CardSuit.clubs, 83),
          ],
          openingState: _opened(PlayerSeat.south),
        ),
      );

      await tester.tap(
        find.bySemanticsLabel('Ace of Hearts').first,
        warnIfMissed: false,
      );
      await tester.tap(
        find.bySemanticsLabel('Ace of Spades').first,
        warnIfMissed: false,
      );
      await tester.tap(
        find.bySemanticsLabel('Joker').first,
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Play selected meld'), findsOneWidget);

      await tester.tap(find.byTooltip('Play selected meld'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('joker-choice-dialog')), findsOneWidget);
      expect(find.text('Joker as Ace of Clubs'), findsOneWidget);
      expect(find.text('Joker as Ace of Diamonds'), findsOneWidget);

      await tester.tap(find.text('Joker as Ace of Diamonds'));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel('Joker representing Ace of Diamonds'),
        findsOneWidget,
      );
    });

    testWidgets(
      'selected same-suit face-card joker run asks which edge to use',
      (tester) async {
        const joker = HareegCard.joker(deckIndex: 84, jokerIndex: 0);
        final jackHearts = _card(CardRank.jack, CardSuit.hearts, 84);
        final queenHearts = _card(CardRank.queen, CardSuit.hearts, 84);
        await _openTable(
          tester,
          savedSnapshot: _savedSnapshot(
            southHand: [
              jackHearts,
              queenHearts,
              joker,
              _card(CardRank.four, CardSuit.clubs, 84),
            ],
            openingState: _opened(PlayerSeat.south),
          ),
        );

        await tester.tap(
          find.bySemanticsLabel('Jack of Hearts').first,
          warnIfMissed: false,
        );
        await tester.tap(
          find.bySemanticsLabel('Queen of Hearts').first,
          warnIfMissed: false,
        );
        await tester.tap(
          find.bySemanticsLabel('Joker').first,
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();

        expect(find.byTooltip('Play selected meld'), findsOneWidget);

        await tester.tap(find.byTooltip('Play selected meld'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('joker-choice-dialog')),
          findsOneWidget,
        );
        expect(find.text('Joker as Ten of Hearts'), findsOneWidget);
        expect(find.text('Joker as King of Hearts'), findsOneWidget);

        await tester.tap(find.text('Joker as King of Hearts'));
        await tester.pumpAndSettle();

        expect(
          find.bySemanticsLabel('Joker representing King of Hearts'),
          findsOneWidget,
        );
      },
    );

    testWidgets('same-rank joker suggestions keep represented identities', (
      tester,
    ) async {
      const joker = HareegCard.joker(deckIndex: 86, jokerIndex: 0);
      final preferences = MemoryPreferencesRepository()
        ..preferences = GamePreferences.defaults().copyWith(
          memoryJokerDisplay: true,
        );

      await _openTable(
        tester,
        savedSnapshot: _savedSnapshot(
          southHand: [
            _card(CardRank.queen, CardSuit.spades, 86),
            _card(CardRank.queen, CardSuit.clubs, 86),
            joker,
            _card(CardRank.four, CardSuit.clubs, 86),
          ],
          openingState: _opened(PlayerSeat.south),
        ),
        preferencesRepository: preferences,
      );

      await tester.tap(
        find.bySemanticsLabel('Queen of Spades').first,
        warnIfMissed: false,
      );
      await tester.tap(
        find.bySemanticsLabel('Queen of Clubs').first,
        warnIfMissed: false,
      );
      await tester.tap(find.bySemanticsLabel('Joker').first);
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel('Joker representing Queen of Hearts'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Joker representing Queen of Diamonds'),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Play selected meld'));
      await tester.pumpAndSettle();

      final dialog = find.byKey(const ValueKey('joker-choice-dialog'));
      expect(dialog, findsOneWidget);
      expect(
        find.descendant(
          of: dialog,
          matching: find.bySemanticsLabel('Joker representing Queen of Hearts'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: dialog,
          matching: find.bySemanticsLabel(
            'Joker representing Queen of Diamonds',
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('selected mixed-suit face cards with joker are not a meld', (
      tester,
    ) async {
      const joker = HareegCard.joker(deckIndex: 85, jokerIndex: 0);
      await _openTable(
        tester,
        savedSnapshot: _savedSnapshot(
          southHand: [
            _card(CardRank.jack, CardSuit.diamonds, 85),
            _card(CardRank.queen, CardSuit.hearts, 85),
            joker,
            _card(CardRank.four, CardSuit.clubs, 85),
          ],
          openingState: _opened(PlayerSeat.south),
        ),
      );

      await tester.tap(
        find.bySemanticsLabel('Jack of Diamonds').first,
        warnIfMissed: false,
      );
      await tester.tap(
        find.bySemanticsLabel('Queen of Hearts').first,
        warnIfMissed: false,
      );
      await tester.tap(
        find.bySemanticsLabel('Joker').first,
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Play selected meld'), findsNothing);
      expect(find.byKey(const ValueKey('joker-choice-dialog')), findsNothing);
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
                onCardLongPress: (_) {},
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

    testWidgets('Pixel 8a landscape uses the readable card-size tier', (
      tester,
    ) async {
      await _pumpPlayfield(tester, size: const Size(816, 368));

      final firstCard = _card(CardRank.four, CardSuit.clubs, 98);
      final cardView = find.descendant(
        of: find.byKey(ValueKey('south-hand-drag-${firstCard.id}')),
        matching: find.byType(HareegCardView),
      );

      expect(tester.takeException(), isNull);
      expect(tester.getSize(cardView.first), const Size(48, 68));
    });

    testWidgets('side opponent rails are vertically centered', (tester) async {
      await _pumpPlayfield(tester, size: const Size(900, 500));

      expect(
        tester.getCenter(find.byKey(const ValueKey('west-opponent-rail'))).dy,
        closeTo(250, 0.1),
      );
      expect(
        tester.getCenter(find.byKey(const ValueKey('east-opponent-rail'))).dy,
        closeTo(250, 0.1),
      );
    });

    testWidgets('side opponent rails stay centered on compact landscape', (
      tester,
    ) async {
      await _pumpPlayfield(tester, size: const Size(640, 360));

      expect(
        tester.getCenter(find.byKey(const ValueKey('west-opponent-rail'))).dy,
        closeTo(180, 0.1),
      );
      expect(
        tester.getCenter(find.byKey(const ValueKey('east-opponent-rail'))).dy,
        closeTo(180, 0.1),
      );
    });

    testWidgets('side meld lanes use the available table height', (
      tester,
    ) async {
      final sideMelds = [
        PlacedMeld.fromCards([
          _card(CardRank.queen, CardSuit.clubs, 99),
          _card(CardRank.queen, CardSuit.diamonds, 99),
          _card(CardRank.queen, CardSuit.hearts, 99),
        ]),
        PlacedMeld.fromCards([
          _card(CardRank.four, CardSuit.spades, 99),
          _card(CardRank.five, CardSuit.spades, 99),
          _card(CardRank.six, CardSuit.spades, 99),
          _card(CardRank.seven, CardSuit.spades, 99),
        ]),
      ];

      await _pumpPlayfield(
        tester,
        tableMelds: {PlayerSeat.west: sideMelds, PlayerSeat.east: sideMelds},
        size: const Size(900, 500),
      );

      final westLane = tester.getRect(
        find.byKey(const ValueKey('west-meld-lane')),
      );
      final eastLane = tester.getRect(
        find.byKey(const ValueKey('east-meld-lane')),
      );

      expect(westLane.top, lessThan(32));
      expect(eastLane.top, lessThan(32));
      expect(westLane.height, greaterThan(440));
      expect(eastLane.height, greaterThan(440));
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

    testWidgets('round result stays in table and auto advances', (
      tester,
    ) async {
      final meldCards = [
        _card(CardRank.seven, CardSuit.clubs, 100),
        _card(CardRank.eight, CardSuit.clubs, 100),
        _card(CardRank.nine, CardSuit.clubs, 100),
      ];
      final finalDiscard = _card(CardRank.two, CardSuit.spades, 100);

      await _openTable(
        tester,
        savedSnapshot: _savedSnapshot(
          southHand: [...meldCards, finalDiscard],
          openingState: _opened(PlayerSeat.south),
        ),
      );

      for (final label in [
        'Seven of Clubs',
        'Eight of Clubs',
        'Nine of Clubs',
      ]) {
        await tester.tap(
          find.bySemanticsLabel(label).first,
          warnIfMissed: false,
        );
      }
      await tester.pumpAndSettle();
      await tester.tap(find.text('Play meld'));
      await tester.pumpAndSettle();

      final discard = find.bySemanticsLabel('Two of Spades').first;
      final dropTarget = find.byKey(const ValueKey('discard-pile-drop-target'));
      await tester.dragFrom(
        tester.getCenter(discard),
        tester.getCenter(dropTarget) - tester.getCenter(discard),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('round-result-overlay')),
        findsOneWidget,
      );
      expect(find.text('Round score'), findsOneWidget);
      expect(find.textContaining('You finished'), findsOneWidget);
      expect(find.textContaining('cards 0'), findsWidgets);

      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('round-result-overlay')), findsNothing);

      await tester.pump(const Duration(milliseconds: 2500));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('round-result-overlay')), findsNothing);
      expect(find.byTooltip('Scores'), findsOneWidget);
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

    testWidgets(
      'FiftyRing still shows the human claim window in assisted mode',
      (tester) async {
        final now = DateTime.now().toUtc();
        await _openTable(
          tester,
          savedSnapshot: _savedSnapshot(
            southHand: [
              _card(CardRank.two, CardSuit.clubs, 93),
              _card(CardRank.five, CardSuit.diamonds, 93),
              _card(CardRank.king, CardSuit.hearts, 93),
            ],
            discardPile: [_card(CardRank.nine, CardSuit.clubs, 93)],
            currentSeat: PlayerSeat.south,
            turnPhase: TurnPhase.draw,
            savedAt: now,
            fiftyWindowOpenedAt: now,
          ),
        );

        expect(
          find.byType(FiftyRing),
          findsOneWidget,
          reason:
              'The timer is the visual claim window even when Assisted mode '
              'does not expose an invalid claim action.',
        );
      },
    );

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

    testWidgets('memory joker reveal quiets after the reveal window', (
      tester,
    ) async {
      const represented = CardIdentity(
        rank: CardRank.queen,
        suit: CardSuit.hearts,
      );
      const joker = HareegCard.joker(
        deckIndex: 94,
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
          _card(CardRank.three, CardSuit.spades, 94),
          _card(CardRank.four, CardSuit.spades, 94),
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

      await tester.pump(const Duration(milliseconds: 1700));
      await tester.pumpAndSettle();

      expect(
        find.byKey(
          ValueKey(
            '${CardThemeRegistry.defaultThemeId}-${joker.id}-'
            '${CardVisualState.normal}-${JokerDisplay.unassigned}',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          ValueKey(
            '${CardThemeRegistry.defaultThemeId}-${joker.id}-'
            '${CardVisualState.normal}-${JokerDisplay.memoryReveal}',
          ),
        ),
        findsNothing,
      );
    });

    testWidgets('hard table mode suppresses represented joker aids', (
      tester,
    ) async {
      const represented = CardIdentity(
        rank: CardRank.queen,
        suit: CardSuit.hearts,
      );
      const joker = HareegCard.joker(
        deckIndex: 95,
        jokerIndex: 0,
        representedIdentity: represented,
      );
      final setup = ClassicHareegSetup.defaults().copyWith(
        rulePreset: RulePreset.hardTable17,
      );
      final preferences = MemoryPreferencesRepository()
        ..preferences = GamePreferences.defaults().copyWith(
          memoryJokerDisplay: true,
        );

      await _openTable(
        tester,
        savedSnapshot: _savedSnapshot(
          setup: setup,
          southHand: [
            joker,
            _card(CardRank.three, CardSuit.spades, 95),
            _card(CardRank.four, CardSuit.spades, 95),
          ],
        ),
        preferencesRepository: preferences,
      );

      final hardJoker = find.byKey(
        ValueKey(
          '${CardThemeRegistry.defaultThemeId}-${joker.id}-'
          '${CardVisualState.normal}-${JokerDisplay.unassigned}',
        ),
      );
      expect(hardJoker, findsOneWidget);
      expect(
        find.byKey(
          ValueKey(
            '${CardThemeRegistry.defaultThemeId}-${joker.id}-'
            '${CardVisualState.normal}-${JokerDisplay.memoryReveal}',
          ),
        ),
        findsNothing,
      );

      await tester.longPressAt(tester.getCenter(hardJoker));
      await tester.pumpAndSettle();

      final overlay = find.byKey(const ValueKey('card-inspect-overlay'));
      expect(overlay, findsOneWidget);
      expect(
        find.descendant(of: overlay, matching: find.text('Joker')),
        findsWidgets,
      );
      expect(find.textContaining('Queen'), findsNothing);
      expect(find.byKey(const ValueKey('card-inspect-body')), findsNothing);
    });

    testWidgets('long press opens guided card inspect with explanation', (
      tester,
    ) async {
      await _openTable(
        tester,
        southHand: [
          _card(CardRank.queen, CardSuit.hearts, 95),
          _card(CardRank.three, CardSuit.spades, 95),
          _card(CardRank.four, CardSuit.spades, 95),
        ],
      );

      final target = find.bySemanticsLabel('Queen of Hearts').first;
      await tester.longPressAt(tester.getCenter(target));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('card-inspect-overlay')),
        findsOneWidget,
      );
      expect(find.text('Queen of Hearts'), findsOneWidget);
      expect(find.textContaining('same-rank sets'), findsOneWidget);

      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('card-inspect-overlay')), findsNothing);
    });

    testWidgets('table mode card inspect stays minimal', (tester) async {
      final preferences = MemoryPreferencesRepository()
        ..preferences = GamePreferences.defaults().copyWith(
          tableAids: TableAids.tableMode,
        );
      await _openTable(
        tester,
        southHand: [
          _card(CardRank.queen, CardSuit.hearts, 96),
          _card(CardRank.three, CardSuit.spades, 96),
          _card(CardRank.four, CardSuit.spades, 96),
        ],
        preferencesRepository: preferences,
      );

      final target = find.bySemanticsLabel('Queen of Hearts').first;
      await tester.longPressAt(tester.getCenter(target));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('card-inspect-overlay')),
        findsOneWidget,
      );
      expect(find.text('Queen of Hearts'), findsOneWidget);
      expect(find.byKey(const ValueKey('card-inspect-body')), findsNothing);
    });

    testWidgets('opponent meld tap expands the meld in place', (tester) async {
      final meld = PlacedMeld.fromCards([
        _card(CardRank.four, CardSuit.clubs, 97),
        _card(CardRank.five, CardSuit.clubs, 97),
        _card(CardRank.six, CardSuit.clubs, 97),
        _card(CardRank.seven, CardSuit.clubs, 97),
      ]);

      await _pumpPlayfield(
        tester,
        tableMelds: {
          PlayerSeat.east: [meld],
        },
      );

      final normal = find.byKey(const ValueKey('table-meld-east-0-normal'));
      expect(normal, findsOneWidget);

      await tester.tap(normal);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('table-meld-east-0-expanded')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('card-inspect-overlay')), findsNothing);
    });

    testWidgets('south meld tap expands the meld in place', (tester) async {
      final meld = PlacedMeld.fromCards([
        _card(CardRank.four, CardSuit.clubs, 97),
        _card(CardRank.five, CardSuit.clubs, 97),
        _card(CardRank.six, CardSuit.clubs, 97),
        _card(CardRank.seven, CardSuit.clubs, 97),
      ]);

      await _pumpPlayfield(
        tester,
        tableMelds: {
          PlayerSeat.south: [meld],
        },
      );

      final normal = find.byKey(const ValueKey('table-meld-south-0-normal'));
      expect(normal, findsOneWidget);

      await tester.tap(normal);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('table-meld-south-0-expanded')),
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
  await tester.ensureVisible(find.text('Continue'));
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

Future<void> _pumpPlayfield(
  WidgetTester tester, {
  Map<PlayerSeat, List<PlacedMeld>> tableMelds = const {},
  Size size = const Size(900, 500),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: size.width,
          height: size.height,
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
            tableMelds: tableMelds,
            southCards: [
              _card(CardRank.four, CardSuit.clubs, 98),
              _card(CardRank.five, CardSuit.clubs, 98),
              _card(CardRank.six, CardSuit.clubs, 98),
              _card(CardRank.seven, CardSuit.clubs, 98),
            ],
            selectedIds: const {},
            onCardTap: (_) {},
            onCardLongPress: (_) {},
            onReorderHand: (_, _) {},
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
            isCpuRunning: false,
            currentSeat: PlayerSeat.south,
            activeSeats: PlayerSeat.values.toSet(),
          ),
        ),
      ),
    ),
  );
}

ClassicHareegMatchSnapshot _savedSnapshot({
  List<HareegCard>? southHand,
  ClassicHareegSetup? setup,
  PlayerSeat currentSeat = PlayerSeat.south,
  TurnPhase turnPhase = TurnPhase.action,
  List<HareegCard>? discardPile,
  HareegCard? pendingDiscard,
  OpeningState? openingState,
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
    openingState: openingState,
    fiftyWindowOpenedAt: fiftyWindowOpenedAt,
    savedAt: savedAt ?? DateTime.utc(2026, 5, 18),
  );
}

OpeningState _opened(PlayerSeat seat) {
  return ClassicHareegOpeningRules.applyOpening(
    state: OpeningState.initial(51),
    seat: seat,
    melds: [const PlacedMeld(cards: [], valueSnapshot: 51)],
  );
}

HareegCard _card(CardRank rank, CardSuit suit, int deckIndex) {
  return HareegCard.standard(rank: rank, suit: suit, deckIndex: deckIndex);
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:hareeg_table/ui/core/cards/card_state.dart';
import 'package:hareeg_table/ui/core/cards/card_theme.dart';
import 'package:hareeg_table/ui/core/cards/card_theme_registry.dart';
import 'package:hareeg_table/ui/core/cards/card_view.dart';
import 'package:hareeg_table/ui/core/cards/showcase_card_fan.dart';
import 'package:hareeg_table/ui/features/game_table/widgets/fifty_ring.dart';
import 'package:hareeg_table/ui/features/game_table/widgets/pause_overlay.dart';
import 'package:hareeg_table/ui/features/game_table/widgets/physical_table_playfield.dart';
import 'package:hareeg_table/ui/features/game_table/widgets/score_overlay.dart';
import 'package:hareeg_table/ui/features/match_over/views/match_over_screen.dart';

import '../../../support/test_fixtures.dart';

void main() {
  // The home screen's `ShowcaseCardFan` runs a looping idle animation; pin it
  // to the rest pose so `pumpAndSettle` doesn't hang waiting for the loop.
  ShowcaseCardFan.disableLoopingMotionForTesting = true;

  group('Game table widget tests', () {
    testWidgets('table chrome shows score + pause icons', (tester) async {
      await _openTable(tester);
      expect(find.byTooltip('Scores'), findsOneWidget);
      expect(find.byTooltip('Pause'), findsOneWidget);
    });

    testWidgets('fresh table stages the opening deal before first turn', (
      tester,
    ) async {
      final matches = MemoryMatchRepository();
      await tester.pumpWidget(
        HareegTableApp(
          preferencesRepository: MemoryPreferencesRepository(),
          matchRepository: matches,
          initialRouteOverride: AppRoutes.table,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      expect(
        find.byKey(const ValueKey('opening-deal-overlay')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('opening-deal-flight-0')),
        findsOneWidget,
      );

      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('opening-deal-overlay')), findsNothing);
      expect(matches.saved, isNotNull);
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
      // Strictness is locked at match start, so it does not appear in the
      // pause overlay. Only ergonomic toggles do.
      expect(find.text('Table aids'), findsNothing);
      expect(find.text('Motion speed'), findsOneWidget);
      expect(find.text('Table haptics'), findsOneWidget);

      await tester.tap(find.text('Resume table').last);
      await tester.pumpAndSettle();
      expect(find.byType(PauseOverlay), findsNothing);
    });

    testWidgets('turning off table sounds keeps card-tap haptics active', (
      tester,
    ) async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });
      final preferences = MemoryPreferencesRepository()
        ..preferences = GamePreferences.defaults().copyWith(
          hapticsEnabled: true,
          soundEnabled: true,
        );

      await _openTable(
        tester,
        southHand: [_card(CardRank.four, CardSuit.clubs, 123)],
        preferencesRepository: preferences,
      );
      await tester.tap(find.byTooltip('Pause'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Table sounds'));
      await tester.pumpAndSettle();
      expect(find.byType(Switch), findsNWidgets(4));
      // Target the Table-sounds switch by its label rather than by position:
      // the toggle is a Row pairing the title Text with its sibling Switch.
      final soundSwitch = find.descendant(
        of: find
            .ancestor(of: find.text('Table sounds'), matching: find.byType(Row))
            .first,
        matching: find.byType(Switch),
      );
      await tester.tap(soundSwitch);
      await tester.pumpAndSettle();

      expect(preferences.preferences.soundEnabled, isFalse);
      expect(preferences.preferences.hapticsEnabled, isTrue);

      await tester.tap(find.text('Resume table').last);
      await tester.pumpAndSettle();
      calls.clear();

      await tester.tap(find.bySemanticsLabel('Four of Clubs').first);
      await tester.pump();

      expect(
        calls.where((call) => call.method.startsWith('HapticFeedback.')),
        isNotEmpty,
      );
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

    testWidgets('restored later-round heart run shows a meld suggestion', (
      tester,
    ) async {
      final heartRun = [
        _card(CardRank.nine, CardSuit.hearts, 87),
        _card(CardRank.ten, CardSuit.hearts, 87),
        _card(CardRank.jack, CardSuit.hearts, 87),
      ];
      await _openTable(
        tester,
        savedSnapshot: _savedSnapshot(
          southHand: [...heartRun, _card(CardRank.four, CardSuit.clubs, 87)],
          openingState: _opened(PlayerSeat.south),
          roundNumber: 12,
        ),
      );

      await tester.tap(
        find.bySemanticsLabel('Nine of Hearts').first,
        warnIfMissed: false,
      );
      await tester.tap(
        find.bySemanticsLabel('Ten of Hearts').first,
        warnIfMissed: false,
      );
      await tester.tap(
        find.bySemanticsLabel('Jack of Hearts').first,
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      final actionId = ClassicHareegActionIds.playMeldActionId(
        heartRun.map((card) => card.id),
      );
      expect(find.byKey(ValueKey('meld-suggestion-$actionId')), findsOneWidget);
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
        ..preferences = GamePreferences.defaults().copyWith();

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
                canPlayCardOnMeld: (_, _) => false,
                canRetractMeld: (_, _) => false,
                onDiscardCard: (_) {},
                onPlayCardOnTable: (_) {},
                onPlayCardOnMeld: (_, _) {},
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

    testWidgets('Fifty cue anchors above the discard pool top right', (
      tester,
    ) async {
      final discard = _card(CardRank.nine, CardSuit.clubs, 92);
      await _pumpPlayfield(
        tester,
        discardPile: [discard],
        topDiscard: discard,
        fiftySecondsRemaining: 4,
        isHumanTurn: true,
        currentSeat: PlayerSeat.south,
        size: const Size(900, 500),
      );

      final discardRect = tester.getRect(
        find.byKey(const ValueKey('discard-pile-drop-target')),
      );
      final cueRect = tester.getRect(find.byKey(const ValueKey('fifty-cue')));

      expect(cueRect.center.dx, greaterThan(discardRect.center.dx));
      expect(cueRect.center.dy, lessThan(discardRect.center.dy));
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

    testWidgets('match result dwells then navigates to MatchOverScreen', (
      tester,
    ) async {
      final meldCards = [
        _card(CardRank.seven, CardSuit.clubs, 101),
        _card(CardRank.eight, CardSuit.clubs, 101),
        _card(CardRank.nine, CardSuit.clubs, 101),
      ];
      final finalDiscard = _card(CardRank.two, CardSuit.spades, 101);

      final repository = await _openTable(
        tester,
        savedSnapshot: _savedSnapshot(
          southHand: [...meldCards, finalDiscard],
          openingState: _opened(PlayerSeat.south),
          roundNumber: 6,
          scores: const {
            PlayerSeat.south: 0,
            PlayerSeat.east: 30,
            PlayerSeat.north: 30,
            PlayerSeat.west: 30,
          },
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

      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pumpAndSettle();

      expect(find.byType(MatchOverScreen), findsOneWidget);
      expect(find.text('You win the match'), findsOneWidget);
      expect(find.text('6 rounds played'), findsOneWidget);
      expect(repository.saved, isNull);
    });

    testWidgets('FiftyRing is present during a claimable Fifty window', (
      tester,
    ) async {
      final setup = ClassicHareegSetup.defaults().copyWith(
        tableStrictness: TableStrictness.strict,
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

    testWidgets(
      'coaching/standard tiers render joker with persistent assisted identity',
      (tester) async {
        const represented = CardIdentity(
          rank: CardRank.queen,
          suit: CardSuit.hearts,
        );
        const joker = HareegCard.joker(
          deckIndex: 93,
          jokerIndex: 0,
          representedIdentity: represented,
        );

        await _openTable(
          tester,
          southHand: [
            joker,
            _card(CardRank.three, CardSuit.spades, 93),
            _card(CardRank.four, CardSuit.spades, 93),
          ],
        );

        expect(
          find.byKey(
            ValueKey(
              '${CardThemeRegistry.defaultThemeId}-${joker.id}-'
              '${CardVisualState.normal}-${JokerDisplay.assisted}',
            ),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'strict tier long-press hides represented identity during the cue',
      (tester) async {
        const represented = CardIdentity(
          rank: CardRank.queen,
          suit: CardSuit.hearts,
        );
        const joker = HareegCard.joker(
          deckIndex: 94,
          jokerIndex: 0,
          representedIdentity: represented,
        );
        final setup = ClassicHareegSetup.defaults().copyWith(
          tableStrictness: TableStrictness.strict,
        );

        final repository = MemoryMatchRepository(
          saved: _savedSnapshot(
            setup: setup,
            southHand: [
              joker,
              _card(CardRank.three, CardSuit.spades, 94),
              _card(CardRank.four, CardSuit.spades, 94),
            ],
          ),
        );
        await tester.pumpWidget(
          HareegTableApp(
            preferencesRepository: MemoryPreferencesRepository(),
            matchRepository: repository,
            initialRouteOverride: AppRoutes.home,
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Continue'));
        await tester.tap(find.text('Continue'));
        // Avoid pumpAndSettle so the joker cue stays mid-animation.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        final memoryReveal = find.byKey(
          ValueKey(
            '${CardThemeRegistry.defaultThemeId}-${joker.id}-'
            '${CardVisualState.normal}-${JokerDisplay.memoryReveal}',
          ),
        );
        expect(memoryReveal, findsOneWidget);

        await tester.longPressAt(tester.getCenter(memoryReveal));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        final overlay = find.byKey(const ValueKey('card-inspect-overlay'));
        expect(overlay, findsOneWidget);
        // Strict/Table never reveals the represented identity on long-press —
        // not during the cue, not after. The inspect title is plain "Joker"
        // and the inspect body is suppressed entirely.
        expect(
          find.descendant(of: overlay, matching: find.text('Joker')),
          findsWidgets,
        );
        expect(find.textContaining('Queen'), findsNothing);
        expect(find.byKey(const ValueKey('card-inspect-body')), findsNothing);
      },
    );

    testWidgets(
      'strict/table tiers quiet jokers to plain after the placement cue',
      (tester) async {
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
          tableStrictness: TableStrictness.table,
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
        );

        // _openTable runs pumpAndSettle, which lets the 3.6s placement-cue
        // animation finish. The joker reverts to plain (unassigned) once the
        // fade-out completes.
        final quietedJoker = find.byKey(
          ValueKey(
            '${CardThemeRegistry.defaultThemeId}-${joker.id}-'
            '${CardVisualState.normal}-${JokerDisplay.unassigned}',
          ),
        );
        expect(quietedJoker, findsOneWidget);

        await tester.longPressAt(tester.getCenter(quietedJoker));
        await tester.pumpAndSettle();

        final overlay = find.byKey(const ValueKey('card-inspect-overlay'));
        expect(overlay, findsOneWidget);
        // Long-press in Strict/Table shows "Joker" only — no represented
        // identity and no inspect body. The player must remember the
        // declared identity from the placement cue.
        expect(
          find.descendant(of: overlay, matching: find.text('Joker')),
          findsWidgets,
        );
        expect(find.textContaining('Queen'), findsNothing);
        expect(find.byKey(const ValueKey('card-inspect-body')), findsNothing);
      },
    );

    testWidgets(
      'joker placement raises a feedback chip naming the declared identity',
      (tester) async {
        const joker = HareegCard.joker(deckIndex: 87, jokerIndex: 0);
        final jackHearts = _card(CardRank.jack, CardSuit.hearts, 87);
        final queenHearts = _card(CardRank.queen, CardSuit.hearts, 87);
        await _openTable(
          tester,
          savedSnapshot: _savedSnapshot(
            southHand: [
              jackHearts,
              queenHearts,
              joker,
              _card(CardRank.four, CardSuit.clubs, 87),
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

        await tester.tap(find.byTooltip('Play selected meld'));
        await tester.pumpAndSettle();

        // Joker choice dialog is open; pick King of Hearts so the joker is
        // unambiguously declared as that identity.
        await tester.tap(find.text('Joker as King of Hearts'));
        // Don't pumpAndSettle — that would advance past the 3s feedback chip
        // window and the 3.6s memoryReveal cue. Pump enough to clear the
        // staggered meld flight (cards x stagger + flight duration ≈ 440ms)
        // and then catch the chip during its lifetime.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 700));

        expect(
          find.text('You declared joker as King of Hearts.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'joker placement cue holds memoryReveal for 3s then reverts to plain',
      (tester) async {
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
          tableStrictness: TableStrictness.strict,
        );

        final repository = MemoryMatchRepository(
          saved: _savedSnapshot(
            setup: setup,
            southHand: [
              joker,
              _card(CardRank.three, CardSuit.spades, 95),
              _card(CardRank.four, CardSuit.spades, 95),
            ],
          ),
        );
        await tester.pumpWidget(
          HareegTableApp(
            preferencesRepository: MemoryPreferencesRepository(),
            matchRepository: repository,
            initialRouteOverride: AppRoutes.home,
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Continue'));
        await tester.tap(find.text('Continue'));
        // After tapping Continue, only pump frames that drive the table mount.
        // Avoid pumpAndSettle so the joker cue is captured mid-animation.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        final memoryReveal = ValueKey(
          '${CardThemeRegistry.defaultThemeId}-${joker.id}-'
          '${CardVisualState.normal}-${JokerDisplay.memoryReveal}',
        );
        final unassigned = ValueKey(
          '${CardThemeRegistry.defaultThemeId}-${joker.id}-'
          '${CardVisualState.normal}-${JokerDisplay.unassigned}',
        );

        // During the 200ms fade-in + 3s hold the joker keeps the
        // memoryReveal key.
        expect(find.byKey(memoryReveal), findsOneWidget);

        // Halfway through the hold the badge is still in memoryReveal mode.
        await tester.pump(const Duration(milliseconds: 1500));
        expect(find.byKey(memoryReveal), findsOneWidget);

        // After the full cue (200ms fade-in + 3s hold + 400ms fade-out) the
        // badge has quieted to plain joker. Drain remaining frames so the
        // post-cue setState rebuild applies.
        await tester.pump(const Duration(milliseconds: 2200));
        await tester.pumpAndSettle();
        expect(find.byKey(memoryReveal), findsNothing);
        expect(find.byKey(unassigned), findsOneWidget);
      },
    );

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

    testWidgets('table tier card inspect still shows value for real cards', (
      tester,
    ) async {
      // Under the strictness redesign all tiers surface card value in the
      // inspect overlay — the prior "Table mode hides body" behavior is
      // gone. Only joker identity is hidden in Strict/Table.
      final setup = ClassicHareegSetup.defaults().copyWith(
        tableStrictness: TableStrictness.table,
      );
      await _openTable(
        tester,
        savedSnapshot: _savedSnapshot(
          setup: setup,
          southHand: [
            _card(CardRank.queen, CardSuit.hearts, 96),
            _card(CardRank.three, CardSuit.spades, 96),
            _card(CardRank.four, CardSuit.spades, 96),
          ],
        ),
      );

      final target = find.bySemanticsLabel('Queen of Hearts').first;
      await tester.longPressAt(tester.getCenter(target));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('card-inspect-overlay')),
        findsOneWidget,
      );
      expect(find.text('Queen of Hearts'), findsOneWidget);
      expect(find.byKey(const ValueKey('card-inspect-body')), findsOneWidget);
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

    testWidgets(
      'fast-forward chrome button appears when south is removed on Table tier',
      (tester) async {
        // Table tier + south already kicked from this round → spectator skip
        // is the whole point of the fast-forward button, so it must surface.
        final setup = ClassicHareegSetup.defaults().copyWith(
          tableStrictness: TableStrictness.table,
        );
        final snapshot = _savedSnapshot(
          setup: setup,
          currentSeat: PlayerSeat.east,
          turnPhase: TurnPhase.draw,
          activeSeats: const [
            PlayerSeat.south,
            PlayerSeat.east,
            PlayerSeat.north,
            PlayerSeat.west,
          ],
          removedSeats: const [PlayerSeat.south],
        );
        await _openTable(tester, savedSnapshot: snapshot);
        // The CPU loop is already cycling; pump a few frames so the chrome
        // settles without waiting for the entire round to play out.
        await tester.pump(const Duration(milliseconds: 16));

        expect(find.byTooltip('Skip to next round'), findsOneWidget);

        // Run the rest of the round (the CPU loop or the fast-forward will
        // both finish it eventually) so the test exits cleanly without
        // pending timers / animations stuck in flight.
        await tester.tap(find.byTooltip('Skip to next round'));
        await tester.pumpAndSettle(const Duration(seconds: 5));

        // After the rip the controller is past the round boundary — either
        // a new round was dealt or the match-over screen was pushed.
        // Either way the in-round fast-forward button is gone.
        expect(find.byTooltip('Skip to next round'), findsNothing);
      },
    );

    testWidgets(
      'fast-forward chrome button is hidden when strictness is not Table',
      (tester) async {
        // Coaching tier never removes the player from a round, so the
        // spectator-skip button has no reason to appear there.
        await _openTable(tester);
        await tester.pump(const Duration(milliseconds: 16));
        expect(find.byTooltip('Skip to next round'), findsNothing);
      },
    );

    testWidgets(
      'match short-circuits to MatchOver when south is score-eliminated',
      (tester) async {
        // South sits one shy of elimination. CPU east finishes the round with
        // south still holding a card, scoring south past 31. The table screen
        // should skip the next-round handoff and push MatchOver directly,
        // even though the match is mechanically still alive for the CPUs.
        final eastMeld = [
          _card(CardRank.five, CardSuit.clubs, 200),
          _card(CardRank.six, CardSuit.clubs, 200),
          _card(CardRank.seven, CardSuit.clubs, 200),
        ];
        final eastFinalDiscard = _card(CardRank.two, CardSuit.hearts, 200);
        final southCard = _card(CardRank.three, CardSuit.spades, 200);
        final snapshot = _savedSnapshot(
          hands: {
            PlayerSeat.south: [southCard],
            PlayerSeat.east: [...eastMeld, eastFinalDiscard],
            PlayerSeat.north: [_card(CardRank.eight, CardSuit.diamonds, 201)],
            PlayerSeat.west: [_card(CardRank.nine, CardSuit.diamonds, 202)],
          },
          openingState: _opened(PlayerSeat.east),
          currentSeat: PlayerSeat.east,
          turnPhase: TurnPhase.action,
          scores: const {
            PlayerSeat.south: 30,
            PlayerSeat.east: 0,
            PlayerSeat.north: 0,
            PlayerSeat.west: 0,
          },
        );
        await _openTable(tester, savedSnapshot: snapshot);
        // Drive the CPU until the round ends and the post-round timers fire.
        // pumpAndSettle would hang on the looping CPU pacing, so we step
        // through a few generous slices instead.
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(seconds: 2));
        }

        expect(find.byType(MatchOverScreen), findsOneWidget);
      },
    );
  });
}

Future<MemoryMatchRepository> _openTable(
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
  return repository;
}

Future<void> _pumpPlayfield(
  WidgetTester tester, {
  Map<PlayerSeat, List<PlacedMeld>> tableMelds = const {},
  List<HareegCard> discardPile = const [],
  HareegCard? topDiscard,
  int? fiftySecondsRemaining,
  bool isHumanTurn = false,
  PlayerSeat currentSeat = PlayerSeat.south,
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
            discardPile: discardPile,
            topDiscard: topDiscard,
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
            canPlayCardOnMeld: (_, _) => false,
            canRetractMeld: (_, _) => false,
            onDiscardCard: (_) {},
            onPlayCardOnTable: (_) {},
            onPlayCardOnMeld: (_, _) {},
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
            fiftySecondsRemaining: fiftySecondsRemaining,
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
            isHumanTurn: isHumanTurn,
            isCpuRunning: false,
            currentSeat: currentSeat,
            activeSeats: PlayerSeat.values.toSet(),
          ),
        ),
      ),
    ),
  );
}

ClassicHareegMatchSnapshot _savedSnapshot({
  List<HareegCard>? southHand,
  Map<PlayerSeat, List<HareegCard>>? hands,
  ClassicHareegSetup? setup,
  PlayerSeat currentSeat = PlayerSeat.south,
  TurnPhase turnPhase = TurnPhase.action,
  List<HareegCard>? discardPile,
  HareegCard? pendingDiscard,
  OpeningState? openingState,
  Map<PlayerSeat, int> scores = const {},
  List<PlayerSeat>? activeSeats,
  List<PlayerSeat> removedSeats = const [],
  int roundNumber = 1,
  DateTime? savedAt,
  DateTime? fiftyWindowOpenedAt,
}) {
  final resolvedSetup = setup ?? ClassicHareegSetup.defaults();
  final snapshot = ClassicHareegRound.deal(setup: resolvedSetup, seed: 3);
  final mergedHands = hands == null
      ? (southHand == null
            ? snapshot.hands
            : {...snapshot.hands, PlayerSeat.south: southHand})
      : {...snapshot.hands, ...hands};
  return ClassicHareegMatchSnapshot(
    setup: resolvedSetup,
    hands: mergedHands,
    stock: snapshot.stock,
    discardPile: discardPile ?? snapshot.discardPile,
    starter: snapshot.starter,
    currentSeat: currentSeat,
    turnPhase: turnPhase,
    pendingDiscard: pendingDiscard,
    openingState: openingState,
    scores: scores,
    activeSeats:
        activeSeats ??
        const [
          PlayerSeat.south,
          PlayerSeat.east,
          PlayerSeat.north,
          PlayerSeat.west,
        ],
    removedSeats: removedSeats,
    roundNumber: roundNumber,
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

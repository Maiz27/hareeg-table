import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/opening_rules.dart';
import 'package:hareeg_table/ui/core/cards/card_theme_registry.dart';
import 'package:hareeg_table/ui/features/game_table/widgets/physical_table_playfield.dart';

/// Regression test for the east/west meld area redesign: instead of one long
/// vertical strip that scrolls when a seat has many melds, the side lane fills
/// into centred columns that grow toward the table centre. With more melds
/// than fit one column, melds must occupy at least two distinct columns.
void main() {
  testWidgets('a crowded east lane fills a second column toward centre', (
    tester,
  ) async {
    // Six 3-card melds: taller than a single column can hold, so the lane
    // must open a second column.
    final melds = [
      for (var i = 0; i < 6; i++)
        PlacedMeld.fromCards([
          _card(CardRank.four, CardSuit.clubs, 100 + i * 3),
          _card(CardRank.five, CardSuit.clubs, 101 + i * 3),
          _card(CardRank.six, CardSuit.clubs, 102 + i * 3),
        ]),
    ];

    await _pumpPlayfield(
      tester,
      tableMelds: {PlayerSeat.east: melds},
      size: const Size(900, 500),
    );

    final lefts = <double>{};
    for (var i = 0; i < melds.length; i++) {
      final finder = find.byKey(ValueKey('table-meld-east-$i-normal'));
      expect(finder, findsOneWidget, reason: 'east meld $i should render');
      lefts.add(tester.getTopLeft(finder).dx.roundToDouble());
    }

    expect(
      lefts.length,
      greaterThanOrEqualTo(2),
      reason:
          'the crowded east lane should spread melds across at least two '
          'columns, not stack them in one scrolling strip (lefts: $lefts)',
    );
  });
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
              _card(CardRank.two, CardSuit.spades, 99),
              _card(CardRank.three, CardSuit.spades, 99),
              _card(CardRank.four, CardSuit.spades, 99),
              _card(CardRank.five, CardSuit.spades, 99),
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

HareegCard _card(CardRank rank, CardSuit suit, int deckIndex) =>
    HareegCard.standard(rank: rank, suit: suit, deckIndex: deckIndex);
